// OmniTerm — Interactive Alpine Linux terminal powered by embedded blink x86-64 emulator.
//
// Boots into a lightweight Alpine Linux shell running through blink's x86-64
// syscall emulation with a Wanix-inspired VFS namespace (CowFS overlay on
// Alpine minirootfs). No Docker, no VMs — just an embedded emulator.
//
// Usage:
//   omniterm                    # Boot into Alpine /bin/sh
//   omniterm --network          # Enable outbound networking (for apk)
//   omniterm --bind /path       # Bind host directory at /workspace
//   omniterm -- /bin/busybox ls # Run a specific command

import Foundation
import OmniVFS
import OmniContainer
import OmniExecution
import CBlinkEmulator

// MARK: - Argument Parsing

struct TermConfig {
    var networkEnabled = false
    var hostBindPath: String? = nil
    var command: [String] = ["/bin/sh", "-l"]
    var imageRef = "alpine:minirootfs"
}

func parseArgs() -> TermConfig {
    var config = TermConfig()
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0

    while i < args.count {
        switch args[i] {
        case "--network", "-n":
            config.networkEnabled = true
        case "--bind", "-b":
            i += 1
            if i < args.count { config.hostBindPath = args[i] }
        case "--image":
            i += 1
            if i < args.count { config.imageRef = args[i] }
        case "--help", "-h":
            printUsage()
            exit(0)
        case "--":
            config.command = Array(args.dropFirst(i + 1))
            return config
        default:
            // Treat as command
            config.command = Array(args.dropFirst(i))
            return config
        }
        i += 1
    }

    return config
}

func printUsage() {
    let usage = """
    OmniTerm — Interactive Alpine Linux terminal (blink x86-64 emulator)

    USAGE:
      omniterm [OPTIONS] [-- COMMAND [ARGS...]]

    OPTIONS:
      -n, --network       Enable outbound networking (for apk add, curl, etc.)
      -b, --bind PATH     Bind a host directory at /workspace in the container
          --image REF     Image reference (default: alpine:minirootfs)
      -h, --help          Show this help

    EXAMPLES:
      omniterm                           # Interactive Alpine shell
      omniterm --network                 # Shell with networking (apk works)
      omniterm --bind .                  # Mount current dir at /workspace
      omniterm -- /bin/busybox uname -a  # Run a single command
      omniterm --network -- apk add curl # Install a package
    """
    print(usage)
}

// MARK: - Image Resolution

func resolveImage(_ ref: String) async throws -> any VFS {
    let cacheDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".omnikit/images")
    let tarGzPath = cacheDir.appendingPathComponent("alpine-minirootfs.tar.gz")

    // Download if not cached
    if !FileManager.default.fileExists(atPath: tarGzPath.path) {
        print("Downloading Alpine minirootfs...")
        let url = URL(string: "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-minirootfs-3.21.3-x86_64.tar.gz")!
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let (data, _) = try await URLSession.shared.data(from: url)
        try data.write(to: tarGzPath)
        print("Cached to \(tarGzPath.path)")
    }

    // Decompress gzip -> tar
    let tarPath = cacheDir.appendingPathComponent("alpine-minirootfs.tar")
    if !FileManager.default.fileExists(atPath: tarPath.path) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        proc.arguments = ["-k", "-f", tarGzPath.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "OmniTerm", code: 1, userInfo: [NSLocalizedDescriptionKey: "gunzip failed"])
        }
    }

    let tarData = try Data(contentsOf: tarPath)
    return try TarFS(data: Array(tarData))
}

// MARK: - Main

@main
struct OmniTermMain {
    static func main() async throws {
        let config = parseArgs()

        // 1. Resolve Alpine rootfs
        let rootFS = try await resolveImage(config.imageRef)

        // 2. Build VFS namespace
        let overlay = MemFS()
        let cow = CowFS(base: rootFS, overlay: overlay)
        var namespace = VFSNamespace()
        namespace.bind(src: cow, srcPath: ".", dstPath: ".", mode: .replace)

        // Bind /tmp
        let tmpFS = MemFS()
        namespace.bind(src: tmpFS, srcPath: ".", dstPath: "tmp", mode: .replace)

        // Bind host directory at /workspace if requested
        if let hostPath = config.hostBindPath {
            let absPath = hostPath.hasPrefix("/") ? hostPath :
                FileManager.default.currentDirectoryPath + "/" + hostPath
            let diskFS = DiskFS(root: absPath)
            namespace.bind(src: diskFS, srcPath: ".", dstPath: "workspace", mode: .replace)
        }

        // 3. Materialize VFS to temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("omniterm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // SIGINT handled by child process — parent just waits

        print("Materializing Alpine rootfs...")
        try BlinkVFSSync.materialize(namespace: namespace, to: tempDir.path)

        // 4. Build blink config
        // With blink VFS, program_path is the HOST path to the binary
        // but argv[0] is the guest path
        let programPath = config.command[0]
        let guestProgramPath = programPath.hasPrefix("/") ? programPath : "/\(programPath)"
        let hostProgramPath = tempDir.path + guestProgramPath

        // Verify the binary exists in materialized rootfs
        guard FileManager.default.fileExists(atPath: hostProgramPath) else {
            fputs("omniterm: \(guestProgramPath): not found in rootfs\n", stderr)
            try? FileManager.default.removeItem(at: tempDir)
            exit(127)
        }

        // Build argv — argv[0] is the guest-visible program name
        var argv = config.command
        argv[0] = guestProgramPath

        // Build env
        var env: [String] = [
            "HOME=/root",
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "TERM=\(ProcessInfo.processInfo.environment["TERM"] ?? "xterm-256color")",
            "LANG=C.UTF-8",
            "PS1=\\[\\033[1;32m\\]omniterm\\[\\033[0m\\]:\\[\\033[1;34m\\]\\w\\[\\033[0m\\]\\$ ",
        ]
        if config.hostBindPath != nil {
            env.append("WORKSPACE=/workspace")
        }

        // 5. Call blink_run_interactive — child inherits our terminal
        // program_path must be the GUEST path — blink VFS translates it
        let exitCode: Int32 = argv.withCArrayOfCStrings { cArgv in
            env.withCArrayOfCStrings { cEnv in
                guestProgramPath.withCString { cProgram in
                    tempDir.path.withCString { cPrefix in
                        var blinkConfig = blink_run_config_t()
                        blinkConfig.program_path = cProgram
                        blinkConfig.argv = cArgv
                        blinkConfig.argc = Int32(argv.count)
                        blinkConfig.envp = cEnv
                        blinkConfig.envc = Int32(env.count)
                        blinkConfig.vfs_prefix = cPrefix
                        return Int32(blink_run_interactive(&blinkConfig))
                    }
                }
            }
        }

        // 6. Cleanup
        try? FileManager.default.removeItem(at: tempDir)
        exit(exitCode)
    }
}

// MARK: - C String Array Helper

extension Array where Element == String {
    func withCArrayOfCStrings<R>(_ body: (UnsafePointer<UnsafePointer<CChar>?>) -> R) -> R {
        // strdup each string
        let duped: [UnsafeMutablePointer<CChar>] = self.map { strdup($0)! }
        defer { duped.forEach { free($0) } }
        // Build null-terminated array of const pointers
        var ptrs: [UnsafePointer<CChar>?] = duped.map { UnsafePointer($0) }
        ptrs.append(nil)
        return ptrs.withUnsafeBufferPointer { buf in
            body(buf.baseAddress!)
        }
    }
}
