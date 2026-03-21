import Testing
import Foundation
@testable import OmniContainer
@testable import OmniVFS
import OmniExecution

@Suite("WasmEngine")
struct WasmEngineTests {

    /// Load the hello.wasm fixture bytes from the test bundle.
    private func loadHelloWasm() throws -> [UInt8] {
        guard let url = Bundle.module.url(forResource: "hello", withExtension: "wasm", subdirectory: "Fixtures") else {
            throw TestError(message: "hello.wasm fixture not found in bundle")
        }
        let data = try Data(contentsOf: url)
        return [UInt8](data)
    }

    @Test("canExecute recognizes WASM magic bytes")
    func canExecuteWasm() {
        let engine = WasmEngine()
        let wasmMagic: [UInt8] = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
        #expect(engine.canExecute(wasmMagic))
    }

    @Test("canExecute rejects ELF")
    func cannotExecuteELF() {
        let engine = WasmEngine()
        let elfMagic: [UInt8] = [0x7f, 0x45, 0x4c, 0x46, 0x02, 0x01]
        #expect(!engine.canExecute(elfMagic))
    }

    @Test("execute runs WASI hello world module")
    func executeHelloWorld() async throws {
        let wasmBytes = try loadHelloWasm()

        // Set up a VFS namespace with the wasm binary at /hello.wasm
        let memFS = MemFS()
        try memFS.createFile("hello.wasm", data: wasmBytes)

        var namespace = VFSNamespace()
        namespace.bind(src: memFS, dstPath: ".", mode: .replace)

        let engine = WasmEngine()
        let result = try await engine.execute(
            binaryPath: "/hello.wasm",
            args: [],
            env: [:],
            workingDir: "/",
            namespace: namespace,
            timeoutMs: 10_000
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("hello"))
        #expect(!result.timedOut)
    }

    @Test("execute returns error for missing binary")
    func executeMissingBinary() async throws {
        let memFS = MemFS()
        var namespace = VFSNamespace()
        namespace.bind(src: memFS, dstPath: ".", mode: .replace)

        let engine = WasmEngine()
        let result = try await engine.execute(
            binaryPath: "/nonexistent.wasm",
            args: [],
            env: [:],
            workingDir: "/",
            namespace: namespace,
            timeoutMs: 5_000
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("not found"))
    }

    @Test("execute passes environment variables")
    func executeWithEnv() async throws {
        // The hello.wasm fixture doesn't use env vars, but we verify the engine
        // doesn't crash when environment variables are provided.
        let wasmBytes = try loadHelloWasm()

        let memFS = MemFS()
        try memFS.createFile("hello.wasm", data: wasmBytes)

        var namespace = VFSNamespace()
        namespace.bind(src: memFS, dstPath: ".", mode: .replace)

        let engine = WasmEngine()
        let result = try await engine.execute(
            binaryPath: "/hello.wasm",
            args: ["arg1", "arg2"],
            env: ["HOME": "/tmp", "PATH": "/usr/bin"],
            workingDir: "/",
            namespace: namespace,
            timeoutMs: 10_000
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("hello"))
    }
}

@Suite("BlinkRuntime", .serialized)
struct BlinkRuntimeTests {

    private func blinkAvailable() -> Bool {
        FileManager.default.fileExists(atPath: "/opt/homebrew/bin/blink")
    }

