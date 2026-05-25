import Dispatch
import Foundation
import OmniUICore
#if canImport(AppKit) && !os(Linux)
import AppKit
import CoreGraphics
#endif
#if os(Linux) || os(macOS)
import CAdwaita
#endif
#if os(Linux)
import Glibc
#endif
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif

private final class _OmniLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private final class _OmniPolicyBox<Policy>: @unchecked Sendable {
    private let lock = NSLock()
    private var policy: Policy?

    func set(_ policy: Policy) {
        lock.lock()
        self.policy = policy
        lock.unlock()
    }

    func get(default defaultPolicy: Policy) -> Policy {
        lock.lock()
        defer { lock.unlock() }
        return policy ?? defaultPolicy
    }
}

private final class _OmniAsyncPolicyRunner<Policy>: @unchecked Sendable {
    private let operation: () async -> Policy

    init(_ operation: @escaping () async -> Policy) {
        self.operation = operation
    }

    func run() async -> Policy {
        await operation()
    }
}

#if os(Linux)
public final class NSKeyValueObservation {
    private let onInvalidate: () -> Void
    private var isInvalidated = false

    init(_ onInvalidate: @escaping () -> Void = {}) {
        self.onInvalidate = onInvalidate
    }

    public func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        onInvalidate()
    }

    deinit {
        invalidate()
    }
}

public struct NSKeyValueObservingOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let initial = NSKeyValueObservingOptions(rawValue: 1 << 0)
    public static let new = NSKeyValueObservingOptions(rawValue: 1 << 1)
}

public struct NSKeyValueObservedChange<Value> {
    public let newValue: Value?
}
#endif

public final class WKNavigation: NSObject, @unchecked Sendable {}
public final class WKWindowFeatures: NSObject, @unchecked Sendable {}
public final class WKFrameInfo: NSObject, @unchecked Sendable {
    public let isMainFrame: Bool
    public let request: URLRequest

    public init(isMainFrame: Bool = true, request: URLRequest = URLRequest(url: URL(string: "about:blank")!)) {
        self.isMainFrame = isMainFrame
        self.request = request
        super.init()
    }
}

public enum WKNavigationActionPolicy: Int, Sendable {
    case cancel = 0
    case allow = 1
    case download = 2
}

public enum WKNavigationResponsePolicy: Int, Sendable {
    case cancel = 0
    case allow = 1
    case download = 2
}

public final class WKNavigationResponse: NSObject, @unchecked Sendable {
    public let response: URLResponse
    public var canShowMIMEType: Bool

    public init(
        response: URLResponse = URLResponse(
            url: URL(string: "about:blank")!,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        ),
        canShowMIMEType: Bool = true
    ) {
        self.response = response
        self.canShowMIMEType = canShowMIMEType
        super.init()
    }
}

public protocol WKDownloadDelegate: AnyObject {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    )

    func downloadDidFinish(_ download: WKDownload)

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?)
}

public extension WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        completionHandler(nil)
    }

    func downloadDidFinish(_ download: WKDownload) {}

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {}
}

public final class WKDownload: NSObject, @unchecked Sendable {
    public weak var delegate: WKDownloadDelegate?
}

public enum WKNavigationType: Int, Sendable {
    case linkActivated = 0
    case formSubmitted = 1
    case backForward = 2
    case reload = 3
    case formResubmitted = 4
    case other = -1
}

public final class WKNavigationAction: NSObject, @unchecked Sendable {
    public let request: URLRequest
    public let navigationType: WKNavigationType
    public let sourceFrame: WKFrameInfo
    public let targetFrame: WKFrameInfo?
    public let shouldPerformDownload: Bool

    public init(
        request: URLRequest,
        navigationType: WKNavigationType = .other,
        sourceFrame: WKFrameInfo = WKFrameInfo(),
        targetFrame: WKFrameInfo? = WKFrameInfo(),
        shouldPerformDownload: Bool = false
    ) {
        self.request = request
        self.navigationType = navigationType
        self.sourceFrame = sourceFrame
        self.targetFrame = targetFrame
        self.shouldPerformDownload = shouldPerformDownload
        super.init()
    }
}

public final class WKScriptMessage: NSObject, @unchecked Sendable {
    public let name: String
    public let body: Any
    public weak var webView: WKWebView?

    public init(name: String, body: Any, webView: WKWebView?) {
        self.name = name
        self.body = body
        self.webView = webView
        super.init()
    }
}

public protocol WKScriptMessageHandler: AnyObject {
    @MainActor
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage)
}

public protocol WKNavigationDelegate: AnyObject {
    @MainActor
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!)
    @MainActor
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!)
    @MainActor
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!)
    @MainActor
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!)
    @MainActor
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error)
    @MainActor
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error)
    @MainActor
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView)
    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void)
    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy
    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void)
    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload)
}

public extension WKNavigationDelegate {
    @MainActor
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {}
    @MainActor
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {}
    @MainActor
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {}
    @MainActor
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
    @MainActor
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {}
    @MainActor
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
    @MainActor
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {}
    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        await withCheckedContinuation { continuation in
            self.webView(webView, decidePolicyFor: navigationAction) { policy in
                continuation.resume(returning: policy)
            }
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.allow)
    }

    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        await withCheckedContinuation { continuation in
            self.webView(webView, decidePolicyFor: navigationResponse) { policy in
                continuation.resume(returning: policy)
            }
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {}
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {}
}

public protocol WKUIDelegate: AnyObject {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView?
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void)
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void)
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void)
}

public extension WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        completionHandler(nil)
    }
}

public final class WKPreferences: NSObject, @unchecked Sendable {
    private struct WebViewBox {
        weak var webView: WKWebView?
    }

    private var webViews: [ObjectIdentifier: WebViewBox] = [:]

    public var javaScriptCanOpenWindowsAutomatically: Bool = true {
        didSet {
            forAttachedWebViews { $0.syncNativePopupPolicy() }
        }
    }

    public var javaScriptEnabled: Bool = true {
        didSet {
            forAttachedWebViews { $0.syncNativeJavaScriptEnabled() }
        }
    }

    public var minimumFontSize: CGFloat = 0 {
        didSet {
            forAttachedWebViews { $0.syncNativeMinimumFontSize() }
        }
    }

    public var isFraudulentWebsiteWarningEnabled: Bool = true

    func attach(_ webView: WKWebView) {
        webViews[ObjectIdentifier(webView)] = WebViewBox(webView: webView)
    }

    func detach(_ webView: WKWebView) {
        webViews.removeValue(forKey: ObjectIdentifier(webView))
    }

