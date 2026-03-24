import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import OmniAgentMesh
import TheAgentControlPlaneKit

public actor HTTPIngressServer {
    public struct ListeningAddress: Sendable {
        public let host: String
        public let port: Int

        public var baseURL: URL {
            URL(string: "http://\(host):\(port)")!
        }
    }

    public struct MessageRequest: Codable, Sendable {
        public var transport: ChannelBinding.Transport
        public var actorExternalID: String
        public var actorDisplayName: String?
        public var channelExternalID: String
        public var channelKind: IngressEnvelope.ChannelKind
        public var text: String
        public var mentionTriggerActive: Bool
        public var replyContextActive: Bool
        public var metadata: [String: String]

        public init(
            transport: ChannelBinding.Transport = .api,
            actorExternalID: String,
            actorDisplayName: String? = nil,
            channelExternalID: String,
            channelKind: IngressEnvelope.ChannelKind = .api,
            text: String,
            mentionTriggerActive: Bool = false,
            replyContextActive: Bool = false,
            metadata: [String: String] = [:]
        ) {
            self.transport = transport
            self.actorExternalID = actorExternalID
            self.actorDisplayName = actorDisplayName
            self.channelExternalID = channelExternalID
            self.channelKind = channelKind
            self.text = text
            self.mentionTriggerActive = mentionTriggerActive
            self.replyContextActive = replyContextActive
            self.metadata = metadata
        }
    }

    public struct ScopeRequest: Codable, Sendable {
        public var sessionID: String?
        public var workspaceID: String?
        public var channelID: String?
        public var actorID: String?
        public var unresolvedOnly: Bool?

        public init(
            sessionID: String? = nil,
            workspaceID: String? = nil,
            channelID: String? = nil,
            actorID: String? = nil,
            unresolvedOnly: Bool? = nil
        ) {
            self.sessionID = sessionID
            self.workspaceID = workspaceID
            self.channelID = channelID
            self.actorID = actorID
            self.unresolvedOnly = unresolvedOnly
        }
    }

    public struct ApprovalDecisionRequest: Codable, Sendable {
        public var sessionID: String?
        public var workspaceID: String?
        public var channelID: String?
        public var actorID: String?
        public var requestID: String
        public var approved: Bool
        public var responseText: String?
    }

    public struct QuestionAnswerRequest: Codable, Sendable {
        public var sessionID: String?
        public var workspaceID: String?
        public var channelID: String?
        public var actorID: String?
        public var requestID: String
        public var answerText: String
    }

    public typealias TelegramWebhookForwarder = @Sendable (Data, [String: String]) async -> Void

    private let gateway: IngressGateway
    private let runtimeRegistry: WorkspaceRuntimeRegistry
    private let expectedBearerToken: String?
    private let telegramWebhookForwarder: TelegramWebhookForwarder?
    private let host: String
    private let port: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var channel: Channel?

    public init(
        gateway: IngressGateway,
        runtimeRegistry: WorkspaceRuntimeRegistry,
        expectedBearerToken: String? = nil,
        telegramWebhookForwarder: TelegramWebhookForwarder? = nil,
        host: String = "127.0.0.1",
        port: Int = 0
    ) {
        self.gateway = gateway
        self.runtimeRegistry = runtimeRegistry
        self.expectedBearerToken = expectedBearerToken
        self.telegramWebhookForwarder = telegramWebhookForwarder
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
                    channel.pipeline.addHandler(HTTPIngressRequestHandler(server: self))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)

        do {
            let channel = try await bootstrap.bind(host: host, port: port).get()
            self.eventLoopGroup = group
            self.channel = channel
            return try listeningAddress().unwrap(or: HTTPIngressServerError.missingListeningAddress)
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
        return ListeningAddress(host: localAddress.ipAddress ?? host, port: actualPort)
    }

    fileprivate func handle(
        method: String,
        uri: String,
        headers: HTTPHeaders,
        body: Data?
    ) async throws -> HTTPIngressServerResponse {
        guard method == "POST" else {
            return errorResponse(status: .methodNotAllowed, message: "Only POST is supported.")
        }

        let path = sanitizedPath(uri)
        if path == "/health" {
            return try jsonResponse(["value": "ok"])
        }
        if path == "/telegram/webhook" {
            guard let body else {
                return errorResponse(status: .badRequest, message: "Telegram webhook body is required.")
            }
            if let telegramWebhookForwarder {
                let headerMap = Dictionary(uniqueKeysWithValues: headers.map { ($0.name.lowercased(), $0.value) })
                Task {
                    await telegramWebhookForwarder(body, headerMap)
                }
                return try jsonResponse(["value": "accepted"])
            }
            return errorResponse(status: .notFound, message: "Telegram webhook handling is not configured.")
        }

        do {
            try validateAuthorization(headers: headers)
            switch path {
            case "/api/v1/messages":
                let request: MessageRequest = try decode(body)
                let result = try await gateway.handle(
                    IngressEnvelope(
                        transport: request.transport,
                        payloadKind: .text,
                        actorExternalID: request.actorExternalID,
                        actorDisplayName: request.actorDisplayName,
                        channelExternalID: request.channelExternalID,
                        channelKind: request.channelKind,
                        text: request.text,
                        mentionTriggerActive: request.mentionTriggerActive,
                        replyContextActive: request.replyContextActive,
                        metadata: request.metadata
                    )
                )
                return try jsonResponse(HTTPIngressMessageResponse(result: result))
            case "/api/v1/inbox":
                let request: ScopeRequest = try decode(body)
                let runtime = try await resolveRuntime(for: request)
                let items = try await runtime.server.listInbox(unresolvedOnly: request.unresolvedOnly ?? true)
                return try jsonResponse(items)
            case "/api/v1/approvals":
                let request: ApprovalDecisionRequest = try decode(body)
                let runtime = try await resolveRuntime(
                    sessionID: request.sessionID,
                    workspaceID: request.workspaceID,
                    channelID: request.channelID,
                    actorID: request.actorID
                )
                let approval = try await runtime.server.approveRequest(
                    requestID: request.requestID,
                    approved: request.approved,
                    actorID: request.actorID.map(ActorID.init(rawValue:)),
                    responseText: request.responseText
                )
                return try jsonResponse(approval)
            case "/api/v1/questions":
                let request: QuestionAnswerRequest = try decode(body)
                let runtime = try await resolveRuntime(
                    sessionID: request.sessionID,
                    workspaceID: request.workspaceID,
                    channelID: request.channelID,
                    actorID: request.actorID
                )
                let question = try await runtime.server.answerQuestion(
                    requestID: request.requestID,
                    answerText: request.answerText,
                    actorID: request.actorID.map(ActorID.init(rawValue:))
                )
                return try jsonResponse(question)
            default:
                return errorResponse(status: .notFound, message: "Unknown ingress endpoint \(path)")
            }
        } catch let error as HTTPIngressServerError {
            return errorResponse(status: .badRequest, message: error.description)
        } catch {
            return errorResponse(status: .internalServerError, message: String(describing: error))
        }
    }

    private func validateAuthorization(headers: HTTPHeaders) throws {
        guard let expectedBearerToken, !expectedBearerToken.isEmpty else {
            return
        }
        guard let authorization = headers.first(name: "Authorization") ?? headers.first(name: "authorization") else {
            throw HTTPIngressServerError.missingAuthorization
        }
        guard authorization == "Bearer \(expectedBearerToken)" else {
            throw HTTPIngressServerError.invalidAuthorization
        }
    }

    private func resolveRuntime(for request: ScopeRequest) async throws -> RootAgentRuntime {
        try await resolveRuntime(
            sessionID: request.sessionID,
            workspaceID: request.workspaceID,
            channelID: request.channelID,
            actorID: request.actorID
        )
    }

    private func resolveRuntime(
        sessionID: String?,
        workspaceID: String?,
        channelID: String?,
        actorID: String?
    ) async throws -> RootAgentRuntime {
        if let sessionID, !sessionID.isEmpty {
            return try await runtimeRegistry.runtime(sessionID: sessionID)
        }
        guard let workspaceID, let channelID else {
            throw HTTPIngressServerError.invalidScope
        }
        let scope = SessionScope(
            actorID: actorID.map(ActorID.init(rawValue:)) ?? ActorID(rawValue: "\(workspaceID)-root"),
            workspaceID: WorkspaceID(rawValue: workspaceID),
            channelID: ChannelID(rawValue: channelID)
        )
        return try await runtimeRegistry.runtime(for: scope)
    }

    private func decode<Request: Decodable>(_ body: Data?) throws -> Request {
        guard let body else {
            throw HTTPIngressServerError.missingRequestBody
        }
        do {
            return try decoder.decode(Request.self, from: body)
        } catch {
            throw HTTPIngressServerError.invalidRequestBody(String(describing: error))
        }
    }

    private func jsonResponse<Response: Encodable>(_ payload: Response) throws -> HTTPIngressServerResponse {
        let data = try encoder.encode(payload)
        return HTTPIngressServerResponse(status: .ok, body: data, contentType: "application/json")
    }

    private func errorResponse(status: HTTPResponseStatus, message: String) -> HTTPIngressServerResponse {
        let data = (try? encoder.encode(["error": message])) ?? Data("{\"error\":\"\(message)\"}".utf8)
        return HTTPIngressServerResponse(status: status, body: data, contentType: "application/json")
    }

    private func sanitizedPath(_ uri: String) -> String {
        URLComponents(string: "http://ingress\(uri)")?.path ?? uri
    }
}

