import Foundation
import OmniAgentMesh

public struct IngressDeliveryAttachment: Codable, Sendable, Equatable {
    public var artifactID: String
    public var name: String?
    public var contentType: String?
    public var metadata: [String: String]

    public init(
        artifactID: String,
        name: String? = nil,
        contentType: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.artifactID = artifactID
        self.name = name
        self.contentType = contentType
        self.metadata = metadata
    }
}

public struct IngressDeliveryInstruction: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case message
        case callbackAcknowledgement
    }

    public enum Visibility: String, Codable, Sendable {
        case sameChannel
        case directMessage
    }

    public var deliveryID: String
    public var idempotencyKey: String
    public var kind: Kind
    public var transport: ChannelBinding.Transport
    public var visibility: Visibility
    public var workspaceID: WorkspaceID
    public var channelID: ChannelID
    public var actorID: ActorID?
    public var targetExternalID: String
    public var chunks: [String]
    public var attachments: [IngressDeliveryAttachment]
    public var metadata: [String: String]

    public init(
        deliveryID: String = UUID().uuidString,
        idempotencyKey: String,
        kind: Kind,
        transport: ChannelBinding.Transport,
        visibility: Visibility,
        workspaceID: WorkspaceID,
        channelID: ChannelID,
        actorID: ActorID? = nil,
        targetExternalID: String,
        chunks: [String],
        attachments: [IngressDeliveryAttachment] = [],
        metadata: [String: String] = [:]
    ) {
        self.deliveryID = deliveryID
        self.idempotencyKey = idempotencyKey
        self.kind = kind
        self.transport = transport
        self.visibility = visibility
        self.workspaceID = workspaceID
        self.channelID = channelID
        self.actorID = actorID
        self.targetExternalID = targetExternalID
        self.chunks = chunks
        self.attachments = attachments
        self.metadata = metadata
    }
}

public enum IngressDisposition: String, Codable, Sendable {
    case processed
    case duplicate
    case ignored
    case unsupported
    case failed
}

public struct IngressGatewayResult: Sendable, Equatable {
    public var disposition: IngressDisposition
    public var runtimeScope: SessionScope?
    public var actorID: ActorID?
    public var assistantText: String?
    public var deliveries: [IngressDeliveryInstruction]

    public init(
        disposition: IngressDisposition,
        runtimeScope: SessionScope? = nil,
        actorID: ActorID? = nil,
        assistantText: String? = nil,
        deliveries: [IngressDeliveryInstruction] = []
    ) {
        self.disposition = disposition
        self.runtimeScope = runtimeScope
        self.actorID = actorID
        self.assistantText = assistantText
        self.deliveries = deliveries
    }
}

public enum IngressDeliveryFormatter {
    public static func userVisibleText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func chunkText(_ text: String, maxCharacters: Int = 3_500) -> [String] {
        let trimmed = userVisibleText(text)
        guard !trimmed.isEmpty else {
            return []
        }
        guard trimmed.count > maxCharacters else {
            return [trimmed]
        }

        var chunks: [String] = []
        var remaining = trimmed[...]
        while remaining.count > maxCharacters {
            let splitIndex = remaining.index(remaining.startIndex, offsetBy: maxCharacters)
            let prefix = remaining[..<splitIndex]
            let boundary = prefix.lastIndex(of: "\n") ?? prefix.lastIndex(of: " ") ?? prefix.endIndex
            let nextChunk = remaining[..<boundary].trimmingCharacters(in: .whitespacesAndNewlines)
            if nextChunk.isEmpty {
                let forced = remaining[..<splitIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                chunks.append(String(forced))
                remaining = remaining[splitIndex...]
            } else {
                chunks.append(String(nextChunk))
                remaining = remaining[boundary...]
            }
            remaining = remaining.trimmingPrefix(where: \.isWhitespace)
        }

        let finalChunk = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalChunk.isEmpty {
            chunks.append(String(finalChunk))
        }
        return chunks
    }
}

private extension Substring {
    func trimmingCharacters(in set: CharacterSet) -> Substring {
        var current = self
        while let first = current.first, first.unicodeScalars.allSatisfy({ set.contains($0) }) {
            current = current.dropFirst()
        }
        while let last = current.last, last.unicodeScalars.allSatisfy({ set.contains($0) }) {
            current = current.dropLast()
        }
        return current
    }

    func trimmingPrefix(where predicate: (Character) -> Bool) -> Substring {
        var current = self
        while let first = current.first, predicate(first) {
            current = current.dropFirst()
        }
        return current
    }
}