    private func forAttachedWebViews(_ body: (WKWebView) -> Void) {
        for (id, box) in webViews {
            guard let webView = box.webView else {
                webViews.removeValue(forKey: id)
                continue
            }
            body(webView)
        }
    }
}

public final class WKProcessPool: NSObject, @unchecked Sendable {}

public struct WKAudiovisualMediaTypes: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let audio = WKAudiovisualMediaTypes(rawValue: 1 << 0)
    public static let video = WKAudiovisualMediaTypes(rawValue: 1 << 1)
    public static let all: WKAudiovisualMediaTypes = [.audio, .video]
}

public final class WKWebpagePreferences: NSObject, @unchecked Sendable {
    public var allowsContentJavaScript: Bool = true
}

public enum WKUserScriptInjectionTime: Int, Sendable {
    case atDocumentStart = 0
    case atDocumentEnd = 1
}

public final class WKUserScript: NSObject, @unchecked Sendable {
    public let source: String
    public let injectionTime: WKUserScriptInjectionTime
    public let isForMainFrameOnly: Bool

    public init(source: String, injectionTime: WKUserScriptInjectionTime, forMainFrameOnly: Bool) {
        self.source = source
        self.injectionTime = injectionTime
        self.isForMainFrameOnly = forMainFrameOnly
        super.init()
    }
}

public final class WKContentRuleList: NSObject, @unchecked Sendable {
    public let identifier: String
    public let encodedContentRuleList: String

    init(identifier: String, encodedContentRuleList: String) {
        self.identifier = identifier
        self.encodedContentRuleList = encodedContentRuleList
        super.init()
    }
}

public final class WKContentRuleListStore: NSObject, @unchecked Sendable {
    public static func `default`() -> WKContentRuleListStore {
        WKContentRuleListStore()
    }

    public func compileContentRuleList(
        forIdentifier identifier: String,
        encodedContentRuleList: String,
        completionHandler: @escaping (WKContentRuleList?, Error?) -> Void
    ) {
        completionHandler(WKContentRuleList(identifier: identifier, encodedContentRuleList: encodedContentRuleList), nil)
    }
}

public final class WKUserContentController: NSObject, @unchecked Sendable {
    private struct HandlerBox {
        var handler: WKScriptMessageHandler
    }

    private struct WebViewBox {
        weak var webView: WKWebView?
    }

    private var handlers: [String: HandlerBox] = [:]
    private var scripts: [WKUserScript] = []
    private var ruleLists: [WKContentRuleList] = []
    private var webViews: [ObjectIdentifier: WebViewBox] = [:]

    public var userScripts: [WKUserScript] { scripts }
    public var scriptMessageHandlerNames: [String] { Array(handlers.keys).sorted() }
    public var contentRuleLists: [WKContentRuleList] { ruleLists }

    public func addUserScript(_ userScript: WKUserScript) {
        scripts.append(userScript)
        forAttachedWebViews { $0.installNative(userScript: userScript) }
    }

    public func removeAllUserScripts() {
        scripts.removeAll()
        forAttachedWebViews { $0.removeAllNativeUserScripts() }
    }

    public func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
        handlers[name] = HandlerBox(handler: scriptMessageHandler)
        forAttachedWebViews { $0.registerNativeMessageHandler(name: name) }
    }

    public func removeScriptMessageHandler(forName name: String) {
        handlers.removeValue(forKey: name)
        forAttachedWebViews { $0.unregisterNativeMessageHandler(name: name) }
    }

    public func removeAllScriptMessageHandlers() {
        let names = Array(handlers.keys)
        handlers.removeAll()
        for name in names {
            forAttachedWebViews { $0.unregisterNativeMessageHandler(name: name) }
        }
    }

    public func add(_ contentRuleList: WKContentRuleList) {
        ruleLists.append(contentRuleList)
        forAttachedWebViews { $0.installNative(contentRuleList: contentRuleList) }
    }

    public func removeAllContentRuleLists() {
        ruleLists.removeAll()
        forAttachedWebViews { $0.removeAllNativeContentRules() }
    }

    @MainActor
    func dispatch(name: String, body: Any, webView: WKWebView) {
        guard let handler = handlers[name]?.handler else { return }
        handler.userContentController(self, didReceive: WKScriptMessage(name: name, body: body, webView: webView))
    }

    func attach(_ webView: WKWebView) {
        webViews[ObjectIdentifier(webView)] = WebViewBox(webView: webView)
    }

    func detach(_ webView: WKWebView) {
        webViews.removeValue(forKey: ObjectIdentifier(webView))
    }

    private func forAttachedWebViews(_ body: (WKWebView) -> Void) {
        for (id, box) in webViews {
            guard let webView = box.webView else {
                webViews.removeValue(forKey: id)
                continue
            }
            body(webView)
        }
    }
}

public final class WKHTTPCookieStore: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: HTTPCookie] = [:]

    public func setCookie(_ cookie: HTTPCookie) async {
        setCookie(cookie) {}
    }

    public func setCookie(_ cookie: HTTPCookie, completionHandler: (() -> Void)? = nil) {
        lock.lock()
        storage[key(for: cookie)] = cookie
        lock.unlock()
        HTTPCookieStorage.shared.setCookie(cookie)
        syncNativeSet(cookie)
        completionHandler?()
    }

    public func deleteCookie(_ cookie: HTTPCookie) async {
        delete(cookie)
    }

    public func delete(_ cookie: HTTPCookie, completionHandler: (() -> Void)? = nil) {
        lock.lock()
        storage.removeValue(forKey: key(for: cookie))
        lock.unlock()
        HTTPCookieStorage.shared.deleteCookie(cookie)
        syncNativeDelete(cookie)
        completionHandler?()
    }

    public func allCookies() async -> [HTTPCookie] {
        cookieSnapshot()
    }

    public func getAllCookies(_ completionHandler: @escaping ([HTTPCookie]) -> Void) {
        completionHandler(cookieSnapshot())
    }

    func cookieSnapshot() -> [HTTPCookie] {
        lock.lock()
        var cookies = Array(storage.values)
        lock.unlock()
        if let shared = HTTPCookieStorage.shared.cookies {
            for cookie in shared where !cookies.contains(where: { key(for: $0) == key(for: cookie) }) {
                cookies.append(cookie)
            }
        }
        return cookies
    }

    func mergeNativeCookies(_ cookies: [HTTPCookie]) {
        lock.lock()
        for cookie in cookies {
            storage[key(for: cookie)] = cookie
        }
        lock.unlock()
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func key(for cookie: HTTPCookie) -> String {
        "\(cookie.domain)\u{1f}\(cookie.path)\u{1f}\(cookie.name)"
    }

    private func syncNativeSet(_ cookie: HTTPCookie) {
        #if os(Linux)
        withNativeCookie(cookie) { name, value, domain, path, expiresAt, secure, httpOnly in
            _ = omni_adw_web_cookie_store_set(name, value, domain, path, expiresAt, secure, httpOnly)
        }
        #endif
    }

    private func syncNativeDelete(_ cookie: HTTPCookie) {
        #if os(Linux)
        withNativeCookie(cookie) { name, value, domain, path, expiresAt, secure, httpOnly in
            _ = omni_adw_web_cookie_store_delete(name, value, domain, path, expiresAt, secure, httpOnly)
        }
        #endif
    }

    #if os(Linux)
    private func withNativeCookie<R>(
        _ cookie: HTTPCookie,
        _ body: (
            UnsafePointer<CChar>,
            UnsafePointer<CChar>,
            UnsafePointer<CChar>,
            UnsafePointer<CChar>,
            Double,
            Int32,
            Int32
        ) -> R
    ) -> R {
        cookie.name.withCString { name in
            cookie.value.withCString { value in
                cookie.domain.withCString { domain in
                    cookie.path.withCString { path in
                        body(
                            name,
                            value,
                            domain,
                            path,
                            cookie.expiresDate?.timeIntervalSince1970 ?? -1,
                            cookie.isSecure ? 1 : 0,
                            cookie.isHTTPOnly ? 1 : 0
                        )
                    }
                }
            }
        }
    }
    #endif
}