private struct HTTPIngressMessageResponse: Codable {
    let disposition: String
    let assistantText: String?
    let deliveries: [IngressDeliveryInstruction]

    init(result: IngressGatewayResult) {
        self.disposition = result.disposition.rawValue
        self.assistantText = result.assistantText
        self.deliveries = result.deliveries
    }
}

private struct HTTPIngressServerResponse: Sendable {
    let status: HTTPResponseStatus
    let body: Data
    let contentType: String
}

private enum HTTPIngressServerError: Error, CustomStringConvertible {
    case missingListeningAddress
    case missingRequestBody
    case invalidRequestBody(String)
    case missingAuthorization
    case invalidAuthorization
    case invalidScope

    var description: String {
        switch self {
        case .missingListeningAddress:
            return "HTTP ingress server is not bound to a listening address."
        case .missingRequestBody:
            return "HTTP ingress request body is required."
        case .invalidRequestBody(let message):
            return "HTTP ingress request body could not be decoded: \(message)"
        case .missingAuthorization:
            return "Missing bearer authorization."
        case .invalidAuthorization:
            return "Invalid bearer authorization."
        case .invalidScope:
            return "Either session_id or workspace_id + channel_id must be supplied."
        }
    }
}

private final class HTTPIngressRequestHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let server: HTTPIngressServer
    private var requestHead: HTTPRequestHead?
    private var requestBody = ByteBuffer()

    init(server: HTTPIngressServer) {
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
                write(
                    response: HTTPIngressServerResponse(
                        status: .badRequest,
                        body: Data("{\"error\":\"Missing request head\"}".utf8),
                        contentType: "application/json"
                    ),
                    context: context
                )
                return
            }

            let body = Data(requestBody.readableBytesView)
            let contextBox = HTTPIngressContextBox(context)
            context.eventLoop.makeFutureWithTask {
                try await self.server.handle(
                    method: requestHead.method.rawValue,
                    uri: requestHead.uri,
                    headers: requestHead.headers,
                    body: body
                )
            }.whenComplete { result in
                switch result {
                case .success(let response):
                    self.write(response: response, context: contextBox.context)
                case .failure(let error):
                    self.write(
                        response: HTTPIngressServerResponse(
                            status: .internalServerError,
                            body: Data("{\"error\":\"\(String(describing: error))\"}".utf8),
                            contentType: "application/json"
                        ),
                        context: contextBox.context
                    )
                }
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    private func write(response: HTTPIngressServerResponse, context: ChannelHandlerContext) {
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
        let contextBox = HTTPIngressContextBox(context)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            contextBox.context.close(promise: nil)
        }
    }
}

private final class HTTPIngressContextBox: @unchecked Sendable {
    let context: ChannelHandlerContext

    init(_ context: ChannelHandlerContext) {
        self.context = context
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
