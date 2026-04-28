import Foundation
import Testing
@testable import OmniAIAgent

@Suite
final class SwiftBashExecutionEnvironmentTests {
    @Test
    func executesCommandsInProcess() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let env = SwiftBashExecutionEnvironment(workingDir: tempDir.path)
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
    func usesRequestedWorkingDirectoryAndRealFilesystem() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let env = SwiftBashExecutionEnvironment(workingDir: tempDir.path)
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
