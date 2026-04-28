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
    func persistentSessionPreservesWorkingDirectory() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("subdir"), withIntermediateDirectories: true)

        let env = SwiftBashExecutionEnvironment(
            workingDir: tempDir.path,
            config: SwiftBashBackendConfig(fileSystemMode: .realFileSystem, persistentSession: true)
        )
        try await env.initialize()

        let cdResult = try await env.execCommand(command: "cd subdir", timeoutMs: 10_000, workingDir: nil, envVars: nil)
        let pwdResult = try await env.execCommand(command: "pwd", timeoutMs: 10_000, workingDir: nil, envVars: nil)

        #expect(cdResult.exitCode == 0)
        #expect(pwdResult.exitCode == 0)
        #expect(pwdResult.stdout == "\(tempDir.appendingPathComponent("subdir").path)\n")
    }

    @Test
    func persistentSessionPreservesExports() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let env = SwiftBashExecutionEnvironment(
            workingDir: tempDir.path,
            config: SwiftBashBackendConfig(persistentSession: true)
        )
        try await env.initialize()

        let exportResult = try await env.execCommand(command: "export FOO=bar", timeoutMs: 10_000, workingDir: nil, envVars: nil)
        let echoResult = try await env.execCommand(command: "echo $FOO", timeoutMs: 10_000, workingDir: nil, envVars: nil)

        #expect(exportResult.exitCode == 0)
        #expect(echoResult.exitCode == 0)
        #expect(echoResult.stdout == "bar\n")
    }

    @Test
    func persistentSessionWritesFilesWithRealFilesystem() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let env = SwiftBashExecutionEnvironment(
            workingDir: tempDir.path,
            config: SwiftBashBackendConfig(fileSystemMode: .realFileSystem, persistentSession: true)
        )
        try await env.initialize()

        let writeResult = try await env.execCommand(
            command: "printf persisted > out.txt",
            timeoutMs: 10_000,
            workingDir: nil,
            envVars: nil
        )

        #expect(writeResult.exitCode == 0)
        #expect(FileManager.default.contents(atPath: tempDir.appendingPathComponent("out.txt").path) == Data("persisted".utf8))
    }

    @Test
    func defaultSessionDoesNotPreserveShellState() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("subdir"), withIntermediateDirectories: true)

        let env = SwiftBashExecutionEnvironment(
            workingDir: tempDir.path,
            config: SwiftBashBackendConfig(fileSystemMode: .realFileSystem)
        )
        try await env.initialize()

        _ = try await env.execCommand(command: "cd subdir; export FOO=bar", timeoutMs: 10_000, workingDir: nil, envVars: nil)
        let result = try await env.execCommand(command: "pwd; echo ${FOO:-unset}", timeoutMs: 10_000, workingDir: nil, envVars: nil)

        #expect(result.exitCode == 0)
        #expect(result.stdout == "\(tempDir.path)\nunset\n")
    }

    @Test
    func timeoutDoesNotPoisonPersistentSession() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let env = SwiftBashExecutionEnvironment(
            workingDir: tempDir.path,
            config: SwiftBashBackendConfig(fileSystemMode: .realFileSystem, persistentSession: true)
        )
        try await env.initialize()

        let timeoutResult = try await env.execCommand(
            command: "export FOO=before; while true; do :; done",
            timeoutMs: 100,
            workingDir: nil,
            envVars: nil
        )
        let afterResult = try await env.execCommand(command: "echo ${FOO:-unset}", timeoutMs: 10_000, workingDir: nil, envVars: nil)

        #expect(timeoutResult.timedOut)
        #expect(timeoutResult.exitCode == 124)
        #expect(afterResult.exitCode == 0)
        #expect(afterResult.stdout == "unset\n")
    }

    @Test
    func commandConsoleRunsCommandAtATimeAndResets() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let env = SwiftBashExecutionEnvironment(
            workingDir: tempDir.path,
            config: SwiftBashBackendConfig(fileSystemMode: .realFileSystem)
        )
        let console = try await env.startCommandConsole(workingDir: nil, envVars: nil)

        _ = try await console.run("export FOO=bar", timeoutMs: 10_000)
        let beforeReset = try await console.run("echo $FOO", timeoutMs: 10_000)
        await console.reset()
        let afterReset = try await console.run("echo ${FOO:-unset}", timeoutMs: 10_000)

        #expect(await console.workingDirectory() == tempDir.path)
        #expect(beforeReset.stdout == "bar\n")
        #expect(afterReset.stdout == "unset\n")
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
