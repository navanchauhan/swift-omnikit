import Foundation
import Dispatch
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(AppKit) && !os(Linux)
import AppKit
#endif
#if canImport(WebKit) && !os(Linux)
import WebKit
#endif

private final class _OmniLockedDictionary<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Value] = [:]

    func value(for key: String) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ value: Value, for key: String) {
        lock.lock()
        storage[key] = value
        lock.unlock()
    }
}

private final class _OmniLockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    func value() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func update(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}

public enum _OmniImageRegistry {
    private static let images = _OmniLockedDictionary<Data>()

    public static func store(_ data: Data) -> String {
        let key = "omni-nsimage:\(stableIdentifier(for: data))"
        images.set(data, for: key)
        return key
    }

    public static func data(for key: String) -> Data? {
        guard key.hasPrefix("omni-nsimage:") else { return nil }
        return images.value(for: key)
    }

    private static func stableIdentifier(for data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return "\(String(hash, radix: 16))-\(data.count)"
    }
}

public struct _OmniWebViewPayload {
    public enum Load: Sendable, Equatable {
        case url(URL)
        case html(String, baseURL: URL?)
    }

    public struct UserScript: Sendable, Equatable {
        public let source: String
        public let injectionTime: Int32
        public let forMainFrameOnly: Bool

        public init(source: String, injectionTime: Int32, forMainFrameOnly: Bool) {
            self.source = source
            self.injectionTime = injectionTime
            self.forMainFrameOnly = forMainFrameOnly
        }
    }

    public struct ContentRule: Sendable, Equatable {
        public let identifier: String
        public let encodedRules: String

        public init(identifier: String, encodedRules: String) {
            self.identifier = identifier
            self.encodedRules = encodedRules
        }
    }

    public struct Cookie: Sendable, Equatable {
        public let name: String
        public let value: String
        public let domain: String
        public let path: String
        public let expiresAt: Double?
        public let isSecure: Bool
        public let isHTTPOnly: Bool

        public init(name: String, value: String, domain: String, path: String, expiresAt: Double?, isSecure: Bool, isHTTPOnly: Bool) {
            self.name = name
            self.value = value
            self.domain = domain
            self.path = path
            self.expiresAt = expiresAt
            self.isSecure = isSecure
            self.isHTTPOnly = isHTTPOnly
        }
    }