public final class WKWebsiteDataStore: NSObject, @unchecked Sendable {
    private static let defaultStore = WKWebsiteDataStore(identifier: "default")
    private static let nonPersistentCounter = _OmniLockedCounter()

    public let httpCookieStore = WKHTTPCookieStore()
    public let identifier: String
    public let isPersistent: Bool

    private init(identifier: String, isPersistent: Bool = true) {
        self.identifier = identifier
        self.isPersistent = isPersistent
        super.init()
    }

    public static func `default`() -> WKWebsiteDataStore {
        defaultStore
    }

    public static func defaultDataStore() -> WKWebsiteDataStore {
        defaultStore
    }

    public static func nonPersistent() -> WKWebsiteDataStore {
        WKWebsiteDataStore(identifier: "nonPersistent-\(nonPersistentCounter.next())", isPersistent: false)
    }
}

public final class WKWebViewConfiguration: NSObject, @unchecked Sendable {
    public var processPool = WKProcessPool()
    public var preferences = WKPreferences()
    public var defaultWebpagePreferences = WKWebpagePreferences()
    public var userContentController = WKUserContentController()
    public var websiteDataStore = WKWebsiteDataStore.default()
    public var applicationNameForUserAgent: String?
    public var limitsNavigationsToAppBoundDomains: Bool = false
    public var allowsInlineMediaPlayback: Bool = true
    public var mediaTypesRequiringUserActionForPlayback: WKAudiovisualMediaTypes = []
}

public final class WKWebView: NSView, @preconcurrency _OmniWebViewPayloadProviding, @preconcurrency _OmniNativeRepresentableDismantleAware, @unchecked Sendable {
    public typealias JavaScriptCompletion = (Any?, Error?) -> Void

    private final class EvaluationBox: @unchecked Sendable {
        let completion: JavaScriptCompletion

        init(completion: @escaping JavaScriptCompletion) {
            self.completion = completion
        }
    }

    public let configuration: WKWebViewConfiguration
    public weak var navigationDelegate: WKNavigationDelegate?
    public weak var uiDelegate: WKUIDelegate?
    public var allowsBackForwardNavigationGestures: Bool = false {
        didSet {
            #if os(Linux) || os(macOS)
            withNativeIdentity { identity in
                identity.withCString {
                    _ = omni_adw_web_view_set_allows_back_forward_navigation_gestures($0, allowsBackForwardNavigationGestures ? 1 : 0)
                }
            }
            #endif
            invalidatePayload()
        }
    }
    public var allowsMagnification: Bool = false
    public var allowsLinkPreview: Bool = true
    public var isInspectable: Bool = false {
        didSet {
            syncNativeInspectable()
            invalidatePayload()
        }
    }
    public var customUserAgent: String? {
        didSet {
            syncNativeUserAgent()
            invalidatePayload()
        }
    }
    public override var appearance: NSAppearance? {
        get { super.appearance }
        set {
            super.appearance = newValue
            syncNativeAppearance()
            invalidatePayload()
        }
    }

    public var underPageBackgroundColor: NSColor?

    public private(set) var url: URL?
    public private(set) var isLoading: Bool = false
    public private(set) var canGoBack: Bool = false
    public private(set) var canGoForward: Bool = false
    public private(set) var title: String?
    public private(set) var estimatedProgress: Double = 0

    public var pageZoom: CGFloat = 1 {
        didSet {
            #if os(Linux) || os(macOS)
            withNativeIdentity { identity in
                identity.withCString { _ = omni_adw_web_view_set_zoom($0, Double(pageZoom)) }
            }
            #endif
            invalidatePayload()
        }
    }

    private var loadState: _OmniWebViewPayload.Load = .url(URL(string: "about:blank")!)
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var observers: [UUID: (WKWebView) -> Void] = [:]
    private var lastEvaluation: String?
    private var requestHeaders: [String: String] = [:]
    private var preflightedPolicyURL: URL?
    private var nativeRepresentableIsDismantling = false
    #if os(Linux)
    private var appearanceObservation: _OmniAppearanceChangeObservation?
    #endif

    public init(frame: CGRect = .zero, configuration: WKWebViewConfiguration) {
        self.configuration = configuration
        super.init(frame: frame)
        configuration.userContentController.attach(self)
        configuration.preferences.attach(self)
        observeApplicationAppearance()
    }

    public required init?(coder: NSCoder) {
        self.configuration = WKWebViewConfiguration()
        super.init(coder: coder)
        configuration.userContentController.attach(self)
        configuration.preferences.attach(self)
        observeApplicationAppearance()
    }

    deinit {
        _omniBeginNativeRepresentableDismantle()
        #if os(Linux)
        appearanceObservation?.invalidate()
        #endif
        configuration.userContentController.detach(self)
        configuration.preferences.detach(self)
    }

    public func _omniBeginNativeRepresentableDismantle() {
        guard !nativeRepresentableIsDismantling else { return }
        let identity = nativeIdentity
        nativeRepresentableIsDismantling = true
        _OmniWebViewRegistry.remove(stableIdentity: identity)
        #if os(Linux) || os(macOS)
        identity.withCString { _ = omni_adw_web_view_unregister($0) }
        #endif
    }

