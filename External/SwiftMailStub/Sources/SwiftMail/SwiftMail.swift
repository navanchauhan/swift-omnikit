import Foundation

public struct UID: Sendable, Hashable {
    public var value: Int

    public init(_ value: Int) {
        self.value = value
    }
}

public struct UIDValidity: Sendable, Hashable {
    public var value: Int

    public init(_ value: Int) {
        self.value = value
    }
}

public struct MessageIdentifierSet<Identifier: Sendable & Hashable>: Sendable, Hashable {
    public var rawValue: String

    public init?(
        string: String
    ) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.rawValue = trimmed
    }
}

public struct MailboxSelection: Sendable, Equatable {
    public var messageCount: Int

    public init(messageCount: Int = 0) {
        self.messageCount = messageCount
    }

    public func latest(_ limit: Int) -> MessageIdentifierSet<UID>? {
        guard messageCount > 0, limit > 0 else { return nil }
        let lower = max(1, messageCount - limit + 1)
        return MessageIdentifierSet<UID>(string: "\(lower):\(messageCount)")
    }
}

public struct MessageID: Sendable, Hashable, CustomStringConvertible {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public struct MessageHeader: Sendable, Equatable {
    public var messageId: MessageID?
    public var inReplyTo: MessageID?
    public var references: [MessageID]?

    public init(messageId: MessageID? = nil, inReplyTo: MessageID? = nil, references: [MessageID]? = nil) {
        self.messageId = messageId
        self.inReplyTo = inReplyTo
        self.references = references
    }
}

public struct Attachment: Sendable, Equatable {
    public var filename: String?
    public var contentType: String
    public var data: Data?

    public init(filename: String? = nil, contentType: String = "application/octet-stream", data: Data? = nil) {
        self.filename = filename
        self.contentType = contentType
        self.data = data
    }
}

public struct Message: Sendable, Equatable {
    public var uid: UID?
    public var date: Date?
    public var from: String?
    public var to: [String]
    public var cc: [String]
    public var subject: String?
    public var header: MessageHeader
    public var textBody: String?
    public var htmlBody: String?
    public var attachments: [Attachment]

    public init(
        uid: UID? = nil,
        date: Date? = nil,
        from: String? = nil,
        to: [String] = [],
        cc: [String] = [],
        subject: String? = nil,
        header: MessageHeader = MessageHeader(),
        textBody: String? = nil,
        htmlBody: String? = nil,
        attachments: [Attachment] = []
    ) {
        self.uid = uid
        self.date = date
        self.from = from
        self.to = to
        self.cc = cc
        self.subject = subject
        self.header = header
        self.textBody = textBody
        self.htmlBody = htmlBody
        self.attachments = attachments
    }

    public func preview(maxLength: Int) -> String {
        let body = textBody ?? htmlBody ?? ""
        guard body.count > maxLength else { return body }
        return String(body.prefix(maxLength))
    }
}

public struct EmailAddress: Sendable, Equatable {
    public var name: String?
    public var address: String

    public init(name: String?, address: String) {
        self.name = name
        self.address = address
    }
}

public struct Email: Sendable, Equatable {
    public var sender: EmailAddress
    public var recipients: [EmailAddress]
    public var ccRecipients: [EmailAddress]
    public var bccRecipients: [EmailAddress]
    public var subject: String
    public var textBody: String
    public var additionalHeaders: [String: String]?

    public init(
        sender: EmailAddress,
        recipients: [EmailAddress],
        ccRecipients: [EmailAddress] = [],
        bccRecipients: [EmailAddress] = [],
        subject: String,
        textBody: String
    ) {
        self.sender = sender
        self.recipients = recipients
        self.ccRecipients = ccRecipients
        self.bccRecipients = bccRecipients
        self.subject = subject
        self.textBody = textBody
        self.additionalHeaders = nil
    }
}

public struct DraftAppendResult: Sendable, Equatable {
    public var firstUID: UID?
    public var uidValidity: UIDValidity?

    public init(firstUID: UID? = nil, uidValidity: UIDValidity? = nil) {
        self.firstUID = firstUID
        self.uidValidity = uidValidity
    }
}

public final class IMAPServer: @unchecked Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    public func connect() async throws {}

    public func login(username: String, password: String) async throws {}

    public func disconnect() async throws {}

    public func selectMailbox(_ mailbox: String) async throws -> MailboxSelection {
        MailboxSelection()
    }

    public func fetchMessages(using set: MessageIdentifierSet<UID>) -> AsyncThrowingStream<Message, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    public func createDraft(from email: Email) async throws -> DraftAppendResult {
        DraftAppendResult()
    }
}

public final class SMTPServer: @unchecked Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    public func connect() async throws {}

    public func login(username: String, password: String) async throws {}

    public func disconnect() async throws {}

    public func sendEmail(_ email: Email) async throws {}
}