    public struct Header: Sendable, Equatable {
        public let name: String
        public let value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    public typealias MessageCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
    public typealias NavigationCallback = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
    public typealias PolicyCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int32, Int32) -> Int32
    public typealias TitleCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void
    public typealias ProgressCallback = @convention(c) (UnsafeMutableRawPointer?, Double) -> Void
    public typealias CookieCallback = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<UnsafePointer<CChar>?>?,
        UnsafeMutablePointer<UnsafePointer<CChar>?>?,
        UnsafeMutablePointer<UnsafePointer<CChar>?>?,
        UnsafeMutablePointer<UnsafePointer<CChar>?>?,
        UnsafePointer<Double>?,
        UnsafePointer<Int32>?,
        UnsafePointer<Int32>?,
        Int32
    ) -> Void
    public typealias ScriptDialogCallback = @convention(c) (
        UnsafeMutableRawPointer?,
        Int32,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<Int32>?,
        UnsafeMutablePointer<Int32>?
    ) -> UnsafeMutablePointer<CChar>?

    public let load: Load
    public let fallbackText: String
    public let stableIdentity: String
    public let userAgentApplicationName: String?
    public let customUserAgent: String?
    public let pageZoom: Double
    public let allowsBackForwardNavigationGestures: Bool
    public let javaScriptCanOpenWindowsAutomatically: Bool
    public let javaScriptEnabled: Bool
    public let minimumFontSize: Double
    public let isInspectable: Bool
    public let allowsInlineMediaPlayback: Bool
    public let mediaPlaybackRequiresUserGesture: Bool
    public let userScripts: [UserScript]
    public let scriptMessageHandlerNames: [String]
    public let contentRules: [ContentRule]
    public let cookies: [Cookie]
    public let requestHeaders: [Header]
    public let hasNavigationDelegate: Bool
    public let hasUIDelegate: Bool
    public let dataStoreIdentifier: String
    public let accessibilityLabel: String?
    public let accessibilityDescription: String?
    public let swiftObject: AnyObject?
    public let messageCallback: MessageCallback?
    public let navigationCallback: NavigationCallback?
    public let policyCallback: PolicyCallback?
    public let titleCallback: TitleCallback?
    public let progressCallback: ProgressCallback?
    public let cookieCallback: CookieCallback?
    public let scriptDialogCallback: ScriptDialogCallback?
    public let callbackContext: UnsafeMutableRawPointer?
    #if canImport(AppKit) && !os(Linux)
    public let nativeView: NSView?
    #endif

    public var url: URL {
        switch load {
        case .url(let url): return url
        case .html(_, let baseURL): return baseURL ?? URL(string: "about:blank")!
        }
    }

    public init(url: URL, fallbackText: String) {
        self.load = .url(url)
        self.fallbackText = fallbackText
        self.stableIdentity = url.absoluteString + "\n" + fallbackText
        self.userAgentApplicationName = nil
        self.customUserAgent = nil
        self.pageZoom = 1
        self.allowsBackForwardNavigationGestures = false
        self.javaScriptCanOpenWindowsAutomatically = true
        self.javaScriptEnabled = true
        self.minimumFontSize = 0
        self.isInspectable = false
        self.allowsInlineMediaPlayback = true
        self.mediaPlaybackRequiresUserGesture = false
        self.userScripts = []
        self.scriptMessageHandlerNames = []
        self.contentRules = []
        self.cookies = []
        self.requestHeaders = []
        self.hasNavigationDelegate = false
        self.hasUIDelegate = false
        self.dataStoreIdentifier = "default"
        self.accessibilityLabel = nil
        self.accessibilityDescription = nil
        self.swiftObject = nil
        self.messageCallback = nil
        self.navigationCallback = nil
        self.policyCallback = nil
        self.titleCallback = nil
        self.progressCallback = nil
        self.cookieCallback = nil
        self.scriptDialogCallback = nil
        self.callbackContext = nil
        #if canImport(AppKit) && !os(Linux)
        self.nativeView = nil
        #endif
    }

    public init(
        load: Load,
        fallbackText: String,
        stableIdentity: String,
        userAgentApplicationName: String? = nil,
        customUserAgent: String? = nil,
        pageZoom: Double = 1,
        allowsBackForwardNavigationGestures: Bool = false,
        javaScriptCanOpenWindowsAutomatically: Bool = true,
        javaScriptEnabled: Bool = true,
        minimumFontSize: Double = 0,
        isInspectable: Bool = false,
        allowsInlineMediaPlayback: Bool = true,
        mediaPlaybackRequiresUserGesture: Bool = false,
        userScripts: [UserScript] = [],
        scriptMessageHandlerNames: [String] = [],
        contentRules: [ContentRule] = [],
        cookies: [Cookie] = [],
        requestHeaders: [Header] = [],
        hasNavigationDelegate: Bool = false,
        hasUIDelegate: Bool = false,
        dataStoreIdentifier: String = "default",
        accessibilityLabel: String? = nil,
        accessibilityDescription: String? = nil,
        swiftObject: AnyObject? = nil,
        messageCallback: MessageCallback? = nil,
        navigationCallback: NavigationCallback? = nil,
        policyCallback: PolicyCallback? = nil,
        titleCallback: TitleCallback? = nil,
        progressCallback: ProgressCallback? = nil,
        cookieCallback: CookieCallback? = nil,
        scriptDialogCallback: ScriptDialogCallback? = nil,
        callbackContext: UnsafeMutableRawPointer? = nil
    ) {
        self.load = load
        self.fallbackText = fallbackText
        self.stableIdentity = stableIdentity
        self.userAgentApplicationName = userAgentApplicationName
        self.customUserAgent = customUserAgent
        self.pageZoom = pageZoom
        self.allowsBackForwardNavigationGestures = allowsBackForwardNavigationGestures
        self.javaScriptCanOpenWindowsAutomatically = javaScriptCanOpenWindowsAutomatically
        self.javaScriptEnabled = javaScriptEnabled
        self.minimumFontSize = minimumFontSize
        self.isInspectable = isInspectable
        self.allowsInlineMediaPlayback = allowsInlineMediaPlayback
        self.mediaPlaybackRequiresUserGesture = mediaPlaybackRequiresUserGesture
        self.userScripts = userScripts
        self.scriptMessageHandlerNames = scriptMessageHandlerNames
        self.contentRules = contentRules
        self.cookies = cookies
        self.requestHeaders = requestHeaders
        self.hasNavigationDelegate = hasNavigationDelegate
        self.hasUIDelegate = hasUIDelegate
        self.dataStoreIdentifier = dataStoreIdentifier
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityDescription = accessibilityDescription
        self.swiftObject = swiftObject
        self.messageCallback = messageCallback
        self.navigationCallback = navigationCallback
        self.policyCallback = policyCallback
        self.titleCallback = titleCallback
        self.progressCallback = progressCallback
        self.cookieCallback = cookieCallback
        self.scriptDialogCallback = scriptDialogCallback
        self.callbackContext = callbackContext
        #if canImport(AppKit) && !os(Linux)
        self.nativeView = nil
        #endif
    }

    #if canImport(AppKit) && !os(Linux)
    public init(url: URL, fallbackText: String, nativeView: NSView?) {
        self.load = .url(url)
        self.fallbackText = fallbackText
        self.stableIdentity = url.absoluteString + "\n" + fallbackText
        self.userAgentApplicationName = nil
        self.customUserAgent = nil
        self.pageZoom = 1
        self.allowsBackForwardNavigationGestures = false
        self.javaScriptCanOpenWindowsAutomatically = true
        self.javaScriptEnabled = true
        self.minimumFontSize = 0
        self.isInspectable = false
        self.allowsInlineMediaPlayback = true
        self.mediaPlaybackRequiresUserGesture = false
        self.userScripts = []
        self.scriptMessageHandlerNames = []
        self.contentRules = []
        self.cookies = []
        self.requestHeaders = []
        self.hasNavigationDelegate = false
        self.hasUIDelegate = false
        self.dataStoreIdentifier = "default"
        self.accessibilityLabel = nil
        self.accessibilityDescription = nil
        self.swiftObject = nativeView
        self.messageCallback = nil
        self.navigationCallback = nil
        self.policyCallback = nil
        self.titleCallback = nil
        self.progressCallback = nil
        self.cookieCallback = nil
        self.scriptDialogCallback = nil
        self.callbackContext = nil
        self.nativeView = nativeView
    }

    public var nativeViewPointer: UnsafeMutableRawPointer? {
        guard let nativeView else { return nil }
        return Unmanaged.passUnretained(nativeView).toOpaque()
    }
    #endif
}