    private func observeApplicationAppearance() {
        #if os(Linux)
        appearanceObservation = _omniAddAppearanceChangeHandler { [weak self] _ in
            guard let self else { return }
            self.syncNativeAppearance()
            self.invalidatePayload()
        }
        #endif
    }

    private func decidePolicy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        Self.awaitMainActorValue(default: .allow) { [self, action] in
            guard let navigationDelegate else { return .allow }
            var policy = WKNavigationActionPolicy.allow
            navigationDelegate.webView(self, decidePolicyFor: action) { policy = $0 }
            return policy
        }
    }

    private func decidePolicy(for response: WKNavigationResponse) -> WKNavigationResponsePolicy {
        Self.awaitMainActorValue(default: .allow) { [self, response] in
            guard let navigationDelegate else { return .allow }
            var policy = WKNavigationResponsePolicy.allow
            navigationDelegate.webView(self, decidePolicyFor: response) { policy = $0 }
            return policy
        }
    }

    private func becomeDownload(for action: WKNavigationAction) {
        let download = WKDownload()
        navigationDelegate?.webView(self, navigationAction: action, didBecome: download)
    }

    private func becomeDownload(for response: WKNavigationResponse) {
        let download = WKDownload()
        navigationDelegate?.webView(self, navigationResponse: response, didBecome: download)
    }

    private func decideDownloadDestination(for response: WKNavigationResponse, suggestedFilename: String) -> URL? {
        let download = WKDownload()
        navigationDelegate?.webView(self, navigationResponse: response, didBecome: download)
        guard let delegate = download.delegate else { return nil }
        var destination: URL?
        delegate.download(download, decideDestinationUsing: response.response, suggestedFilename: suggestedFilename) { url in
            destination = url
        }
        return destination
    }

    private static func awaitMainActorValue<Policy: Sendable>(
        default defaultPolicy: Policy,
        timeout: DispatchTime = .now() + .seconds(2),
        operation: @escaping @MainActor @Sendable () -> Policy
    ) -> Policy {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                operation()
            }
        }

        let box = _OmniPolicyBox<Policy>()
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            let policy = operation()
            box.set(policy)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: timeout) == .success else {
            return defaultPolicy
        }
        return box.get(default: defaultPolicy)
    }

    @discardableResult
    public func load(_ request: URLRequest) -> WKNavigation? {
        guard let requestURL = request.url else { return nil }
        let action = WKNavigationAction(request: request, navigationType: .other)
        switch decidePolicy(for: action) {
        case .allow:
            break
        case .download:
            becomeDownload(for: action)
            return nil
        case .cancel:
            return nil
        }
        preflightedPolicyURL = requestURL
        if let current = url, current != requestURL {
            backStack.append(current)
            forwardStack.removeAll()
        }
        url = requestURL
        requestHeaders = request.allHTTPHeaderFields ?? [:]
        loadState = .url(requestURL)
        let navigation = WKNavigation()
        if nativeRepresentableIsDismantling {
            return navigation
        }
        #if os(Linux) || os(macOS)
        let handedToNative = withNativeIdentity { identity in
            identity.withCString { identityPointer in
                requestURL.absoluteString.withCString { urlPointer in
                    if requestHeaders.isEmpty {
                        return omni_adw_web_view_load_uri(identityPointer, urlPointer) != 0
                    }
                    let names = requestHeaders.keys.sorted()
                    let values = names.map { requestHeaders[$0] ?? "" }
                    return withCStringArray(names) { namePointers in
                        withCStringArray(values) { valuePointers in
                            omni_adw_web_view_load_request(
                                identityPointer,
                                urlPointer,
                                namePointers.baseAddress,
                                valuePointers.baseAddress,
                                Int32(names.count)
                            ) != 0
                        }
                    }
                }
            }
        } ?? false
        if handedToNative {
            updateBackForward()
            notifyObservers()
            invalidatePayload()
            return navigation
        }
        updateBackForward()
        notifyObservers()
        invalidatePayload()
        return navigation
        #else
        begin(navigation: navigation)
        commit(navigation: navigation)
        finish(navigation: navigation)
        invalidatePayload()
        return navigation
        #endif
    }

    @discardableResult
    public func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        url = baseURL
        requestHeaders = [:]
        loadState = .html(string, baseURL: baseURL)
        let navigation = WKNavigation()
        if nativeRepresentableIsDismantling {
            return navigation
        }
        #if os(Linux) || os(macOS)
        let handedToNative = withNativeIdentity { identity in
            string.withCString { htmlPointer in
                withOptionalCString(baseURL?.absoluteString) { baseURLPointer in
                    identity.withCString { identityPointer in
                        omni_adw_web_view_load_html(identityPointer, htmlPointer, baseURLPointer) != 0
                    }
                }
            }
        } ?? false
        if handedToNative {
            updateBackForward()
            notifyObservers()
            invalidatePayload()
            return navigation
        }
        updateBackForward()
        notifyObservers()
        invalidatePayload()
        return navigation
        #else
        begin(navigation: navigation)
        commit(navigation: navigation)
        finish(navigation: navigation)
        invalidatePayload()
        return navigation
        #endif
    }

    public func evaluateJavaScript(_ javaScriptString: String, completionHandler: JavaScriptCompletion? = nil) {
        lastEvaluation = javaScriptString
        #if os(Linux) || os(macOS)
        if withNativeIdentity({ identity in
            let context: UnsafeMutableRawPointer?
            let callback: omni_adw_web_evaluate_callback?
            if let completionHandler {
                let box = EvaluationBox(completion: completionHandler)
                context = Unmanaged.passRetained(box).toOpaque()
                callback = WKWebView.evaluateCallback
            } else {
                context = nil
                callback = nil
            }

            let accepted = javaScriptString.withCString { scriptPointer in
                identity.withCString { identityPointer in
                    omni_adw_web_view_evaluate_javascript(identityPointer, scriptPointer, callback, context) != 0
                }
            }
            if !accepted, let context {
                Unmanaged<EvaluationBox>.fromOpaque(context).release()
            }
            return accepted
        }) == true {
            return
        }
        #endif
        completionHandler?(nil, nil)
    }

    public func evaluateJavaScript(_ javaScriptString: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(javaScriptString) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    nonisolated(unsafe) let unsafeResult = result
                    continuation.resume(returning: unsafeResult)
                }
            }
        }
    }

    @discardableResult
    public func goBack() -> WKNavigation? {
        #if os(Linux) || os(macOS)
        if withNativeIdentity({ identity in
            identity.withCString { omni_adw_web_view_go_back($0) != 0 }
        }) == true {
            refreshNativeBackForwardState()
            return WKNavigation()
        }
        #endif
        guard let previous = backStack.popLast() else { return nil }
        if let current = url { forwardStack.append(current) }
        return navigateHistory(to: previous)
    }

    @discardableResult
    public func goForward() -> WKNavigation? {
        #if os(Linux) || os(macOS)
        if withNativeIdentity({ identity in
            identity.withCString { omni_adw_web_view_go_forward($0) != 0 }
        }) == true {
            refreshNativeBackForwardState()
            return WKNavigation()
        }
        #endif
        guard let next = forwardStack.popLast() else { return nil }
        if let current = url { backStack.append(current) }
        return navigateHistory(to: next)
    }

    @discardableResult
    public func reload() -> WKNavigation? {
        #if os(Linux) || os(macOS)
        if withNativeIdentity({ identity in
            identity.withCString { omni_adw_web_view_reload($0) != 0 }
        }) == true {
            return WKNavigation()
        }
        #endif
        guard let url else { return nil }
        return navigateHistory(to: url)
    }

    public func stopLoading() {
        #if os(Linux) || os(macOS)
        _ = withNativeIdentity { identity in
            identity.withCString { omni_adw_web_view_stop_loading($0) != 0 }
        }
        #endif
        isLoading = false
        notifyObservers()
    }

    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        #if os(Linux) || os(macOS)
        return withNativeIdentity { identity in
            identity.withCString { omni_adw_web_view_focus($0) != 0 }
        } ?? false
        #else
        return false
        #endif
    }

    @discardableResult
    public func scrollBy(deltaX: Double = 0, deltaY: Double) -> Bool {
        #if os(Linux) || os(macOS)
        return withNativeIdentity { identity in
            identity.withCString { omni_adw_web_view_scroll_by($0, deltaX, deltaY) != 0 }
        } ?? false
        #else
        _ = deltaX
        _ = deltaY
        return false
        #endif
    }

    @discardableResult
    public func scrollPage(direction: Int32) -> Bool {
        #if os(Linux) || os(macOS)
        return withNativeIdentity { identity in
            identity.withCString { omni_adw_web_view_scroll_page($0, direction) != 0 }
        } ?? false
        #else
        _ = direction
        return false
        #endif
    }

    public func observe<Value>(
        _ keyPath: KeyPath<WKWebView, Value>,
        options: NSKeyValueObservingOptions = [],
        changeHandler: @escaping (WKWebView, NSKeyValueObservedChange<Value>) -> Void
    ) -> NSKeyValueObservation {
#if os(Linux)
        let id = UUID()
        observers[id] = { webView in
            changeHandler(webView, NSKeyValueObservedChange(newValue: webView[keyPath: keyPath]))
        }
        if options.contains(.initial) {
            changeHandler(self, NSKeyValueObservedChange(newValue: self[keyPath: keyPath]))
        }
        return NSKeyValueObservation { [weak self] in
            self?.observers.removeValue(forKey: id)
        }
#else
        _ = keyPath
        _ = options
        _ = changeHandler
        let sentinel = NSObject()
        return sentinel.observe(\.description, options: []) { _, _ in }
#endif
    }

    public var _omniWebViewPayload: _OmniWebViewPayload {
        _OmniWebViewPayload(
            load: loadState,
            fallbackText: "Web content\n\((url ?? URL(string: "about:blank")!).absoluteString)",
            stableIdentity: nativeIdentity,
            userAgentApplicationName: configuration.applicationNameForUserAgent,
            customUserAgent: customUserAgent,
            pageZoom: Double(pageZoom),
            allowsBackForwardNavigationGestures: allowsBackForwardNavigationGestures,
            javaScriptCanOpenWindowsAutomatically: configuration.preferences.javaScriptCanOpenWindowsAutomatically,
            javaScriptEnabled: configuration.preferences.javaScriptEnabled && configuration.defaultWebpagePreferences.allowsContentJavaScript,
            minimumFontSize: Double(configuration.preferences.minimumFontSize),
            isInspectable: isInspectable,
            allowsInlineMediaPlayback: configuration.allowsInlineMediaPlayback,
            mediaPlaybackRequiresUserGesture: !configuration.mediaTypesRequiringUserActionForPlayback.isEmpty,
            userScripts: appearanceUserScripts + configuration.userContentController.userScripts.map {
                _OmniWebViewPayload.UserScript(
                    source: $0.source,
                    injectionTime: Int32($0.injectionTime.rawValue),
                    forMainFrameOnly: $0.isForMainFrameOnly
                )
            },
            scriptMessageHandlerNames: configuration.userContentController.scriptMessageHandlerNames,
            contentRules: configuration.userContentController.contentRuleLists.map {
                _OmniWebViewPayload.ContentRule(identifier: $0.identifier, encodedRules: $0.encodedContentRuleList)
            },
            cookies: configuration.websiteDataStore.httpCookieStore.cookieSnapshot().map {
                _OmniWebViewPayload.Cookie(
                    name: $0.name,
                    value: $0.value,
                    domain: $0.domain,
                    path: $0.path,
                    expiresAt: $0.expiresDate?.timeIntervalSince1970,
                    isSecure: $0.isSecure,
                    isHTTPOnly: $0.isHTTPOnly
                )
            },
            requestHeaders: requestHeaders.sorted(by: { $0.key < $1.key }).map {
                _OmniWebViewPayload.Header(name: $0.key, value: $0.value)
            },
            hasNavigationDelegate: navigationDelegate != nil,
            hasUIDelegate: uiDelegate != nil,
            dataStoreIdentifier: configuration.websiteDataStore.identifier,
            accessibilityLabel: url?.absoluteString,
            accessibilityDescription: "Web content",
            swiftObject: nil,
            messageCallback: WKWebView.messageCallback,
            navigationCallback: WKWebView.navigationCallback,
            policyCallback: WKWebView.policyCallback,
            responsePolicyCallback: WKWebView.responsePolicyCallback,
            downloadDestinationCallback: WKWebView.downloadDestinationCallback,
            titleCallback: WKWebView.titleCallback,
            progressCallback: WKWebView.progressCallback,
            cookieCallback: WKWebView.cookieCallback,
            scriptDialogCallback: WKWebView.scriptDialogCallback,
            callbackContext: Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private var appearanceUserScripts: [_OmniWebViewPayload.UserScript] {
        guard let scheme = webAppearanceColorScheme else { return [] }
        return [
            _OmniWebViewPayload.UserScript(
                source: Self.webAppearanceScript(for: scheme),
                injectionTime: Int32(WKUserScriptInjectionTime.atDocumentStart.rawValue),
                forMainFrameOnly: false
            )
        ]
    }

    private static func webAppearanceScript(for scheme: ColorScheme) -> String {
        let escapedScheme = scheme == .light ? "light" : "dark"
        return """
        (() => {
          const scheme = "\(escapedScheme)";
          const state = window.__omniColorSchemeState || {
            originalMatchMedia: window.matchMedia ? window.matchMedia.bind(window) : null,
            lists: [],
            scheme: null
          };
          window.__omniColorSchemeState = state;
          const matchesSchemeQuery = (query) => {
            const text = String(query || "");
            const normalized = text.replace(/\\s+/g, "").toLowerCase();
            return normalized === "(prefers-color-scheme:dark)" || normalized === "(prefers-color-scheme:light)";
          };
          const queryMatches = (query) => String(query || "").replace(/\\s+/g, "").toLowerCase().includes(state.scheme);
          const updateList = (list) => {
            const next = queryMatches(list.media);
            const changed = list.matches !== next;
            list.matches = next;
            return changed;
          };
          if (!state.installed) {
            window.matchMedia = (query) => {
              const text = String(query || "");
              if (matchesSchemeQuery(text)) {
                const listeners = new Set();
                const list = {
                  matches: false,
                  media: text,
                  onchange: null,
                  addListener(listener) { if (listener) listeners.add(listener); },
                  removeListener(listener) { listeners.delete(listener); },
                  addEventListener(type, listener) { if (type === "change" && listener) listeners.add(listener); },
                  removeEventListener(type, listener) { if (type === "change") listeners.delete(listener); },
                  dispatchEvent(event) {
                    listeners.forEach((listener) => {
                      if (typeof listener === "function") listener.call(list, event);
                      else if (listener && typeof listener.handleEvent === "function") listener.handleEvent(event);
                    });
                    if (typeof list.onchange === "function") list.onchange.call(list, event);
                    return true;
                  }
                };
                state.lists.push(list);
                updateList(list);
                return list;
              }
              return state.originalMatchMedia ? state.originalMatchMedia(text) : {
                matches: false,
                media: text,
                onchange: null,
                addListener() {},
                removeListener() {},
                addEventListener() {},
                removeEventListener() {},
                dispatchEvent() { return false; }
              };
            };
            state.installed = true;
          }
          const previousScheme = state.scheme;
          state.scheme = scheme;
          const apply = () => {
            if (document.documentElement) document.documentElement.style.colorScheme = scheme;
            if (document.body) document.body.style.colorScheme = scheme;
            state.lists.forEach((list) => {
              if (updateList(list) && previousScheme !== null) {
                list.dispatchEvent({ type: "change", matches: list.matches, media: list.media });
              }
            });
          };
          apply();
          if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", apply, { once: true });
        })();
        """
    }

    private var webAppearanceColorScheme: ColorScheme? {
        #if os(Linux)
        let resolved = effectiveAppearance
        if resolved.name == .aqua { return .light }
        if resolved.name == .darkAqua { return .dark }
        return _omniCurrentAppearanceColorScheme()
        #else
        if let appearance {
            if appearance.name == .aqua { return .light }
            if appearance.name == .darkAqua { return .dark }
            return nil
        }
        return nil
        #endif
    }

    private func begin(navigation: WKNavigation) {
        isLoading = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            navigationDelegate?.webView(self, didStartProvisionalNavigation: navigation)
        }
        notifyObservers()
    }

    private func commit(navigation: WKNavigation) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            navigationDelegate?.webView(self, didCommit: navigation)
        }
        notifyObservers()
    }

    private func finish(navigation: WKNavigation) {
        isLoading = false
        updateBackForward()
        Task { @MainActor [weak self] in
            guard let self else { return }
            navigationDelegate?.webView(self, didFinish: navigation)
        }
        notifyObservers()
    }

    private func updateBackForward() {
        canGoBack = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
    }

    @discardableResult
    private func navigateHistory(to destination: URL) -> WKNavigation? {
        url = destination
        loadState = .url(destination)
        let navigation = WKNavigation()
        begin(navigation: navigation)
        finish(navigation: navigation)
        invalidatePayload()
        return navigation
    }

    private var nativeIdentity: String {
        ObjectIdentifier(self).debugDescription
    }

    private func withNativeIdentity<Result>(_ body: (String) -> Result) -> Result? {
        guard !nativeRepresentableIsDismantling else { return nil }
        return body(nativeIdentity)
    }

    private func withOptionalCString<Result>(_ value: String?, _ body: (UnsafePointer<CChar>?) -> Result) -> Result {
        guard let value else { return body(nil) }
        return value.withCString(body)
    }

    private func withCStringArray<Result>(_ values: [String], _ body: (UnsafeMutableBufferPointer<UnsafePointer<CChar>?>) -> Result) -> Result {
        var pointers: [UnsafePointer<CChar>?] = Array(repeating: nil, count: values.count)

        func recurse(_ index: Int) -> Result {
            if index == values.count {
                return pointers.withUnsafeMutableBufferPointer { buffer in
                    body(buffer)
                }
            }
            return values[index].withCString { pointer in
                pointers[index] = pointer
                return recurse(index + 1)
            }
        }

        return recurse(0)
    }

    private func refreshNativeBackForwardState() {
        #if os(Linux) || os(macOS)
        withNativeIdentity { identity in
            identity.withCString { identityPointer in
                canGoBack = omni_adw_web_view_can_go_back(identityPointer) != 0
                canGoForward = omni_adw_web_view_can_go_forward(identityPointer) != 0
            }
        }
        notifyObservers()
        #else
        updateBackForward()
        #endif
    }

    fileprivate func syncNativeAppearance() {
        #if os(Linux) || os(macOS)
        guard let scheme = webAppearanceColorScheme else { return }
        evaluateJavaScript(Self.webAppearanceScript(for: scheme))
        #endif
    }

    fileprivate func syncNativeUserAgent() {
        #if os(Linux) || os(macOS)
        withNativeIdentity { identity in
            identity.withCString { identityPointer in
                withOptionalCString(configuration.applicationNameForUserAgent) { applicationNamePointer in
                    withOptionalCString(customUserAgent) { customUserAgentPointer in
                        _ = omni_adw_web_view_set_user_agent(identityPointer, applicationNamePointer, customUserAgentPointer)
                    }
                }
            }
        }
        #endif
    }

    fileprivate func syncNativePopupPolicy() {
        #if os(Linux) || os(macOS)
        withNativeIdentity { identity in
            identity.withCString {
                _ = omni_adw_web_view_set_javascript_can_open_windows(
                    $0,
                    configuration.preferences.javaScriptCanOpenWindowsAutomatically ? 1 : 0
                )
            }
        }
        #endif
    }

    fileprivate func syncNativeJavaScriptEnabled() {
        #if os(Linux) || os(macOS)
        withNativeIdentity { identity in
            identity.withCString {
                _ = omni_adw_web_view_set_javascript_enabled($0, configuration.preferences.javaScriptEnabled ? 1 : 0)
            }
        }
        #endif
    }

    fileprivate func syncNativeMinimumFontSize() {
        #if os(Linux) || os(macOS)
        withNativeIdentity { identity in
            identity.withCString {
                _ = omni_adw_web_view_set_minimum_font_size($0, Double(configuration.preferences.minimumFontSize))
            }
        }
        #endif
    }

    fileprivate func syncNativeInspectable() {
        #if os(Linux) || os(macOS)
        withNativeIdentity { identity in
            identity.withCString {
                _ = omni_adw_web_view_set_inspectable($0, isInspectable ? 1 : 0)
            }
        }
        #endif
    }

    fileprivate func installNative(userScript: WKUserScript) {
        #if os(Linux) || os(macOS)
        withNativeIdentity { identity in
            identity.withCString { identityPointer in
                userScript.source.withCString { sourcePointer in
                    _ = omni_adw_web_view_add_user_script(
                        identityPointer,
                        sourcePointer,
                        Int32(userScript.injectionTime.rawValue),
                        userScript.isForMainFrameOnly ? 1 : 0
                    )
                }
            }
        }
        #endif
    }

    fileprivate func removeAllNativeUserScripts() {
        #if os(Linux) || os(macOS)
        withNativeIdentity { identity in
            identity.withCString { _ = omni_adw_web_view_remove_all_user_scripts($0) }
        }
        #endif
    }

    fileprivate func registerNativeMessageHandler(name: String) {
        #if os(Linux) || os(macOS)
        withNativeIdentity { identity in
            identity.withCString { identityPointer in
                name.withCString { namePointer in
                    _ = omni_adw_web_view_register_message_handler(identityPointer, namePointer)
                }
            }
        }
        #endif
    }

    fileprivate func unregisterNativeMessageHandler(name: String) {
        #if os(Linux) || os(macOS)
        withNativeIdentity { identity in
            identity.withCString { identityPointer in
                name.withCString { namePointer in
                    _ = omni_adw_web_view_unregister_message_handler(identityPointer, namePointer)
                }
            }
        }
        #endif
    }

    fileprivate func installNative(contentRuleList: WKContentRuleList) {
        #if os(Linux) || os(macOS)
        withNativeIdentity { identity in
            identity.withCString { identityPointer in
                contentRuleList.identifier.withCString { identifierPointer in
                    contentRuleList.encodedContentRuleList.withCString { sourcePointer in
                        _ = omni_adw_web_view_add_content_rule(identityPointer, identifierPointer, sourcePointer)
                    }
                }
            }
        }
        #endif
    }

    fileprivate func removeAllNativeContentRules() {
        #if os(Linux) || os(macOS)
        withNativeIdentity { identity in
            identity.withCString { _ = omni_adw_web_view_remove_all_content_rules($0) }
        }
        #endif
    }

    private func notifyObservers() {
        for observer in observers.values {
            observer(self)
        }
    }

    private func invalidatePayload() {}

    private static let messageCallback: _OmniWebViewPayload.MessageCallback = { context, namePointer, bodyPointer in
        guard let context, let namePointer else { return }
        let webView = Unmanaged<WKWebView>.fromOpaque(context).takeUnretainedValue()
        let name = String(cString: namePointer)
        let bodyString = bodyPointer.map { String(cString: $0) } ?? "null"
        let body = decodeJavaScriptBody(bodyString)
        Task { @MainActor in
            webView.configuration.userContentController.dispatch(name: name, body: body, webView: webView)
        }
    }

    #if os(Linux) || os(macOS)
    private static let evaluateCallback: omni_adw_web_evaluate_callback = { context, bodyPointer, errorPointer in
        guard let context else { return }
        let box = Unmanaged<EvaluationBox>.fromOpaque(context).takeRetainedValue()
        let bodyString = bodyPointer.map { String(cString: $0) } ?? "null"
        let errorString = errorPointer.map { String(cString: $0) }
        let result = decodeJavaScriptBody(bodyString)
        DispatchQueue.main.async {
            if let errorString {
                box.completion(nil, NSError(domain: "OmniWebKit.JavaScript", code: 1, userInfo: [NSLocalizedDescriptionKey: errorString]))
            } else {
                box.completion(result, nil)
            }
        }
    }
    #endif

    private static let navigationCallback: _OmniWebViewPayload.NavigationCallback = { context, event, urlPointer, errorPointer in
        guard let context else { return }
        let webView = Unmanaged<WKWebView>.fromOpaque(context).takeUnretainedValue()
        let url = urlPointer.map { URL(string: String(cString: $0)) } ?? nil
        let error = errorPointer.map { String(cString: $0) }
        Task { @MainActor in
            if ProcessInfo.processInfo.environment["OMNI_WEBKITGTK_TRACE"] == "1" {
                print("OMNIWEBKIT_NAV event=\(event) url=\(url?.absoluteString ?? "") error=\(error ?? "")")
            }
            if let url { webView.url = url }
            webView.refreshNativeBackForwardState()
            let navigation = WKNavigation()
            switch event {
            case 0:
                webView.isLoading = true
                webView.estimatedProgress = 0
                webView.navigationDelegate?.webView(webView, didStartProvisionalNavigation: navigation)
            case 1:
                webView.isLoading = false
                webView.estimatedProgress = 1
                webView.navigationDelegate?.webView(webView, didFinish: navigation)
            case 2:
                webView.isLoading = false
                webView.estimatedProgress = 1
                let nsError = NSError(domain: "OmniWebKit", code: 1, userInfo: [NSLocalizedDescriptionKey: error ?? "Web view load failed"])
                webView.navigationDelegate?.webView(webView, didFail: navigation, withError: nsError)
            case 3:
                break
            case 4:
                webView.navigationDelegate?.webView(webView, didCommit: navigation)
            default:
                break
            }
            webView.refreshNativeBackForwardState()
        }
    }

    private static let policyCallback: _OmniWebViewPayload.PolicyCallback = { context, urlPointer, navigationTypeRaw, isNewWindow in
        guard let context, let urlPointer, let url = URL(string: String(cString: urlPointer)) else {
            return 1
        }
        let webView = Unmanaged<WKWebView>.fromOpaque(context).takeUnretainedValue()
        let navigationType = WKNavigationType(rawValue: Int(navigationTypeRaw)) ?? .other
        let targetFrame: WKFrameInfo? = isNewWindow != 0 ? nil : WKFrameInfo()
        let action = WKNavigationAction(request: URLRequest(url: url), navigationType: navigationType, targetFrame: targetFrame)

        if navigationType == .other, webView.preflightedPolicyURL == url {
            webView.preflightedPolicyURL = nil
            return 1
        }

        if isNewWindow != 0, let uiDelegate = webView.uiDelegate {
            _ = uiDelegate.webView(webView, createWebViewWith: webView.configuration, for: action, windowFeatures: WKWindowFeatures())
            return 0
        }

        switch webView.decidePolicy(for: action) {
        case .allow:
            return 1
        case .download:
            webView.becomeDownload(for: action)
            return 0
        case .cancel:
            return 0
        }
    }

    private static let responsePolicyCallback: _OmniWebViewPayload.ResponsePolicyCallback = { context, urlPointer, mimeTypePointer, canShowMIMEType, expectedContentLength, suggestedFilenamePointer in
        guard let context, let urlPointer, let url = URL(string: String(cString: urlPointer)) else {
            return Int32(WKNavigationResponsePolicy.allow.rawValue)
        }
        let webView = Unmanaged<WKWebView>.fromOpaque(context).takeUnretainedValue()
        let mimeType = mimeTypePointer.map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        _ = suggestedFilenamePointer.map { String(cString: $0) }
        let response = WKNavigationResponse(
            response: URLResponse(
                url: url,
                mimeType: mimeType,
                expectedContentLength: Int(expectedContentLength),
                textEncodingName: nil
            ),
            canShowMIMEType: canShowMIMEType != 0
        )

        let policy = webView.decidePolicy(for: response)
        if policy == .download {
            webView.becomeDownload(for: response)
        }
        return Int32(policy.rawValue)
    }

    private static let downloadDestinationCallback: _OmniWebViewPayload.DownloadDestinationCallback = { context, urlPointer, mimeTypePointer, expectedContentLength, suggestedFilenamePointer in
        guard let context, let urlPointer, let url = URL(string: String(cString: urlPointer)) else {
            return nil
        }
        let webView = Unmanaged<WKWebView>.fromOpaque(context).takeUnretainedValue()
        let mimeType = mimeTypePointer.map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        let suggestedFilename = suggestedFilenamePointer.map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 }
            ?? url.lastPathComponent
        let response = WKNavigationResponse(
            response: URLResponse(
                url: url,
                mimeType: mimeType,
                expectedContentLength: Int(expectedContentLength),
                textEncodingName: nil
            ),
            canShowMIMEType: false
        )
        guard let destination = webView.decideDownloadDestination(for: response, suggestedFilename: suggestedFilename) else {
            return nil
        }
        return strdup(destination.isFileURL ? destination.path : destination.absoluteString)
    }

    private static let titleCallback: _OmniWebViewPayload.TitleCallback = { context, titlePointer in
        guard let context else { return }
        let webView = Unmanaged<WKWebView>.fromOpaque(context).takeUnretainedValue()
        let title = titlePointer.map { String(cString: $0) }
        DispatchQueue.main.async {
            webView.title = title?.isEmpty == true ? nil : title
            webView.notifyObservers()
        }
    }

    private static let progressCallback: _OmniWebViewPayload.ProgressCallback = { context, progress in
        guard let context else { return }
        let webView = Unmanaged<WKWebView>.fromOpaque(context).takeUnretainedValue()
        DispatchQueue.main.async {
            webView.estimatedProgress = min(max(progress, 0), 1)
            webView.notifyObservers()
        }
    }

    private static let cookieCallback: _OmniWebViewPayload.CookieCallback = { context, names, values, domains, paths, expiresAt, secure, httpOnly, count in
        guard let context, count > 0 else { return }
        let webView = Unmanaged<WKWebView>.fromOpaque(context).takeUnretainedValue()
        var cookies: [HTTPCookie] = []
        cookies.reserveCapacity(Int(count))

        for index in 0..<Int(count) {
            guard
                let name = string(at: index, in: names),
                let value = string(at: index, in: values),
                let domain = string(at: index, in: domains),
                let path = string(at: index, in: paths)
            else {
                continue
            }

            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: path.isEmpty ? "/" : path
            ]
            if let expires = expiresAt?.advanced(by: index).pointee, expires > 0 {
                properties[.expires] = Date(timeIntervalSince1970: expires)
            }
            if secure?.advanced(by: index).pointee != 0 {
                properties[.secure] = "TRUE"
            }
            if httpOnly?.advanced(by: index).pointee != 0 {
                properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
            }
            if let cookie = HTTPCookie(properties: properties) {
                cookies.append(cookie)
            }
        }

        guard !cookies.isEmpty else { return }
        DispatchQueue.main.async {
            webView.configuration.websiteDataStore.httpCookieStore.mergeNativeCookies(cookies)
        }
    }

    private static let scriptDialogCallback: _OmniWebViewPayload.ScriptDialogCallback = { context, dialogType, messagePointer, defaultTextPointer, handledPointer, confirmedPointer in
        handledPointer?.pointee = 0
        confirmedPointer?.pointee = 0
        guard let context else { return nil }
        let webView = Unmanaged<WKWebView>.fromOpaque(context).takeUnretainedValue()
        guard let uiDelegate = webView.uiDelegate else { return nil }

        handledPointer?.pointee = 1
        let message = messagePointer.map { String(cString: $0) } ?? ""
        let defaultText = defaultTextPointer.map { String(cString: $0) }
        let frame = WKFrameInfo()

        switch dialogType {
        case 0:
            uiDelegate.webView(webView, runJavaScriptAlertPanelWithMessage: message, initiatedByFrame: frame) {}
            return nil
        case 1, 3:
            var confirmed = false
            uiDelegate.webView(webView, runJavaScriptConfirmPanelWithMessage: message, initiatedByFrame: frame) {
                confirmed = $0
            }
            confirmedPointer?.pointee = confirmed ? 1 : 0
            return nil
        case 2:
            var result: String?
            uiDelegate.webView(webView, runJavaScriptTextInputPanelWithPrompt: message, defaultText: defaultText, initiatedByFrame: frame) {
                result = $0
            }
            return result.map { strdup($0) }
        default:
            handledPointer?.pointee = 0
            return nil
        }
    }

    private static func string(at index: Int, in values: UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> String? {
        guard let pointer = values?.advanced(by: index).pointee else { return nil }
        return String(cString: pointer)
    }

    private static func decodeJavaScriptBody(_ body: String) -> Any {
        guard let data = body.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return body
        }
        return value
    }
}
