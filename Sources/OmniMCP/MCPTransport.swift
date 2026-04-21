import Foundation
import Dispatch
import OmniHTTP

public protocol MCPTransport: Sendable {
    func connect() async throws
    func disconnect() async
    func send(_ data: Data) async throws
    func messageStream() async throws -> AsyncThrowingStream<Data, Error>
}

private final class _ProcessExitContinuationBox: @unchecked Sendable {
    // Safety: `resumed` is guarded by `lock`, and the continuation is resumed at most once.
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<Void, Never>

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resumeOnce() {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume()
    }
}

public actor StdioMCPTransport: MCPTransport {
    private let command: String
    private let arguments: [String]
    private let environment: [String: String]
    #if !os(iOS) && !os(tvOS) && !os(watchOS) && !os(visionOS)
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    #endif
    private var cachedStream: AsyncThrowingStream<Data, Error>?

    public init(command: String, args: [String] = [], env: [String: String] = [:]) {
        self.command = command
        self.arguments = args
        self.environment = env
    }

    public func connect() async throws {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        throw MCPError.invalidConfiguration("Stdio MCP transport is unavailable on this platform")
        #else
        guard process == nil else { return }
        let proc = Process()
        let resolvedURL: URL
        var resolvedArgs: [String]

        if command.contains("/") {
            resolvedURL = URL(fileURLWithPath: command)
            resolvedArgs = arguments
        } else {
            resolvedURL = URL(fileURLWithPath: "/usr/bin/env")
            resolvedArgs = [command] + arguments
        }

        proc.executableURL = resolvedURL
        proc.arguments = resolvedArgs

        var merged = ProcessInfo.processInfo.environment
        for (k, v) in environment {
            merged[k] = v
        }
        proc.environment = merged

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        try proc.run()
        process = proc
        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading

        cachedStream = makeLineStream(from: stdoutPipe.fileHandleForReading)
        if let stderrHandle {
            Self.drain(handle: stderrHandle, label: "omnimcp.stdio.stderr.\(proc.processIdentifier)")
        }
        #endif
    }

    public func disconnect() async {
        cachedStream = nil
        #if !os(iOS) && !os(tvOS) && !os(watchOS) && !os(visionOS)
        try? stdoutHandle?.close()
        try? stdinHandle?.close()
        try? stderrHandle?.close()
        stdoutHandle = nil
        stdinHandle = nil
        stderrHandle = nil
        if let process {
            if process.isRunning {
                process.terminate()
                await Self.waitForExit(of: process)
            }
        }
        process = nil
        #endif
    }

    public func send(_ data: Data) async throws {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        throw MCPError.invalidConfiguration("Stdio MCP transport is unavailable on this platform")
        #else
        guard let stdinHandle else { throw MCPError.notConnected }
        var payload = data
        if payload.last != 0x0A {
            payload.append(0x0A)
        }
        stdinHandle.write(payload)
        #endif
    }

    public func messageStream() async throws -> AsyncThrowingStream<Data, Error> {
        guard let cachedStream else { throw MCPError.notConnected }
        return cachedStream
    }

    private func makeLineStream(from handle: FileHandle) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let queue = DispatchQueue(label: "omnimcp.stdio.stdout.\(UUID().uuidString)")
            queue.async {
                do {
                    var buffer: [UInt8] = []
                    buffer.reserveCapacity(4096)
                    while true {
                        let chunk = try handle.read(upToCount: 4096) ?? Data()
                        if chunk.isEmpty {
                            break
                        }
                        for byte in chunk {
                            if byte == 0x0A {
                                continuation.yield(Data(buffer))
                                buffer.removeAll(keepingCapacity: true)
                            } else {
                                buffer.append(byte)
                            }
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(Data(buffer))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                try? handle.close()
            }
        }
    }

    private nonisolated static func drain(handle: FileHandle, label: String) {
        let queue = DispatchQueue(label: label, qos: .utility)
        queue.async {
            _ = try? handle.readToEnd()
        }
    }

    #if !os(iOS) && !os(tvOS) && !os(watchOS) && !os(visionOS)
    private nonisolated static func waitForExit(of process: Process) async {
        guard process.isRunning else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeBox = _ProcessExitContinuationBox(continuation)

            process.terminationHandler = { _ in
                resumeBox.resumeOnce()
            }

            if !process.isRunning {
                resumeBox.resumeOnce()
            }
        }
        process.terminationHandler = nil
    }
    #endif
}

public actor SSEMCPTransport: MCPTransport {
    private let url: URL
    private let requestURL: URL
    private let headers: [String: String]
    private let transport: HTTPTransport
    private var cachedStream: AsyncThrowingStream<Data, Error>?

    public init(
        url: URL,
        requestURL: URL? = nil,
        headers: [String: String] = [:],
        transport: HTTPTransport = URLSessionHTTPTransport()
    ) {
        self.url = url
        self.requestURL = requestURL ?? url
        self.headers = headers
        self.transport = transport
    }

    public func connect() async throws {
        guard cachedStream == nil else { return }
        var httpHeaders = HTTPHeaders()
        for (k, v) in headers {
            httpHeaders.set(name: k, value: v)
        }
        let request = HTTPRequest(method: .get, url: url, headers: httpHeaders, body: .none)
        let response = try await transport.openStream(request, timeout: nil)
        let sseStream = SSE.parse(response.body)

        cachedStream = AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in sseStream {
                        continuation.yield(Data(event.data.utf8))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func disconnect() async {
        cachedStream = nil
        try? await transport.shutdown()
    }

    public func send(_ data: Data) async throws {
        var httpHeaders = HTTPHeaders()
        httpHeaders.set(name: "content-type", value: "application/json")
        for (k, v) in headers {
            httpHeaders.set(name: k, value: v)
        }
        let request = HTTPRequest(method: .post, url: requestURL, headers: httpHeaders, body: .bytes(Array(data)))
        _ = try await transport.send(request, timeout: .seconds(30))
    }

    public func messageStream() async throws -> AsyncThrowingStream<Data, Error> {
        guard let cachedStream else { throw MCPError.notConnected }
        return cachedStream
    }
}