public protocol _OmniWebViewPayloadProviding: AnyObject {
    var _omniWebViewPayload: _OmniWebViewPayload { get }
}

public enum _OmniWebViewRegistry {
    private static let payloads = _OmniLockedDictionary<_OmniWebViewPayload>()

    public static func store(url: URL, fallbackText: String) -> String {
        store(url: url, fallbackText: fallbackText, identity: nil)
    }

    public static func store(payload: _OmniWebViewPayload) -> String {
        let key = "omni-webview:\(stableIdentifier(for: payload.stableIdentity))"
        payloads.set(payload, for: key)
        return key
    }

    #if canImport(AppKit) && !os(Linux)
    public static func store(url: URL, fallbackText: String, nativeView: NSView?, identity: String? = nil) -> String {
        let key = storeKey(url: url, fallbackText: fallbackText, identity: identity)
        payloads.set(_OmniWebViewPayload(url: url, fallbackText: fallbackText, nativeView: nativeView), for: key)
        return key
    }
    #endif

    private static func store(url: URL, fallbackText: String, identity: String?) -> String {
        let key = storeKey(url: url, fallbackText: fallbackText, identity: identity)
        payloads.set(_OmniWebViewPayload(url: url, fallbackText: fallbackText), for: key)
        return key
    }

    public static func payload(for key: String) -> _OmniWebViewPayload? {
        guard key.hasPrefix("omni-webview:") else { return nil }
        return payloads.value(for: key)
    }

    private static func storeKey(url: URL, fallbackText: String, identity: String?) -> String {
        let seed = identity ?? (url.absoluteString + "\n" + fallbackText)
        return "omni-webview:\(stableIdentifier(for: seed))"
    }

    private static func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

#if canImport(AppKit) && !os(Linux)
extension NSImage {
    func _omniPNGRepresentation() -> Data? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif

enum _OmniRepresentableFallback {
    private final class NativeEntry {
        let nsView: AnyObject
        let update: (Any) -> Void
        let dismantle: () -> Void

        init(nsView: AnyObject, update: @escaping (Any) -> Void, dismantle: @escaping () -> Void) {
            self.nsView = nsView
            self.update = update
            self.dismantle = dismantle
        }

        deinit {
            dismantle()
        }
    }

    private static let nativeEntries = _OmniLockedDictionary<NativeEntry>()

    static func node<R: NSViewRepresentable>(for view: R, path: [Int]) -> _VNode? {
        nativeNode(for: view, erasedView: view, path: path)
    }

