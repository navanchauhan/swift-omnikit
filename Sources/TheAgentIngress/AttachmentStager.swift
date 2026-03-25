import Foundation
import OmniAgentMesh

public struct AttachmentStageResult: Sendable, Equatable {
    public var artifactRefs: [String]
    public var metadata: [String: String]

    public init(artifactRefs: [String] = [], metadata: [String: String] = [:]) {
        self.artifactRefs = artifactRefs
        self.metadata = metadata
    }
}

public actor AttachmentStager {
    private let artifactStore: any ArtifactStore

    public init(artifactStore: any ArtifactStore) {
        self.artifactStore = artifactStore
    }

    public func stage(
        attachments: [IngressEnvelope.Attachment],
        workspaceID: WorkspaceID,
        channelID: ChannelID
    ) async throws -> AttachmentStageResult {
        var artifactRefs: [String] = []
        var metadata: [String: String] = [:]

        for attachment in attachments {
            if let inlineText = attachment.metadata["inline_text"] {
                let record = try await artifactStore.put(
                    ArtifactPayload(
                        workspaceID: workspaceID,
                        channelID: channelID,
                        name: attachment.name,
                        contentType: attachment.contentType,
                        data: Data(inlineText.utf8)
                    )
                )
                artifactRefs.append(record.artifactID)
                continue
            }
            if let inlineBase64 = attachment.metadata["inline_base64"],
               let data = Data(base64Encoded: inlineBase64) {
                let record = try await artifactStore.put(
                    ArtifactPayload(
                        workspaceID: workspaceID,
                        channelID: channelID,
                        name: attachment.name,
                        contentType: attachment.contentType,
                        data: data
                    )
                )
                artifactRefs.append(record.artifactID)
            }
        }

        if !artifactRefs.isEmpty {
            metadata["staged_artifact_refs"] = artifactRefs.joined(separator: ",")
        }
        return AttachmentStageResult(artifactRefs: artifactRefs, metadata: metadata)
    }
}