    private func blinkFixtureRoot() -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/CBlinkEmulator/vendor/blink/third_party/cosmo")
    }

    private func tinyHelloFixtureURL() -> URL {
        blinkFixtureRoot().appending(path: "tinyhello.elf")
    }

    private func makeBlinkFixtureNamespace() -> VFSNamespace {
        let diskFS = DiskFS(root: blinkFixtureRoot().path)
        var namespace = VFSNamespace()
        namespace.bind(src: diskFS, dstPath: ".", mode: .replace)
        return namespace
    }

    private func withForcedNoForkBlink<T>(_ body: () async throws -> T) async throws -> T {
        setenv("OMNIKIT_BLINK_FORCE_NOFORK", "1", 1)
        defer { unsetenv("OMNIKIT_BLINK_FORCE_NOFORK") }
        return try await body()
    }

    @Test("canExecute recognizes ELF")
    func canExecuteELF() {
        let runtime = BlinkRuntime()
        let elfMagic: [UInt8] = [0x7f, 0x45, 0x4c, 0x46, 0x02, 0x01, 0x01, 0x00]
        #expect(runtime.canExecute(elfMagic))
    }

    @Test("canExecute recognizes script")
    func canExecuteScript() {
        let runtime = BlinkRuntime()
        let script: [UInt8] = Array("#!/bin/sh\necho hello".utf8)
        #expect(runtime.canExecute(script))
    }

    @Test("canExecute rejects WASM")
    func cannotExecuteWasm() {
        let runtime = BlinkRuntime()
        let wasmMagic: [UInt8] = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
        #expect(!runtime.canExecute(wasmMagic))
    }

    @Test("findBlink locates /opt/homebrew/bin/blink")
    func findBlinkResolvesPath() throws {
        guard blinkAvailable() else {
            // Skip if blink not installed
            return
        }
        let runtime = BlinkRuntime()
        // The init with no path should still find blink via candidates list.
        // We test indirectly by checking canExecute + that init doesn't throw.
        let elfMagic: [UInt8] = [0x7f, 0x45, 0x4c, 0x46, 0x02, 0x01, 0x01, 0x00]
        #expect(runtime.canExecute(elfMagic))
    }

    @Test("explicit blinkPath is used")
    func explicitBlinkPath() {
        let runtime = BlinkRuntime(blinkPath: "/opt/homebrew/bin/blink")
        let elfMagic: [UInt8] = [0x7f, 0x45, 0x4c, 0x46, 0x02, 0x01, 0x01, 0x00]
        #expect(runtime.canExecute(elfMagic))
    }

    @Test("forced no-fork runtime executes vendored tinyhello")
    func executeTinyHelloNoFork() async throws {
        guard FileManager.default.fileExists(atPath: tinyHelloFixtureURL().path) else {
            return
        }

        let result = try await withForcedNoForkBlink {
            let runtime = BlinkRuntime()
            return try await runtime.execute(
                binaryPath: "/tinyhello.elf",
                args: [],
                env: [:],
                workingDir: "/",
                namespace: makeBlinkFixtureNamespace(),
                timeoutMs: 10_000
            )
        }

        #expect(result.exitCode == 0)
        #expect(result.stdout.localizedStandardContains("hello"))
        #expect(!result.timedOut)
    }

    @Test("forced no-fork runtime can execute repeatedly")
    func executeTinyHelloNoForkTwice() async throws {
        guard FileManager.default.fileExists(atPath: tinyHelloFixtureURL().path) else {
            return
        }

        let results = try await withForcedNoForkBlink {
            let runtime = BlinkRuntime()
            let namespace = makeBlinkFixtureNamespace()

            let first = try await runtime.execute(
                binaryPath: "/tinyhello.elf",
                args: [],
                env: [:],
                workingDir: "/",
                namespace: namespace,
                timeoutMs: 10_000
            )
            let second = try await runtime.execute(
                binaryPath: "/tinyhello.elf",
                args: [],
                env: [:],
                workingDir: "/",
                namespace: namespace,
                timeoutMs: 10_000
            )
            return [first, second]
        }

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.exitCode == 0 })
        #expect(results.allSatisfy { $0.stdout.localizedStandardContains("hello") })
        #expect(results.allSatisfy { !$0.timedOut })
    }

    @Test("forced no-fork runtime executes vendored tinyhello through a symlinked guest path")
    func executeTinyHelloViaSymlink() async throws {
        guard FileManager.default.fileExists(atPath: tinyHelloFixtureURL().path) else {
            return
        }

        let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let binaryURL = tempRoot.appending(path: "tinyhello.elf")
        try FileManager.default.copyItem(at: tinyHelloFixtureURL(), to: binaryURL)
        let linkPath = tempRoot.appending(path: "hello-link").path
        try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: "tinyhello.elf")

        let diskFS = DiskFS(root: tempRoot.path)
        var namespace = VFSNamespace()
        namespace.bind(src: diskFS, dstPath: ".", mode: .replace)

        let result = try await withForcedNoForkBlink {
            let runtime = BlinkRuntime()
            return try await runtime.execute(
                binaryPath: "/hello-link",
                args: [],
                env: [:],
                workingDir: "/",
                namespace: namespace,
                timeoutMs: 10_000
            )
        }

        #expect(result.exitCode == 0)
        #expect(result.stdout.localizedStandardContains("hello"))
        #expect(!result.timedOut)
    }
}

/// Simple error type for test failures.
private struct TestError: Error {
    let message: String
}
