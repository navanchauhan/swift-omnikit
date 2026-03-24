import Foundation
import OmniAgentMesh

public struct IngressEnvelope: Codable, Sendable, Equatable {
    public enum PayloadKind: String, Codable, Sendable {
        case text
        case callback
        case unsupported
    }

    public enum ChannelKind: String, Codable, Sendable {
        case directMessage
        case group
        case topic
        case api
    }

    public struct Attachment: Codable, Sendable, Equatable {
        public var attachmentID: String
        public var name: String
        public var contentType: String
        public var metadata: [String: String]

        public init(
            attachmentID: String = UUID().uuidString,
            name: String,
            contentType: String,
            metadata: [String: String] = [:]
        ) {
            self.attachmentID = attachmentID
            self.name = name
            self.contentType = contentType
            self.metadata = metadata
        }
    }

    public var envelopeID: String
    public var transport: ChannelBinding.Transport
    public var payloadKind: PayloadKind
    public var updateID: String?
    public var messageID: String?
    public var actorExternalID: String
    public var actorDisplayName: String?
    public var channelExternalID: String
    public var channelKind: ChannelKind
    public var text: String?
    public var callbackData: String?
    public var attachments: [Attachment]
    public var mentionTriggerActive: Bool
    public var replyContextActive: Bool
    public var metadata: [String: String]
    public var receivedAt: Date

    public init(
        envelopeID: String = UUID().uuidString,
        transport: ChannelBinding.Transport,
        payloadKind: PayloadKind,
        updateID: String? = nil,
        messageID: String? = nil,
        actorExternalID: String,
        actorDisplayName: String? = nil,
        channelExternalID: String,
        channelKind: ChannelKind,
        text: String? = nil,
        callbackData: String? = nil,
        attachments: [Attachment] = [],
        mentionTriggerActive: Bool = false,
        replyContextActive: Bool = false,
        metadata: [String: String] = [:],
        receivedAt: Date = Date()
    ) {
        self.envelopeID = envelopeID
        self.transport = transport
        self.payloadKind = payloadKind
        self.updateID = updateID
        self.messageID = messageID
        self.actorExternalID = actorExternalID
        self.actorDisplayName = actorDisplayName
        self.channelExternalID = channelExternalID
        self.channelKind = channelKind
        self.text = text
        self.callbackData = callbackData
        self.attachments = attachments
        self.mentionTriggerActive = mentionTriggerActive
        self.replyContextActive = replyContextActive
        self.metadata = metadata
        self.receivedAt = receivedAt
    }

    public var idempotencyKey: String {
        let base = updateID ?? messageID ?? envelopeID
        return "ingress.\(transport.rawValue).\(base)"
    }
}
