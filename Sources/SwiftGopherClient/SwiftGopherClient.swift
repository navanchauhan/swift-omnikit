import Foundation
#if canImport(Dispatch)
import Dispatch
#endif
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public enum GopherClientError: Error, CustomStringConvertible, Sendable {
    case invalidPort(Int)
    case dnsLookupFailed(String)
    case socketError(String)
    case connectFailed(String)
    case sendFailed(String)

    public var description: String {
        switch self {
        case .invalidPort(let p): return "Invalid port: \(p)"
        case .dnsLookupFailed(let h): return "DNS lookup failed: \(h)"
        case .socketError(let s): return "Socket error: \(s)"
        case .connectFailed(let s): return "Connect failed: \(s)"
        case .sendFailed(let s): return "Send failed: \(s)"
        }
    }
}

/// A minimal byte buffer wrapper for non-NIO builds.
///
/// iGopherBrowser expects a value with `readableBytes` and `readBytes(length:)` for file downloads.
public struct GopherByteBuffer: Sendable {
    private var storage: Data
    private var readerIndex: Int = 0

    public init(_ data: Data) {
        self.storage = data
    }

    public var readableBytes: Int {
        max(0, storage.count - readerIndex)
    }

    public mutating func readBytes(length: Int) -> [UInt8]? {
        guard length > 0 else { return [] }
        let remaining = readableBytes
        guard remaining > 0 else { return nil }
        let n = min(length, remaining)
        let start = readerIndex
        let end = readerIndex + n
        readerIndex = end
        return Array(storage[start..<end])
    }
}

public enum GopherParsedItemType: Hashable, Sendable {
    case info
    case directory
    case search
    case text
    case doc
    case image
    case gif
    case movie
    case sound
    case bitmap
    case binary
    case unknown
}

public struct gopherItem: Sendable {
    public var rawLine: String
    public var message: String
    public var selector: String
    public var host: String
    public var port: Int
    public var parsedItemType: GopherParsedItemType
    public var rawData: GopherByteBuffer?

    public init(rawLine: String) {
        self.rawLine = rawLine
        self.message = rawLine
        self.selector = ""
        self.host = ""
        self.port = 70
        self.parsedItemType = .info
        self.rawData = nil
    }

    init(
        rawLine: String,
        message: String,
        selector: String,
        host: String,
        port: Int,
        parsedItemType: GopherParsedItemType,
        rawData: GopherByteBuffer? = nil
    ) {
        self.rawLine = rawLine
        self.message = message
        self.selector = selector
        self.host = host
        self.port = port
        self.parsedItemType = parsedItemType
        self.rawData = rawData
    }

    /// Parses a single line from a Gopher menu response.
    ///
    /// Format: `<type><display>\t<selector>\t<host>\t<port>`
    static func parseMenuLine(_ line: String) -> gopherItem {
        let trimmed = line.hasSuffix("\r") ? String(line.dropLast()) : line
        guard let typeChar = trimmed.first else { return gopherItem(rawLine: trimmed) }
        let rest = String(trimmed.dropFirst())
        let parts = rest.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let display = parts.first ?? rest
        let selector = parts.count > 1 ? parts[1] : ""
        let host = parts.count > 2 ? parts[2] : ""
        let port = parts.count > 3 ? (Int(parts[3]) ?? 70) : 70

        let parsed = _parseItemType(typeChar: typeChar, selector: selector, display: display)
        return gopherItem(
            rawLine: trimmed,
            message: display,
            selector: selector,
            host: host,
            port: port,
            parsedItemType: parsed,
            rawData: nil
        )
    }
}

private func _parseItemType(typeChar: Character, selector: String, display: String) -> GopherParsedItemType {
    // Gopher menu item type chars.
    switch typeChar {
    case "i": return .info
    case "1": return .directory
    case "7": return .search
    case "0": return .text
    case "g": return .gif
    case "I": return .image
    case "9", "5", "6", "4":
        break
    default:
        break
    }

    // Heuristics by selector extension for richer UX in FileView.
    let s = selector.lowercased()
    if s.hasSuffix(".gif") { return .gif }
    if s.hasSuffix(".png") || s.hasSuffix(".jpg") || s.hasSuffix(".jpeg") || s.hasSuffix(".webp") || s.hasSuffix(".bmp") {
        return .image
    }
    if s.hasSuffix(".mp4") || s.hasSuffix(".mov") || s.hasSuffix(".m4v") { return .movie }
    if s.hasSuffix(".mp3") || s.hasSuffix(".wav") || s.hasSuffix(".flac") || s.hasSuffix(".ogg") { return .sound }
    if s.hasSuffix(".pdf") || s.hasSuffix(".doc") || s.hasSuffix(".docx") || s.hasSuffix(".rtf") || s.hasSuffix(".txt") {
        // `.txt` is still a "doc" in the sense that we can preview it; menu type "0" is already `.text`.
        return typeChar == "0" ? .text : .doc
    }
    if s.hasSuffix(".bmp") { return .bitmap }

    // If it wasn't a known menu type, treat it as binary.
    if typeChar == "9" || typeChar == "5" || typeChar == "6" || typeChar == "4" { return .binary }
    if typeChar == "3" {
        // Error items are rendered as info lines in iGopherBrowser.
        return .info
    }
    return .unknown
}

