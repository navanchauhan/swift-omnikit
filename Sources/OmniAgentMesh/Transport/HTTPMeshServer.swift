import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

public actor HTTPMeshServer {
    public struct ListeningAddress: Sendable {
        public let host: String
        public let port: Int

        public var baseURL: URL {
            URL(string: "http://\(host):\(port)")!
        }
    }

    private let jobStore: any JobStore
    private let host: String
    private let port: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var channel: Channel?

    public init(jobStore: any JobStore, host: String = "127.0.0.1", port: Int = 0) {
        self.jobStore = jobStore
        self.host = host
        self.port = port
    }

    public func start() async throws -> ListeningAddress {
        if let existing = try listeningAddress() {
            return existing
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPMeshRequestHandler(server: self))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)

        do {
            let channel = try await bootstrap.bind(host: host, port: port).get()
            self.eventLoopGroup = group
            self.channel = channel
            return try listeningAddress().unwrap(or: HTTPMeshServerError.missingListeningAddress)
        } catch {
            try? await group.asyncShutdownGracefully()
            throw error
        }
    }

    public func stop() async throws {
        if let channel {
            try await channel.close().get()
            self.channel = nil
        }
        if let eventLoopGroup {
            try await eventLoopGroup.asyncShutdownGracefully()
            self.eventLoopGroup = nil
        }
    }

    public func listeningAddress() throws -> ListeningAddress? {
        guard let localAddress = channel?.localAddress,
              let actualPort = localAddress.port else {
            return nil
        }
        let actualHost = localAddress.ipAddress ?? host
        return ListeningAddress(host: actualHost, port: actualPort)
    }

    fileprivate func handle(method: String, uri: String, body: Data?) async throws -> HTTPMeshServerResponse {
        guard method == "POST" else {
            return errorResponse(status: .methodNotAllowed, message: "Only POST is supported.")
        }

        let path = sanitizedPath(uri)
        do {
            switch path {
            case "/health":
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: "ok"))
            case "/tasks/create":
                let request: HTTPMeshProtocol.CreateTaskRequest = try decode(body)
                let task = try await jobStore.createTask(request.task, idempotencyKey: request.idempotencyKey)
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: task))
            case "/tasks/get":
                let request: HTTPMeshProtocol.TaskLookupRequest = try decode(body)
                let task = try await jobStore.task(taskID: request.taskID)
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: task))
            case "/tasks/list":
                let request: HTTPMeshProtocol.TaskListRequest = try decode(body)
                let tasks = try await jobStore.tasks(statuses: request.statuses)
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: tasks))
            case "/tasks/claim-next":
                let request: HTTPMeshProtocol.ClaimNextTaskRequest = try decode(body)
                let task = try await jobStore.claimNextTask(
                    workerID: request.workerID,
                    capabilities: request.capabilities,
                    leaseDuration: request.leaseDuration,
                    now: request.now
                )
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: task))
            case "/tasks/renew-lease":
                let request: HTTPMeshProtocol.RenewLeaseRequest = try decode(body)
                let task = try await jobStore.renewLease(
                    taskID: request.taskID,
                    workerID: request.workerID,
                    leaseDuration: request.leaseDuration,
                    now: request.now
                )
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: task))
            case "/tasks/start":
                let request: HTTPMeshProtocol.StartTaskRequest = try decode(body)
                let event = try await jobStore.startTask(
                    taskID: request.taskID,
                    workerID: request.workerID,
                    now: request.now,
                    idempotencyKey: request.idempotencyKey
                )
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: event))
            case "/tasks/progress":
                let request: HTTPMeshProtocol.AppendProgressRequest = try decode(body)
                let event = try await jobStore.appendProgress(
                    taskID: request.taskID,
                    workerID: request.workerID,
                    summary: request.summary,
                    data: request.data,
                    idempotencyKey: request.idempotencyKey,
                    now: request.now
                )
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: event))
            case "/tasks/complete":
                let request: HTTPMeshProtocol.CompleteTaskRequest = try decode(body)
                let event = try await jobStore.completeTask(
                    taskID: request.taskID,
                    workerID: request.workerID,
                    summary: request.summary,
                    artifactRefs: request.artifactRefs,
                    idempotencyKey: request.idempotencyKey,
                    now: request.now
                )
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: event))
            case "/tasks/fail":
                let request: HTTPMeshProtocol.FailTaskRequest = try decode(body)
                let event = try await jobStore.failTask(
                    taskID: request.taskID,
                    workerID: request.workerID,
                    summary: request.summary,
                    idempotencyKey: request.idempotencyKey,
                    now: request.now
                )
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: event))
            case "/tasks/cancel":
                let request: HTTPMeshProtocol.CancelTaskRequest = try decode(body)
                let event = try await jobStore.cancelTask(
                    taskID: request.taskID,
                    workerID: request.workerID,
                    summary: request.summary,
                    idempotencyKey: request.idempotencyKey,
                    now: request.now
                )
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: event))
            case "/tasks/events":
                let request: HTTPMeshProtocol.EventsRequest = try decode(body)
                let events = try await jobStore.events(taskID: request.taskID, afterSequence: request.afterSequence)
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: events))
            case "/tasks/recover-orphaned":
                let request: HTTPMeshProtocol.RecoverOrphanedTasksRequest = try decode(body)
                let recovered = try await jobStore.recoverOrphanedTasks(now: request.now)
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: recovered))
            case "/workers/upsert":
                let request: HTTPMeshProtocol.ValueResponse<WorkerRecord> = try decode(body)
                try await jobStore.upsertWorker(request.value)
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: true))
            case "/workers/get":
                let request: HTTPMeshProtocol.WorkerLookupRequest = try decode(body)
                let worker = try await jobStore.worker(workerID: request.workerID)
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: worker))
            case "/workers/list":
                _ = try decode(body) as HTTPMeshProtocol.EmptyRequest
                let workers = try await jobStore.workers()
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: workers))
            case "/workers/heartbeat":
                let request: HTTPMeshProtocol.HeartbeatRequest = try decode(body)
                let worker = try await jobStore.recordHeartbeat(workerID: request.workerID, state: request.state, at: request.at)
                return try jsonResponse(HTTPMeshProtocol.ValueResponse(value: worker))
            default:
                return errorResponse(status: .notFound, message: "Unknown mesh endpoint \(path)")
            }
        } catch let error as JobStoreError {
            return errorResponse(status: .notFound, message: String(describing: error))
        } catch let error as HTTPMeshServerError {
            return errorResponse(status: .badRequest, message: error.description)
        } catch {
            return errorResponse(status: .internalServerError, message: String(describing: error))
        }
    }

    private func decode<Request: Decodable>(_ body: Data?) throws -> Request {
        guard let body else {
            throw HTTPMeshServerError.missingRequestBody
        }
        do {
            return try decoder.decode(Request.self, from: body)
        } catch {
            throw HTTPMeshServerError.invalidRequestBody(String(describing: error))
        }
    }

    private func jsonResponse<Response: Encodable>(_ payload: Response) throws -> HTTPMeshServerResponse {
        let data = try encoder.encode(payload)
        return HTTPMeshServerResponse(status: .ok, body: data, contentType: "application/json")
    }

    private func errorResponse(status: HTTPResponseStatus, message: String) -> HTTPMeshServerResponse {
        let payload = HTTPMeshProtocol.ErrorResponse(error: message)
        let data = (try? encoder.encode(payload)) ?? Data("{\"error\":\"\(message)\"}".utf8)
        return HTTPMeshServerResponse(status: status, body: data, contentType: "application/json")
    }

    private func sanitizedPath(_ uri: String) -> String {
        URLComponents(string: "http://mesh\(uri)")?.path ?? uri
    }
}

