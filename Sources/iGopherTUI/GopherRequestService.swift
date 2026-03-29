import Foundation
import Dispatch
@preconcurrency import GopherHelpers

#if os(Linux)
import Glibc
#else
import Darwin
#endif

final class GopherRequestService: Sendable {
    static let shared = GopherRequestService()
    private static let socketQueue = DispatchQueue(
        label: "igopher.tui.gopher-transport",
        qos: .userInitiated,
        attributes: .concurrent
    )

    func sendRequest(to host: String, port: Int, message: String) async throws -> [gopherItem] {
        let data = try await fetchData(to: host, port: port, message: message)
        return parseResponseItems(from: data)
    }

    func fetchData(to host: String, port: Int, message: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            Self.socketQueue.async {
                do {
                    continuation.resume(returning: try Self.fetchDataSync(to: host, port: port, message: message))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func fetchDataSync(to host: String, port: Int, message: String) throws -> Data {
        guard let service = String(port).cString(using: .utf8) else {
            throw GopherTransportError.invalidHost
        }

        var hints = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_UNSPEC
        #if os(Linux)
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #else
        hints.ai_socktype = SOCK_STREAM
        #endif
        hints.ai_protocol = 0
        var info: UnsafeMutablePointer<addrinfo>?
        let lookupResult = host.withCString { hostCString in
            getaddrinfo(hostCString, service, &hints, &info)
        }
        guard lookupResult == 0, let startInfo = info else {
            throw GopherTransportError.lookupFailed(code: lookupResult)
        }
        defer { freeaddrinfo(startInfo) }

        var current: UnsafeMutablePointer<addrinfo>? = startInfo
        var lastError: Error = GopherTransportError.connectFailed
        while let address = current {
            let pointer = address.pointee
            let socketFD = socket(pointer.ai_family, pointer.ai_socktype, pointer.ai_protocol)
            guard socketFD >= 0 else {
                current = pointer.ai_next
                continue
            }

            defer { close(socketFD) }

            if connect(socketFD, pointer.ai_addr, pointer.ai_addrlen) == 0 {
                do {
                    try writeAll(message.utf8, to: socketFD)
                    shutdown(socketFD, Int32(SHUT_WR))
                    return try readAll(from: socketFD)
                } catch {
                    lastError = error
                }
            } else {
                lastError = GopherTransportError.connectFailed
            }

            current = pointer.ai_next
        }

        throw lastError
    }

    private static func writeAll<S: Sequence>(_ bytes: S, to socketFD: Int32) throws where S.Element == UInt8 {
        let payload = Array(bytes)
        var sent = 0
        while sent < payload.count {
            let wrote = payload.withUnsafeBytes { rawBuffer in
                send(socketFD, rawBuffer.baseAddress!.advanced(by: sent), payload.count - sent, 0)
            }
            guard wrote >= 0 else {
                throw GopherTransportError.writeFailed
            }
            sent += wrote
        }
    }

    private static func readAll(from socketFD: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = recv(socketFD, &buffer, buffer.count, 0)
            if count == 0 {
                return data
            }
            guard count > 0 else {
                throw GopherTransportError.readFailed
            }
            data.append(buffer, count: count)
        }
    }

    private func parseResponseItems(from data: Data) -> [gopherItem] {
        let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        let normalized = decoded
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let rawLines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        if rawLines.isEmpty {
            return []
        }

        return rawLines.compactMap { rawLine in
            let line = String(rawLine)
            guard line != "." else { return nil }
            return makeItem(rawLine: line)
        }
    }

    private func makeItem(rawLine: String) -> gopherItem {
        let itemType = getGopherFileType(item: String(rawLine.first ?? " "))
        var item = gopherItem(rawLine: rawLine)
        item.parsedItemType = itemType

        guard rawLine.isEmpty == false else {
            item.valid = false
            return item
        }

        let components = rawLine.components(separatedBy: "\t")
        item.message = components[0].isEmpty ? "" : String(components[0].dropFirst())
        if components.indices.contains(1) {
            item.selector = components[1]
        }
        if components.indices.contains(2) {
            item.host = components[2]
        }
        if components.indices.contains(3) {
            item.port = Int(components[3]) ?? 70
        }
        return item
    }
}

private enum GopherTransportError: LocalizedError {
    case invalidHost
    case lookupFailed(code: Int32)
    case connectFailed
    case writeFailed
    case readFailed

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Invalid gopher host."
        case .lookupFailed(let code):
            if let message = gai_strerror(code) {
                return String(cString: message)
            }
            return "Unable to resolve gopher host."
        case .connectFailed:
            return "Unable to connect to gopher server."
        case .writeFailed:
            return "Unable to send gopher request."
        case .readFailed:
            return "Unable to read gopher response."
        }
    }
}
