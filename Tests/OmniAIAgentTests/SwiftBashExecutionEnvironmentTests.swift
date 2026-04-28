import Foundation
import Testing
@testable import OmniAIAgent

@Suite
final class SwiftBashExecutionEnvironmentTests {
    @Test
    func executesCommandsInProcess() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let env = SwiftBashExecutionEnvironment(
            workingDir: tempDir.path,
            config: SwiftBashBackendConfig(fileSystemMode: .realFileSystem)
        )
        try await env.initialize()

        let result = try await env.execCommand(
            command: "echo hello | tr a-z A-Z",
            timeoutMs: 10_000,
            workingDir: nil,
            envVars: nil
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout == "HELLO\n")
        #expect(result.stderr.isEmpty)
        #expect(result.timedOut == false)
    }

    @Test
    func canUseRequestedWorkingDirectoryWithRealFilesystem() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let env = SwiftBashExecutionEnvironment(
            workingDir: tempDir.path,
            config: SwiftBashBackendConfig(fileSystemMode: .realFileSystem)
        )
        try await env.initialize()

        let result = try await env.execCommand(
            command: "printf 'abc' > out.txt; pwd; cat out.txt",
            timeoutMs: 10_000,
            workingDir: nil,
            envVars: nil
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout == "\(tempDir.path)\nabc")
        #expect(FileManager.default.contents(atPath: tempDir.appendingPathComponent("out.txt").path) == Data("abc".utf8))
    }

    @Test
    func defaultsToSandboxedWorkspace() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try Data("host\n".utf8).write(to: tempDir.appendingPathComponent("input.txt"))

        let env = SwiftBashExecutionEnvironment(workingDir: tempDir.path)
        try await env.initialize()

        let result = try await env.execCommand(
            command: "cat input.txt; printf overlay > out.txt",
            timeoutMs: 10_000,
            workingDir: nil,
            envVars: nil
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout == "host\n")
        #expect(!FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("out.txt").path))
    }

    @Test(arguments: [
        "while true; do :; done",
        "sleep 10",
        "yes",
    ])
    func commandsThatDoNotFinishTimeOut(command: String) async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let env = SwiftBashExecutionEnvironment(workingDir: tempDir.path)
        try await env.initialize()

        let result = try await env.execCommand(
            command: command,
            timeoutMs: 100,
            workingDir: nil,
            envVars: nil
        )

        #expect(result.timedOut)
        #expect(result.exitCode == 124)
        #expect(result.durationMs < 5_000)
    }

    @Test
    func emptyNetworkAllowlistDoesNotAllowFullInternetAccess() async throws {
        let config = SwiftBashBackendConfig(networkEnabled: true)
        #expect(config.allowedURLPrefixes.isEmpty)
        #expect(config.allowFullInternetAccess == false)
    }

    @Test
    func factoryCreatesSwiftBashBackend() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let env = try await CodingAgent.createExecutionEnvironment(
            workingDir: tempDir.path,
            executionBackend: .swiftBash()
        )

        #expect(env is SwiftBashExecutionEnvironment)
        #expect(env.workingDirectory() == tempDir.path)
    }

    private static func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnikit-swiftbash-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