    static func node<V>(for view: V, path: [Int]) -> _VNode? {
        guard let url = mirrorValue(named: "url", in: view) as? URL else { return nil }
        let textScale = mirrorValue(named: "textScale", in: view) as? Double ?? 1.0
        let text = _OmniRemoteDocumentRegistry.text(for: url, textScale: textScale)
        return .image(_OmniWebViewRegistry.store(url: url, fallbackText: text))
    }

    private static func nativeNode<R: NSViewRepresentable>(for view: R, erasedView: Any, path: [Int]) -> _VNode {
        let key = nativeRepresentableKey(typeName: String(reflecting: R.self), path: path)
        let entry: NativeEntry
        if let cached = nativeEntries.value(for: key) {
            entry = cached
        } else {
            let coordinator = view.makeCoordinator()
            let context = NSViewRepresentableContext<R>(coordinator: coordinator)
            let nsView = view.makeNSView(context: context)
            entry = NativeEntry(
                nsView: nsView,
                update: { next in
                    guard let typed = next as? R else { return }
                    typed.updateNSView(nsView, context: context)
                },
                dismantle: {
                    R.dismantleNSView(nsView, coordinator: coordinator)
                }
            )
            nativeEntries.set(entry, for: key)
        }

        entry.update(erasedView)

        if let provider = entry.nsView as? _OmniWebViewPayloadProviding {
            return .image(_OmniWebViewRegistry.store(payload: provider._omniWebViewPayload))
        }

        let url = nativeRepresentableURL(for: erasedView, nsView: entry.nsView)
        let textScale = mirrorValue(named: "textScale", in: erasedView) as? Double ?? 1.0
        let fallback = nativeFallbackText(for: url, nsView: entry.nsView, textScale: textScale)
        trace("native \(String(reflecting: R.self)) path=\(path.map(String.init).joined(separator: ".")) url=\(url.absoluteString)")
        #if canImport(AppKit) && !os(Linux)
        return .image(_OmniWebViewRegistry.store(url: url, fallbackText: fallback, nativeView: entry.nsView as? NSView, identity: key))
        #else
        return .image(_OmniWebViewRegistry.store(payload: _OmniWebViewPayload(load: .url(url), fallbackText: fallback, stableIdentity: key, swiftObject: entry.nsView)))
        #endif
    }

    private static func nativeRepresentableKey(typeName: String, path: [Int]) -> String {
        let pathKey = path.map(String.init).joined(separator: ".")
        return "\(typeName):\(pathKey)"
    }

    private static func nativeRepresentableURL(for view: Any, nsView: AnyObject) -> URL {
        _ = nsView
        if let url = mirrorValue(named: "url", in: view) as? URL {
            return url
        }
        return URL(string: "about:blank")!
    }

    private static func nativeFallbackText(for url: URL, nsView: AnyObject, textScale: Double) -> String {
        #if canImport(WebKit) && !os(Linux)
        if nsView is WKWebView {
            return "Web content\n\(url.absoluteString)"
        }
        #endif
        if url.scheme == "http" || url.scheme == "https" {
            return _OmniRemoteDocumentRegistry.text(for: url, textScale: textScale)
        }
        return "Native view\n\(String(describing: type(of: nsView)))"
    }

    private static func trace(_ message: String) {
        guard ProcessInfo.processInfo.environment["OMNIUI_NATIVE_FALLBACK_TRACE"] == "1" else { return }
        FileHandle.standardError.write(Data(("OmniUI fallback: " + message + "\n").utf8))
    }

    private static func mirrorValue<V>(named name: String, in value: V) -> Any? {
        var current: Mirror? = Mirror(reflecting: value)
        while let mirror = current {
            if let child = mirror.children.first(where: { $0.label == name }) {
                return child.value
            }
            current = mirror.superclassMirror
        }
        return nil
    }

    private static func unwrapOptional(_ value: Any?) -> Any? {
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }
}

public enum _OmniRemoteDocumentRegistry {
    public static let didUpdateNotification = Notification.Name("OmniRemoteDocumentRegistryDidUpdate")

    private static let documents = _OmniLockedDictionary<String>()
    private static let inFlight = _OmniLockedDictionary<Bool>()
    private static let versionCounter = _OmniLockedValue(0)

    public static var version: Int {
        versionCounter.value()
    }

    static func text(for url: URL, textScale: Double) -> String {
        let key = url.absoluteString
        if let cached = documents.value(for: key) {
            trace("cache hit \(key) bytes=\(cached.utf8.count)")
            return cached
        }

        trace("cache miss \(key)")
        scheduleFetch(for: url, key: key, textScale: textScale)
        return loadingText(for: url)
    }

