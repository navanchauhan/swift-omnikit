import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SSEEvent: Sendable {
    public var event: String?
    public var data: String
    public var id: String?
    public var retry: Int?

    public init(event: String? = nil, data: String, id: String? = nil, retry: Int? = nil) {
        self.event = event
        self.data = data
        self.id = id
        self.retry = retry
    }
}

public struct SSEParser {
    public static func parse(stream: AsyncThrowingStream<UInt8, Error>) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var currentEvent: String?
                var currentData: [String] = []
                var currentId: String?
                var currentRetry: Int?
                var lineBuffer = Data()

                do {
                    for try await byte in stream {
                        if byte == UInt8(ascii: "\n") {
                            let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                            lineBuffer = Data()

                            if line.isEmpty {
                                // Blank line = event boundary
                                if !currentData.isEmpty {
                                    let data = currentData.joined(separator: "\n")
                                    let event = SSEEvent(
                                        event: currentEvent,
                                        data: data,
                                        id: currentId,
                                        retry: currentRetry
                                    )
                                    continuation.yield(event)
                                }
                                currentEvent = nil
                                currentData = []
                                currentId = nil
                                currentRetry = nil
                            } else if line.hasPrefix(":") {
                                // Comment, ignore
                            } else if line.hasPrefix("event:") {
                                currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("data:") {
                                currentData.append(String(line.dropFirst(5)).trimmingCharacters(in: .init(charactersIn: " ")))
                            } else if line.hasPrefix("id:") {
                                currentId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("retry:") {
                                currentRetry = Int(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces))
                            }
                        } else if byte == UInt8(ascii: "\r") {
                            // Skip CR, handle CRLF
                        } else {
                            lineBuffer.append(byte)
                        }
                    }

                    // Handle final event if stream ends without trailing newline
                    if !currentData.isEmpty {
                        let data = currentData.joined(separator: "\n")
                        let event = SSEEvent(
                            event: currentEvent,
                            data: data,
                            id: currentId,
                            retry: currentRetry
                        )
                        continuation.yield(event)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Parse SSE from URLSession bytes
    #if !os(Linux)
    public static func parse(bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var currentEvent: String?
                var currentData: [String] = []
                var currentId: String?
                var currentRetry: Int?
                var lineBuffer = Data()

                do {
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                            lineBuffer = Data()

                            if line.isEmpty {
                                if !currentData.isEmpty {
                                    let data = currentData.joined(separator: "\n")
                                    continuation.yield(SSEEvent(
                                        event: currentEvent,
                                        data: data,
                                        id: currentId,
                                        retry: currentRetry
                                    ))
                                }
                                currentEvent = nil
                                currentData = []
                                currentId = nil
                                currentRetry = nil
                            } else if line.hasPrefix(":") {
                                // Comment
                            } else if line.hasPrefix("event:") {
                                currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("data:") {
                                currentData.append(String(line.dropFirst(5)).trimmingCharacters(in: .init(charactersIn: " ")))
                            } else if line.hasPrefix("id:") {
                                currentId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("retry:") {
                                currentRetry = Int(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces))
                            }
                        } else if byte == UInt8(ascii: "\r") {
                            // Skip
                        } else {
                            lineBuffer.append(byte)
                        }
                    }

                    if !currentData.isEmpty {
                        let data = currentData.joined(separator: "\n")
                        continuation.yield(SSEEvent(
                            event: currentEvent,
                            data: data,
                            id: currentId,
                            retry: currentRetry
                        ))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    #endif
}
