import Foundation
import Dispatch
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(AppKit)
import AppKit
#endif
#if canImport(WebKit)
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
    public let url: URL
    public let fallbackText: String
    #if canImport(AppKit)
    public let nativeView: NSView?
    #endif

    public init(url: URL, fallbackText: String) {
        self.url = url
        self.fallbackText = fallbackText
        #if canImport(AppKit)
        self.nativeView = nil
        #endif
    }

    #if canImport(AppKit)
    public init(url: URL, fallbackText: String, nativeView: NSView?) {
        self.url = url
        self.fallbackText = fallbackText
        self.nativeView = nativeView
    }

    public var nativeViewPointer: UnsafeMutableRawPointer? {
        guard let nativeView else { return nil }
        return Unmanaged.passUnretained(nativeView).toOpaque()
    }
    #endif
}

public enum _OmniWebViewRegistry {
    private static let payloads = _OmniLockedDictionary<_OmniWebViewPayload>()

    public static func store(url: URL, fallbackText: String) -> String {
        store(url: url, fallbackText: fallbackText, identity: nil)
    }

    #if canImport(AppKit)
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

#if canImport(AppKit)
extension NSImage {
    func _omniPNGRepresentation() -> Data? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif

enum _OmniRepresentableFallback {
    #if canImport(AppKit)
    private final class NativeEntry {
        let nsView: NSView
        let update: (Any) -> Void
        let dismantle: () -> Void

        init(nsView: NSView, update: @escaping (Any) -> Void, dismantle: @escaping () -> Void) {
            self.nsView = nsView
            self.update = update
            self.dismantle = dismantle
        }

        deinit {
            dismantle()
        }
    }

    private static let nativeEntries = _OmniLockedDictionary<NativeEntry>()
    #endif

    #if canImport(AppKit)
    static func node<R: NSViewRepresentable>(for view: R, path: [Int]) -> _VNode? {
        nativeNode(for: view, erasedView: view, path: path)
    }
    #endif

    static func node<V>(for view: V, path: [Int]) -> _VNode? {
        guard let url = mirrorValue(named: "url", in: view) as? URL else { return nil }
        let textScale = mirrorValue(named: "textScale", in: view) as? Double ?? 1.0
        let text = _OmniRemoteDocumentRegistry.text(for: url, textScale: textScale)
        return .image(_OmniWebViewRegistry.store(url: url, fallbackText: text))
    }

    #if canImport(AppKit)
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

        let url = nativeRepresentableURL(for: erasedView, nsView: entry.nsView)
        let textScale = mirrorValue(named: "textScale", in: erasedView) as? Double ?? 1.0
        let fallback = nativeFallbackText(for: url, nsView: entry.nsView, textScale: textScale)
        trace("native \(String(reflecting: R.self)) path=\(path.map(String.init).joined(separator: ".")) url=\(url.absoluteString)")
        return .image(_OmniWebViewRegistry.store(url: url, fallbackText: fallback, nativeView: entry.nsView, identity: key))
    }

    private static func nativeRepresentableKey(typeName: String, path: [Int]) -> String {
        let pathKey = path.map(String.init).joined(separator: ".")
        return "\(typeName):\(pathKey)"
    }

    private static func nativeRepresentableURL(for view: Any, nsView: NSView) -> URL {
        _ = nsView
        if let url = mirrorValue(named: "url", in: view) as? URL {
            return url
        }
        return URL(string: "about:blank")!
    }

    private static func nativeFallbackText(for url: URL, nsView: NSView, textScale: Double) -> String {
        #if canImport(WebKit)
        if nsView is WKWebView {
            return "Web content\n\(url.absoluteString)"
        }
        #endif
        if url.scheme == "http" || url.scheme == "https" {
            return _OmniRemoteDocumentRegistry.text(for: url, textScale: textScale)
        }
        return "Native view\n\(String(describing: type(of: nsView)))"
    }
    #endif

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