    private static func scheduleFetch(for url: URL, key: String, textScale: Double) {
        guard inFlight.value(for: key) != true else { return }
        inFlight.set(true, for: key)
        Task.detached(priority: .utility) {
            trace("fetch start \(key)")
            let display = await fetchDisplayText(for: url, textScale: textScale)
            trace("fetch finish \(key) bytes=\(display.utf8.count)")
            documents.set(display, for: key)
            inFlight.set(false, for: key)
            incrementVersion()
            NotificationCenter.default.post(name: didUpdateNotification, object: url)
        }
    }

    private static func incrementVersion() {
        versionCounter.update { $0 += 1 }
    }

    private static func loadingText(for url: URL) -> String {
        "Loading web content\n\(url.absoluteString)"
    }

    private static func fetchDisplayText(for url: URL, textScale: Double) async -> String {
        let heading = "Web content\n\(url.absoluteString)\n\n"
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 8
        guard let data = fetchData(for: request), !data.isEmpty else {
            return heading + "Unable to load this page in the Adwaita renderer fallback."
        }
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        guard !html.isEmpty else {
            return heading + "Loaded \(data.count) bytes, but the content was not text."
        }

        let body = htmlToReadableText(html, sourceURL: url)
        if body.isEmpty {
            return heading + "Loaded page, but no readable text was extracted."
        }
        return body
    }

    private static func fetchData(for request: URLRequest) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var data: Data?
            var error: Error?
        }
        let box = Box()
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            box.data = data
            box.error = error
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            trace("fetch timeout \(request.url?.absoluteString ?? "")")
            task.cancel()
            return nil
        }
        if let error = box.error {
            trace("fetch error \(request.url?.absoluteString ?? "") \(error)")
        }
        return box.data
    }

    private static func htmlToReadableText(_ html: String, sourceURL: URL) -> String {
        var text = html
        text = replacePattern("(?is)<script[^>]*>.*?</script>", in: text, with: " ")
        text = replacePattern("(?is)<style[^>]*>.*?</style>", in: text, with: " ")
        text = replacePattern("(?is)<noscript[^>]*>.*?</noscript>", in: text, with: " ")

        let title = firstMatch("(?is)<title[^>]*>(.*?)</title>", in: text)
            .map { decodeHTMLEntities(stripTags($0)).trimmingCharacters(in: .whitespacesAndNewlines) }

        text = replacePattern("(?i)<br\\s*/?>", in: text, with: "\n")
        text = replacePattern("(?i)</(p|div|section|article|header|footer|li|tr|table|h[1-6])>", in: text, with: "\n")
        text = replacePattern("(?i)<(p|div|section|article|header|footer|li|tr|table|h[1-6])[^>]*>", in: text, with: "\n")
        text = stripTags(text)
        text = decodeHTMLEntities(text)
        text = normalizeWhitespace(text)

        var lines: [String] = []
        if let title, !title.isEmpty {
            lines.append(title)
            lines.append(sourceURL.host ?? sourceURL.absoluteString)
            lines.append("")
        } else {
            lines.append(sourceURL.absoluteString)
            lines.append("")
        }

        lines.append(text)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func replacePattern(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    private static func trace(_ message: String) {
        guard ProcessInfo.processInfo.environment["OMNIUI_REMOTE_DOCUMENT_TRACE"] == "1" else { return }
        FileHandle.standardError.write(Data(("OmniUI remote document: " + message + "\n").utf8))
    }

    private static func stripTags(_ text: String) -> String {
        replacePattern("(?is)<[^>]+>", in: text, with: " ")
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        let collapsedSpaces = replacePattern("[ \\t\\u{00a0}]+", in: text, with: " ")
        let collapsedLines = replacePattern("\\n[ \\t]+", in: collapsedSpaces, with: "\n")
        return replacePattern("\\n{3,}", in: collapsedLines, with: "\n\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let named: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&ndash;", "-"),
            ("&mdash;", "-"), ("&hellip;", "..."), ("&rsquo;", "'"), ("&lsquo;", "'"),
            ("&rdquo;", "\""), ("&ldquo;", "\"")
        ]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        result = decodeNumericEntities(in: result, pattern: "&#(\\d+);", radix: 10)
        result = decodeNumericEntities(in: result, pattern: "&#x([0-9a-fA-F]+);", radix: 16)
        return result
    }

    private static func decodeNumericEntities(in text: String, pattern: String, radix: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed()
        for match in matches {
            guard match.numberOfRanges > 1,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let valueRange = Range(match.range(at: 1), in: result),
                  let scalarValue = UInt32(result[valueRange], radix: radix),
                  let scalar = UnicodeScalar(scalarValue) else { continue }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
    }
}
