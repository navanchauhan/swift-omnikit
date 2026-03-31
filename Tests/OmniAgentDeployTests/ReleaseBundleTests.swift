import Foundation
import Testing
import OmniAgentDeliveryCore
@testable import OmniAgentDeployKit

@Suite
struct ReleaseBundleTests {
    @Test
    func fileReleaseBundleStorePersistsAndListsBundles() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "release-bundles-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let store = try FileReleaseBundleStore(rootDirectory: rootDirectory)
        let bundle = ReleaseBundle(
            changeID: "change-1",
            rootSessionID: "root",
            service: "the-agent",
            targetEnvironment: "canary",
            version: "1.2.3",
            artifactRefs: [
                ReleaseBundleArtifact(
                    artifactID: "artifact-1",
                    name: "patch.swift",
                    contentType: "text/plain",
                    byteCount: 12,
                    contentHash: ReleaseBundleHash.hash(Data("hello world".utf8))
                ),
            ],
            healthPlan: ["service_liveness"]
        )

        try await store.saveBundle(bundle)

        let restored = try await store.bundle(bundleID: bundle.bundleID)
        let listed = try await store.listBundles()

        #expect(restored == bundle)
        #expect(listed.first == bundle)
        #expect(listed.count == 1)
    }
}
