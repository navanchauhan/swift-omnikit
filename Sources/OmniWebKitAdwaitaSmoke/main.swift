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
    var loadError: Error?
    var evaluationDescription: String?
    var evaluationError: Error?

    func makeWebView() -> WKWebView {
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
                  <p id="status">Waiting</p>
                </main>
              </body>
            </html>
            """,
            baseURL: URL(string: "https://example.test/omni-webkit-smoke")!
        )
        lock.lock()
        self.webView = webView
        lock.unlock()
        return webView
    }

    func runVerifier() async {
        for _ in 0..<120 {
            let snapshot = stateSnapshot()
            if snapshot.didFinish, snapshot.hasMessage, let webView = snapshot.webView {
                webView.evaluateJavaScript(
                        "({ title: document.title, marker: window.__omniStart === true, smoke: document.body.dataset.smoke, cookie: document.cookie, zoom: window.visualViewport ? window.visualViewport.scale : 1 })"
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
        decisionHandler(.allow)
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
            await WebKitSmokeProbe.shared.runVerifier()
        }
    }
}

@main
struct OmniWebKitAdwaitaSmokeApp: App {
    var body: some Scene {
        WindowGroup {
            WebKitSmokeContent()
        }
        .defaultSize(width: 760, height: 560)
    }
}
