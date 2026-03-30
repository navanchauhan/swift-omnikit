import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol TelegramBotAPI: Sendable {
    func getMe() async throws -> TelegramUser
    func getUpdates(
        offset: Int?,
        timeoutSeconds: Int,
        allowedUpdates: [String],
        limit: Int
    ) async throws -> [TelegramUpdate]
    func sendMessage(_ request: TelegramSendMessageRequest) async throws -> TelegramMessage
    func answerCallbackQuery(
        callbackQueryID: String,
        text: String?,
        showAlert: Bool
    ) async throws
    func setWebhook(url: String, secretToken: String?, allowedUpdates: [String]) async throws
    func deleteWebhook(dropPendingUpdates: Bool) async throws
}

public enum TelegramBotClientError: Error, CustomStringConvertible, Sendable {
    case invalidResponse
    case apiError(description: String)

    public var description: String {
        switch self {
        case .invalidResponse:
            return "Telegram returned an invalid HTTP response."
        case .apiError(let description):
            return "Telegram API error: \(description)"
        }
    }
}

public struct TelegramUser: Codable, Sendable, Equatable {
    public var id: Int64
    public var isBot: Bool
    public var firstName: String
    public var lastName: String?
    public var username: String?

    enum CodingKeys: String, CodingKey {
        case id
        case isBot = "is_bot"
        case firstName = "first_name"
        case lastName = "last_name"
        case username
    }

    public init(
        id: Int64,
        isBot: Bool,
        firstName: String,
        lastName: String? = nil,
        username: String? = nil
    ) {
        self.id = id
        self.isBot = isBot
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
    }
}

public struct TelegramChat: Codable, Sendable, Equatable {
    public enum ChatType: String, Codable, Sendable {
        case `private`
        case group
        case supergroup
        case channel
    }

    public var id: Int64
    public var type: ChatType
    public var title: String?
    public var username: String?
    public var firstName: String?
    public var lastName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case username
        case firstName = "first_name"
        case lastName = "last_name"
    }

    public init(
        id: Int64,
        type: ChatType,
        title: String? = nil,
        username: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.username = username
        self.firstName = firstName
        self.lastName = lastName
    }
}

public struct TelegramReplyMessage: Codable, Sendable, Equatable {
    public var messageID: Int64
    public var from: TelegramUser?
    public var chat: TelegramChat
    public var text: String?

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case from
        case chat
        case text
    }

    public init(
        messageID: Int64,
        from: TelegramUser? = nil,
        chat: TelegramChat,
        text: String? = nil
    ) {
        self.messageID = messageID
        self.from = from
        self.chat = chat
        self.text = text
    }
}

public struct TelegramMessage: Codable, Sendable, Equatable {
    public var messageID: Int64
    public var from: TelegramUser?
    public var chat: TelegramChat
    public var date: Int64
    public var text: String?
    public var replyToMessage: TelegramReplyMessage?
    public var messageThreadID: Int64?
    public var hasUnsupportedMedia: Bool

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case from
        case chat
        case date
        case text
        case replyToMessage = "reply_to_message"
        case messageThreadID = "message_thread_id"
        case photo
        case document
        case audio
        case voice
        case sticker
        case video
        case animation
    }

    public init(
        messageID: Int64,
        from: TelegramUser?,
        chat: TelegramChat,
        date: Int64,
        text: String?,
        replyToMessage: TelegramReplyMessage? = nil,
        messageThreadID: Int64? = nil,
        hasUnsupportedMedia: Bool = false
    ) {
        self.messageID = messageID
        self.from = from
        self.chat = chat
        self.date = date
        self.text = text
        self.replyToMessage = replyToMessage
        self.messageThreadID = messageThreadID
        self.hasUnsupportedMedia = hasUnsupportedMedia
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let photo = try container.decodeIfPresent([JSONObject].self, forKey: .photo)
        let document = try container.decodeIfPresent(JSONObject.self, forKey: .document)
        let audio = try container.decodeIfPresent(JSONObject.self, forKey: .audio)
        let voice = try container.decodeIfPresent(JSONObject.self, forKey: .voice)
        let sticker = try container.decodeIfPresent(JSONObject.self, forKey: .sticker)
        let video = try container.decodeIfPresent(JSONObject.self, forKey: .video)
        let animation = try container.decodeIfPresent(JSONObject.self, forKey: .animation)

        self.messageID = try container.decode(Int64.self, forKey: .messageID)
        self.from = try container.decodeIfPresent(TelegramUser.self, forKey: .from)
        self.chat = try container.decode(TelegramChat.self, forKey: .chat)
        self.date = try container.decode(Int64.self, forKey: .date)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.replyToMessage = try container.decodeIfPresent(TelegramReplyMessage.self, forKey: .replyToMessage)
        self.messageThreadID = try container.decodeIfPresent(Int64.self, forKey: .messageThreadID)
        self.hasUnsupportedMedia = photo != nil || document != nil || audio != nil || voice != nil || sticker != nil || video != nil || animation != nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageID, forKey: .messageID)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encode(chat, forKey: .chat)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(replyToMessage, forKey: .replyToMessage)
        try container.encodeIfPresent(messageThreadID, forKey: .messageThreadID)
    }
}

