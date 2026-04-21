import Testing
import Foundation
@testable import OmniContainer
@testable import OmniVFS
import OmniExecution

@Suite("ContainerExecutionEnvironment")
struct ContainerExecEnvTests {
    private struct FixtureError: Error {
        let message: String
    }

    private func loadHelloWasm() throws -> [UInt8] {
        guard let url = Bundle.module.url(forResource: "hello", withExtension: "wasm", subdirectory: "Fixtures") else {
            throw FixtureError(message: "hello.wasm fixture not found in bundle")
        }
        let data = try Data(contentsOf: url)
        return [UInt8](data)
    }

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
        #expect(content == "   1 | Alpine Linux 3.21\n")
    }

    @Test("writeFile and readFile round-trip")
    func writeReadRoundTrip() async throws {
        let env = try await makeTestEnv()
        try await env.writeFile(path: "/bin/test.txt", content: "test content")
        let content = try await env.readFile(path: "/bin/test.txt", offset: nil, limit: nil)
        #expect(content == "   1 | test content\n")
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

    @Test("workingDirectory returns guest workspace path")
    func workingDirectoryIsHost() async throws {
        let env = try await makeTestEnv()
        #expect(env.workingDirectory() == "/workspace")
    }

    @Test("path translation: host workspace path maps to guest")
    func pathTranslation() async throws {
        let env = try await makeTestEnv()
        // Write via guest path
        try await env.writeFile(path: "/workspace/new.txt", content: "via guest")
        // Read via guest path
        let content = try await env.readFile(path: "/workspace/new.txt", offset: nil, limit: nil)
        #expect(content == "   1 | via guest\n")
    }

    @Test("listDirectory")
    func listDirectoryTest() async throws {
        let env = try await makeTestEnv()
        let entries = try await env.listDirectory(path: "/workspace", depth: 1)
        #expect(entries.contains(where: { $0.name == "hello.txt" }))
    }

    @Test("glob returns host workspace paths and matches top-level files")
    func globReturnsHostPaths() async throws {
        let env = try await makeTestEnv()
        let matches = try await env.glob(pattern: "**/*", path: "/tmp/test-workspace")
        #expect(matches == ["/tmp/test-workspace/hello.txt"])
    }

    @Test("grep returns host workspace paths")
    func grepReturnsHostPaths() async throws {
        let env = try await makeTestEnv()
        let output = try await env.grep(
            pattern: "workspace",
            path: "/tmp/test-workspace",
            options: GrepOptions(maxResults: 10)
        )
        #expect(output.contains("/tmp/test-workspace/hello.txt:1:hello from workspace"))
    }

    @Test("execCommand respects working directory", .serialized)
    func execCommandRespectsWorkingDirectory() async throws {
        let fileManager = FileManager.default
        let hostWorkspace = fileManager.temporaryDirectory.appendingPathComponent(
            "omnikit-container-exec-\(UUID().uuidString)",
            isDirectory: true
        )
        let nestedDirectory = hostWorkspace.appendingPathComponent("nested", isDirectory: true)
        try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: hostWorkspace) }

        let rootFS = try await ImageStore.shared.resolve("alpine:minirootfs")
        let spec = ContainerSpec(
            imageRef: "alpine:minirootfs",
            hostWorkspaceDir: hostWorkspace.path,
            capabilities: [.workspace(hostPath: hostWorkspace.path)]
        )
        let container = ContainerActor(config: spec, rootFS: rootFS)
        let env = ContainerExecutionEnvironment(
            container: container,
            hostWorkspaceDir: hostWorkspace.path
        )

        try await env.initialize()
        defer { Task { try? await env.cleanup() } }

        let result = try await env.execCommand(
            command: "pwd",
            timeoutMs: 15_000,
            workingDir: nestedDirectory.path,
            envVars: nil
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "/workspace/nested")
    }

    @Test("network-enabled container seeds resolv.conf")
    func networkEnabledContainerSeedsResolvConf() async throws {
        let rootFS = try await ImageStore.shared.resolve("alpine:minirootfs")
        let spec = ContainerSpec(
            imageRef: "alpine:minirootfs",
            capabilities: [.network]
        )
        let container = ContainerActor(config: spec, rootFS: rootFS)
        try await container.start()

        let resolvConf = try await container.readFile(path: "etc/resolv.conf")

        #expect(resolvConf.contains("nameserver"))
    }

    @Test("execCommand seeds baseline shell environment", .serialized)
    func execCommandSeedsBaselineEnvironment() async throws {
        let fileManager = FileManager.default
        let hostWorkspace = fileManager.temporaryDirectory.appendingPathComponent(
            "omnikit-container-env-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: hostWorkspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: hostWorkspace) }

        let rootFS = try await ImageStore.shared.resolve("alpine:minirootfs")
        let spec = ContainerSpec(
            imageRef: "alpine:minirootfs",
            hostWorkspaceDir: hostWorkspace.path,
            capabilities: [.workspace(hostPath: hostWorkspace.path)]
        )
        let container = ContainerActor(config: spec, rootFS: rootFS)
        let env = ContainerExecutionEnvironment(
            container: container,
            hostWorkspaceDir: hostWorkspace.path
        )

        try await env.initialize()
        defer { Task { try? await env.cleanup() } }

        let result = try await env.execCommand(
            command: "env | sort",
            timeoutMs: 15_000,
            workingDir: hostWorkspace.path,
            envVars: nil
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("HOME=/tmp/iagentsmith-home"))
        #expect(result.stdout.contains("USER=codex"))
        #expect(result.stdout.contains("LOGNAME=codex"))
        #expect(result.stdout.contains("SHELL=/bin/sh"))
        #expect(result.stdout.contains("TERM=xterm-256color"))
        #expect(result.stdout.contains("PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"))
    }

    @Test("container config can override HOME for persistent guest state", .serialized)
    func containerConfigOverridesHome() async throws {
        let fileManager = FileManager.default
        let hostWorkspace = fileManager.temporaryDirectory.appendingPathComponent(
            "omnikit-container-home-\(UUID().uuidString)",
            isDirectory: true
        )
        let hostState = fileManager.temporaryDirectory.appendingPathComponent(
            "omnikit-container-state-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: hostWorkspace, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: hostState, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: hostWorkspace)
            try? fileManager.removeItem(at: hostState)
        }

        let rootFS = try await ImageStore.shared.resolve("alpine:minirootfs")
        let spec = ContainerSpec(
            imageRef: "alpine:minirootfs",
            env: [
                "HOME": "/mnt/iagentsmith-state/home",
                "USER": "codex",
                "LOGNAME": "codex",
            ],
            hostWorkspaceDir: hostWorkspace.path,
            capabilities: [
                .workspace(hostPath: hostWorkspace.path),
                .persistentVolume(name: "iagentsmith-state", hostPath: hostState.path),
            ]
        )
        let container = ContainerActor(config: spec, rootFS: rootFS)
        let env = ContainerExecutionEnvironment(
            container: container,
            hostWorkspaceDir: hostWorkspace.path
        )

        try await env.initialize()
        defer { Task { try? await env.cleanup() } }

        let result = try await env.execCommand(
            command: "env | sort",
            timeoutMs: 15_000,
            workingDir: hostWorkspace.path,
            envVars: nil
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("HOME=/mnt/iagentsmith-state/home"))
        #expect(result.stdout.contains("USER=codex"))
        #expect(result.stdout.contains("LOGNAME=codex"))
    }

    @Test("container config can seed git safe.directory env", .serialized)
    func containerConfigSeedsGitSafeDirectoryEnv() async throws {
        let fileManager = FileManager.default
        let hostWorkspace = fileManager.temporaryDirectory.appendingPathComponent(
            "omnikit-container-git-env-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: hostWorkspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: hostWorkspace) }

        let rootFS = try await ImageStore.shared.resolve("alpine:minirootfs")
        let spec = ContainerSpec(
            imageRef: "alpine:minirootfs",
            env: [
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "safe.directory",
                "GIT_CONFIG_VALUE_0": "*",
            ],
            hostWorkspaceDir: hostWorkspace.path,
            capabilities: [.workspace(hostPath: hostWorkspace.path)]
        )
        let container = ContainerActor(config: spec, rootFS: rootFS)
        let env = ContainerExecutionEnvironment(
            container: container,
            hostWorkspaceDir: hostWorkspace.path
        )

        try await env.initialize()
        defer { Task { try? await env.cleanup() } }

        let result = try await env.execCommand(
            command: "env | sort",
            timeoutMs: 15_000,
            workingDir: hostWorkspace.path,
            envVars: nil
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("GIT_CONFIG_COUNT=1"))
        #expect(result.stdout.contains("GIT_CONFIG_KEY_0=safe.directory"))
        #expect(result.stdout.contains("GIT_CONFIG_VALUE_0=*"))
    }

    @Test("bundled codex image exposes core local tooling", .serialized)
    func bundledCodexImageExposesCoreTooling() async throws {
        let fileManager = FileManager.default
        let hostWorkspace = fileManager.temporaryDirectory.appendingPathComponent(
            "omnikit-container-tooling-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: hostWorkspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: hostWorkspace) }

        let rootFS = try await ImageStore.shared.resolve("alpine:codex-ios")
        let spec = ContainerSpec(
            imageRef: "alpine:codex-ios",
            hostWorkspaceDir: hostWorkspace.path,
            capabilities: [.workspace(hostPath: hostWorkspace.path)]
        )
        let container = ContainerActor(config: spec, rootFS: rootFS)
        let env = ContainerExecutionEnvironment(
            container: container,
            hostWorkspaceDir: hostWorkspace.path
        )

        try await env.initialize()
        defer { Task { try? await env.cleanup() } }

        let result = try await env.execCommand(
            command: "for cmd in git rg curl wget python3; do command -v \"$cmd\" || exit 1; done",
            timeoutMs: 15_000,
            workingDir: hostWorkspace.path,
            envVars: nil
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("/usr/bin/git"))
        #expect(result.stdout.contains("/usr/bin/rg"))
        #expect(result.stdout.contains("/usr/bin/curl"))
        #expect(result.stdout.contains("/usr/bin/wget"))
        #expect(result.stdout.contains("/usr/bin/python3"))
    }

    @Test("execCommand dispatches direct wasm invocations through WASI")
    func execCommandDispatchesDirectWasmInvocation() async throws {
        let fileManager = FileManager.default
        let hostWorkspace = fileManager.temporaryDirectory.appendingPathComponent(
            "omnikit-container-wasm-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: hostWorkspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: hostWorkspace) }

        let wasmBytes = try loadHelloWasm()
        try Data(wasmBytes).write(to: hostWorkspace.appendingPathComponent("hello.wasm"))

        let rootFS = MemFS()
        let spec = ContainerSpec(
            imageRef: "test:wasm",
            hostWorkspaceDir: hostWorkspace.path,
            capabilities: [.workspace(hostPath: hostWorkspace.path)]
        )
        let container = ContainerActor(config: spec, rootFS: rootFS)
        let env = ContainerExecutionEnvironment(
            container: container,
            hostWorkspaceDir: hostWorkspace.path
        )

        try await env.initialize()
        defer { Task { try? await env.cleanup() } }

        let result = try await env.execCommand(
            command: "./hello.wasm",
            timeoutMs: 10_000,
            workingDir: hostWorkspace.path,
            envVars: nil
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("hello"))
        #expect(!result.timedOut)
    }

    @Test("execCommand keeps shell semantics for compound wasm-shaped commands", .serialized)
    func execCommandKeepsShellSemanticsForCompoundCommands() async throws {
        let fileManager = FileManager.default
        let hostWorkspace = fileManager.temporaryDirectory.appendingPathComponent(
            "omnikit-container-wasm-shell-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: hostWorkspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: hostWorkspace) }

        let wasmBytes = try loadHelloWasm()
        try Data(wasmBytes).write(to: hostWorkspace.appendingPathComponent("hello.wasm"))

        let rootFS = try await ImageStore.shared.resolve("alpine:minirootfs")
        let spec = ContainerSpec(
            imageRef: "alpine:minirootfs",
            hostWorkspaceDir: hostWorkspace.path,
            capabilities: [.workspace(hostPath: hostWorkspace.path)]
        )
        let container = ContainerActor(config: spec, rootFS: rootFS)
        let env = ContainerExecutionEnvironment(
            container: container,
            hostWorkspaceDir: hostWorkspace.path
        )

        try await env.initialize()
        defer { Task { try? await env.cleanup() } }

        let result = try await env.execCommand(
            command: "./hello.wasm > /tmp/hello.txt || echo shell-fallback",
            timeoutMs: 10_000,
            workingDir: hostWorkspace.path,
            envVars: nil
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("shell-fallback"))
        #expect(!result.stdout.contains("hello"))
    }
}
