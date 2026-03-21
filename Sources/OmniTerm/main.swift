// OmniTerm — Interactive Alpine Linux terminal powered by embedded blink x86-64 emulator.
//
// Boots into a lightweight Alpine Linux shell running through blink's x86-64
// syscall emulation with a Wanix-inspired VFS namespace (CowFS overlay on
// Alpine minirootfs). No Docker, no VMs — just an embedded emulator.
//
// The container rootfs is snapshotted into a FlatVFS and passed to blink via
// C-accessible structs. Host workspace binds stay as direct host mounts so
// large trees do not get copied into memory up front.
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
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private let blinkHelperFlag = "--_blink-helper"

private struct BlinkHelperMount: Codable {
    let hostPath: String
    let guestPath: String
}

private struct BlinkHelperConfig: Codable {
    let rootPath: String
    let programPath: String
    let argv: [String]
    let env: [String]
    let hostMounts: [BlinkHelperMount]
}

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
    try await ImageStore.shared.resolve(ref)
}

private func shellQuote(_ argument: String) -> String {
    "'" + argument.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

private func helperConfigPathIfPresent() -> String? {
    let args = CommandLine.arguments
    guard args.count == 3, args[1] == blinkHelperFlag else {
        return nil
    }
    return args[2]
}

private func shouldUseSpawnedBlinkHelper() -> Bool {
#if os(macOS)
    return ProcessInfo.processInfo.environment["OMNIKIT_BLINK_FORCE_NOFORK"] == nil
#else
    return false
#endif
}

private func materializeFlatVFS(_ flatVFS: FlatVFS, to rootURL: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)

    for entry in flatVFS.entries {
        let relativePath = entry.path == "." ? "" : entry.path
        let hostURL = relativePath.isEmpty ? rootURL : rootURL.appending(path: relativePath)
        let parentURL = hostURL.deletingLastPathComponent()

        switch entry.type {
        case .directory:
            try fm.createDirectory(at: hostURL, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: NSNumber(value: Int(entry.mode))], ofItemAtPath: hostURL.path)
        case .file:
            try fm.createDirectory(at: parentURL, withIntermediateDirectories: true)
            guard fm.createFile(atPath: hostURL.path, contents: Data(entry.data)) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try fm.setAttributes([.posixPermissions: NSNumber(value: Int(entry.mode))], ofItemAtPath: hostURL.path)
        case .symlink:
            try fm.createDirectory(at: parentURL, withIntermediateDirectories: true)
            if fm.fileExists(atPath: hostURL.path) {
                try fm.removeItem(at: hostURL)
            }
            try fm.createSymbolicLink(atPath: hostURL.path, withDestinationPath: entry.symlinkTarget)
        }
    }
}

private func runBlinkHelperMode(configPath: String) throws -> Int32 {
    adoptParentProcessGroupIfPossible()

    let configData = try Data(contentsOf: URL(fileURLWithPath: configPath))
    let helperConfig = try JSONDecoder().decode(BlinkHelperConfig.self, from: configData)
    let hostMounts = helperConfig.hostMounts.map {
        BlinkHostMount(hostPath: $0.hostPath, guestPath: $0.guestPath)
    }
    let cHostMounts = buildCHostMounts(hostMounts)
    defer { freeCHostMounts(cHostMounts.ptr, count: cHostMounts.count) }

    _ = FileManager.default.changeCurrentDirectoryPath("/")

    return helperConfig.argv.withCArrayOfCStrings { cArgv in
        helperConfig.env.withCArrayOfCStrings { cEnv in
            helperConfig.programPath.withCString { cProgram in
                var blinkConfig = blink_run_config_t()
                blinkConfig.program_path = cProgram
                blinkConfig.argv = cArgv
                blinkConfig.argc = Int32(helperConfig.argv.count)
                blinkConfig.envp = cEnv
                blinkConfig.envc = Int32(helperConfig.env.count)
                let vfsPrefix = strdup(helperConfig.rootPath)
                blinkConfig.vfs_prefix = vfsPrefix.map { UnsafePointer($0) }
                blinkConfig.host_mounts = cHostMounts.ptr.map { UnsafePointer($0) }
                blinkConfig.host_mount_count = Int32(cHostMounts.count)
                defer {
                    free(vfsPrefix)
                }
                return Int32(blink_run_interactive(&blinkConfig))
            }
        }
    }
}

private func adoptParentProcessGroupIfPossible() {
#if canImport(Darwin) || canImport(Glibc)
    let parentPID = getppid()
    guard parentPID > 1 else {
        return
    }

    let parentGroup = getpgid(parentPID)
    guard parentGroup > 0 else {
        return
    }

    // `Process` can place the spawned helper into its own process group on
    // macOS. Rejoining the parent's group keeps the interactive Blink child in
    // the foreground terminal job instead of being background-stopped on tty
    // access.
    _ = setpgid(0, parentGroup)
#endif
}

