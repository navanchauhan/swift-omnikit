import Foundation
import OmniUICore
import OmniWebKit
import XCTest

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class ScriptHandlerProbe: NSObject, WKScriptMessageHandler {
    var messages: [WKScriptMessage] = []
    var onMessage: ((WKScriptMessage) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        messages.append(message)
        onMessage?(message)
    }
}

private final class NavigationProbe: NSObject, WKNavigationDelegate {
    var starts = 0
    var finishes = 0
    var commits = 0
    var policyDecisions: [URL] = []
    var nextPolicy: WKNavigationActionPolicy = .allow
    var actionDownloads = 0
    var responsePolicyDecisions: [URL] = []
    var nextResponsePolicy: WKNavigationResponsePolicy = .allow
    var responseDownloads = 0
    weak var downloadDelegate: WKDownloadDelegate?

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        starts += 1
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        commits += 1
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishes += 1
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            policyDecisions.append(url)
        }
        decisionHandler(nextPolicy)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        actionDownloads += 1
        download.delegate = downloadDelegate
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let url = navigationResponse.response.url {
            responsePolicyDecisions.append(url)
        }
        decisionHandler(nextResponsePolicy)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        responseDownloads += 1
        download.delegate = downloadDelegate
    }
}

private final class AsyncNavigationProbe: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.host == "blocked.example.com" ? .cancel : .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }
}

private final class DownloadProbe: NSObject, WKDownloadDelegate {
    var destinationResponse: URLResponse?
    var suggestedFilename: String?
    var finished = 0
    var failures: [Error] = []

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        destinationResponse = response
        self.suggestedFilename = suggestedFilename
        completionHandler(URL(fileURLWithPath: "/tmp/\(suggestedFilename)"))
    }

    func downloadDidFinish(_ download: WKDownload) {
        finished += 1
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        failures.append(error)
    }
}

private final class UIProbe: NSObject, WKUIDelegate {
    var popupURLs: [URL] = []
    var popupTargetFrames: [WKFrameInfo?] = []

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        _ = webView
        _ = configuration
        _ = windowFeatures
        if let url = navigationAction.request.url {
            popupURLs.append(url)
        }
        popupTargetFrames.append(navigationAction.targetFrame)
        return nil
    }
}

@MainActor
final class OmniWebKitTests: XCTestCase {
    func testPayloadCarriesCommonConfigurationState() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = "OmniKitProbe"
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.javaScriptEnabled = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.minimumFontSize = 14
        configuration.allowsInlineMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: "window.__omniProbe = true;",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let handler = ScriptHandlerProbe()
        configuration.userContentController.add(handler, name: "probeHandler")

