import Testing
@testable import OmniContainer
@testable import OmniVFS
import OmniExecution

@Suite("ContainerExecutionEnvironment")
struct ContainerExecEnvTests {

    func makeTestEnv() async throws -> ContainerExecutionEnvironment {
        let rootFS = MemFS()
        try rootFS.mkdir("bin")
        try rootFS.mkdir("workspace")
        try rootFS.mkdir("tmp")
        try rootFS.createFile("workspace/hello.txt", data: Array("hello from workspace".utf8))
        try rootFS.mkdir("etc")
        try rootFS.createFile("etc/os-release", data: Array("Alpine Linux 3.21".utf8))

        let spec = ContainerSpec(
            imageRef: "test:local",
            hostWorkspaceDir: "/tmp/test-workspace"
        )
        let container = ContainerActor(config: spec, rootFS: rootFS)
        try await container.start()

        return ContainerExecutionEnvironment(
            container: container,
            hostWorkspaceDir: "/tmp/test-workspace"
        )
    }

    @Test("readFile via guest path")
    func readFileGuestPath() async throws {
        let env = try await makeTestEnv()
        let content = try await env.readFile(path: "/etc/os-release", offset: nil, limit: nil)
        #expect(content == "Alpine Linux 3.21")
    }

    @Test("writeFile and readFile round-trip")
    func writeReadRoundTrip() async throws {
        let env = try await makeTestEnv()
        try await env.writeFile(path: "/bin/test.txt", content: "test content")
        let content = try await env.readFile(path: "/bin/test.txt", offset: nil, limit: nil)
        #expect(content == "test content")
    }

    @Test("fileExists")
    func fileExistsTest() async throws {
        let env = try await makeTestEnv()
        let exists = await env.fileExists(path: "/etc/os-release")
        #expect(exists)
        let notExists = await env.fileExists(path: "/nonexistent")
        #expect(!notExists)
    }

    @Test("platform reports linux")
    func platformReportsLinux() async throws {
        let env = try await makeTestEnv()
        #expect(env.platform() == "linux")
    }

    @Test("osVersion reports Alpine")
    func osVersionReportsAlpine() async throws {
        let env = try await makeTestEnv()
        #expect(env.osVersion().contains("Alpine"))
    }

    @Test("workingDirectory returns host path")
    func workingDirectoryIsHost() async throws {
        let env = try await makeTestEnv()
        #expect(env.workingDirectory() == "/tmp/test-workspace")
    }

    @Test("path translation: host workspace path maps to guest")
    func pathTranslation() async throws {
        let env = try await makeTestEnv()
        // Write via guest path
        try await env.writeFile(path: "/workspace/new.txt", content: "via guest")
        // Read via guest path
        let content = try await env.readFile(path: "/workspace/new.txt", offset: nil, limit: nil)
        #expect(content == "via guest")
    }

    @Test("listDirectory")
    func listDirectoryTest() async throws {
        let env = try await makeTestEnv()
        let entries = try await env.listDirectory(path: "/workspace", depth: 1)
        #expect(entries.contains(where: { $0.name == "hello.txt" }))
    }
}