private func runViaSpawnedBlinkHelper(
    flatVFS: FlatVFS,
    hostMounts: [BlinkHostMount],
    guestProgramPath: String,
    argv: [String],
    env: [String]
) throws -> Int32 {
    let fm = FileManager.default
    let keepHelperRoot = ProcessInfo.processInfo.environment["OMNITERM_KEEP_HELPER_ROOT"] != nil
    let helperBaseURL = fm.temporaryDirectory.appending(
        path: "omniterm-helper-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    let rootURL = helperBaseURL.appending(path: "rootfs", directoryHint: .isDirectory)
    let configURL = helperBaseURL.appending(path: "blink-helper.json")

    try fm.createDirectory(at: helperBaseURL, withIntermediateDirectories: true)
    defer {
        if !keepHelperRoot {
            try? fm.removeItem(at: helperBaseURL)
        }
    }

    try materializeFlatVFS(flatVFS, to: rootURL)

    let helperConfig = BlinkHelperConfig(
        rootPath: rootURL.path,
        programPath: guestProgramPath,
        argv: argv,
        env: env,
        hostMounts: hostMounts.map {
            BlinkHelperMount(hostPath: $0.hostPath, guestPath: $0.guestPath)
        }
    )
    let helperConfigData = try JSONEncoder().encode(helperConfig)
    try helperConfigData.write(to: configURL, options: .atomic)
    if keepHelperRoot {
        fputs("OmniTerm helper config: \(configURL.path)\n", stderr)
    }

    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let process = Process()
    process.executableURL = executableURL
    process.arguments = [blinkHelperFlag, configURL.path]
    var helperEnvironment = ProcessInfo.processInfo.environment
    helperEnvironment.removeValue(forKey: "OMNIKIT_BLINK_FORCE_NOFORK")
    process.environment = helperEnvironment
    process.standardInput = FileHandle.standardInput
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    try process.run()
    process.waitUntilExit()

    switch process.terminationReason {
    case .exit:
        return process.terminationStatus
    case .uncaughtSignal:
        return 128 + process.terminationStatus
    @unknown default:
        return process.terminationStatus
    }
}

// MARK: - Main

@main
struct OmniTermMain {
    static func main() async throws {
        if let helperConfigPath = helperConfigPathIfPresent() {
            exit(try runBlinkHelperMode(configPath: helperConfigPath))
        }

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

        // Inject DNS config from host so networking works inside the container
        if config.networkEnabled {
            let hostResolv = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8)
            let resolvConf = BlinkGuestNetworking.resolvConf(hostContents: hostResolv)
            try? overlay.mkdir("etc")
            try? overlay.writeFile("etc/resolv.conf", data: Array(resolvConf.utf8))
        }

        // 3. Build the guest VFS plan.
        print("Planning guest VFS...")
        let vfsPlan = BlinkVFSPlanner.buildLaunchPlan(namespace: namespace)
        print(
            "Guest VFS ready: \(vfsPlan.flatVFS.entries.count) snapshot entries, "
                + "\(vfsPlan.hostMounts.count) host mounts"
        )

        // 4. Convert FlatVFS to C flatvfs_t
        let cEntries = buildCFlatVFS(vfsPlan.flatVFS)
        defer { freeCFlatVFS(cEntries.ptr, count: cEntries.count) }
        let cHostMounts = buildCHostMounts(vfsPlan.hostMounts)
        defer { freeCHostMounts(cHostMounts.ptr, count: cHostMounts.count) }

        var flatvfs = flatvfs_t()
        flatvfs.entries = UnsafePointer(cEntries.ptr)
        flatvfs.entry_count = Int32(cEntries.count)

        // 5. Build blink config
        let guestProgramPath: String
        let argv: [String]
        if config.command[0].hasPrefix("/") {
            guestProgramPath = config.command[0]
            var directArgv = config.command
            directArgv[0] = guestProgramPath
            argv = directArgv
        } else {
            guestProgramPath = "/bin/sh"
            let shellCommand = config.command.map(shellQuote).joined(separator: " ")
            argv = [guestProgramPath, "-lc", shellCommand]
        }

        // Build env
        var env: [String] = [
            "HOME=/root",
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "TERM=\(ProcessInfo.processInfo.environment["TERM"] ?? "xterm-256color")",
            "LANG=C.UTF-8",
            "PS1=\\[\\033[1;32m\\]omniterm\\[\\033[0m\\]:\\[\\033[1;34m\\]\\w\\[\\033[0m\\]\\$ ",
        ]
        if !config.networkEnabled {
            env.append("BLINK_DISABLE_NETWORKING=1")
        }
        if config.hostBindPath != nil {
            env.append("WORKSPACE=/workspace")
        }
        env = BlinkGuestNodeRuntime.mergedEnvironmentStrings(env)

        if shouldUseSpawnedBlinkHelper() {
            exit(try runViaSpawnedBlinkHelper(
                flatVFS: vfsPlan.flatVFS,
                hostMounts: vfsPlan.hostMounts,
                guestProgramPath: guestProgramPath,
                argv: argv,
                env: env
            ))
        }

        // 6. Flush output before fork to avoid duplicates in child
        fflush(nil)

        // 7. Call blink_run_memvfs directly.
        //    chdir to "/" first to avoid getcwd issues in the forked child.
        _ = FileManager.default.changeCurrentDirectoryPath("/")

        let exitCode: Int32 = argv.withCArrayOfCStrings { cArgv in
            env.withCArrayOfCStrings { cEnv in
                guestProgramPath.withCString { cProgram in
                    var blinkConfig = blink_run_config_t()
                    blinkConfig.program_path = cProgram
                    blinkConfig.argv = cArgv
                    blinkConfig.argc = Int32(argv.count)
                    blinkConfig.envp = cEnv
                    blinkConfig.envc = Int32(env.count)
                    blinkConfig.vfs_prefix = nil
                    blinkConfig.host_mounts = cHostMounts.ptr.map { UnsafePointer($0) }
                    blinkConfig.host_mount_count = Int32(cHostMounts.count)
                    return Int32(blink_run_memvfs(&blinkConfig, &flatvfs))
                }
            }
        }

        exit(exitCode)
    }
}