        var compiledRuleList: WKContentRuleList?
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "probeRules",
            encodedContentRuleList: #"[]"#
        ) { ruleList, error in
            XCTAssertNil(error)
            compiledRuleList = ruleList
        }
        configuration.userContentController.add(try XCTUnwrap(compiledRuleList))

        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "session",
            .value: "abc123",
            .secure: "TRUE",
            HTTPCookiePropertyKey(rawValue: "HttpOnly"): "TRUE",
        ]))
        await configuration.websiteDataStore.httpCookieStore.setCookie(cookie)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigation = NavigationProbe()
        let ui = UIProbe()
        webView.navigationDelegate = navigation
        webView.uiDelegate = ui
        webView.customUserAgent = "ProbeBrowser/1.0"
        webView.pageZoom = 1.35
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        webView.appearance = NSAppearance(named: .darkAqua)
        webView.loadHTMLString("<!doctype html><p>Probe</p>", baseURL: URL(string: "https://example.com/article")!)

        let payload = webView._omniWebViewPayload
        XCTAssertEqual(payload.url.absoluteString, "https://example.com/article")
        XCTAssertEqual(payload.userAgentApplicationName, "OmniKitProbe")
        XCTAssertEqual(payload.customUserAgent, "ProbeBrowser/1.0")
        XCTAssertEqual(payload.pageZoom, 1.35)
        XCTAssertTrue(payload.allowsBackForwardNavigationGestures)
        XCTAssertEqual(payload.javaScriptCanOpenWindowsAutomatically, false)
        XCTAssertEqual(payload.javaScriptEnabled, false)
        XCTAssertEqual(payload.minimumFontSize, 14)
        XCTAssertTrue(payload.isInspectable)
        XCTAssertEqual(payload.allowsInlineMediaPlayback, false)
        XCTAssertTrue(payload.mediaPlaybackRequiresUserGesture)
        XCTAssertEqual(payload.userScripts.count, 2)
        XCTAssertTrue(payload.userScripts[0].source.contains("colorScheme = scheme"))
        XCTAssertTrue(payload.userScripts[0].source.contains(#"scheme = "dark""#))
        XCTAssertEqual(payload.userScripts[0].injectionTime, Int32(WKUserScriptInjectionTime.atDocumentStart.rawValue))
        XCTAssertFalse(payload.userScripts[0].forMainFrameOnly)
        XCTAssertEqual(
            payload.userScripts[1],
            _OmniWebViewPayload.UserScript(
                source: "window.__omniProbe = true;",
                injectionTime: Int32(WKUserScriptInjectionTime.atDocumentStart.rawValue),
                forMainFrameOnly: true
            )
        )
        XCTAssertEqual(payload.scriptMessageHandlerNames, ["probeHandler"])
        XCTAssertEqual(payload.contentRules, [
            _OmniWebViewPayload.ContentRule(identifier: "probeRules", encodedRules: #"[]"#)
        ])
        XCTAssertTrue(payload.cookies.contains {
            $0.name == "session" &&
            $0.value == "abc123" &&
            $0.domain == "example.com" &&
            $0.isSecure &&
            $0.isHTTPOnly
        })
        XCTAssertTrue(payload.hasNavigationDelegate)
        XCTAssertTrue(payload.hasUIDelegate)
        XCTAssertEqual(payload.dataStoreIdentifier, "default")
        XCTAssertEqual(payload.accessibilityLabel, "https://example.com/article")
        XCTAssertEqual(payload.accessibilityDescription, "Web content")
        XCTAssertNotNil(payload.scriptDialogCallback)
    }

    func testWebViewAppearanceAddsDocumentStartColorSchemeHint() throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        XCTAssertTrue(webView._omniWebViewPayload.userScripts.isEmpty)

        webView.appearance = NSAppearance(named: .aqua)
        let lightPayload = webView._omniWebViewPayload
        XCTAssertEqual(lightPayload.userScripts.count, 1)
        XCTAssertTrue(lightPayload.userScripts[0].source.contains(#"scheme = "light""#))
        XCTAssertTrue(lightPayload.userScripts[0].source.contains("window.matchMedia"))
        XCTAssertTrue(lightPayload.userScripts[0].source.contains("prefers-color-scheme:dark"))
        XCTAssertTrue(lightPayload.userScripts[0].source.contains("__omniColorSchemeState"))
        XCTAssertTrue(lightPayload.userScripts[0].source.contains("addEventListener(type, listener)"))
        XCTAssertEqual(lightPayload.userScripts[0].injectionTime, Int32(WKUserScriptInjectionTime.atDocumentStart.rawValue))

        webView.appearance = NSAppearance(named: .darkAqua)
        let darkPayload = webView._omniWebViewPayload
        XCTAssertEqual(darkPayload.userScripts.count, 1)
        XCTAssertTrue(darkPayload.userScripts[0].source.contains(#"scheme = "dark""#))
    }

    func testWebViewAppearanceChangeSyncsExistingNativePageColorScheme() throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        webView.appearance = NSAppearance(named: .darkAqua)

        let lastEvaluation = Mirror(reflecting: webView).children
            .first { $0.label == "lastEvaluation" }?
            .value as? String
        XCTAssertTrue(lastEvaluation?.contains(#"scheme = "dark""#) == true)
        XCTAssertTrue(lastEvaluation?.contains("window.matchMedia") == true)
        XCTAssertTrue(lastEvaluation?.contains("document.documentElement.style.colorScheme = scheme") == true)
        XCTAssertTrue(lastEvaluation?.contains("list.dispatchEvent({ type: \"change\"") == true)
    }

    func testWebViewSyncsExistingNativePageWhenInheritedAppearanceChanges() throws {
        let container = NSView()
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        container.addSubview(webView)

        container.appearance = NSAppearance(named: .aqua)

        let lightEvaluation = Mirror(reflecting: webView).children
            .first { $0.label == "lastEvaluation" }?
            .value as? String
        XCTAssertTrue(lightEvaluation?.contains(#"scheme = "light""#) == true)

        container.appearance = NSAppearance(named: .darkAqua)

        let darkEvaluation = Mirror(reflecting: webView).children
            .first { $0.label == "lastEvaluation" }?
            .value as? String
        XCTAssertTrue(darkEvaluation?.contains(#"scheme = "dark""#) == true)
    }

    func testWebViewInheritsLinuxPreferredColorSchemeWhenAppearanceIsNil() throws {
        #if os(Linux)
        NSApp.appearance = nil
        _omniSetPreferredColorScheme(nil)
        defer {
            _omniSetPreferredColorScheme(nil)
            NSApp.appearance = nil
        }

        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        XCTAssertTrue(webView._omniWebViewPayload.userScripts.isEmpty)

        _omniSetPreferredColorScheme(.light)
        let lightPayload = webView._omniWebViewPayload
        XCTAssertEqual(lightPayload.userScripts.count, 1)
        XCTAssertTrue(lightPayload.userScripts[0].source.contains(#"scheme = "light""#))

        _omniSetPreferredColorScheme(.dark)
        let darkPayload = webView._omniWebViewPayload
        XCTAssertEqual(darkPayload.userScripts.count, 1)
        XCTAssertTrue(darkPayload.userScripts[0].source.contains(#"scheme = "dark""#))
        #endif
    }

    func testExistingWebViewSyncsWhenLinuxPreferredColorSchemeChanges() throws {
        #if os(Linux)
        NSApp.appearance = nil
        _omniSetPreferredColorScheme(nil)
        defer {
            _omniSetPreferredColorScheme(nil)
            NSApp.appearance = nil
        }

        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        _omniSetPreferredColorScheme(.light)
        let lightEvaluation = Mirror(reflecting: webView).children
            .first { $0.label == "lastEvaluation" }?
            .value as? String
        XCTAssertTrue(lightEvaluation?.contains(#"scheme = "light""#) == true)

        _omniSetPreferredColorScheme(.dark)
        let darkEvaluation = Mirror(reflecting: webView).children
            .first { $0.label == "lastEvaluation" }?
            .value as? String
        XCTAssertTrue(darkEvaluation?.contains(#"scheme = "dark""#) == true)
        #endif
    }

    func testWebViewInheritsSuperviewEffectiveAppearanceOnLinux() throws {
        #if os(Linux)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        defer { NSApp.appearance = nil }

        let container = NSView()
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        container.addSubview(webView)

        container.appearance = NSAppearance(named: .aqua)
        let lightPayload = webView._omniWebViewPayload
        XCTAssertEqual(lightPayload.userScripts.count, 1)
        XCTAssertTrue(lightPayload.userScripts[0].source.contains(#"scheme = "light""#))

        container.appearance = NSAppearance(named: .darkAqua)
        let darkPayload = webView._omniWebViewPayload
        XCTAssertEqual(darkPayload.userScripts.count, 1)
        XCTAssertTrue(darkPayload.userScripts[0].source.contains(#"scheme = "dark""#))
        #endif
    }

    func testFallbackNavigationAndObservationBehaveLikeWebViewState() throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let navigation = NavigationProbe()
        webView.navigationDelegate = navigation

        var observedURLs: [URL?] = []
        var observedLoadingStates: [Bool] = []
        var observedBackStates: [Bool] = []
        var observedForwardStates: [Bool] = []
        let urlObservation = webView.observe(\.url, options: [.initial, .new]) { view, _ in
            observedURLs.append(view.url)
        }
        let loadingObservation = webView.observe(\.isLoading, options: [.initial, .new]) { view, _ in
            observedLoadingStates.append(view.isLoading)
        }
        let observation = webView.observe(\.canGoBack, options: [.initial, .new]) { view, _ in
            observedBackStates.append(view.canGoBack)
        }
        let forwardObservation = webView.observe(\.canGoForward, options: [.initial, .new]) { view, _ in
            observedForwardStates.append(view.canGoForward)
        }
        defer {
            urlObservation.invalidate()
            loadingObservation.invalidate()
            observation.invalidate()
            forwardObservation.invalidate()
        }

        let first = URL(string: "https://example.com/one")!
        let second = URL(string: "https://example.com/two")!
        XCTAssertNotNil(webView.load(URLRequest(url: first)))
        XCTAssertNotNil(webView.load(URLRequest(url: second)))
        XCTAssertEqual(webView.url, second)
        XCTAssertTrue(webView.canGoBack)
        XCTAssertEqual(webView.canGoForward, false)
        XCTAssertEqual(navigation.starts, 2)
        XCTAssertEqual(navigation.commits, 2)
        XCTAssertEqual(navigation.finishes, 2)
        XCTAssertEqual(navigation.policyDecisions, [first, second])
        XCTAssertEqual(observedURLs.first!, nil)
        XCTAssertTrue(observedURLs.contains(first))
        XCTAssertTrue(observedURLs.contains(second))
        XCTAssertEqual(observedLoadingStates.first, false)
        XCTAssertTrue(observedLoadingStates.contains(true))
        XCTAssertEqual(observedBackStates.first, false)
        XCTAssertTrue(observedBackStates.contains(true))
        XCTAssertEqual(observedForwardStates.first, false)
        XCTAssertFalse(observedForwardStates.contains(true))

        XCTAssertNotNil(webView.goBack())
        XCTAssertEqual(webView.url, first)
        XCTAssertEqual(webView.canGoBack, false)
        XCTAssertTrue(webView.canGoForward)
        XCTAssertTrue(observedForwardStates.contains(true))
        XCTAssertNotNil(webView.goForward())
        XCTAssertEqual(webView.url, second)
        XCTAssertTrue(webView.canGoBack)
        XCTAssertFalse(webView.canGoForward)
    }

    func testDownloadNavigationPolicyBecomesDownloadInsteadOfLoading() throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let navigation = NavigationProbe()
        navigation.nextPolicy = .download
        webView.navigationDelegate = navigation

        let url = URL(string: "https://example.com/archive.zip")!
        XCTAssertNil(webView.load(URLRequest(url: url)))
        XCTAssertNil(webView.url)
        XCTAssertEqual(navigation.policyDecisions, [url])
        XCTAssertEqual(navigation.actionDownloads, 1)
    }

    func testPayloadResponsePolicyCallbackMapsToNavigationResponseDownload() throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let navigation = NavigationProbe()
        navigation.nextResponsePolicy = .download
        webView.navigationDelegate = navigation

        let payload = webView._omniWebViewPayload
        let callback = try XCTUnwrap(payload.responsePolicyCallback)
        let context = try XCTUnwrap(payload.callbackContext)
        let url = "https://example.com/archive.zip"
        let mimeType = "application/zip"
        let suggestedFilename = "archive.zip"

        let policy = url.withCString { urlPointer in
            mimeType.withCString { mimePointer in
                suggestedFilename.withCString { filenamePointer in
                    callback(context, urlPointer, mimePointer, 0, 42, filenamePointer)
                }
            }
        }

        XCTAssertEqual(policy, Int32(WKNavigationResponsePolicy.download.rawValue))
        XCTAssertEqual(navigation.responsePolicyDecisions, [URL(string: url)!])
        XCTAssertEqual(navigation.responseDownloads, 1)
    }

    func testPayloadDownloadDestinationCallbackUsesWKDownloadDelegate() throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let navigation = NavigationProbe()
        let downloadDelegate = DownloadProbe()
        navigation.downloadDelegate = downloadDelegate
        webView.navigationDelegate = navigation

        let payload = webView._omniWebViewPayload
        let callback = try XCTUnwrap(payload.downloadDestinationCallback)
        let context = try XCTUnwrap(payload.callbackContext)
        let url = "https://example.com/file.bin"
        let mimeType = "application/octet-stream"
        let suggestedFilename = "file.bin"

        let destinationPointer = url.withCString { urlPointer in
            mimeType.withCString { mimePointer in
                suggestedFilename.withCString { filenamePointer in
                    callback(context, urlPointer, mimePointer, 512, filenamePointer)
                }
            }
        }
        defer { free(destinationPointer) }

        let destination = try XCTUnwrap(destinationPointer.map { String(cString: $0) })
        XCTAssertEqual(destination, "/tmp/file.bin")
        XCTAssertEqual(navigation.responseDownloads, 1)
        XCTAssertEqual(downloadDelegate.suggestedFilename, "file.bin")
        XCTAssertEqual(downloadDelegate.destinationResponse?.url, URL(string: url))
    }

    func testPayloadPolicyCallbackRoutesNewWindowsToUIDelegate() throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let ui = UIProbe()
        webView.uiDelegate = ui

        let payload = webView._omniWebViewPayload
        let callback = try XCTUnwrap(payload.policyCallback)
        let context = try XCTUnwrap(payload.callbackContext)
        let url = "https://example.com/popup"

        let policy = url.withCString { urlPointer in
            callback(context, urlPointer, Int32(WKNavigationType.linkActivated.rawValue), 1)
        }

        XCTAssertEqual(policy, 0)
        XCTAssertEqual(ui.popupURLs, [URL(string: url)!])
        XCTAssertEqual(ui.popupTargetFrames.count, 1)
        XCTAssertNil(ui.popupTargetFrames.first!)
    }

    func testModernAsyncPolicyAndDownloadDelegateAPIsMatchWebKitShape() async throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let navigation = AsyncNavigationProbe()
        let allowed = await navigation.webView(
            webView,
            decidePolicyFor: WKNavigationAction(request: URLRequest(url: URL(string: "https://example.com")!))
        )
        let blocked = await navigation.webView(
            webView,
            decidePolicyFor: WKNavigationAction(request: URLRequest(url: URL(string: "https://blocked.example.com")!))
        )
        let responsePolicy = await navigation.webView(
            webView,
            decidePolicyFor: WKNavigationResponse(
                response: URLResponse(url: URL(string: "https://example.com/file.bin")!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil),
                canShowMIMEType: false
            )
        )

        XCTAssertEqual(allowed, .allow)
        XCTAssertEqual(blocked, .cancel)
        XCTAssertEqual(responsePolicy, .download)

        let download = WKDownload()
        let delegate = DownloadProbe()
        download.delegate = delegate
        let response = URLResponse(url: URL(string: "https://example.com/file.bin")!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        var destination: URL?
        download.delegate?.download(download, decideDestinationUsing: response, suggestedFilename: "file.bin") { url in
            destination = url
        }
        download.delegate?.downloadDidFinish(download)
        let error = NSError(domain: "OmniWebKitTests", code: 7)
        download.delegate?.download(download, didFailWithError: error, resumeData: nil)

        XCTAssertEqual(destination?.lastPathComponent, "file.bin")
        XCTAssertEqual(delegate.destinationResponse, response)
        XCTAssertEqual(delegate.suggestedFilename, "file.bin")
        XCTAssertEqual(delegate.finished, 1)
        XCTAssertEqual((delegate.failures.first as NSError?)?.code, 7)
    }

    func testUserContentControllerCanRemoveAllMessageHandlers() {
        let controller = WKUserContentController()
        let handler = ScriptHandlerProbe()
        controller.add(handler, name: "one")
        controller.add(handler, name: "two")
        XCTAssertEqual(controller.scriptMessageHandlerNames, ["one", "two"])

        controller.removeAllScriptMessageHandlers()
        XCTAssertTrue(controller.scriptMessageHandlerNames.isEmpty)
    }

    func testUserContentControllerRetainsScriptMessageHandlersLikeWebKit() throws {
        let controller = WKUserContentController()
        weak var weakHandler: ScriptHandlerProbe?

        do {
            let handler = ScriptHandlerProbe()
            weakHandler = handler
            controller.add(handler, name: "bridge")
        }

        var retainedHandler: ScriptHandlerProbe? = try XCTUnwrap(weakHandler)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let payload = webView._omniWebViewPayload
        let callback = try XCTUnwrap(payload.messageCallback)
        let context = try XCTUnwrap(payload.callbackContext)
        "bridge".withCString { namePointer in
            "\"ping\"".withCString { bodyPointer in
                callback(context, namePointer, bodyPointer)
            }
        }
        XCTAssertEqual(retainedHandler?.messages.count, 1)

        controller.removeScriptMessageHandler(forName: "bridge")
        retainedHandler = nil
        XCTAssertNil(weakHandler)
    }

    func testPayloadMessageCallbackDecodesDictionaryBodies() throws {
        let configuration = WKWebViewConfiguration()
        let handler = ScriptHandlerProbe()
        let received = expectation(description: "script message delivered")
        handler.onMessage = { message in
            guard message.name == "bridge",
                  let body = message.body as? [String: Any],
                  body["type"] as? String == "save",
                  body["content"] as? String == "# Probe",
                  body["count"] as? Int == 3,
                  body["enabled"] as? Bool == true
            else {
                XCTFail("Unexpected script message body: \(message.body)")
                return
            }
            received.fulfill()
        }
        configuration.userContentController.add(handler, name: "bridge")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let payload = webView._omniWebViewPayload
        let callback = try XCTUnwrap(payload.messageCallback)
        let context = try XCTUnwrap(payload.callbackContext)
        let body = ##"{"type":"save","content":"# Probe","count":3,"enabled":true}"##

        "bridge".withCString { namePointer in
            body.withCString { bodyPointer in
                callback(context, namePointer, bodyPointer)
            }
        }

        wait(for: [received], timeout: 1)
        XCTAssertEqual(handler.messages.count, 1)
        XCTAssertTrue(handler.messages.first?.webView === webView)
    }

    func testPayloadMessageCallbackDecodesPrimitiveBodies() throws {
        let configuration = WKWebViewConfiguration()
        let handler = ScriptHandlerProbe()
        let received = expectation(description: "primitive script messages delivered")
        handler.onMessage = { _ in
            guard handler.messages.count == 3 else { return }
            XCTAssertEqual(handler.messages[0].body as? Double, 0.625)
            XCTAssertEqual(handler.messages[1].body as? Bool, true)
            XCTAssertEqual(handler.messages[2].body as? String, "ready")
            received.fulfill()
        }
        configuration.userContentController.add(handler, name: "bridge")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let payload = webView._omniWebViewPayload
        let callback = try XCTUnwrap(payload.messageCallback)
        let context = try XCTUnwrap(payload.callbackContext)

        for body in ["0.625", "true", #""ready""#] {
            "bridge".withCString { namePointer in
                body.withCString { bodyPointer in
                    callback(context, namePointer, bodyPointer)
                }
            }
        }

        wait(for: [received], timeout: 1)
    }

    func testPayloadMessageCallbackDecodesCommandDictionaryStream() throws {
        let configuration = WKWebViewConfiguration()
        let handler = ScriptHandlerProbe()
        configuration.userContentController.add(handler, name: "bridge")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let payload = webView._omniWebViewPayload
        let callback = try XCTUnwrap(payload.messageCallback)
        let context = try XCTUnwrap(payload.callbackContext)
        let messages = [
            ##"{"type":"save","content":"# Title\n\nBody with \"quotes\"","path":"/tmp/notes.md"}"##,
            ##"{"type":"open"}"##,
            ##"{"type":"new"}"##,
            ##"{"type":"back"}"##,
            ##"{"type":"fwd"}"##,
            ##"{"type":"mode","mode":"mp"}"##,
            ##"{"type":"focus"}"##,
        ]

        for body in messages {
            "bridge".withCString { namePointer in
                body.withCString { bodyPointer in
                    callback(context, namePointer, bodyPointer)
                }
            }
        }

        XCTAssertEqual(handler.messages.count, messages.count)
        XCTAssertTrue(handler.messages.allSatisfy { $0.name == "bridge" && $0.webView === webView })
        let bodies = handler.messages.compactMap { $0.body as? [String: Any] }
        XCTAssertEqual(bodies.compactMap { $0["type"] as? String }, ["save", "open", "new", "back", "fwd", "mode", "focus"])
        XCTAssertEqual(bodies.first?["content"] as? String, "# Title\n\nBody with \"quotes\"")
        XCTAssertEqual(bodies.first?["path"] as? String, "/tmp/notes.md")
        XCTAssertEqual(bodies.first { $0["type"] as? String == "mode" }?["mode"] as? String, "mp")
    }

    func testNonPersistentDataStoresHaveDistinctIdentity() {
        let first = WKWebsiteDataStore.nonPersistent()
        let second = WKWebsiteDataStore.nonPersistent()

        XCTAssertEqual(first.isPersistent, false)
        XCTAssertEqual(second.isPersistent, false)
        XCTAssertNotEqual(first.identifier, second.identifier)
        XCTAssertTrue(WKWebsiteDataStore.default().isPersistent)
    }
}
