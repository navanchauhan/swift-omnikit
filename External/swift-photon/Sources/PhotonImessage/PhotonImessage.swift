import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GRPC
import NIOPosix
import NIO
import SwiftProtobuf

public enum PhotonImessageError: Error, LocalizedError {
  case badCloudResponse(statusCode: Int, body: String)
  case tokenError(String)
  case invalidServerAddress(String)

  public var errorDescription: String? {
    switch self {
    case let .badCloudResponse(statusCode, body):
      "Cloud token request failed (\(statusCode)): \(body)"
    case let .tokenError(message):
      "Token error: \(message)"
    case let .invalidServerAddress(address):
      "Invalid server address: \(address)"
    }
  }
}

extension PhotonImessage.Session: @unchecked Sendable {}

public struct PhotonImessage {
  public struct Credentials: Sendable {
    public let projectId: String
    public let projectSecret: String

    public init(projectId: String, projectSecret: String) {
      self.projectId = projectId
      self.projectSecret = projectSecret
    }

    public static func fromEnvironment() -> Credentials? {
      let env = ProcessInfo.processInfo.environment
      guard
        let projectId = env["PHOTON_PROJECT_ID"], !projectId.isEmpty,
        let projectSecret = env["PHOTON_PROJECT_SECRET"] ?? env["PHOTON_SECRET_KEY"] ?? env["PHOTON_PROJECT_SECRET_KEY"],
        !projectSecret.isEmpty
      else {
        return nil
      }
      return Credentials(projectId: projectId, projectSecret: projectSecret)
    }
  }

  private struct CloudTokenEnvelope<T: Decodable>: Decodable {
    let succeed: Bool
    let data: T
  }

  private enum IssuedToken {
    case shared(token: String, expiresIn: Int64)
    case dedicated(auth: [String: String], expiresIn: Int64)
  }

  private struct TokenPayload: Decodable {
    let type: String
    let expiresIn: Int64
    let token: String?
    let auth: [String: String]?
  }

  private struct ServerSpec {
    let token: String
    let host: String
    let port: Int
  }

  private static let defaultCloudHost = "spectrum.photon.codes"
  private static let defaultSharedHost = "imessage.spectrum.photon.codes"
  private static let defaultSharedPort = 443

  private static func bearerAuth(projectId: String, projectSecret: String) -> String {
    let raw = "\(projectId):\(projectSecret)"
    let encoded = raw.data(using: .utf8)?.base64EncodedString() ?? ""
    return "Basic \(encoded)"
  }

