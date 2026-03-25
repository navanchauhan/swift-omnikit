import Foundation
import Testing
import OmniAgentMesh
@testable import TheAgentIngress

@Suite
struct AttachmentStagerTests {
    @Test
    func stagerPersistsInlineAttachmentsAsArtifacts() async throws {
        let stateRoot = try makeStateRoot(prefix: "attachment-stage")
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let stager = AttachmentStager(artifactStore: artifactStore)

        let result = try await stager.stage(
            attachments: [
                IngressEnvelope.Attachment(
                    name: "note.txt",
                    contentType: "text/plain",
                    metadata: ["inline_text": "hello world"]
                ),
                IngressEnvelope.Attachment(
                    name: "data.bin",
                    contentType: "application/octet-stream",
                    metadata: ["inline_base64": Data([0x41, 0x42, 0x43]).base64EncodedString()]
                ),
            ],
            workspaceID: WorkspaceID(rawValue: "workspace-a"),
            channelID: ChannelID(rawValue: "channel-a")
        )

        #expect(result.artifactRefs.count == 2)
        #expect(result.metadata["staged_artifact_refs"]?.split(separator: ",").count == 2)
        #expect(try await artifactStore.data(for: result.artifactRefs[0]) == Data("hello world".utf8))
        #expect(try await artifactStore.data(for: result.artifactRefs[1]) == Data([0x41, 0x42, 0x43]))
    }

    private func makeStateRoot(prefix: String) throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
