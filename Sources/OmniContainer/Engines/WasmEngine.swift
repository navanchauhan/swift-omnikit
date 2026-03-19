import Foundation
import OmniVFS
import OmniExecution
import WasmKit
import WasmKitWASI
import SystemPackage

/// Executes WASI binaries via WasmKit.
public final class WasmEngine: ContainerRuntime, Sendable {

    public init() {}

    public func canExecute(_ data: [UInt8]) -> Bool {
        BinaryProbe.detect(data) == .wasm
    }

    public func execute(
        binaryPath: String,
        args: [String],
        env: [String: String],
        workingDir: String,
        namespace: VFSNamespace,
        timeoutMs: Int
    ) async throws -> ExecResult {
        let startTime = DispatchTime.now()

        // 1. Materialize VFS namespace to a temp host directory for WASI preopens.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnikit-wasm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try BlinkVFSSync.materialize(namespace: namespace, to: tempDir.path)

        // 2. Read the .wasm binary from the materialized directory.
        let wasmHostPath: String
        if binaryPath.hasPrefix("/") {
            wasmHostPath = tempDir.path + binaryPath
        } else {
            wasmHostPath = tempDir.path + "/" + binaryPath
        }

        guard FileManager.default.fileExists(atPath: wasmHostPath) else {
            return ExecResult(
                stdout: "",
                stderr: "WasmEngine: binary not found at \(binaryPath)",
                exitCode: 127,
                timedOut: false,
                durationMs: 0
            )
        }

        let wasmBytes: [UInt8]
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: wasmHostPath))
            wasmBytes = [UInt8](data)
        } catch {
            return ExecResult(
                stdout: "",
                stderr: "WasmEngine: failed to read binary: \(error)",
                exitCode: 1,
                timedOut: false,
                durationMs: 0
            )
        }

        // 3. Set up stdout/stderr capture pipes.
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutFD = FileDescriptor(rawValue: stdoutPipe.fileHandleForWriting.fileDescriptor)
        let stderrFD = FileDescriptor(rawValue: stderrPipe.fileHandleForWriting.fileDescriptor)

        // 4. Parse the WASM module.
        let module: Module
        do {
            module = try parseWasm(bytes: wasmBytes)
        } catch {
            return ExecResult(
                stdout: "",
                stderr: "WasmEngine: failed to parse WASM module: \(error)",
                exitCode: 1,
                timedOut: false,
                durationMs: 0
            )
        }

        // 5. Configure WASI bridge with preopens, args, env, and captured stdio.
        let wasiArgs = [binaryPath] + args
        let preopens = ["/": tempDir.path]

        let wasi: WASIBridgeToHost
        do {
            wasi = try WASIBridgeToHost(
                args: wasiArgs,
                environment: env,
                preopens: preopens,
                stdin: .standardInput,
                stdout: stdoutFD,
                stderr: stderrFD
            )
        } catch {
            return ExecResult(
                stdout: "",
                stderr: "WasmEngine: failed to set up WASI bridge: \(error)",
                exitCode: 1,
                timedOut: false,
                durationMs: 0
            )
        }

        // 6. Create engine, store, and instantiate module.
        let engine = Engine()
        let store = Store(engine: engine)
        var imports = Imports()
        wasi.link(to: &imports, store: store)

        let instance: Instance
        do {
            instance = try module.instantiate(store: store, imports: imports)
        } catch {
            stdoutPipe.fileHandleForWriting.closeFile()
            stderrPipe.fileHandleForWriting.closeFile()
            return ExecResult(
                stdout: "",
                stderr: "WasmEngine: failed to instantiate module: \(error)",
                exitCode: 1,
                timedOut: false,
                durationMs: 0
            )
        }

        // 7. Run the WASI _start function with timeout.
        var exitCode: Int32 = 0
        var timedOut = false

        let result: ExecResult = await withCheckedContinuation { continuation in
            let workItem = DispatchWorkItem {
                do {
                    let wasiExitCode = try wasi.start(instance)
                    exitCode = Int32(wasiExitCode)
                } catch {
                    exitCode = 1
                }

                // Close write ends so reads can complete.
                stdoutPipe.fileHandleForWriting.closeFile()
                stderrPipe.fileHandleForWriting.closeFile()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
                let durationMs = Int(elapsed / 1_000_000)

                let result = ExecResult(
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? "",
                    exitCode: exitCode,
                    timedOut: timedOut,
                    durationMs: durationMs
                )
                continuation.resume(returning: result)
            }

            let timeoutItem = DispatchWorkItem {
                timedOut = true
                // Cannot easily kill a running wasm module, but mark as timed out.
                stdoutPipe.fileHandleForWriting.closeFile()
                stderrPipe.fileHandleForWriting.closeFile()
            }

            DispatchQueue(label: "omnikit.wasm.exec.\(UUID().uuidString)").async(execute: workItem)
            DispatchQueue.global().asyncAfter(
                deadline: .now() + .milliseconds(timeoutMs),
                execute: timeoutItem
            )
        }

        return result
    }
}
