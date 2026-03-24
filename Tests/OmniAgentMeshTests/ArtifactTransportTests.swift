import Foundation
import Testing
@testable import OmniAgentMesh

@Suite
struct ArtifactTransportTests {
    @Test
    func remoteArtifactPutGetAndListRoundTripsOverHTTPMesh() async throws {
        let stateRoot = try makeStateRoot(prefix: "artifact-http")
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let server = HTTPMeshServer(
            jobStore: jobStore,
            artifactStore: artifactStore,
            host: "127.0.0.1",
            port: 0
        )
        let listeningAddress = try await server.start()
        defer {
            Task {
                try? await server.stop()
            }
        }

        let client = HTTPMeshClient(baseURL: listeningAddress.baseURL)
        let record = try await client.put(
            ArtifactPayload(
                taskID: "task-1",
                missionID: "mission-1",
                workspaceID: "workspace-1",
                channelID: "channel-1",
                name: "result.txt",
                contentType: "text/plain",
                data: Data("artifact transport".utf8)
            )
        )

        let restoredRecord = try await client.record(artifactID: record.artifactID)
        let restoredData = try await client.data(for: record.artifactID)
        let listed = try await client.list(taskID: "task-1", missionID: nil, workspaceID: nil)
        let listedByMission = try await client.list(taskID: nil, missionID: "mission-1", workspaceID: "workspace-1")

        #expect(restoredRecord == record)
        #expect(restoredData == Data("artifact transport".utf8))
        #expect(listed.map(\.artifactID) == [record.artifactID])
        #expect(listedByMission.map(\.artifactID) == [record.artifactID])
        #expect(try await artifactStore.data(for: record.artifactID) == Data("artifact transport".utf8))
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
