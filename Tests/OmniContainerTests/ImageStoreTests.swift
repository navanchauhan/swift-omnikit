import Testing
@testable import OmniContainer

@Suite("ImageStore")
struct ImageStoreTests {
    @Test("bundled Alpine minirootfs resolves without external state", .serialized)
    func bundledAlpineRootfsResolves() async throws {
        let rootFS = try await ImageStore.shared.resolve("alpine:minirootfs")
        let file = try rootFS.open("bin/sh")
        defer { try? file.close() }

        let info = try file.stat()
        #expect(info.size > 0)
        #expect(!info.isDir)
    }
}