private struct HTTPMeshServerResponse: Sendable {
    let status: HTTPResponseStatus
    let body: Data
    let contentType: String
}

private enum HTTPMeshServerError: Error, CustomStringConvertible {
    case missingListeningAddress
    case missingRequestBody
    case invalidRequestBody(String)

    var description: String {
        switch self {
        case .missingListeningAddress:
            return "HTTP mesh server is not bound to a listening address."
        case .missingRequestBody:
            return "Mesh request body is required."
        case .invalidRequestBody(let message):
            return "Mesh request body could not be decoded: \(message)"
        }
    }
}

private final class HTTPMeshRequestHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let server: HTTPMeshServer
    private var requestHead: HTTPRequestHead?
    private var requestBody = ByteBuffer()

    init(server: HTTPMeshServer) {
        self.server = server
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            requestHead = head
            requestBody = context.channel.allocator.buffer(capacity: 0)
        case .body(var body):
            requestBody.writeBuffer(&body)
        case .end:
            guard let requestHead else {
                write(response: HTTPMeshServerResponse(
                    status: .badRequest,
                    body: Data("{\"error\":\"Missing request head\"}".utf8),
                    contentType: "application/json"
                ), context: context)
                return
            }

            let body = Data(requestBody.readableBytesView)
            context.eventLoop.makeFutureWithTask {
                try await self.server.handle(method: requestHead.method.rawValue, uri: requestHead.uri, body: body)
            }.whenComplete { result in
                switch result {
                case .success(let response):
                    self.write(response: response, context: context)
                case .failure(let error):
                    let response = HTTPMeshServerResponse(
                        status: .internalServerError,
                        body: Data("{\"error\":\"\(String(describing: error))\"}".utf8),
                        contentType: "application/json"
                    )
                    self.write(response: response, context: context)
                }
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    private func write(response: HTTPMeshServerResponse, context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: response.contentType)
        headers.add(name: "Content-Length", value: "\(response.body.count)")
        headers.add(name: "Connection", value: "close")

        let head = HTTPResponseHead(version: .http1_1, status: response.status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        if !response.body.isEmpty {
            var buffer = context.channel.allocator.buffer(capacity: response.body.count)
            buffer.writeBytes(response.body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }

        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}

private extension EventLoopGroup {
    func asyncShutdownGracefully() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.shutdownGracefully { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
        guard let value = self else {
            throw error()
        }
        return value
    }
}
