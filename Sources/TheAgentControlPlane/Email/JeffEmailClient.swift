import Foundation
import SwiftMail

struct JeffEmailMessageSummary: Sendable {
    var uid: String
    var date: Date?
    var from: String?
    var to: [String]
    var subject: String?
    var preview: String
    var hasAttachments: Bool

    func json() -> [String: Any] {
        [
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

        static func load() throws -> Config {
            let env = ProcessInfo.processInfo.environment.merging(loadDotEnv()) { current, _ in current }

            let imapHost = try required("IMAP_HOST", env: env)
            let imapUsername = try required("IMAP_USERNAME", env: env)
            let imapPassword = try required("IMAP_PASSWORD", env: env)
            let imapPort = int("IMAP_PORT", env: env) ?? 993

            let smtpHost = optional("SMTP_HOST", env: env)
            let smtpPort = int("SMTP_PORT", env: env) ?? 587
            let smtpUsername = optional("SMTP_USERNAME", env: env) ?? imapUsername
            let smtpPassword = optional("SMTP_PASSWORD", env: env) ?? imapPassword
            let fromAddress = optional("EMAIL_FROM_ADDRESS", env: env) ?? smtpUsername

            return Config(
                imapHost: imapHost,
                imapPort: imapPort,
                imapUsername: imapUsername,
                imapPassword: imapPassword,
                smtpHost: smtpHost,
                smtpPort: smtpPort,
                smtpUsername: smtpUsername,
                smtpPassword: smtpPassword,
                fromName: optional("EMAIL_FROM_NAME", env: env),
                fromAddress: fromAddress,
                signature: optional("EMAIL_SIGNATURE", env: env)
            )
        }

        private static func required(_ key: String, env: [String: String]) throws -> String {
            guard let value = optional(key, env: env) else {
                throw JeffEmailError.missingConfiguration(key)
            }
            return value
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

    static func listRecent(mailbox: String, limit: Int) async throws -> [String: Any] {
        let limit = max(1, min(limit, 50))
        return try await withIMAP { server in
            let selection = try await server.selectMailbox(mailbox)
            guard let latest = selection.latest(limit) else {
                return [
                    "mailbox": mailbox,
                    "message_count": selection.messageCount,
                    "messages": [],
                ]
            }

            var messages: [JeffEmailMessageSummary] = []
            for try await message in server.fetchMessages(using: latest) {
                messages.append(summary(message))
            }
            return [
                "mailbox": mailbox,
                "message_count": selection.messageCount,
                "messages": messages.reversed().map { $0.json() },
            ]
        }
    }

    static func search(mailbox: String, query: String, limit: Int, recentWindow: Int) async throws -> [String: Any] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let limit = max(1, min(limit, 50))
        let recentWindow = max(limit, min(recentWindow, 250))

        return try await withIMAP { server in
            let selection = try await server.selectMailbox(mailbox)
            guard let latest = selection.latest(recentWindow) else {
                return [
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
                    matches.append(summary(message))
                }
            }
            return [
                "mailbox": mailbox,
                "query": query,
                "searched_recent_message_count": recentWindow,
                "messages": matches.reversed().prefix(limit).map { $0.json() },
            ]
        }
    }

    static func getMessage(mailbox: String, uid: String) async throws -> [String: Any] {
        try await withIMAP { server in
            _ = try await server.selectMailbox(mailbox)
            guard let set = MessageIdentifierSet<UID>(string: uid) else {
                throw JeffEmailError.invalidUID(uid)
            }
            for try await message in server.fetchMessages(using: set) {
                guard message.uid != nil else {
                    continue
                }
                return [
                    "mailbox": mailbox,
                    "uid": message.uid.map { String($0.value) } ?? uid,
                    "date": message.date?.ISO8601Format() ?? NSNull(),
                    "from": message.from ?? NSNull(),
                    "to": message.to,
                    "cc": message.cc,
                    "subject": message.subject ?? NSNull(),
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

    static func createDraft(to: [String], cc: [String], bcc: [String], subject: String, body: String) async throws -> [String: Any] {
        let config = try Config.load()
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
                "uid": result.firstUID.map { String($0.value) } ?? NSNull(),
                "uid_validity": result.uidValidity.map { String($0.value) } ?? NSNull(),
            ]
        }
    }

    static func send(to: [String], cc: [String], bcc: [String], subject: String, body: String) async throws -> [String: Any] {
        let config = try Config.load()
        guard let smtpHost = config.smtpHost else {
            throw JeffEmailError.missingConfiguration("SMTP_HOST")
        }

        let server = SMTPServer(host: smtpHost, port: config.smtpPort)
        try await server.connect()
        try await server.login(username: config.smtpUsername, password: config.smtpPassword)
        let email = Email(
            sender: EmailAddress(name: config.fromName, address: config.fromAddress),
            recipients: to.map { EmailAddress(name: nil, address: $0) },
            ccRecipients: cc.map { EmailAddress(name: nil, address: $0) },
            bccRecipients: bcc.map { EmailAddress(name: nil, address: $0) },
            subject: subject,
            textBody: signedBody(body, signature: config.signature)
        )
        try await server.sendEmail(email)
        try? await server.disconnect()
        return [
            "status": "sent",
            "to": to,
            "cc": cc,
            "bcc_count": bcc.count,
            "subject": subject,
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

    private static func summary(_ message: Message) -> JeffEmailMessageSummary {
        JeffEmailMessageSummary(
            uid: message.uid.map { String($0.value) } ?? "",
            date: message.date,
            from: message.from,
            to: message.to,
            subject: message.subject,
            preview: message.preview(maxLength: 500),
            hasAttachments: !message.attachments.isEmpty
        )
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

    var description: String {
        switch self {
        case .missingConfiguration(let key):
            return "Missing email configuration \(key). Set it in .env or the process environment."
        case .invalidUID(let uid):
            return "Invalid email UID '\(uid)'."
        case .messageNotFound(let uid):
            return "No email found for UID '\(uid)'."
        }
    }
}