// MARK: - C FlatVFS Conversion Helpers

private struct CFlatVFSResult {
    let ptr: UnsafeMutablePointer<flatvfs_entry_t>
    let count: Int
}

private struct CHostMountsResult {
    let ptr: UnsafeMutablePointer<blink_host_mount_t>?
    let count: Int
}

private func buildCFlatVFS(_ flat: FlatVFS) -> CFlatVFSResult {
    let count = flat.entries.count
    let entries = UnsafeMutablePointer<flatvfs_entry_t>.allocate(capacity: count)

    for (i, entry) in flat.entries.enumerated() {
        var cEntry = flatvfs_entry_t()
        cEntry.path = UnsafePointer(strdup(entry.path))
        cEntry.type = entry.type.rawValue
        cEntry.mode = entry.mode

        if entry.type == .file && !entry.data.isEmpty {
            let dataBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: entry.data.count)
            entry.data.withUnsafeBufferPointer { buf in
                dataBuf.initialize(from: buf.baseAddress!, count: buf.count)
            }
            cEntry.data = UnsafePointer(dataBuf)
            cEntry.data_size = entry.data.count
        } else {
            cEntry.data = nil
            cEntry.data_size = 0
        }

        if entry.type == .symlink && !entry.symlinkTarget.isEmpty {
            cEntry.symlink_target = UnsafePointer(strdup(entry.symlinkTarget))
        } else {
            cEntry.symlink_target = nil
        }

        entries[i] = cEntry
    }

    return CFlatVFSResult(ptr: entries, count: count)
}

private func freeCFlatVFS(_ entries: UnsafeMutablePointer<flatvfs_entry_t>, count: Int) {
    for i in 0..<count {
        let e = entries[i]
        free(UnsafeMutablePointer(mutating: e.path))
        if let data = e.data {
            UnsafeMutablePointer(mutating: data).deallocate()
        }
        if let target = e.symlink_target {
            free(UnsafeMutablePointer(mutating: target))
        }
    }
    entries.deallocate()
}

private func buildCHostMounts(_ hostMounts: [BlinkHostMount]) -> CHostMountsResult {
    guard !hostMounts.isEmpty else {
        return CHostMountsResult(ptr: nil, count: 0)
    }

    let mounts = UnsafeMutablePointer<blink_host_mount_t>.allocate(capacity: hostMounts.count)
    for (index, hostMount) in hostMounts.enumerated() {
        var cMount = blink_host_mount_t()
        cMount.host_path = UnsafePointer(strdup(hostMount.hostPath))
        cMount.guest_path = UnsafePointer(strdup(hostMount.guestPath))
        mounts[index] = cMount
    }
    return CHostMountsResult(ptr: mounts, count: hostMounts.count)
}

private func freeCHostMounts(_ mounts: UnsafeMutablePointer<blink_host_mount_t>?, count: Int) {
    guard let mounts else {
        return
    }

    for index in 0..<count {
        let mount = mounts[index]
        free(UnsafeMutablePointer(mutating: mount.host_path))
        free(UnsafeMutablePointer(mutating: mount.guest_path))
    }
    mounts.deallocate()
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
