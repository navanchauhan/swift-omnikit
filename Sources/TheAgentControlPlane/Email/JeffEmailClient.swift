import Foundation
import SwiftMail

struct JeffEmailMessageSummary: Sendable {
    var accountID: String
    var uid: String
    var date: Date?
    var from: String?
    var to: [String]
    var subject: String?
    var preview: String
    var hasAttachments: Bool

    func json() -> [String: Any] {
        [
            "account_id": accountID,
            "uid": uid,
            "date": date?.ISO8601Format() ?? NSNull(),
            "from": from ?? NSNull(),
            "to": to,
            "subject": subject ?? NSNull(),
            "preview": preview,
            "has_attachments": hasAttachments,
        ]
    }
}

struct JeffEmailClient {
    struct Config: Sendable {
        var accountID: String
        var displayName: String
        var imapHost: String
        var imapPort: Int
        var imapUsername: String
        var imapPassword: String
        var smtpHost: String?
        var smtpPort: Int
        var smtpUsername: String
        var smtpPassword: String
        var fromName: String?
        var fromAddress: String
        var signature: String?

        static func load(accountID requestedAccountID: String? = nil) throws -> Config {
            let env = ProcessInfo.processInfo.environment.merging(loadDotEnv()) { current, _ in current }
            let accountID = normalizeAccountID(requestedAccountID ?? optional("EMAIL_DEFAULT_ACCOUNT", env: env) ?? "jeff")
            let prefix = accountID == "jeff" ? "EMAIL_" : "EMAIL_ACCOUNT_\(accountID.uppercased())_"

            let imapHost = try required("\(prefix)IMAP_HOST", fallbackKey: "IMAP_HOST", env: env)
            let imapUsername = try required("\(prefix)IMAP_USERNAME", fallbackKey: "IMAP_USERNAME", env: env)
            let imapPassword = try required("\(prefix)IMAP_PASSWORD", fallbackKey: "IMAP_PASSWORD", env: env)
            let imapPort = int("\(prefix)IMAP_PORT", env: env) ?? (accountID == "jeff" ? int("IMAP_PORT", env: env) : nil) ?? 993

            let smtpHost = optional("\(prefix)SMTP_HOST", env: env) ?? (accountID == "jeff" ? optional("SMTP_HOST", env: env) : nil)
            let smtpPort = int("\(prefix)SMTP_PORT", env: env) ?? (accountID == "jeff" ? int("SMTP_PORT", env: env) : nil) ?? 587
            let smtpUsername = optional("\(prefix)SMTP_USERNAME", env: env) ?? (accountID == "jeff" ? optional("SMTP_USERNAME", env: env) : nil) ?? imapUsername
            let smtpPassword = optional("\(prefix)SMTP_PASSWORD", env: env) ?? (accountID == "jeff" ? optional("SMTP_PASSWORD", env: env) : nil) ?? imapPassword
            let fromAddress = optional("\(prefix)FROM_ADDRESS", env: env) ?? (accountID == "jeff" ? optional("EMAIL_FROM_ADDRESS", env: env) : nil) ?? smtpUsername

            return Config(
                accountID: accountID,
                displayName: optional("\(prefix)DISPLAY_NAME", env: env) ?? (accountID == "jeff" ? "Jeff" : accountID),
                imapHost: imapHost,
                imapPort: imapPort,
                imapUsername: imapUsername,
                imapPassword: imapPassword,
                smtpHost: smtpHost,
                smtpPort: smtpPort,
                smtpUsername: smtpUsername,
                smtpPassword: smtpPassword,
                fromName: optional("\(prefix)FROM_NAME", env: env) ?? (accountID == "jeff" ? optional("EMAIL_FROM_NAME", env: env) : nil),
                fromAddress: fromAddress,
                signature: optional("\(prefix)SIGNATURE", env: env) ?? optional("EMAIL_SIGNATURE", env: env)
            )
        }

        static func loadAccounts() -> [Config] {
            let env = ProcessInfo.processInfo.environment.merging(loadDotEnv()) { current, _ in current }
            let listed = optional("EMAIL_ACCOUNTS", env: env)?
                .split(separator: ",")
                .map { normalizeAccountID(String($0)) } ?? ["jeff"]
            var seen = Set<String>()
            return listed.compactMap { accountID in
                guard seen.insert(accountID).inserted else { return nil }
                return try? load(accountID: accountID)
            }
        }

        private static func required(_ key: String, env: [String: String]) throws -> String {
            guard let value = optional(key, env: env) else {
                throw JeffEmailError.missingConfiguration(key)
            }
            return value
        }