public struct TelegramCallbackQuery: Codable, Sendable, Equatable {
    public var id: String
    public var from: TelegramUser
    public var message: TelegramMessage?
    public var data: String?

    enum CodingKeys: String, CodingKey {
        case id
        case from
        case message
        case data
    }

    public init(
        id: String,
        from: TelegramUser,
        message: TelegramMessage? = nil,
        data: String? = nil
    ) {
        self.id = id
        self.from = from
        self.message = message
        self.data = data
    }
}

public struct TelegramUpdate: Codable, Sendable, Equatable {
    public var updateID: Int
    public var message: TelegramMessage?
    public var callbackQuery: TelegramCallbackQuery?

    enum CodingKeys: String, CodingKey {
        case updateID = "update_id"
        case message
        case callbackQuery = "callback_query"
    }

    public init(
        updateID: Int,
        message: TelegramMessage? = nil,
        callbackQuery: TelegramCallbackQuery? = nil
    ) {
        self.updateID = updateID
        self.message = message
        self.callbackQuery = callbackQuery
    }
}

public struct TelegramInlineKeyboardButton: Codable, Sendable, Equatable {
    public var text: String
    public var callbackData: String?

    enum CodingKeys: String, CodingKey {
        case text
        case callbackData = "callback_data"
    }

    public init(text: String, callbackData: String? = nil) {
        self.text = text
        self.callbackData = callbackData
    }
}

public struct TelegramInlineKeyboardMarkup: Codable, Sendable, Equatable {
    public var inlineKeyboard: [[TelegramInlineKeyboardButton]]

    enum CodingKeys: String, CodingKey {
        case inlineKeyboard = "inline_keyboard"
    }

    public init(inlineKeyboard: [[TelegramInlineKeyboardButton]]) {
        self.inlineKeyboard = inlineKeyboard
    }
}

public enum TelegramParseMode: String, Codable, Sendable, Equatable {
    case html = "HTML"
}

public struct TelegramSendMessageRequest: Codable, Sendable, Equatable {
    public var chatID: String
    public var text: String
    public var parseMode: TelegramParseMode?
    public var messageThreadID: Int64?
    public var replyMarkup: TelegramInlineKeyboardMarkup?

    enum CodingKeys: String, CodingKey {
        case chatID = "chat_id"
        case text
        case parseMode = "parse_mode"
        case messageThreadID = "message_thread_id"
        case replyMarkup = "reply_markup"
    }

    public init(
        chatID: String,
        text: String,
        parseMode: TelegramParseMode? = nil,
        messageThreadID: Int64? = nil,
        replyMarkup: TelegramInlineKeyboardMarkup? = nil
    ) {
        self.chatID = chatID
        self.text = text
        self.parseMode = parseMode
        self.messageThreadID = messageThreadID
        self.replyMarkup = replyMarkup
    }
}

