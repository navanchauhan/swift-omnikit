import Foundation

public protocol ScopedIdentifier: RawRepresentable, Codable, Hashable, Sendable where RawValue == String {}

public struct ActorID: ScopedIdentifier, Comparable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static func < (lhs: ActorID, rhs: ActorID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct WorkspaceID: ScopedIdentifier, Comparable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static func < (lhs: WorkspaceID, rhs: WorkspaceID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ChannelID: ScopedIdentifier, Comparable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static func < (lhs: ChannelID, rhs: ChannelID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SessionScope: Codable, Hashable, Sendable, Equatable {
    private static let prefix = "scope"

    public static let root = SessionScope(actorID: "root", workspaceID: "root", channelID: "root")

    public var actorID: ActorID
    public var workspaceID: WorkspaceID
    public var channelID: ChannelID

    public init(actorID: ActorID, workspaceID: WorkspaceID, channelID: ChannelID) {
        self.actorID = actorID
        self.workspaceID = workspaceID
        self.channelID = channelID
    }

    public init(actorID: String, workspaceID: String, channelID: String) {
        self.init(
            actorID: ActorID(rawValue: actorID),
            workspaceID: WorkspaceID(rawValue: workspaceID),
            channelID: ChannelID(rawValue: channelID)
        )
    }

    public init?(sessionID: String) {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == Self.prefix else {
            return nil
        }
        guard
            let actor = Self.decodePart(String(parts[1])),
            let workspace = Self.decodePart(String(parts[2])),
            let channel = Self.decodePart(String(parts[3]))
        else {
            return nil
        }
        self.init(actorID: actor, workspaceID: workspace, channelID: channel)
    }

    public static func bestEffort(sessionID: String) -> SessionScope {
        if let parsed = SessionScope(sessionID: sessionID) {
            return parsed
        }
        let legacy = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = legacy.isEmpty ? "root" : legacy
        return SessionScope(
            actorID: ActorID(rawValue: sanitized),
            workspaceID: WorkspaceID(rawValue: sanitized),
            channelID: ChannelID(rawValue: sanitized)
        )
    }

    public var sessionID: String {
        "\(Self.prefix):\(Self.encodePart(actorID.rawValue)):\(Self.encodePart(workspaceID.rawValue)):\(Self.encodePart(channelID.rawValue))"
    }

    private static func encodePart(_ rawValue: String) -> String {
        let encoded = Data(rawValue.utf8).base64EncodedString()
        return encoded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodePart(_ encodedValue: String) -> String? {
        var base64 = encodedValue
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