        private static func required(_ key: String, fallbackKey: String, env: [String: String]) throws -> String {
            if let value = optional(key, env: env) {
                return value
            }
            guard key.hasPrefix("EMAIL_"), let value = optional(fallbackKey, env: env) else {
                throw JeffEmailError.missingConfiguration(key)
            }
            return value
        }

        private static func normalizeAccountID(_ rawValue: String) -> String {
            rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }

        private static func optional(_ key: String, env: [String: String]) -> String? {
            let value = env[key].map(decodeDotEnvDoubleQuotedEscapes)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }

        private static func int(_ key: String, env: [String: String]) -> Int? {
            optional(key, env: env).flatMap(Int.init)
        }

        private static func loadDotEnv() -> [String: String] {
            guard let data = try? String(contentsOfFile: ".env", encoding: .utf8) else {
                return [:]
            }
            var values: [String: String] = [:]
            for rawLine in data.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else {
                    continue
                }
                let key = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
                var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if value.count >= 2,
                   let first = value.first,
                   let last = value.last,
                   (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                    value.removeFirst()
                    value.removeLast()
                    if first == "\"" {
                        value = decodeDotEnvDoubleQuotedEscapes(value)
                    }
                }
                if !key.isEmpty {
                    values[key] = value
                }
            }
            return values
        }