public final class GopherClient: @unchecked Sendable {
    public init() {}

    public func sendRequest(to host: String, port: Int, message: String) async throws -> [gopherItem] {
        let data = try await _fetch(host: host, port: port, request: message)
        // Gopher menus are UTF-8-ish text; parse by lines.
        let text = String(decoding: data, as: UTF8.self)
        var items: [gopherItem] = []
        // Split by newline characters instead of a literal `"\n"` separator because CRLF is
        // represented as a single grapheme cluster in Swift strings.
        for lineSub in text.split(whereSeparator: { $0.isNewline }) {
            let line = String(lineSub)
            if line == "." { break }
            items.append(gopherItem.parseMenuLine(line))
        }
        return items
    }

    public func sendRequest(
        to host: String,
        port: Int,
        message: String,
        completion: @escaping (Result<[gopherItem], Error>) -> Void
    ) {
        final class _CallbackBox: @unchecked Sendable {
            let cb: (Result<[gopherItem], Error>) -> Void
            init(_ cb: @escaping (Result<[gopherItem], Error>) -> Void) { self.cb = cb }
        }
        let box = _CallbackBox(completion)

        // Avoid Swift 6 `Sendable` restrictions for callbacks: use a GCD hop and call back on the main queue.
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try _fetchSync(host: host, port: port, request: message)
                let item = gopherItem(
                    rawLine: "",
                    message: "",
                    selector: "",
                    host: host,
                    port: port,
                    parsedItemType: .binary,
                    rawData: GopherByteBuffer(data)
                )
                DispatchQueue.main.async {
                    box.cb(.success([item]))
                }
            } catch {
                DispatchQueue.main.async {
                    box.cb(.failure(error))
                }
            }
        }
    }
}

private func _fetch(host: String, port: Int, request: String) async throws -> Data {
    try await Task.detached(priority: .utility) {
        try _fetchSync(host: host, port: port, request: request)
    }.value
}

private func _fetchSync(host: String, port: Int, request: String) throws -> Data {
    guard port > 0 && port <= 65535 else { throw GopherClientError.invalidPort(port) }

    // getaddrinfo
    var hints = addrinfo()
    #if os(Linux)
    hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
    #else
    hints.ai_socktype = SOCK_STREAM
    #endif
    hints.ai_family = AF_UNSPEC

    var res: UnsafeMutablePointer<addrinfo>?
    let err = getaddrinfo(host, String(port), &hints, &res)
    if err != 0 || res == nil {
        throw GopherClientError.dnsLookupFailed(host)
    }
    defer { freeaddrinfo(res) }

    var lastError: Error? = nil
    var p = res
    while let ai = p?.pointee {
        let fd = socket(ai.ai_family, ai.ai_socktype, ai.ai_protocol)
        if fd < 0 {
            lastError = GopherClientError.socketError(String(cString: strerror(errno)))
            p = ai.ai_next
            continue
        }

        let ok = withUnsafePointer(to: ai.ai_addr.pointee) { addrPtr -> Int32 in
            let raw = UnsafeRawPointer(addrPtr).assumingMemoryBound(to: sockaddr.self)
            return connect(fd, raw, ai.ai_addrlen)
        }
        if ok != 0 {
            lastError = GopherClientError.connectFailed(String(cString: strerror(errno)))
            _ = close(fd)
            p = ai.ai_next
            continue
        }

        // Connected: send request.
        let req = request.hasSuffix("\r\n") ? request : (request + "\r\n")
        let bytes = Array(req.utf8)
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return send(fd, base.advanced(by: sent), bytes.count - sent, 0)
            }
            if n <= 0 {
                lastError = GopherClientError.sendFailed(String(cString: strerror(errno)))
                _ = close(fd)
                return try _throwLast(lastError)
            }
            sent += n
        }

        // Read until EOF.
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0 {
                out.append(buf, count: n)
            } else {
                break
            }
        }
        _ = close(fd)
        return out
    }

    return try _throwLast(lastError)
}

private func _throwLast(_ err: Error?) throws -> Data {
    if let err { throw err }
    throw GopherClientError.socketError("Unknown socket error")
}
