import Foundation
import OmniAgentMesh

public struct StagedAttachment: Sendable, Equatable {
    public var artifactID: String
    public var name: String
    public var contentType: String
    public var byteCount: Int
    public var localPath: String?
    public var metadata: [String: String]

    public init(
        artifactID: String,
        name: String,
        contentType: String,
        byteCount: Int,
        localPath: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.artifactID = artifactID
        self.name = name
        self.contentType = contentType
        self.byteCount = byteCount
        self.localPath = localPath
        self.metadata = metadata
    }
}

public struct AttachmentStageResult: Sendable, Equatable {
    public var artifactRefs: [String]
    public var attachments: [StagedAttachment]
    public var metadata: [String: String]

    public init(
        artifactRefs: [String] = [],
        attachments: [StagedAttachment] = [],
        metadata: [String: String] = [:]
    ) {
        self.artifactRefs = artifactRefs
        self.attachments = attachments
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
        var stagedAttachments: [StagedAttachment] = []
        var metadata: [String: String] = [:]

        var unstagedIndex = 0
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
                stagedAttachments.append(try await stagedAttachment(record: record, sourceMetadata: attachment.metadata))
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
                stagedAttachments.append(try await stagedAttachment(record: record, sourceMetadata: attachment.metadata))
                continue
            }

            unstagedIndex += 1
            let prefix = "unstaged_attachment_\(unstagedIndex)"
            metadata["\(prefix)_name"] = attachment.name
            metadata["\(prefix)_content_type"] = attachment.contentType
            metadata["\(prefix)_attachment_id"] = attachment.attachmentID
            metadata["\(prefix)_reason"] = attachment.metadata["photon_attachment_download_error"] ?? "attachment data was not available inline"
            for (key, value) in attachment.metadata where key.hasPrefix("photon_attachment_") {
                metadata["\(prefix)_\(key)"] = value
            }
        }

        if !artifactRefs.isEmpty {
            metadata["staged_artifact_refs"] = artifactRefs.joined(separator: ",")
            metadata["staged_attachment_count"] = String(stagedAttachments.count)
        }
        if unstagedIndex > 0 {
            metadata["unstaged_attachment_count"] = String(unstagedIndex)
        }
        return AttachmentStageResult(
            artifactRefs: artifactRefs,
            attachments: stagedAttachments,
            metadata: metadata
        )
    }

    private func stagedAttachment(
        record: ArtifactRecord,
        sourceMetadata: [String: String]
    ) async throws -> StagedAttachment {
        StagedAttachment(
            artifactID: record.artifactID,
            name: record.name,
            contentType: record.contentType,
            byteCount: record.byteCount,
            localPath: try await artifactStore.localFilePath(for: record.artifactID),
            metadata: sourceMetadata
        )
    }
}