        private static func decodeDotEnvDoubleQuotedEscapes(_ rawValue: String) -> String {
            var decoded = ""
            var iterator = rawValue.makeIterator()
            while let character = iterator.next() {
                guard character == "\\" else {
                    decoded.append(character)
                    continue
                }
                guard let escaped = iterator.next() else {
                    decoded.append(character)
                    break
                }
                switch escaped {
                case "n":
                    decoded.append("\n")
                case "r":
                    decoded.append("\r")
                case "t":
                    decoded.append("\t")
                case "\\":
                    decoded.append("\\")
                case "\"":
                    decoded.append("\"")
                default:
                    decoded.append("\\")
                    decoded.append(escaped)
                }
            }
            return decoded
        }
    }

    static func listAccounts() -> [String: Any] {
        [
            "accounts": Config.loadAccounts().map { config in
                [
                    "account_id": config.accountID,
                    "display_name": config.displayName,
                    "email": config.fromAddress,
                    "from_name": config.fromName ?? NSNull(),
                    "imap_host": config.imapHost,
                    "smtp_host": config.smtpHost ?? NSNull(),
                ] as [String: Any]
            },
        ]
    }

    static func listRecent(accountID: String?, mailbox: String, limit: Int) async throws -> [String: Any] {
        let limit = max(1, min(limit, 50))
        let config = try Config.load(accountID: accountID)
        return try await withIMAP(config: config) { server in
            let selection = try await server.selectMailbox(mailbox)
            guard let latest = selection.latest(limit) else {
                return [
                    "account_id": config.accountID,
                    "mailbox": mailbox,
                    "message_count": selection.messageCount,
                    "messages": [],
                ]
            }

            var messages: [JeffEmailMessageSummary] = []
            for try await message in server.fetchMessages(using: latest) {
                messages.append(summary(message, accountID: config.accountID))
            }
            return [
                "account_id": config.accountID,
                "mailbox": mailbox,
                "message_count": selection.messageCount,
                "messages": messages.reversed().map { $0.json() },
            ]
        }
    }

    static func search(accountID: String?, mailbox: String, query: String, limit: Int, recentWindow: Int) async throws -> [String: Any] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let limit = max(1, min(limit, 50))
        let recentWindow = max(limit, min(recentWindow, 250))
        let config = try Config.load(accountID: accountID)

        return try await withIMAP(config: config) { server in
            let selection = try await server.selectMailbox(mailbox)
            guard let latest = selection.latest(recentWindow) else {
                return [
                    "account_id": config.accountID,
                    "mailbox": mailbox,
                    "query": query,
                    "messages": [],
                ]
            }

            var matches: [JeffEmailMessageSummary] = []
            for try await message in server.fetchMessages(using: latest) {
                let haystack = [
                    message.subject ?? "",
                    message.from ?? "",
                    message.to.joined(separator: " "),
                    message.preview(maxLength: 1_000),
                ].joined(separator: "\n").lowercased()
                if normalizedQuery.isEmpty || haystack.contains(normalizedQuery) {
                    matches.append(summary(message, accountID: config.accountID))
                }
            }
            return [
                "account_id": config.accountID,
                "mailbox": mailbox,
                "query": query,
                "searched_recent_message_count": recentWindow,
                "messages": matches.reversed().prefix(limit).map { $0.json() },
            ]
        }
    }

    static func getMessage(accountID: String?, mailbox: String, uid: String) async throws -> [String: Any] {
        let config = try Config.load(accountID: accountID)
        return try await withIMAP(config: config) { server in
            _ = try await server.selectMailbox(mailbox)
            guard let set = MessageIdentifierSet<UID>(string: uid) else {
                throw JeffEmailError.invalidUID(uid)
            }
            for try await message in server.fetchMessages(using: set) {
                guard message.uid != nil else {
                    continue
                }
                return [
                    "account_id": config.accountID,
                    "mailbox": mailbox,
                    "uid": message.uid.map { String($0.value) } ?? uid,
                    "date": message.date?.ISO8601Format() ?? NSNull(),
                    "from": message.from ?? NSNull(),
                    "to": message.to,
                    "cc": message.cc,
                    "subject": message.subject ?? NSNull(),
                    "message_id": message.header.messageId?.description ?? NSNull(),
                    "in_reply_to": message.header.inReplyTo?.description ?? NSNull(),
                    "references": message.header.references?.map(\.description) ?? [],
                    "text_body": message.textBody ?? NSNull(),
                    "html_body": message.htmlBody ?? NSNull(),
                    "preview": message.preview(maxLength: 2_000),
                    "attachments": message.attachments.map { part in
                        [
                            "filename": part.filename as Any? ?? NSNull(),
                            "content_type": part.contentType,
                            "byte_count": part.data?.count ?? 0,
                        ]
                    },
                ]
            }
            throw JeffEmailError.messageNotFound(uid)
        }
    }

    static func createDraft(accountID: String?, to: [String], cc: [String], bcc: [String], subject: String, body: String) async throws -> [String: Any] {
        let config = try Config.load(accountID: accountID)
        return try await withIMAP(config: config) { server in
            let email = Email(
                sender: EmailAddress(name: config.fromName, address: config.fromAddress),
                recipients: to.map { EmailAddress(name: nil, address: $0) },
                ccRecipients: cc.map { EmailAddress(name: nil, address: $0) },
                bccRecipients: bcc.map { EmailAddress(name: nil, address: $0) },
                subject: subject,
                textBody: signedBody(body, signature: config.signature)
            )
            let result = try await server.createDraft(from: email)
            return [
                "status": "draft_created",
                "account_id": config.accountID,
                "uid": result.firstUID.map { String($0.value) } ?? NSNull(),
                "uid_validity": result.uidValidity.map { String($0.value) } ?? NSNull(),
            ]
        }
    }

    static func send(accountID: String?, to: [String], cc: [String], bcc: [String], subject: String, body: String) async throws -> [String: Any] {
        let config = try Config.load(accountID: accountID)
        return try await send(config: config, to: to, cc: cc, bcc: bcc, subject: subject, body: body, additionalHeaders: nil)
    }

    static func reply(
        accountID: String?,
        mailbox: String,
        uid: String,
        body: String,
        cc: [String],
        bcc: [String],
        replyAll: Bool
    ) async throws -> [String: Any] {
        let config = try Config.load(accountID: accountID)
        let original = try await fetchMessage(config: config, mailbox: mailbox, uid: uid)
        guard let originalMessageID = original.header.messageId else {
            throw JeffEmailError.missingMessageID(uid)
        }
        let recipients = replyRecipients(for: original, config: config, replyAll: replyAll)
        guard !recipients.to.isEmpty else {
            throw JeffEmailError.noReplyRecipient(uid)
        }
        let subject = replySubject(original.subject)
        var referenceIDs = original.header.references ?? []
        if !referenceIDs.contains(originalMessageID) {
            referenceIDs.append(originalMessageID)
        }
        return try await send(
            config: config,
            to: recipients.to,
            cc: Array(Set(recipients.cc + cc)).sorted(),
            bcc: bcc,
            subject: subject,
            body: body,
            additionalHeaders: [
                "In-Reply-To": originalMessageID.description,
                "References": referenceIDs.map(\.description).joined(separator: " "),
            ]
        )
    }

    private static func send(
        config: Config,
        to: [String],
        cc: [String],
        bcc: [String],
        subject: String,
        body: String,
        additionalHeaders: [String: String]?
    ) async throws -> [String: Any] {
        guard let smtpHost = config.smtpHost else {
            throw JeffEmailError.missingConfiguration("SMTP_HOST for account \(config.accountID)")
        }

        let server = SMTPServer(host: smtpHost, port: config.smtpPort)
        try await server.connect()
        try await server.login(username: config.smtpUsername, password: config.smtpPassword)
        var email = Email(
            sender: EmailAddress(name: config.fromName, address: config.fromAddress),
            recipients: to.map { EmailAddress(name: nil, address: $0) },
            ccRecipients: cc.map { EmailAddress(name: nil, address: $0) },
            bccRecipients: bcc.map { EmailAddress(name: nil, address: $0) },
            subject: subject,
            textBody: signedBody(body, signature: config.signature)
        )
        email.additionalHeaders = additionalHeaders
        try await server.sendEmail(email)
        try? await server.disconnect()
        return [
            "status": "sent",
            "account_id": config.accountID,
            "to": to,
            "cc": cc,
            "bcc_count": bcc.count,
            "subject": subject,
            "threaded_reply": additionalHeaders?["In-Reply-To"] != nil,
        ]
    }

    private static func withIMAP<T>(_ block: (IMAPServer) async throws -> T) async throws -> T {
        try await withIMAP(config: try Config.load(), block)
    }

    private static func withIMAP<T>(
        config: Config,
        _ block: (IMAPServer) async throws -> T
    ) async throws -> T {
        let server = IMAPServer(host: config.imapHost, port: config.imapPort)
        try await server.connect()
        try await server.login(username: config.imapUsername, password: config.imapPassword)
        do {
            let result = try await block(server)
            try? await server.disconnect()
            return result
        } catch {
            try? await server.disconnect()
            throw error
        }
    }

    private static func fetchMessage(config: Config, mailbox: String, uid: String) async throws -> Message {
        try await withIMAP(config: config) { server in
            _ = try await server.selectMailbox(mailbox)
            guard let set = MessageIdentifierSet<UID>(string: uid) else {
                throw JeffEmailError.invalidUID(uid)
            }
            for try await message in server.fetchMessages(using: set) {
                if message.uid != nil {
                    return message
                }
            }
            throw JeffEmailError.messageNotFound(uid)
        }
    }

    private static func summary(_ message: Message, accountID: String) -> JeffEmailMessageSummary {
        JeffEmailMessageSummary(
            accountID: accountID,
            uid: message.uid.map { String($0.value) } ?? "",
            date: message.date,
            from: message.from,
            to: message.to,
            subject: message.subject,
            preview: message.preview(maxLength: 500),
            hasAttachments: !message.attachments.isEmpty
        )
    }

    private static func replyRecipients(for message: Message, config: Config, replyAll: Bool) -> (to: [String], cc: [String]) {
        let own = Set([config.fromAddress, config.imapUsername, config.smtpUsername].map { $0.lowercased() })
        let from = message.from.flatMap(extractEmailAddress)
        let to = from.map { [$0] } ?? []
        guard replyAll else {
            return (to, [])
        }
        let additionalTo = message.to.compactMap(extractEmailAddress).filter { !own.contains($0.lowercased()) }
        let cc = message.cc.compactMap(extractEmailAddress).filter { !own.contains($0.lowercased()) }
        return (Array(Set(to + additionalTo)).sorted(), Array(Set(cc)).sorted())
    }

    private static func extractEmailAddress(_ rawValue: String) -> String? {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        guard let range = rawValue.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return String(rawValue[range])
    }

    private static func replySubject(_ subject: String?) -> String {
        let trimmed = subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Re:" }
        return trimmed.range(of: #"^\s*re:"# , options: [.regularExpression, .caseInsensitive]) == nil ? "Re: \(trimmed)" : trimmed
    }

    private static func signedBody(_ body: String, signature: String?) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signature = signature?.trimmingCharacters(in: .whitespacesAndNewlines),
              !signature.isEmpty
        else {
            return trimmedBody
        }
        if trimmedBody.localizedCaseInsensitiveContains(signature) {
            return trimmedBody
        }
        return "\(trimmedBody)\n\n\(signature)"
    }
}

enum JeffEmailError: Error, CustomStringConvertible {
    case missingConfiguration(String)
    case invalidUID(String)
    case messageNotFound(String)
    case missingMessageID(String)
    case noReplyRecipient(String)

    var description: String {
        switch self {
        case .missingConfiguration(let key):
            return "Missing email configuration \(key). Set it in .env or the process environment."
        case .invalidUID(let uid):
            return "Invalid email UID '\(uid)'."
        case .messageNotFound(let uid):
            return "No email found for UID '\(uid)'."
        case .missingMessageID(let uid):
            return "Email UID '\(uid)' does not have a Message-ID, so it cannot be replied to as a threaded message."
        case .noReplyRecipient(let uid):
            return "Email UID '\(uid)' does not contain a usable reply recipient."
        }
    }
}
