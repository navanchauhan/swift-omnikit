import Foundation
import OmniUICore
import OmniWebKit
import XCTest

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class ScriptHandlerProbe: NSObject, WKScriptMessageHandler {
    var messages: [WKScriptMessage] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        messages.append(message)
    }
}

private final class NavigationProbe: NSObject, WKNavigationDelegate {
    var starts = 0
    var finishes = 0
    var commits = 0
    var policyDecisions: [URL] = []

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
        decisionHandler(.allow)
    }
}

private final class UIProbe: NSObject, WKUIDelegate {}

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
        XCTAssertEqual(payload.userScripts, [
            _OmniWebViewPayload.UserScript(
                source: "window.__omniProbe = true;",
                injectionTime: Int32(WKUserScriptInjectionTime.atDocumentStart.rawValue),
                forMainFrameOnly: true
            )
        ])
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

    func testFallbackNavigationAndObservationBehaveLikeWebViewState() throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let navigation = NavigationProbe()
        webView.navigationDelegate = navigation

        var observedBackStates: [Bool] = []
        let observation = webView.observe(\.canGoBack, options: [.initial, .new]) { view, _ in
            observedBackStates.append(view.canGoBack)
        }
        defer { observation.invalidate() }

        let first = URL(string: "https://example.com/one")!
        let second = URL(string: "https://example.com/two")!
        XCTAssertNotNil(webView.load(URLRequest(url: first)))
        XCTAssertNotNil(webView.load(URLRequest(url: second)))
        XCTAssertEqual(webView.url, second)
        XCTAssertTrue(webView.canGoBack)
        XCTAssertEqual(webView.canGoForward, false)
        XCTAssertEqual(navigation.starts, 2)
        XCTAssertEqual(navigation.finishes, 2)
        XCTAssertEqual(navigation.policyDecisions, [first, second])
        XCTAssertEqual(observedBackStates.first, false)
        XCTAssertTrue(observedBackStates.contains(true))

        XCTAssertNotNil(webView.goBack())
        XCTAssertEqual(webView.url, first)
        XCTAssertEqual(webView.canGoBack, false)
        XCTAssertTrue(webView.canGoForward)
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

    func testNonPersistentDataStoresHaveDistinctIdentity() {
        let first = WKWebsiteDataStore.nonPersistent()
        let second = WKWebsiteDataStore.nonPersistent()

        XCTAssertEqual(first.isPersistent, false)
        XCTAssertEqual(second.isPersistent, false)
        XCTAssertNotEqual(first.identifier, second.identifier)
        XCTAssertTrue(WKWebsiteDataStore.default().isPersistent)
    }
}