  private static func fetchIssuedToken(from credentials: Credentials, cloudHost: String) async throws -> IssuedToken {
    let trimmedCloudHost = cloudHost.trimmingCharacters(in: .whitespacesAndNewlines)
    let baseCloudHost = (trimmedCloudHost.hasPrefix("http://") || trimmedCloudHost.hasPrefix("https://"))
      ? trimmedCloudHost
      : "https://\(trimmedCloudHost)"

    guard let url = URL(string: "\(baseCloudHost)/projects/\(credentials.projectId)/imessage/tokens") else {
      throw PhotonImessageError.badCloudResponse(statusCode: 0, body: "Invalid cloud URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(bearerAuth(projectId: credentials.projectId, projectSecret: credentials.projectSecret), forHTTPHeaderField: "Authorization")

    let (body, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse?), Error>) in
      let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
          continuation.resume(throwing: error)
          return
        }
        continuation.resume(returning: (data ?? Data(), response))
      }
      task.resume()
    }
    guard let status = (response as? HTTPURLResponse)?.statusCode else {
      throw PhotonImessageError.badCloudResponse(statusCode: 0, body: "No HTTP status")
    }
    guard (200..<300).contains(status) else {
      throw PhotonImessageError.badCloudResponse(statusCode: status, body: String(data: body, encoding: .utf8) ?? "")
    }

    if let wrapped = try? JSONDecoder().decode(CloudTokenEnvelope<TokenPayload>.self, from: body), wrapped.succeed {
      return try parseIssuedToken(wrapped.data)
    }

    if let direct = try? JSONDecoder().decode(TokenPayload.self, from: body) {
      return try parseIssuedToken(direct)
    }

    throw PhotonImessageError.badCloudResponse(
      statusCode: status,
      body: String(data: body, encoding: .utf8) ?? ""
    )
  }

  private static func parseIssuedToken(_ payload: TokenPayload) throws -> IssuedToken {
    switch payload.type {
    case "shared":
      guard let token = payload.token else {
        throw PhotonImessageError.tokenError("shared response missing token")
      }
      return .shared(token: token, expiresIn: payload.expiresIn)
    case "dedicated":
      guard let auth = payload.auth else {
        throw PhotonImessageError.tokenError("dedicated response missing auth map")
      }
      return .dedicated(auth: auth, expiresIn: payload.expiresIn)
    default:
      throw PhotonImessageError.tokenError("unsupported token type: \(payload.type)")
    }
  }

  private static func resolveServerAndToken(from issued: IssuedToken) throws -> ServerSpec {
    let env = ProcessInfo.processInfo.environment
    switch issued {
    case let .shared(token, _):
      let address = env["SPECTRUM_IMESSAGE_ADDRESS"] ?? "\(defaultSharedHost):\(defaultSharedPort)"
      let (host, port) = try parse(address: address)
      return ServerSpec(token: token, host: host, port: port)
    case let .dedicated(auth, _):
      guard let (instance, token) = auth.first else {
        throw PhotonImessageError.tokenError("dedicated auth map is empty")
      }
      return ServerSpec(token: token, host: "\(instance).imsg.photon.codes", port: 443)
    }
  }

  private static func parse(address: String) throws -> (host: String, port: Int) {
    guard let colon = address.lastIndex(of: ":") else {
      if address.isEmpty {
        throw PhotonImessageError.invalidServerAddress(address)
      }
      return (address, defaultSharedPort)
    }

    let host = String(address[..<colon])
    let portText = String(address[address.index(after: colon)...])
    guard let port = Int(portText), !host.isEmpty else {
      throw PhotonImessageError.invalidServerAddress(address)
    }
    return (host, port)
  }

  private static func closeChannel(_ channel: GRPCChannel) async {
    await withCheckedContinuation { continuation in
      channel.close().whenComplete { _ in
        continuation.resume()
      }
    }
  }

  private static func shutdownGroup(_ group: EventLoopGroup) async {
    do {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        group.shutdownGracefully { error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: ())
          }
        }
      }
    } catch {
      print("[iMessage] failed to shutdown event loop group: \(error)")
    }
  }

  private static func buildAuthOptions(token: String) -> CallOptions {
    CallOptions(customMetadata: ["authorization": "Bearer \(token)"])
  }

  public struct Session {
    public let serverHost: String
    public let serverPort: Int
    public let messageClient: PIMsg_MessageServiceAsyncClient
    public let chatClient: PIMsg_ChatServiceAsyncClient
    public let addressClient: PIMsg_AddressServiceAsyncClient
    public let attachmentClient: PIMsg_AttachmentServiceAsyncClient
    public let pollClient: PIMsg_PollServiceAsyncClient

    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let channel: GRPCChannel

    public static func connect(credentials: Credentials? = nil, cloudHost: String? = nil) async throws -> Session {
      guard let activeCredentials = credentials ?? Credentials.fromEnvironment() else {
        throw PhotonImessageError.tokenError(
          "Missing credentials. Set PHOTON_PROJECT_ID and PHOTON_PROJECT_SECRET (or PHOTON_SECRET_KEY / PHOTON_PROJECT_SECRET_KEY)."
        )
      }
      let hostForToken = cloudHost ?? ProcessInfo.processInfo.environment["SPECTRUM_CLOUD_URL"] ?? defaultCloudHost
      let issuedToken = try await fetchIssuedToken(from: activeCredentials, cloudHost: hostForToken)
      let serverSpec = try resolveServerAndToken(from: issuedToken)

      let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
      let tls = GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL()
      let channel = try GRPCChannelPool.with(
        target: .host(serverSpec.host, port: serverSpec.port),
        transportSecurity: .tls(tls),
        eventLoopGroup: group
      )

      let metadata = buildAuthOptions(token: serverSpec.token)
      return Session(
        serverHost: serverSpec.host,
        serverPort: serverSpec.port,
        messageClient: PIMsg_MessageServiceAsyncClient(channel: channel, defaultCallOptions: metadata),
        chatClient: PIMsg_ChatServiceAsyncClient(channel: channel, defaultCallOptions: metadata),
        addressClient: PIMsg_AddressServiceAsyncClient(channel: channel, defaultCallOptions: metadata),
        attachmentClient: PIMsg_AttachmentServiceAsyncClient(channel: channel, defaultCallOptions: metadata),
        pollClient: PIMsg_PollServiceAsyncClient(channel: channel, defaultCallOptions: metadata),
        eventLoopGroup: group,
        channel: channel
      )
    }

    public func close() async {
      await closeChannel(channel)
      await shutdownGroup(eventLoopGroup)
    }

    // MARK: Message operations

    public func send(
      chatGuid: String,
      message: String? = nil,
      clientMessageId: String? = nil,
      attributedBody: Data? = nil,
      subject: String? = nil,
      effectId: String? = nil,
      ddScan: Bool = false,
      richLink: Bool = false,
      attachmentPath: String? = nil,
      attachmentName: String? = nil,
      attachmentGuid: String? = nil,
      isAudioMessage: Bool = false,
      isSticker: Bool = false,
      selectedMessageGuid: String? = nil,
      partIndex: Int32 = 0
    ) async throws -> PIMsg_MessageSendReceipt {
      var request = PIMsg_SendRequest()
      request.chatGuid = chatGuid
      if let message {
        request.message = message
      }
      if let clientMessageId {
        request.clientMessageID = clientMessageId
      }
      if let attributedBody {
        request.attributedBody = attributedBody
      }
      if let subject {
        request.subject = subject
      }
      if let effectId {
        request.effectID = effectId
      }
      request.ddScan = ddScan
      request.richLink = richLink
      if let attachmentPath {
        request.attachmentPath = attachmentPath
      }
      if let attachmentName {
        request.attachmentName = attachmentName
      }
      if let attachmentGuid {
        request.attachmentGuid = attachmentGuid
      }
      request.isAudioMessage = isAudioMessage
      request.isSticker = isSticker
      request.partIndex = partIndex
      if let selectedMessageGuid {
        request.selectedMessageGuid = selectedMessageGuid
      }
      return try await messageClient.send(request).receipt
    }

    public func sendReaction(
      chatGuid: String,
      messageGuid: String,
      reaction: String,
      partIndex: Int32 = 0,
      emoji: String? = nil
    ) async throws -> PIMsg_MessageCommandReceipt {
      var request = PIMsg_SendReactionRequest()
      request.chatGuid = chatGuid
      request.messageGuid = messageGuid
      request.reaction = reaction
      request.partIndex = partIndex
      if let emoji {
        request.emoji = emoji
      }
      return try await messageClient.sendReaction(request).receipt
    }

    public func unreact(
      chatGuid: String,
      messageGuid: String,
      reaction: String,
      partIndex: Int32 = 0
    ) async throws -> PIMsg_MessageCommandReceipt {
      try await sendReaction(
        chatGuid: chatGuid,
        messageGuid: messageGuid,
        reaction: "-\(reaction)",
        partIndex: partIndex
      )
    }

    public func editMessage(
      chatGuid: String,
      messageGuid: String,
      newText: String,
      backwardCompatText: String? = nil,
      partIndex: Int32 = 0
    ) async throws {
      var request = PIMsg_EditMessageRequest()
      request.chatGuid = chatGuid
      request.messageGuid = messageGuid
      request.newText = newText
      if let backwardCompatText {
        request.backwardCompatText = backwardCompatText
      }
      request.partIndex = partIndex
      _ = try await messageClient.editMessage(request)
    }

    public func unsendMessage(
      chatGuid: String,
      messageGuid: String,
      partIndex: Int32 = 0
    ) async throws {
      var request = PIMsg_UnsendMessageRequest()
      request.chatGuid = chatGuid
      request.messageGuid = messageGuid
      request.partIndex = partIndex
      _ = try await messageClient.unsendMessage(request)
    }

    public func getMessage(guid: String) async throws -> PIMsg_Message {
      var request = PIMsg_GetMessageRequest()
      request.guid = guid
      return try await messageClient.getMessage(request).message
    }

    public func listMessages(
      chatGuid: String? = nil,
      sort: PIMsg_SortDirection = .unspecified,
      limit: Int32? = nil,
      offset: Int32 = 0,
      withChats: Bool = false,
      withAttachments: Bool = false,
      afterCursor: String? = nil,
      before: Date? = nil,
      after: Date? = nil
    ) async throws -> PIMsg_ListMessagesResponse {
      var request = PIMsg_ListMessagesRequest()
      if let chatGuid {
        request.chatGuid = chatGuid
      }
      request.sort = sort
      if let limit {
        request.limit = limit
      }
      request.offset = offset
      request.withChats = withChats
      request.withAttachments = withAttachments
      if let afterCursor {
        var cursor = PIMsg_StreamCursor()
        cursor.value = afterCursor
        request.afterCursor = cursor
      }
      if let before {
        request.before = Self.protobufTimestamp(from: before)
      }
      if let after {
        request.after = Self.protobufTimestamp(from: after)
      }
      return try await messageClient.listMessages(request)
    }

    public func fetchMissedMessages(
      afterCursor: String,
      chatGuid: String? = nil,
      limit: Int32? = nil,
      withChats: Bool = true,
      withAttachments: Bool = true
    ) async throws -> PIMsg_ListMessagesResponse {
      try await listMessages(
        chatGuid: chatGuid,
        sort: .ascending,
        limit: limit,
        offset: 0,
        withChats: withChats,
        withAttachments: withAttachments,
        afterCursor: afterCursor
      )
    }

    public func getEmbeddedMedia(
      chatGuid: String,
      messageGuid: String
    ) async throws -> [PIMsg_EmbeddedMediaItem] {
      var request = PIMsg_GetEmbeddedMediaRequest()
      request.chatGuid = chatGuid
      request.messageGuid = messageGuid
      return try await messageClient.getEmbeddedMedia(request).items
    }

    public func getMessageStats() async throws -> PIMsg_GetMessageStatsResponse {
      try await messageClient.getMessageStats(PIMsg_GetMessageStatsRequest())
    }

    public func subscribeMessageEvents(
      cursor: String? = nil
    ) -> GRPCAsyncResponseStream<PIMsg_SubscribeMessageEventsResponse> {
      var request = PIMsg_SubscribeMessageEventsRequest()
      if let cursor {
        var streamCursor = PIMsg_StreamCursor()
        streamCursor.value = cursor
        request.cursor = streamCursor
      }
      return messageClient.subscribeMessageEvents(request)
    }

    // MARK: Chat operations

    public func createChat(
      addresses: [String],
      message: String? = nil,
      service: String = "iMessage",
      effectId: String? = nil,
      subject: String? = nil,
      clientMessageId: String? = nil
    ) async throws -> PIMsg_CreateChatResponse {
      var request = PIMsg_CreateChatRequest()
      request.addresses = addresses
      if let message {
        request.message = message
      }
      request.service = service
      if let effectId {
        request.effectID = effectId
      }
      if let subject {
        request.subject = subject
      }
      if let clientMessageId {
        request.clientMessageID = clientMessageId
      }
      return try await chatClient.createChat(request)
    }

    public func getChat(guid: String) async throws -> PIMsg_Chat {
      var request = PIMsg_GetChatRequest()
      request.guid = guid
      return try await chatClient.getChat(request).chat
    }

    public func getChatCount(includeArchived: Bool) async throws -> Int64 {
      var request = PIMsg_GetChatCountRequest()
      request.includeArchived = includeArchived
      return try await chatClient.getChatCount(request).count
    }

    public func leaveChat(guid: String) async throws {
      var request = PIMsg_LeaveChatRequest()
      request.guid = guid
      _ = try await chatClient.leaveChat(request)
    }

    public func markRead(chatGuid: String) async throws {
      var request = PIMsg_MarkReadRequest()
      request.chatGuid = chatGuid
      _ = try await chatClient.markRead(request)
    }

    public func shareContactInfo(chatGuid: String) async throws {
      var request = PIMsg_ShareContactInfoRequest()
      request.chatGuid = chatGuid
      _ = try await chatClient.shareContactInfo(request)
    }

    public func startTyping(chatGuid: String) async throws {
      var request = PIMsg_StartTypingRequest()
      request.chatGuid = chatGuid
      _ = try await chatClient.startTyping(request)
    }

    public func stopTyping(chatGuid: String) async throws {
      var request = PIMsg_StopTypingRequest()
      request.chatGuid = chatGuid
      _ = try await chatClient.stopTyping(request)
    }

    public func getParticipants(chatGuid: String) async throws -> [PIMsg_AddressInfo] {
      var request = PIMsg_GetParticipantsRequest()
      request.chatGuid = chatGuid
      return try await chatClient.getParticipants(request).participants
    }

    public func subscribeChatEvents() -> GRPCAsyncResponseStream<PIMsg_SubscribeChatEventsResponse> {
      let request = PIMsg_SubscribeChatEventsRequest()
      return chatClient.subscribeChatEvents(request)
    }

    // MARK: Address operations

    public func getAddress(address: String) async throws -> PIMsg_AddressInfo {
      var request = PIMsg_GetAddressRequest()
      request.address = address
      return try await addressClient.getAddress(request).address
    }

    public func getFocusStatus(address: String) async throws -> Bool {
      var request = PIMsg_GetFocusStatusRequest()
      request.address = address
      return try await addressClient.getFocusStatus(request).isFocused
    }

    public func checkAvailability(address: String, type: PIMsg_AvailabilityType = .imessage) async throws -> Bool {
      var request = PIMsg_CheckAvailabilityRequest()
      request.address = address
      request.type = type
      return try await addressClient.checkAvailability(request).available
    }

    // MARK: Attachment operations

    public func getAttachment(guid: String) async throws -> PIMsg_AttachmentInfo {
      var request = PIMsg_GetAttachmentRequest()
      request.guid = guid
      return try await attachmentClient.getAttachment(request).attachment
    }

    public func getAttachmentCount() async throws -> Int64 {
      let request = PIMsg_GetAttachmentCountRequest()
      return try await attachmentClient.getAttachmentCount(request).count
    }

    public func uploadAttachment(filePath: String) async throws -> PIMsg_UploadResponse {
      let path = URL(fileURLWithPath: filePath)
      let fileData = try Data(contentsOf: path)
      var request = PIMsg_UploadRequest()
      request.fileName = path.lastPathComponent
      request.mimeType = Self.mimeType(for: path.pathExtension)
      request.data = fileData
      return try await attachmentClient.upload(request)
    }

    public func downloadAttachment(guid: String) async throws -> Data {
      var request = PIMsg_DownloadRequest()
      request.attachmentGuid = guid
      let stream = attachmentClient.download(request)
      var payload = Data()
      for try await response in stream {
        payload.append(response.data)
      }
      return payload
    }

    public func getLivePhoto(guid: String) async throws -> Data {
      var request = PIMsg_GetLivePhotoRequest()
      request.attachmentGuid = guid
      let stream = attachmentClient.getLivePhoto(request)
      var payload = Data()
      for try await response in stream {
        payload.append(response.data)
      }
      return payload
    }

    // MARK: Poll operations

    public func createPoll(
      chatGuid: String,
      title: String,
      options: [String]
    ) async throws -> PIMsg_MessageCommandReceipt {
      var request = PIMsg_CreatePollRequest()
      request.chatGuid = chatGuid
      request.title = title
      request.options = options
      return try await pollClient.createPoll(request).receipt
    }

    public func vote(
      chatGuid: String,
      pollMessageGuid: String,
      optionIdentifier: String
    ) async throws -> PIMsg_MessageCommandReceipt {
      var request = PIMsg_VoteRequest()
      request.chatGuid = chatGuid
      request.pollMessageGuid = pollMessageGuid
      request.optionIdentifier = optionIdentifier
      return try await pollClient.vote(request).receipt
    }

    public func unvote(
      chatGuid: String,
      pollMessageGuid: String
    ) async throws -> PIMsg_MessageCommandReceipt {
      var request = PIMsg_UnvoteRequest()
      request.chatGuid = chatGuid
      request.pollMessageGuid = pollMessageGuid
      return try await pollClient.unvote(request).receipt
    }

    public func addPollOption(
      chatGuid: String,
      pollMessageGuid: String,
      optionText: String
    ) async throws -> PIMsg_MessageCommandReceipt {
      var request = PIMsg_AddOptionRequest()
      request.chatGuid = chatGuid
      request.pollMessageGuid = pollMessageGuid
      request.optionText = optionText
      return try await pollClient.addOption(request).receipt
    }

    public func getPoll(messageGuid: String) async throws -> PIMsg_PollInfo {
      var request = PIMsg_GetPollRequest()
      request.messageGuid = messageGuid
      return try await pollClient.getPoll(request).poll
    }

    public func subscribePollEvents() -> GRPCAsyncResponseStream<PIMsg_SubscribePollEventsResponse> {
      let request = PIMsg_SubscribePollEventsRequest()
      return pollClient.subscribePollEvents(request)
    }

    // MARK: Stream helpers

    private static func mimeType(for extensionName: String) -> String {
      switch extensionName.lowercased() {
      case "png": return "image/png"
      case "jpg", "jpeg": return "image/jpeg"
      case "gif": return "image/gif"
      case "webp": return "image/webp"
      case "heic": return "image/heic"
      case "mp4": return "video/mp4"
      case "mov", "qt": return "video/quicktime"
      case "mp3": return "audio/mpeg"
      case "aac": return "audio/aac"
      case "wav": return "audio/wav"
      case "m4a": return "audio/m4a"
      case "txt": return "text/plain"
      case "pdf": return "application/pdf"
      case "json": return "application/json"
      case "zip": return "application/zip"
      default: return "application/octet-stream"
      }
    }

    private static func protobufTimestamp(from date: Date) -> SwiftProtobuf.Google_Protobuf_Timestamp {
      let interval = date.timeIntervalSince1970
      let seconds = Int64(interval)
      let nanos = Int32((interval - Double(seconds)) * 1_000_000_000)

      var timestamp = SwiftProtobuf.Google_Protobuf_Timestamp()
      timestamp.seconds = seconds
      timestamp.nanos = nanos
      return timestamp
    }
  }

  public static func runHelloWorld(credentials: Credentials? = nil) async throws {
    let session = try await Session.connect(credentials: credentials)
    print("[iMessage] connected to \(session.serverHost):\(session.serverPort)")

    do {
      let request = PIMsg_SubscribeMessageEventsRequest()
      for try await response in session.messageClient.subscribeMessageEvents(request) {
        guard let payload = response.payload else {
          continue
        }

        switch payload {
        case .messageReceived(let event):
          let inboundMessage = event.message
          guard inboundMessage.hasText else {
            continue
          }
          let sender = inboundMessage.sender.address.isEmpty ? "unknown" : inboundMessage.sender.address
          print("[iMessage] received: [\(sender)] \(inboundMessage.text)")

          let chatGuid = event.chatGuid.isEmpty ? inboundMessage.chatGuids.first ?? "" : event.chatGuid
          guard !chatGuid.isEmpty else {
            continue
          }

          do {
            _ = try await session.send(
              chatGuid: chatGuid,
              message: "hello world",
              effectId: "com.apple.MobileSMS.effect.impact"
            )
          } catch {
            print("[iMessage] failed to send: \(error)")
          }
        case .messageSent(let event):
          print("[iMessage] sent message event: \(event.message.guid)")
        case .messageUpdated(let event):
          print("[iMessage] updated message event: \(event.message.guid) \(event.updateType)")
        case .heartbeat:
          continue
        }
      }
    } catch {
      print("[iMessage] stream ended: \(error)")
    }

    await session.close()
  }
}
