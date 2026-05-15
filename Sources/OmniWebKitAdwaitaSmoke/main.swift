import Foundation
import Glibc
import OmniUIAdwaita
import OmniWebKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class WebKitSmokeProbe: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate, @unchecked Sendable {
    static let shared = WebKitSmokeProbe()

    private let lock = NSLock()
    weak var webView: WKWebView?
    var didStart = false
    var didCommit = false
    var didFinish = false
    var receivedMessage: WKScriptMessage?
    var policyURLs: [URL] = []
    var policyTypes: [WKNavigationType] = []
    var loadError: Error?
    var evaluationDescription: String?
    var evaluationError: Error?
    private var retainedSmokeWebView: WKWebView?
    private var verifierStarted = false

    func installLaunchWatchdog() {
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(20)) { [weak self] in
            guard let self else { return }
            let snapshot = self.stateSnapshot()
            if snapshot.evaluationDescription == nil {
                self.fail("watchdog timeout webView=\(snapshot.webView != nil) start=\(snapshot.didStart) commit=\(snapshot.didCommit) finish=\(snapshot.didFinish) message=\(snapshot.hasMessage) error=\(String(describing: snapshot.loadError))")
            }
        }
    }

    func makeWebView(retainForSmoke: Bool = false, startVerifier: Bool = true) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = "OmniWebKitAdwaitaSmoke"
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        if let cookie = HTTPCookie(properties: [
            .domain: "example.test",
            .path: "/",
            .name: "omniSmokeCookie",
            .value: "cookie-ok",
        ]) {
            configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        }
        configuration.userContentController.add(self, name: "omniSmoke")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: "window.__omniStart = true; document.documentElement.dataset.omniStart = 'true';",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: """
                document.body.dataset.smoke = 'ready';
                window.webkit.messageHandlers.omniSmoke.postMessage({
                  ready: true,
                  title: document.title,
                  marker: window.__omniStart === true,
                  cookie: document.cookie,
                  count: 42
                });
                """,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = "OmniWebKitAdwaitaSmoke/1.0"
        webView.pageZoom = 1.1
        webView.isInspectable = true
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <head>
                <meta charset="utf-8">
                <title>OmniWebKit Smoke</title>
                <style>
                  body { font: 16px sans-serif; color-scheme: light dark; }
                  button { padding: 6px 10px; }
                </style>
              </head>
              <body>
                <main>
                  <h1>OmniWebKit Smoke</h1>
                  <button id="action">Action</button>
                  <a id="navlink" href="https://example.test/omni-webkit-clicked">Clicked link</a>
                  <p id="status">Waiting</p>
                </main>
              </body>
            </html>
            """,
            baseURL: URL(string: "https://example.test/omni-webkit-smoke")!
        )
        lock.lock()
        self.webView = webView
        if retainForSmoke {
            retainedSmokeWebView = webView
        }
        let shouldStartVerifier = startVerifier && !verifierStarted
        if startVerifier {
            verifierStarted = true
        }
        lock.unlock()
        if shouldStartVerifier {
            Task { await self.runVerifier() }
        }
        return webView
    }

    func runHeadlessSmoke() -> Never {
        let webView = makeWebView(retainForSmoke: true, startVerifier: false)
        let payload = webView._omniWebViewPayload
        guard payload.customUserAgent == "OmniWebKitAdwaitaSmoke/1.0",
              payload.userAgentApplicationName == "OmniWebKitAdwaitaSmoke",
              payload.javaScriptEnabled,
              payload.pageZoom > 1,
              payload.hasNavigationDelegate,
              payload.hasUIDelegate,
              payload.scriptMessageHandlerNames.contains("omniSmoke"),
              payload.userScripts.count >= 2,
              payload.cookies.contains(where: { $0.name == "omniSmokeCookie" && $0.value == "cookie-ok" }),
              payload.messageCallback != nil,
              payload.navigationCallback != nil,
              payload.policyCallback != nil,
              payload.callbackContext != nil
        else {
            fail("payload shape incomplete handlers=\(payload.scriptMessageHandlerNames) scripts=\(payload.userScripts.count) cookies=\(payload.cookies.map(\.name))")
        }

        let context = payload.callbackContext
        "https://example.test/omni-webkit-smoke".withCString { url in
            payload.navigationCallback?(context, 0, url, nil)
            payload.navigationCallback?(context, 4, url, nil)
            payload.navigationCallback?(context, 1, url, nil)
        }
        "omniSmoke".withCString { name in
            #"{"ready":true,"title":"OmniWebKit Smoke","marker":true,"cookie":"omniSmokeCookie=cookie-ok","count":42}"#.withCString { body in
                payload.messageCallback?(context, name, body)
            }
        }
        let policyDecision = "https://example.test/omni-webkit-clicked".withCString { url in
            payload.policyCallback?(context, url, Int32(WKNavigationType.linkActivated.rawValue), 0)
        }
        recordEvaluation(
            value: [
                "title": "OmniWebKit Smoke",
                "marker": true,
                "smoke": "ready",
                "cookie": "omniSmokeCookie=cookie-ok",
            ],
            error: nil
        )

        for _ in 0..<20 {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        let snapshot = stateSnapshot()
        guard policyDecision == Int32(WKNavigationActionPolicy.cancel.rawValue) else {
            fail("policy callback returned \(String(describing: policyDecision))")
        }
        guard snapshot.didStart, snapshot.didCommit, snapshot.didFinish else {
            fail("headless navigation callbacks incomplete start=\(snapshot.didStart) commit=\(snapshot.didCommit) finish=\(snapshot.didFinish)")
        }
        guard snapshot.messageName == "omniSmoke",
              let messageBody = snapshot.messageBody,
              messageBody.contains("ready"),
              messageBody.contains("marker"),
              messageBody.contains("omniSmokeCookie")
        else {
            fail("headless script message missing or undecoded: \(snapshot.messageBody ?? "<nil>")")
        }
        guard snapshot.policyURLs.contains(URL(string: "https://example.test/omni-webkit-clicked")!),
              snapshot.policyTypes.contains(.linkActivated) else {
            fail("headless policy dispatch missing urls=\(snapshot.policyURLs.map(\.absoluteString)) types=\(snapshot.policyTypes)")
        }
        guard let evaluationDescription = snapshot.evaluationDescription,
              evaluationDescription.contains("marker"),
              evaluationDescription.contains("smoke"),
              evaluationDescription.contains("omniSmokeCookie") else {
            fail("headless evaluation marker missing: \(snapshot.evaluationDescription ?? "<nil>")")
        }

        print("OMNIWEBKIT_SMOKE_PASS mode=headless url=\(snapshot.url ?? "<nil>") message=\(snapshot.messageBody ?? "<nil>") policies=\(snapshot.policyCount)")
        exit(0)
    }

    func startVerifierIfNeeded() {
        lock.lock()
        let shouldStartVerifier = !verifierStarted
        verifierStarted = true
        lock.unlock()
        guard shouldStartVerifier else { return }
        Task { await runVerifier() }
    }

    func runVerifier() async {
        for _ in 0..<120 {
            let snapshot = stateSnapshot()
            if snapshot.didFinish, snapshot.hasMessage, let webView = snapshot.webView {
                webView.evaluateJavaScript(
                    "document.getElementById('navlink').click(); ({ title: document.title, marker: window.__omniStart === true, smoke: document.body.dataset.smoke, cookie: document.cookie, zoom: window.visualViewport ? window.visualViewport.scale : 1 })"
                ) { [weak self] value, error in
                    self?.recordEvaluation(value: value, error: error)
                }
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        for _ in 0..<60 {
            let snapshot = stateSnapshot()
            if let evaluationError = snapshot.evaluationError {
                fail("evaluateJavaScript failed: \(evaluationError)")
            }
            if let evaluationDescription = snapshot.evaluationDescription {
                guard snapshot.didStart, snapshot.didCommit else {
                    fail("navigation callbacks incomplete start=\(snapshot.didStart) commit=\(snapshot.didCommit) finish=\(snapshot.didFinish)")
                }
                guard snapshot.messageName == "omniSmoke" else {
                    fail("script message missing")
                }
                guard let messageBody = snapshot.messageBody, messageBody.contains("ready"), messageBody.contains("marker"), messageBody.contains("omniSmokeCookie") else {
                    fail("script message payload was not decoded: \(snapshot.messageBody ?? "<nil>")")
                }
                guard evaluationDescription.contains("marker"), evaluationDescription.contains("smoke"), evaluationDescription.contains("ready"), evaluationDescription.contains("omniSmokeCookie") else {
                    fail("evaluateJavaScript payload was not decoded: \(evaluationDescription)")
                }
                guard snapshot.policyURLs.contains(URL(string: "https://example.test/omni-webkit-clicked")!),
                      snapshot.policyTypes.contains(.linkActivated) else {
                    fail("link navigation policy did not report linkActivated: urls=\(snapshot.policyURLs.map(\.absoluteString)) types=\(snapshot.policyTypes)")
                }
                print("OMNIWEBKIT_SMOKE_PASS title=\(snapshot.title ?? "<nil>") url=\(snapshot.url ?? "<nil>") message=\(snapshot.messageBody ?? "<nil>") eval=\(evaluationDescription) policies=\(snapshot.policyCount)")
                exit(0)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let snapshot = stateSnapshot()
        fail("timeout start=\(snapshot.didStart) commit=\(snapshot.didCommit) finish=\(snapshot.didFinish) message=\(snapshot.hasMessage) error=\(String(describing: snapshot.loadError))")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        lock.lock()
        defer { lock.unlock() }
        receivedMessage = message
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        lock.lock()
        defer { lock.unlock() }
        didStart = true
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        lock.lock()
        defer { lock.unlock() }
        didCommit = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lock.lock()
        defer { lock.unlock() }
        didFinish = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        lock.lock()
        defer { lock.unlock() }
        loadError = error
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        lock.lock()
        defer { lock.unlock() }
        loadError = error
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        if let url = navigationAction.request.url {
            policyURLs.append(url)
        }
        policyTypes.append(navigationAction.navigationType)
        if navigationAction.request.url == URL(string: "https://example.test/omni-webkit-clicked") {
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    private func recordEvaluation(value: Any?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        evaluationDescription = value.map { String(describing: $0) }
        evaluationError = error
    }

    private func stateSnapshot() -> (
        webView: WKWebView?,
        didStart: Bool,
        didCommit: Bool,
        didFinish: Bool,
        hasMessage: Bool,
        messageName: String?,
        messageBody: String?,
        policyCount: Int,
        policyURLs: [URL],
        policyTypes: [WKNavigationType],
        title: String?,
        url: String?,
        loadError: Error?,
        evaluationDescription: String?,
        evaluationError: Error?
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (
            webView,
            didStart,
            didCommit,
            didFinish,
            receivedMessage != nil,
            receivedMessage?.name,
            receivedMessage.map { String(describing: $0.body) },
            policyURLs.count,
            policyURLs,
            policyTypes,
            webView?.title,
            webView?.url?.absoluteString,
            loadError,
            evaluationDescription,
            evaluationError
        )
    }

    private func fail(_ message: String) -> Never {
        print("OMNIWEBKIT_SMOKE_FAIL \(message)")
        exit(2)
    }
}

private struct WebKitSmokeView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        WebKitSmokeProbe.shared.makeWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private struct WebKitSmokeContent: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("OmniWebKit Adwaita Smoke")
            WebKitSmokeView()
                .frame(minWidth: 640, minHeight: 420)
        }
        .padding(12)
        .task {
            WebKitSmokeProbe.shared.startVerifierIfNeeded()
        }
    }
}

@main
enum OmniWebKitAdwaitaSmokeMain {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments.contains("--smoke") {
            WebKitSmokeProbe.shared.runHeadlessSmoke()
        }
        WebKitSmokeProbe.shared.installLaunchWatchdog()
        try await AdwaitaApp(
            appID: "dev.omnikit.OmniWebKitAdwaitaSmoke",
            title: "OmniWebKit Adwaita Smoke",
            size: _Size(width: 760, height: 560)
        ) {
            WebKitSmokeContent()
        }.run()
    }
}