public actor TelegramBotClient: TelegramBotAPI {
    private struct Envelope<Result: Decodable>: Decodable {
        let ok: Bool
        let result: Result?
        let description: String?
    }

    private let token: String
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        token: String,
        configuration: URLSessionConfiguration = .ephemeral
    ) {
        self.token = token
        self.session = URLSession(configuration: configuration)
    }

    public func getMe() async throws -> TelegramUser {
        try await request(method: "getMe", payload: EmptyPayload(), responseType: TelegramUser.self)
    }

    public func getUpdates(
        offset: Int?,
        timeoutSeconds: Int,
        allowedUpdates: [String],
        limit: Int = 100
    ) async throws -> [TelegramUpdate] {
        try await request(
            method: "getUpdates",
            payload: GetUpdatesPayload(
                offset: offset,
                timeout: timeoutSeconds,
                allowedUpdates: allowedUpdates,
                limit: limit
            ),
            responseType: [TelegramUpdate].self
        )
    }

    public func sendMessage(_ request: TelegramSendMessageRequest) async throws -> TelegramMessage {
        try await self.request(method: "sendMessage", payload: request, responseType: TelegramMessage.self)
    }

    public func answerCallbackQuery(
        callbackQueryID: String,
        text: String? = nil,
        showAlert: Bool = false
    ) async throws {
        _ = try await request(
            method: "answerCallbackQuery",
            payload: AnswerCallbackQueryPayload(
                callbackQueryID: callbackQueryID,
                text: text,
                showAlert: showAlert
            ),
            responseType: Bool.self
        )
    }

    public func setWebhook(url: String, secretToken: String?, allowedUpdates: [String]) async throws {
        _ = try await request(
            method: "setWebhook",
            payload: SetWebhookPayload(
                url: url,
                secretToken: secretToken,
                allowedUpdates: allowedUpdates
            ),
            responseType: Bool.self
        )
    }

    public func deleteWebhook(dropPendingUpdates: Bool) async throws {
        _ = try await request(
            method: "deleteWebhook",
            payload: DeleteWebhookPayload(dropPendingUpdates: dropPendingUpdates),
            responseType: Bool.self
        )
    }

    private func request<Payload: Encodable, Result: Decodable>(
        method: String,
        payload: Payload,
        responseType: Result.Type
    ) async throws -> Result {
        var request = URLRequest(url: URL(string: "https://api.telegram.org/bot\(token)/\(method)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TelegramBotClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TelegramBotClientError.apiError(description: String(decoding: data, as: UTF8.self))
        }

        let envelope = try decoder.decode(Envelope<Result>.self, from: data)
        guard envelope.ok, let result = envelope.result else {
            throw TelegramBotClientError.apiError(description: envelope.description ?? "Unknown Telegram error")
        }
        return result
    }
}

private struct EmptyPayload: Encodable {}

private struct GetUpdatesPayload: Encodable {
    let offset: Int?
    let timeout: Int
    let allowedUpdates: [String]
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case offset
        case timeout
        case allowedUpdates = "allowed_updates"
        case limit
    }
}

private struct AnswerCallbackQueryPayload: Encodable {
    let callbackQueryID: String
    let text: String?
    let showAlert: Bool

    enum CodingKeys: String, CodingKey {
        case callbackQueryID = "callback_query_id"
        case text
        case showAlert = "show_alert"
    }
}

private struct SetWebhookPayload: Encodable {
    let url: String
    let secretToken: String?
    let allowedUpdates: [String]

    enum CodingKeys: String, CodingKey {
        case url
        case secretToken = "secret_token"
        case allowedUpdates = "allowed_updates"
    }
}

private struct DeleteWebhookPayload: Encodable {
    let dropPendingUpdates: Bool

    enum CodingKeys: String, CodingKey {
        case dropPendingUpdates = "drop_pending_updates"
    }
}

private struct JSONObject: Codable, Sendable, Equatable {}
