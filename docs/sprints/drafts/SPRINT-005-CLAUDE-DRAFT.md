# SPRINT-005: OmniVFS + OmniContainer — Wanix-Inspired Container Runtime

## Overview

Introduce two new SPM modules — `OmniVFS` and `OmniContainer` — plus a C interop target `CBlinkEmulator`, to create a Wanix-inspired lightweight container runtime with in-memory filesystems, Plan 9-style namespace binding, and two-tier binary execution (blink for x86-64 ELF, WasmKit for WASI). The system implements the existing `ExecutionEnvironment` protocol via `ContainerExecutionEnvironment`, enabling sandboxed agent tool execution with zero Docker/VM dependencies. All new code targets Swift 6 strict concurrency. The VFS layer is synchronous and lock-free by design; actor isolation is reserved for container lifecycle and process management only.

## Use Cases

1. **Sandboxed agent tool execution**: An `OmniAgentsSDK` tool invokes `execCommand` on a `ContainerExecutionEnvironment` instead of `LocalExecutionEnvironment`. The command runs inside an Alpine-based container with its own VFS namespace. File writes are captured in a CowFS overlay — the base image is never mutated.

2. **Two-tier binary dispatch**: A container detects binary format by magic bytes. ELF binaries (`\x7fELF`) route to blink for full Linux syscall emulation; WASM binaries (`\0asm`) route to WasmKit for near-native WASI execution. The caller doesn't choose — `BinaryDispatcher` inspects the first 4 bytes and selects the engine.

3. **Composable filesystem layering**: A pipeline node constructs a custom VFS namespace: Alpine rootfs (read-only `TarFS`) → project files (read-only `DiskFS` bind) → scratch overlay (`MemFS` via `CowFS`). On container stop, the overlay can be serialized to disk for persistence or discarded.

4. **Per-process namespace cloning**: When a container forks a child process (blink `clone`/`fork`), the child inherits a cloned namespace. Modifications to the child's namespace (e.g., `bind` a temp directory) don't affect the parent — identical to Wanix's `NS.Clone()` semantics.

5. **Attractor pipeline integration**: An Attractor DOT node sets `execution_env=container` and `image=alpine:minirootfs`. The pipeline engine constructs a `ContainerExecutionEnvironment`, passes it to `CodingAgentBackend`, and all tool invocations run sandboxed.

6. **WASI tool development**: Developers compile Swift/Rust/C tools to `.wasm`, place them in the container's `/usr/local/bin`, and they execute with filesystem access scoped to the container's VFS namespace — no host filesystem leakage.

## Architecture

### SPM Target Graph

```
                    ┌─────────────────────┐
                    │   OmniAIAgent       │
                    │ (ExecutionEnvironment│
                    │  protocol)          │
                    └──────────┬──────────┘
                               │ depends on
                    ┌──────────▼──────────┐
                    │   OmniContainer     │
                    │ (Container, Engines, │
                    │  ContainerExecEnv)  │
                    └──┬──────────────┬───┘
                       │              │
            depends on │              │ depends on
                       │              │
              ┌────────▼───┐   ┌──────▼──────────┐
              │  OmniVFS   │   │ CBlinkEmulator   │
              │ (Namespace, │   │ (C target:       │
              │  MemFS,     │   │  vendored blink  │
              │  CowFS,     │   │  source + shim)  │
              │  UnionFS,   │   └─────────────────┘
              │  DiskFS,    │
              │  TarFS,     │
              │  PipeFS)    │
              └─────────────┘

External dependency:  WasmKit (https://github.com/swiftwasm/WasmKit)
                      ↳ used by OmniContainer/Engines/WasmEngine.swift
```

### VFS Protocol Hierarchy

Translating Wanix's Go interface tower (`fs.FS`, `fs.StatFS`, `fs.ReadDirFS`, `fs.CreateFS`, `fs.ResolveFS`) into a Swift protocol hierarchy. All VFS protocols are synchronous and `Sendable` — no actors, no async. This avoids the reentrancy deadlocks documented in the project memory for actor-based `Session`.

```swift
// ── Core read-only protocols ──────────────────────────────

/// Minimal filesystem: open a file by path (Go fs.FS equivalent).
public protocol VFS: Sendable {
    func open(_ path: String) throws -> VFSFile
}

/// File handle returned by VFS.open().
public protocol VFSFile: Sendable {
    func stat() throws -> VFSFileInfo
    func read(into buffer: inout [UInt8], count: Int) throws -> Int
    func close() throws
}

/// Directory listing capability (Go fs.ReadDirFS).
public protocol VFSReadDirFS: VFS {
    func readDir(_ path: String) throws -> [VFSDirEntry]
}

/// Stat without opening (Go fs.StatFS).
public protocol VFSStatFS: VFS {
    func stat(_ path: String) throws -> VFSFileInfo
}

/// Namespace resolution: given a path, return (filesystem, resolvedPath)
/// (Go fs.ResolveFS — the key abstraction that enables Plan 9 bind semantics).
public protocol VFSResolveFS: VFS {
    func resolveFS(_ path: String) throws -> (any VFS, String)
}

// ── Mutable protocols ─────────────────────────────────────

/// Write support (Go fs.CreateFS).
public protocol VFSMutableFS: VFS {
    func createFile(_ path: String, data: [UInt8]) throws
    func mkdir(_ path: String) throws
    func remove(_ path: String) throws
    func writeFile(_ path: String, data: [UInt8]) throws
}

/// Combined read-write filesystem (convenience conformance).
public protocol VFSFullFS: VFSReadDirFS, VFSStatFS, VFSMutableFS, VFSResolveFS {}
```

### Namespace (Plan 9 Bind Semantics)

```
┌──────────────────────────────────────────────────────────────┐
│                      VFSNamespace                            │
│                                                              │
│  bindings: [String: [BindTarget]]                            │
│                                                              │
│  bind(src: VFS, srcPath, dstPath, mode: .before/.after/.rep) │
│  unbind(src: VFS, srcPath, dstPath)                          │
│  resolveFS(path) -> (VFS, resolvedPath)                      │
│  clone() -> VFSNamespace                                     │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────────┐ │
│  │ "." → [     │  │ "bin" → [   │  │ "tmp" → [            │ │
│  │   CowFS {   │  │   DiskFS {  │  │   MemFS {}           │ │
│  │     base:   │  │     root:   │  │ ]                     │ │
│  │       TarFS │  │     /usr/   │  └──────────────────────┘ │
│  │     overlay:│  │     local/  │                            │
│  │       MemFS │  │     bin     │                            │
│  │   }         │  │   }         │                            │
│  │ ]           │  │ ]           │                            │
│  └─────────────┘  └─────────────┘                            │
└──────────────────────────────────────────────────────────────┘
```

`VFSNamespace` is a `struct` (value type, cloneable) with `internal(set)` bindings. It is **not an actor**. Path resolution is a pure function over the bindings map — no async, no suspension points, no reentrancy risk. Thread safety for concurrent mutation is handled at the container level (the `ContainerActor` serializes namespace mutations).

### Bind Modes (from Wanix)

| Mode | Behavior | Wanix equivalent |
|------|----------|-----------------|
| `.after` | New binding prepended to list (checked first) | `ModeAfter` (default) |
| `.before` | New binding appended to list (checked last) | `ModeBefore` |
| `.replace` | Replaces all existing bindings at path | `ModeReplace` |

### Container Architecture

```
┌────────────────────────────────────────────────────────────┐
│                     ContainerActor                         │
│                                                            │
│  state: .created | .running | .stopped | .destroyed        │
│  namespace: VFSNamespace (actor-isolated mutation)         │
│  env: [String: String]                                     │
│  processes: [ProcessID: ProcessHandle]                     │
│                                                            │
│  create(config:) → ContainerID                             │
│  start() async throws                                      │
│  exec(binary:args:env:) async throws → ExecResult          │
│  stop() async                                              │
│  destroy() async                                           │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              BinaryDispatcher                        │  │
│  │                                                      │  │
│  │  dispatch(data: [UInt8]) → ExecutionEngine           │  │
│  │                                                      │  │
│  │  ┌────────────────┐    ┌─────────────────────┐       │  │
│  │  │  BlinkEngine   │    │    WasmEngine        │      │  │
│  │  │                │    │                      │      │  │
│  │  │ C interop via  │    │ WasmKit runtime      │      │  │
│  │  │ CBlinkEmulator │    │ + VFSWASIBridge      │      │  │
│  │  │                │    │                      │      │  │
│  │  │ ELF magic:     │    │ WASM magic:          │      │  │
│  │  │ 7f 45 4c 46    │    │ 00 61 73 6d          │      │  │
│  │  └────────────────┘    └─────────────────────┘       │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

### Concurrency Architecture

| Boundary | Isolation | Rationale |
|----------|-----------|-----------|
| `VFSNamespace` | `struct` (value type) | Path resolution is a pure function. No async. Cloned on fork. |
| `MemFS`, `CowFS`, `DiskFS`, `TarFS` | `final class: @unchecked Sendable` with `NSLock` | Filesystem state requires interior mutability. Lock-based (not actor) to keep VFS operations synchronous and avoid reentrancy. |
| `UnionFS` | `struct: Sendable` | Immutable composition of child filesystems. |
| `ContainerActor` | `actor` | Serializes container lifecycle (create/start/stop/destroy) and namespace mutations. The single point of actor isolation for the container subsystem. |
| `BlinkEngine` | `final class: Sendable` | Stateless — each `exec` call spawns a blink process. Process management via `Process`/`posix_spawn`. |
| `WasmEngine` | `final class: Sendable` | Stateless — each `exec` instantiates a WasmKit module. `WASIBridgeToHost` lifetime is scoped to the call. |
| `ContainerExecutionEnvironment` | `final class: Sendable` | Holds a reference to `ContainerActor`. All methods `await` actor-isolated calls. |
| `VFSFileInfo`, `VFSDirEntry`, `BindMode` | `struct`/`enum: Sendable` | Value types cross boundaries freely. |
| `ImageManager` | `actor` | Serializes rootfs fetch/cache/extraction. Single instance per process. |

### blink C Interop Strategy

blink is a C11 x86-64 Linux syscall emulator. We vendor its source into a `CBlinkEmulator` SPM C target:

```
Sources/CBlinkEmulator/
├── include/
│   └── blink_shim.h          // Public header: Swift-callable API
├── blink/                     // Vendored blink source (git subtree or copy)
│   ├── blink.h
│   ├── machine.h
│   ├── ...
│   └── (blink .c files)
└── blink_shim.c               // Thin wrapper exposing blink_exec()
```

The shim exposes a single C function:

```c
// blink_shim.h
#ifndef BLINK_SHIM_H
#define BLINK_SHIM_H

#include <stdint.h>
#include <stddef.h>

/// Filesystem callback table — blink calls these instead of real syscalls.
typedef struct {
    int (*open)(const char *path, int flags, int mode, void *ctx);
    ssize_t (*read)(int fd, void *buf, size_t count, void *ctx);
    ssize_t (*write)(int fd, const void *buf, size_t count, void *ctx);
    int (*close)(int fd, void *ctx);
    int (*stat)(const char *path, void *statbuf, void *ctx);
    int (*fstat)(int fd, void *statbuf, void *ctx);
    void *(*mmap)(void *addr, size_t len, int prot, int flags,
                  int fd, int64_t offset, void *ctx);
    int (*munmap)(void *addr, size_t len, void *ctx);
    void *context;  // Opaque pointer passed to all callbacks
} blink_fs_callbacks_t;

/// Execute an ELF binary through blink.
/// Returns the process exit code.
/// `elf_data`/`elf_size`: the ELF binary bytes (read from VFS).
/// `argv`/`argc`: argument vector.
/// `envp`/`envc`: environment vector.
/// `fs`: filesystem callback table (NULL = use host filesystem).
/// `stdout_buf`/`stderr_buf`: output capture buffers.
/// `stdout_cap`/`stderr_cap`: buffer capacities.
/// `stdout_len`/`stderr_len`: actual bytes written (out params).
int blink_exec(
    const uint8_t *elf_data, size_t elf_size,
    const char **argv, int argc,
    const char **envp, int envc,
    const blink_fs_callbacks_t *fs,
    uint8_t *stdout_buf, size_t stdout_cap, size_t *stdout_len,
    uint8_t *stderr_buf, size_t stderr_cap, size_t *stderr_len
);

#endif
```

The Swift side (`BlinkEngine.swift`) populates `blink_fs_callbacks_t` with closures that delegate to the container's `VFSNamespace`:

```swift
import CBlinkEmulator

final class BlinkEngine: Sendable {
    func exec(
        elfData: [UInt8],
        args: [String],
        env: [String: String],
        namespace: VFSNamespace,
        timeout: Duration
    ) async throws -> ExecResult {
        // 1. Create a VFSBridgeContext holding the namespace + fd table
        // 2. Populate blink_fs_callbacks_t with C function pointers
        //    that cast context back to VFSBridgeContext and call VFS methods
        // 3. Call blink_exec() on a detached thread (not cooperative pool)
        // 4. Apply timeout via DispatchWorkItem cancellation
        // 5. Capture stdout/stderr, return ExecResult
    }
}
```

**Key design choice**: blink's filesystem callbacks are synchronous C function pointers. Our VFS is also synchronous. This means no async bridging is needed at the blink↔VFS boundary — the C callbacks call Swift VFS methods directly via `@convention(c)` thunks. This is why the VFS must remain synchronous.

### WasmKit WASI Filesystem Bridge

WasmKit provides `WASIBridgeToHost` for WASI Preview 1 filesystem access. We create a custom `VFSWASIBridge` that substitutes our VFS namespace as the WASI root:

```swift
import WasmKit
import WASI

/// Maps WASI filesystem operations to an OmniVFS namespace.
final class VFSWASIBridge: Sendable {
    private let namespace: VFSNamespace
    private let fdTable: LockedFDTable  // Maps WASI fd numbers to VFSFile handles

    init(namespace: VFSNamespace) {
        self.namespace = namespace
        self.fdTable = LockedFDTable()
        // Pre-open fd 0 (stdin), 1 (stdout), 2 (stderr) as PipeFS endpoints
        // Pre-open fd 3 as "/" (the VFS root) per WASI convention
    }

    /// Create a WASI instance configured to use this VFS bridge.
    func makeWASIInstance() throws -> WASIBridgeToHost {
        // WasmKit's WASIBridgeToHost accepts a `WASIFileSystem` protocol
        // or directory preopens. We provide:
        //   - preopens: ["/": VFSDirectoryHandle(namespace, ".")]
        //   - stdin/stdout/stderr: PipeFS endpoints from the container
        var config = WASIBridgeToHost.Configuration()
        config.preopens = [
            WASIPreopen(
                guestPath: "/",
                hostPath: ".",  // resolved through our VFS, not host
                fileSystem: VFSFileSystemAdapter(namespace: namespace)
            )
        ]
        return try WASIBridgeToHost(configuration: config)
    }
}

/// Adapts OmniVFS to WasmKit's expected filesystem interface.
/// Implements whatever protocol WasmKit exposes for custom filesystem backends.
struct VFSFileSystemAdapter: /* WasmKit's filesystem protocol */ Sendable {
    let namespace: VFSNamespace

    func open(_ path: String, flags: Int32) throws -> /* WasmKit fd type */ {
        let (fs, resolvedPath) = try namespace.resolveFS(path)
        return try fs.open(resolvedPath)
        // ... wrap in WasmKit's expected handle type
    }

    func stat(_ path: String) throws -> /* WasmKit stat type */ {
        let (fs, resolvedPath) = try namespace.resolveFS(path)
        guard let statFS = fs as? VFSStatFS else {
            throw VFSError.notSupported("stat")
        }
        return try statFS.stat(resolvedPath)
        // ... convert VFSFileInfo to WasmKit's stat structure
    }

    // ... readDir, write, mkdir, remove, etc.
}
```

**Key insight**: WasmKit's `WASIBridgeToHost` already abstracts filesystem access. The challenge is conforming our `VFSNamespace` to whatever filesystem protocol WasmKit exposes. If WasmKit does not expose a pluggable filesystem protocol (it may only support host path preopens), we have a fallback: materialize the VFS namespace to a temp directory on host, pass that path to WasmKit, and clean up after. This is the `BLINK_OVERLAYS`-equivalent strategy — functional but less elegant. Phase 3 implementation will prototype both approaches.

### Alpine Rootfs Management

```
┌──────────────────────────────────────────────────────────┐
│                    ImageManager (actor)                   │
│                                                          │
│  cache: [ImageRef: CachedImage]                          │
│  cacheDir: URL  (~/.omnikit/images/)                     │
│                                                          │
│  resolve(ref:) async throws → any VFS                    │
│    1. Check in-memory cache → return TarFS               │
│    2. Check disk cache → load tar, return TarFS          │
│    3. Download minirootfs tar from mirror                 │
│    4. Verify SHA256                                       │
│    5. Write to disk cache                                 │
│    6. Return TarFS                                        │
│                                                          │
│  Built-in refs:                                          │
│    "alpine:minirootfs" → alpine-minirootfs-3.20-x86_64  │
│    "alpine:latest"     → same                            │
└──────────────────────────────────────────────────────────┘
```

The rootfs is fetched on first use (not bundled in SPM resources). `TarFS` is a read-only in-memory filesystem backed by a parsed tar archive — same pattern as Wanix's `tarfs.From(tar.NewReader(buf))`. This keeps the base image immutable and shareable across containers.

## Implementation

### Phase 1: OmniVFS — Core VFS Protocols and Filesystems

Create `Sources/OmniVFS/` as a new zero-dependency SPM target with Swift 6 strict concurrency.

**1a. `Types.swift`** — Value types: `VFSFileInfo` (name, size, mode, modTime, isDir), `VFSDirEntry` (name, isDir, size), `VFSError` enum (notFound, permissionDenied, isDirectory, notDirectory, alreadyExists, notSupported, pathTraversal, invalidPath). `BindMode` enum (.after, .before, .replace). `VFSFileMode` as `UInt16` with Plan 9-style permission bits.

**1b. `Protocols.swift`** — `VFS`, `VFSFile`, `VFSReadDirFS`, `VFSStatFS`, `VFSResolveFS`, `VFSMutableFS`, `VFSFullFS` protocols as described in the Architecture section. Also `VFSSeekableFile` (adds seek) and `VFSWritableFile` (adds write to file handle) for engines that need random access.

**1c. `MemFS.swift`** — In-memory mutable filesystem. Internal tree of `MemNode` (either `.file(Data)` or `.directory([String: MemNode])`). Conforms to `VFSFullFS`. Thread-safe via `NSLock` on the root node. `final class: @unchecked Sendable`. Path validation rejects `..` components and enforces Wanix's `fs.ValidPath` rules (no leading `/`, no trailing `/`, `.` is root).

**1d. `DiskFS.swift`** — Read-write filesystem backed by a host directory. Conforms to `VFSFullFS`. Maps VFS paths to host paths relative to a root directory. Path traversal guard: resolved host path must have the root as prefix. `final class: Sendable` (all state is in the host filesystem, operations are thread-safe via OS).

**1e. `TarFS.swift`** — Read-only filesystem parsed from a tar archive byte buffer. Parses the tar on init, builds an in-memory directory tree. Conforms to `VFSReadDirFS`, `VFSStatFS`. File data is sliced from the original buffer (zero-copy for large archives). `final class: Sendable` (immutable after init).

**1f. `CowFS.swift`** — Copy-on-Write filesystem with a read-only `base: any VFS` and a mutable `overlay: any VFSMutableFS`. Reads check overlay first, fall through to base. Writes always go to overlay. Deletes recorded as whiteout entries (`.wh.<name>` sentinel files in overlay, matching Wanix/Docker convention). Conforms to `VFSFullFS`. `final class: @unchecked Sendable` with lock on the whiteout set.

**1g. `UnionFS.swift`** — Merges multiple read-only filesystems for directory listing. `struct: Sendable` holding `[any VFS]`. `readDir` concatenates and deduplicates entries from all children. `open` tries children in order, returns first hit. Conforms to `VFSReadDirFS`. This is the Wanix `fskit.UnionFS` equivalent.

**1h. `PipeFS.swift`** — In-memory pipe pair for stdin/stdout/stderr bridging. `PipeFS.create() -> (reader: VFSFile, writer: VFSFile)`. Backed by a shared `LockedRingBuffer`. This maps to Wanix's `pipe.New()` used in task service for fd0/fd1/fd2.

**1i. `Namespace.swift`** — `VFSNamespace` struct implementing Plan 9 bind/resolve. `bindings: [String: [BindTarget]]` where `BindTarget` is `(fs: any VFS, path: String)`. `bind()`, `unbind()`, `resolveFS()`, `clone()` methods. `resolveFS()` implements the Wanix resolution algorithm: check direct bindings → check subpath bindings → try `VFSResolveFS` on each candidate → stat fallback → create-op directory check. Synthesized parent directories for bindings that imply intermediate paths. Conforms to `VFS`, `VFSReadDirFS`, `VFSStatFS`, `VFSResolveFS`.

**1j. `PathUtils.swift`** — `validPath(_:)` (Wanix's `fs.ValidPath`), `cleanPath(_:)`, `joinPath(_:_:)`, `matchPaths(_:_:)` (find binding paths that are prefixes of a target path, sorted longest-first). Pure functions, no state.

**Guard check:**
```bash
swift build --target OmniVFS 2>&1 | grep -c 'error:'
# expect: 0
```

### Phase 2: OmniContainer — Container Lifecycle and Image Management

Create `Sources/OmniContainer/` depending on `OmniVFS`.

**2a. `ContainerConfig.swift`** — `ContainerConfig` struct: image ref (String), env vars ([String: String]), working directory (String), resource limits (memory MB, timeout seconds), mount binds ([(hostPath: String, guestPath: String)]). All `Sendable`, `Codable`.

**2b. `ContainerState.swift`** — `ContainerState` enum: `.created`, `.running`, `.stopped(exitCode: Int32)`, `.destroyed`. `ContainerID` as a `struct` wrapping UUID.

**2c. `ContainerActor.swift`** — The core `actor`. Holds `VFSNamespace`, `ContainerConfig`, `ContainerState`, process table (`[ProcessID: Task<ExecResult, Error>]`). Methods:

```swift
public actor ContainerActor {
    private var namespace: VFSNamespace
    private var state: ContainerState = .created
    private let config: ContainerConfig
    private let dispatcher: BinaryDispatcher
    private var processes: [UUID: Task<ExecResult, Error>] = [:]

    public init(config: ContainerConfig, rootFS: any VFS) {
        self.config = config
        self.namespace = VFSNamespace()
        self.dispatcher = BinaryDispatcher()
        // Bind rootFS at "." (root)
        // Bind MemFS at "tmp"
        // Bind PipeFS for /dev/stdin, /dev/stdout, /dev/stderr
    }

    public func start() async throws { ... }

    public func exec(
        command: String, args: [String],
        env: [String: String]?, timeout: Duration
    ) async throws -> ExecResult {
        // 1. Resolve binary path in namespace (check /usr/bin, /bin, etc.)
        // 2. Read binary bytes from VFS
        // 3. Detect format via BinaryDispatcher
        // 4. Execute via appropriate engine
        // 5. Return ExecResult with stdout/stderr/exitCode
    }

    public func stop() async { ... }
    public func destroy() async { ... }

    // VFS operations (delegated from ContainerExecutionEnvironment)
    public func readFile(path: String) throws -> String { ... }
    public func writeFile(path: String, content: String) throws { ... }
    public func listDirectory(path: String) throws -> [DirEntry] { ... }
    public func fileExists(path: String) -> Bool { ... }
}
```

**2d. `BinaryDispatcher.swift`** — `struct: Sendable`. Inspects first 4 bytes: `[0x7f, 0x45, 0x4c, 0x46]` → `.elf`, `[0x00, 0x61, 0x73, 0x6d]` → `.wasm`, else → `.script` (passed to `/bin/sh` inside the container). Returns an `enum BinaryFormat { case elf, wasm, script }`.

**2e. `ImageManager.swift`** — `actor`. Manages rootfs image fetch, cache, and extraction:

```swift
public actor ImageManager {
    public static let shared = ImageManager()

    private var cache: [String: any VFS] = [:]
    private let cacheDir: URL  // ~/.omnikit/images/

    /// Resolve an image reference to a read-only VFS.
    public func resolve(_ ref: String) async throws -> any VFS {
        if let cached = cache[ref] { return cached }

        let tarData = try await fetchOrLoadFromDisk(ref)
        let tarFS = TarFS(data: tarData)
        cache[ref] = tarFS
        return tarFS
    }

    private func fetchOrLoadFromDisk(_ ref: String) async throws -> Data {
        // 1. Check cacheDir for existing tar
        // 2. If not found, download from Alpine mirror
        // 3. Verify SHA256 checksum
        // 4. Write to cacheDir
        // 5. Return tar data
    }
}
```

**2f. `ContainerExecutionEnvironment.swift`** — Placed in `Sources/OmniContainer/` (not OmniAIAgent, to avoid circular deps). Conforms to `ExecutionEnvironment`:

```swift
public final class ContainerExecutionEnvironment: ExecutionEnvironment, @unchecked Sendable {
    private let container: ContainerActor
    private let workingDir: String

    public init(container: ContainerActor, workingDir: String = "/") {
        self.container = container
        self.workingDir = workingDir
    }

    public func readFile(path: String, offset: Int?, limit: Int?) async throws -> String {
        try await container.readFile(path: resolvePath(path))
    }

    public func writeFile(path: String, content: String) async throws {
        try await container.writeFile(path: resolvePath(path), content: content)
    }

    public func execCommand(
        command: String, timeoutMs: Int,
        workingDir: String?, envVars: [String: String]?
    ) async throws -> ExecResult {
        // Parse command string into binary + args
        // Delegate to container.exec()
    }

    public func grep(pattern: String, path: String, options: GrepOptions) async throws -> String {
        // Implement in-VFS grep using Swift regex over readDir + readFile
        // No external process needed
    }

    public func glob(pattern: String, path: String) async throws -> [String] {
        // Implement in-VFS glob using fnmatch-style pattern matching
        // Walk directory tree in namespace
    }

    // ... remaining ExecutionEnvironment methods
}
```

**Guard check:**
```bash
swift build --target OmniContainer 2>&1 | grep -c 'error:'
# expect: 0
```

### Phase 3: WasmKit Engine

Integrate WasmKit for WASI binary execution.

**3a. Update `Package.swift`** — Add WasmKit dependency. Note: WasmKit requires Swift 6.1+. If our 6.0 tools-version is incompatible, gate the WasmKit integration behind `#if compiler(>=6.1)` and provide a stub that throws `.notSupported("WasmKit requires Swift 6.1+")`.

```swift
// In Package.swift dependencies:
.package(url: "https://github.com/swiftwasm/WasmKit.git", from: "0.3.0"),

// OmniContainer target:
.target(
    name: "OmniContainer",
    dependencies: [
        "OmniVFS",
        .product(name: "WasmKit", package: "WasmKit"),
        .product(name: "WASI", package: "WasmKit"),
    ],
    swiftSettings: swift6CommonSwiftSettings
),
```

**3b. `Sources/OmniContainer/Engines/WasmEngine.swift`** — WASI execution engine:

```swift
import WasmKit
import WASI

final class WasmEngine: Sendable {
    func exec(
        wasmData: [UInt8],
        args: [String],
        env: [String: String],
        namespace: VFSNamespace,
        stdin: VFSFile,
        stdout: VFSFile,
        stderr: VFSFile,
        timeout: Duration
    ) async throws -> ExecResult {
        // 1. Parse WASM module: let module = try parseWasm(bytes: wasmData)
        // 2. Create VFSWASIBridge with namespace
        // 3. Configure WASI with preopens, args, env
        // 4. Instantiate module with WASI imports
        // 5. Call _start (or _initialize + main)
        // 6. Capture exit code from WASI proc_exit trap
        // 7. Read stdout/stderr from pipe endpoints
        // 8. Return ExecResult
    }
}
```

**3c. `Sources/OmniContainer/Engines/VFSWASIBridge.swift`** — Adapts `VFSNamespace` to WasmKit's WASI filesystem interface. Implements fd table management, path resolution through VFS, and WASI-specific stat structure conversion.

**Guard check:**
```bash
swift build --target OmniContainer 2>&1 | grep -c 'error:'
# expect: 0
```

### Phase 4: blink Engine (CBlinkEmulator C Target)

**4a. `Sources/CBlinkEmulator/`** — Vendored blink source with shim header. The C target in Package.swift:

```swift
.target(
    name: "CBlinkEmulator",
    path: "Sources/CBlinkEmulator",
    exclude: ["blink/test", "blink/third_party/qemu"],  // Exclude test/unused dirs
    sources: ["blink_shim.c", "blink/"],
    publicHeadersPath: "include",
    cSettings: [
        .define("HAVE_JIT", .when(platforms: [.macOS, .linux])),
        .define("BLINK_DISABLE_NETWORKING"),  // No network syscalls
        .unsafeFlags(["-w"]),  // Suppress warnings in vendored C code
    ]
),
```

**4b. `Sources/OmniContainer/Engines/BlinkEngine.swift`** — Swift wrapper:

```swift
import CBlinkEmulator

final class BlinkEngine: Sendable {
    func exec(
        elfData: [UInt8],
        args: [String],
        env: [String: String],
        namespace: VFSNamespace,
        timeout: Duration
    ) async throws -> ExecResult {
        // Must run on a non-cooperative thread — blink_exec() blocks.
        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "blink.exec.\(UUID())")
            queue.async {
                // 1. Create VFSBridgeContext with namespace + fd table
                let bridgeCtx = VFSBridgeContext(namespace: namespace)

                // 2. Build C callbacks struct
                var callbacks = blink_fs_callbacks_t()
                callbacks.context = Unmanaged.passUnretained(bridgeCtx)
                    .toOpaque()
                callbacks.open = { path, flags, mode, ctx in
                    let bridge = Unmanaged<VFSBridgeContext>
                        .fromOpaque(ctx!).takeUnretainedValue()
                    return bridge.handleOpen(path!, flags: flags, mode: mode)
                }
                callbacks.read = { fd, buf, count, ctx in
                    let bridge = Unmanaged<VFSBridgeContext>
                        .fromOpaque(ctx!).takeUnretainedValue()
                    return bridge.handleRead(fd: fd, buf: buf!, count: count)
                }
                // ... write, close, stat, fstat, mmap, munmap

                // 3. Prepare argv/envp as C strings
                let cArgs = args.map { strdup($0) }
                let cEnv = env.map { strdup("\($0.key)=\($0.value)") }
                defer {
                    cArgs.forEach { free($0) }
                    cEnv.forEach { free($0) }
                }

                // 4. Allocate output buffers
                let stdoutBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_048_576)
                let stderrBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_048_576)
                var stdoutLen: Int = 0
                var stderrLen: Int = 0
                defer {
                    stdoutBuf.deallocate()
                    stderrBuf.deallocate()
                }

                // 5. Execute
                let exitCode = blink_exec(
                    elfData, elfData.count,
                    /* argv */, Int32(args.count),
                    /* envp */, Int32(env.count),
                    &callbacks,
                    stdoutBuf, 1_048_576, &stdoutLen,
                    stderrBuf, 1_048_576, &stderrLen
                )

                let result = ExecResult(
                    stdout: String(bytes: UnsafeBufferPointer(
                        start: stdoutBuf, count: stdoutLen), encoding: .utf8) ?? "",
                    stderr: String(bytes: UnsafeBufferPointer(
                        start: stderrBuf, count: stderrLen), encoding: .utf8) ?? "",
                    exitCode: exitCode,
                    timedOut: false,
                    durationMs: 0  // TODO: measure
                )
                continuation.resume(returning: result)
            }
        }
    }
}
```

**4c. `Sources/OmniContainer/Engines/VFSBridgeContext.swift`** — Manages the file descriptor table for C callbacks. Maps integer fds to `VFSFile` handles. Thread-safe (blink may call from multiple threads if it emulates `clone`).

```swift
final class VFSBridgeContext: @unchecked Sendable {
    private let namespace: VFSNamespace
    private let lock = NSLock()
    private var fdTable: [Int32: any VFSFile] = [:]
    private var nextFD: Int32 = 3  // 0,1,2 reserved for stdio

    init(namespace: VFSNamespace) {
        self.namespace = namespace
    }

    func handleOpen(_ path: UnsafePointer<CChar>, flags: Int32, mode: Int32) -> Int32 {
        let swiftPath = String(cString: path)
        let cleanedPath = PathUtils.cleanPath(swiftPath)
        do {
            let (fs, resolved) = try namespace.resolveFS(cleanedPath)
            let file = try fs.open(resolved)
            lock.lock()
            let fd = nextFD
            nextFD += 1
            fdTable[fd] = file
            lock.unlock()
            return fd
        } catch {
            return -1  // errno ENOENT
        }
    }

    func handleRead(fd: Int32, buf: UnsafeMutableRawPointer, count: Int) -> Int {
        lock.lock()
        guard let file = fdTable[fd] else {
            lock.unlock()
            return -1  // EBADF
        }
        lock.unlock()
        var buffer = [UInt8](repeating: 0, count: count)
        do {
            let n = try file.read(into: &buffer, count: count)
            buf.copyMemory(from: buffer, byteCount: n)
            return n
        } catch {
            return -1
        }
    }

    // ... handleWrite, handleClose, handleStat, handleFstat
}
```

**Guard check:**
```bash
swift build --target CBlinkEmulator 2>&1 | grep -c 'error:'
# expect: 0
swift build --target OmniContainer 2>&1 | grep -c 'error:'
# expect: 0
```

### Phase 5: Integration + Tests

**5a. `Tests/OmniVFSTests/`:**
- `MemFSTests.swift` — Create/read/write/delete files and directories, path validation, concurrent access.
- `CowFSTests.swift` — Read-through to base, write captures in overlay, whiteout on delete, directory merge.
- `UnionFSTests.swift` — Merged directory listings, deduplication, priority ordering.
- `TarFSTests.swift` — Parse a test tar archive, read files, stat, readDir.
- `NamespaceTests.swift` — bind/unbind, BindMode semantics, resolveFS with nested bindings, clone independence, synthesized parent directories.
- `PipeFSTests.swift` — Write-then-read, blocking behavior, close propagation.
- `PathUtilsTests.swift` — validPath, cleanPath edge cases, traversal rejection.

**5b. `Tests/OmniContainerTests/`:**
- `BinaryDispatcherTests.swift` — ELF magic, WASM magic, script fallback detection.
- `ContainerLifecycleTests.swift` — create→start→exec→stop→destroy state machine, invalid transitions rejected.
- `ContainerExecEnvTests.swift` — `ContainerExecutionEnvironment` conforms to `ExecutionEnvironment`, readFile/writeFile/fileExists/listDirectory work through VFS.
- `ImageManagerTests.swift` — Cache hit/miss, disk cache round-trip.

**5c. `Tests/OmniContainerTests/Integration/`:**
- `WasmIntegrationTests.swift` — Compile a trivial WASI hello-world to .wasm (fixture checked into repo), execute through `WasmEngine`, verify stdout. Gated behind `#if compiler(>=6.1)`.
- `BlinkIntegrationTests.swift` — Execute a static x86-64 ELF binary (busybox `echo hello`, fixture checked in or downloaded), verify stdout.
- `ContainerEndToEndTests.swift` — Full vertical: ImageManager resolves Alpine rootfs → Container creates with CowFS → exec `echo hello` → verify output → exec creates file → verify file persists in overlay → stop → verify overlay state.

**Guard check:**
```bash
swift test --filter OmniVFSTests 2>&1 | tail -5
swift test --filter OmniContainerTests 2>&1 | tail -5
# All green
```

## Files Summary

| File | Change |
|------|--------|
| `Package.swift` | Add `OmniVFS`, `OmniContainer`, `CBlinkEmulator` targets + products, test targets. Add WasmKit dependency. Add `OmniContainer` to `OmniAIAgent` dependencies. |
| `Sources/OmniVFS/Types.swift` | Create — VFSFileInfo, VFSDirEntry, VFSError, BindMode, VFSFileMode |
| `Sources/OmniVFS/Protocols.swift` | Create — VFS, VFSFile, VFSReadDirFS, VFSStatFS, VFSResolveFS, VFSMutableFS, VFSFullFS |
| `Sources/OmniVFS/MemFS.swift` | Create — In-memory mutable filesystem |
| `Sources/OmniVFS/DiskFS.swift` | Create — Host-directory-backed filesystem |
| `Sources/OmniVFS/TarFS.swift` | Create — Read-only tar-archive filesystem |
| `Sources/OmniVFS/CowFS.swift` | Create — Copy-on-Write overlay filesystem |
| `Sources/OmniVFS/UnionFS.swift` | Create — Merged read-only filesystem |
| `Sources/OmniVFS/PipeFS.swift` | Create — In-memory pipe pair for stdio |
| `Sources/OmniVFS/Namespace.swift` | Create — Plan 9 bind/resolve namespace |
| `Sources/OmniVFS/PathUtils.swift` | Create — Path validation and manipulation |
| `Sources/CBlinkEmulator/include/blink_shim.h` | Create — Public C header for blink interop |
| `Sources/CBlinkEmulator/blink_shim.c` | Create — C shim wrapping blink entry points |
| `Sources/CBlinkEmulator/blink/` | Create — Vendored blink source tree |
| `Sources/OmniContainer/ContainerConfig.swift` | Create — Container configuration types |
| `Sources/OmniContainer/ContainerState.swift` | Create — Container state machine types |
| `Sources/OmniContainer/ContainerActor.swift` | Create — Core container actor |
| `Sources/OmniContainer/BinaryDispatcher.swift` | Create — Magic-byte binary format detection |
| `Sources/OmniContainer/ImageManager.swift` | Create — Rootfs fetch/cache/extraction actor |
| `Sources/OmniContainer/ContainerExecutionEnvironment.swift` | Create — ExecutionEnvironment conformance |
| `Sources/OmniContainer/Engines/WasmEngine.swift` | Create — WasmKit WASI execution |
| `Sources/OmniContainer/Engines/VFSWASIBridge.swift` | Create — VFS↔WASI filesystem adapter |
| `Sources/OmniContainer/Engines/BlinkEngine.swift` | Create — blink ELF execution |
| `Sources/OmniContainer/Engines/VFSBridgeContext.swift` | Create — C callback fd table for blink |
| `Tests/OmniVFSTests/MemFSTests.swift` | Create |
| `Tests/OmniVFSTests/CowFSTests.swift` | Create |
| `Tests/OmniVFSTests/UnionFSTests.swift` | Create |
| `Tests/OmniVFSTests/TarFSTests.swift` | Create |
| `Tests/OmniVFSTests/NamespaceTests.swift` | Create |
| `Tests/OmniVFSTests/PipeFSTests.swift` | Create |
| `Tests/OmniVFSTests/PathUtilsTests.swift` | Create |
| `Tests/OmniContainerTests/BinaryDispatcherTests.swift` | Create |
| `Tests/OmniContainerTests/ContainerLifecycleTests.swift` | Create |
| `Tests/OmniContainerTests/ContainerExecEnvTests.swift` | Create |
| `Tests/OmniContainerTests/ImageManagerTests.swift` | Create |
| `Tests/OmniContainerTests/Integration/WasmIntegrationTests.swift` | Create |
| `Tests/OmniContainerTests/Integration/BlinkIntegrationTests.swift` | Create |
| `Tests/OmniContainerTests/Integration/ContainerEndToEndTests.swift` | Create |

## Definition of Done

1. `swift build` passes with zero errors for all new targets (`OmniVFS`, `CBlinkEmulator`, `OmniContainer`) and all pre-existing targets on macOS arm64
2. All new Swift targets compile under Swift 6 strict concurrency (`-warn-concurrency`, `-strict-concurrency=complete`, `-enable-actor-data-race-checks` in debug) with zero warnings
3. No `nonisolated(unsafe)` on any type. `@unchecked Sendable` permitted only on `MemFS`, `CowFS`, `VFSBridgeContext` (lock-protected interior mutability) with documented invariants
4. `swift test --filter OmniVFSTests` passes: MemFS CRUD, CowFS read-through + write overlay + whiteout, UnionFS merge + dedup, TarFS parse + read, Namespace bind/unbind/resolve/clone, PipeFS read-write, PathUtils validation
5. `swift test --filter OmniContainerTests` passes: BinaryDispatcher magic detection, Container lifecycle state machine, ContainerExecutionEnvironment readFile/writeFile/listDirectory via VFS
6. Integration test: WasmEngine executes a WASI hello-world binary through VFS, captures `hello\n` on stdout
7. Integration test: BlinkEngine executes a static x86-64 ELF binary through VFS, captures expected stdout
8. Integration test: Full container lifecycle — create with Alpine rootfs → CowFS overlay → exec command → verify output → verify file persistence in overlay → stop → destroy
9. All pre-existing tests pass (`swift test` overall green, no regressions)
10. `ContainerExecutionEnvironment` is a drop-in replacement for `LocalExecutionEnvironment` — passes the same interface contract (all `ExecutionEnvironment` protocol methods implemented)
11. Linux x86-64 cross-compilation: `swift build --target OmniVFS` and `swift build --target OmniContainer` pass on Linux (CI verification)

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| **blink vendoring complexity**: blink's source tree is large (~30K LOC C) with platform-specific JIT code and build system assumptions | High | Start with a minimal blink subset: disable JIT (`-DBLINK_DISABLE_JIT`), disable networking, exclude test/benchmark directories. Only compile the interpreter core + syscall handlers. If vendoring proves intractable, fall back to building blink as a standalone binary and shelling out to it (like `LocalExecutionEnvironment` does with `Process`), using `BLINK_OVERLAYS` for filesystem redirection to a DiskFS-materialized temp dir. |
| **blink filesystem callback interception**: blink may not support clean callback-based filesystem interception — its syscall emulation may directly call host `open`/`read`/`write` | High | Two fallback strategies: (1) Compile blink with `BLINK_OVERLAYS` support and materialize the VFS namespace to a temp directory on host before each exec, cleaning up after. (2) Patch blink's `sys_open`/`sys_read` etc. to call our shim functions via C preprocessor macros (`#define SYS_OPEN blink_shim_open`). Strategy (1) is the safest first approach. |
| **WasmKit Swift version incompatibility**: WasmKit requires Swift 6.1+, project uses 6.0 tools-version | Medium | Gate WasmKit integration behind `#if compiler(>=6.1)`. Provide a `StubWasmEngine` that throws `.notSupported` when compiled with 6.0. This unblocks the VFS and blink work without waiting for toolchain upgrade. Track WasmKit compatibility in a `COMPATIBILITY.md` file. |
| **VFS reentrancy in namespace resolution**: Wanix's `ResolveFS` can call back into the namespace (self-referential resolution). In Go this is handled by goroutines; in Swift a naive actor implementation would deadlock. | Medium | VFS is synchronous structs, not actors. `resolveFS()` is a pure function call chain — no suspension points, no actor boundaries to cross. The `ContainerActor` owns the namespace but VFS operations read a snapshot (the namespace is a value type cloned on access if needed). Cycle detection: limit resolution depth to 64 hops, error on exceeded. |
| **Scope exceeds single sprint**: OmniVFS + OmniContainer + two engines + integration tests is substantial (~3-4K new LOC) | Medium | Strict phase gating. Phase 1 (VFS) and Phase 2 (Container with mock engine) are independently shippable. Phase 3 (WasmKit) and Phase 4 (blink) can be deferred to Sprint 006 if needed. Minimum viable delivery: Phases 1-2 with `ContainerExecutionEnvironment` working for in-VFS operations (no binary execution). |
| **Alpine rootfs download in tests**: Integration tests that download Alpine minirootfs (~5MB) are slow and network-dependent | Low | Bundle a tiny test rootfs fixture (3-4 files: `/bin/sh` stub, `/etc/hostname`, `/tmp/`) for unit tests. Gate Alpine download tests behind an `OMNIKIT_INTEGRATION_TESTS` env var. `ImageManager` tests use a mock HTTP server or local fixture. |
| **TarFS memory consumption**: Large tar archives (hundreds of MB) fully parsed into memory | Low | For Sprint 005, only Alpine minirootfs (~5MB) is targeted. Add lazy parsing (mmap + seek-based) as a follow-up optimization if larger images are needed. |

## Security Considerations

- **Path traversal prevention**: Every VFS filesystem validates that resolved paths cannot escape their mount root. `PathUtils.validPath()` rejects any path containing `..` components. `DiskFS` additionally verifies that the resolved host path has the root directory as a prefix after symlink resolution.
- **No host filesystem leakage**: `ContainerExecutionEnvironment` never delegates to `FileManager` or host `Process`. All file operations route through the VFS namespace. A container cannot read `/etc/passwd` on the host unless the host explicitly binds it into the namespace.
- **blink syscall restriction**: Build blink with `BLINK_DISABLE_NETWORKING` to prevent network syscalls (socket, connect, bind, listen). This contains the emulated process to filesystem operations only. `mmap` is intercepted to prevent mapping host memory regions — only VFS-backed mappings are permitted.
- **WasmKit sandboxing**: WASI preopens are scoped to the container's VFS namespace root. No ambient authority — the WASM module cannot access filesystem paths outside its preopens. `WASIBridgeToHost` does not grant network, clock, or random capabilities beyond the minimum WASI Preview 1 requirements.
- **Resource limits**: `ContainerActor` enforces memory limits (configurable, default 256MB) by tracking overlay `MemFS` allocation. Execution timeout is enforced per-command via `DispatchWorkItem` cancellation for blink and `Task` cancellation for WasmKit.
- **No shell injection**: `ContainerExecutionEnvironment.execCommand` does not invoke a host shell. The command string is parsed into a binary path + arguments using basic tokenization (split on spaces, respecting quotes). The binary is resolved in the VFS namespace and executed directly through the engine.
- **Sensitive environment filtering**: `ContainerActor` does not inherit the host environment by default. Only explicitly passed `env` variables are available. This prevents API keys and secrets from leaking into containerized processes.

## Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| Swift 6.0 toolchain | Already configured | `swift-tools-version: 6.0`, `swiftLanguageModes: [.v6]` |
| Strict concurrency flags | Already configured | `-warn-concurrency`, `-strict-concurrency=complete` on all targets |
| `swift-testing` | Existing dependency | `@Test`, `#expect` for all new test targets |
| `Foundation` | System framework | `Data`, `FileManager` (for `DiskFS` and `ImageManager`), `NSLock`, `UUID` |
| **WasmKit** | **New** | `https://github.com/swiftwasm/WasmKit`, ~0.3.0. WASI Preview 1 runtime. Requires Swift 6.1+ — gated behind compiler check. |
| **blink** (vendored) | **New** | `https://github.com/jart/blink`, vendored C source in `CBlinkEmulator` target. No external package dependency — compiled as part of SPM build. |
| `OmniAIAgent` | Existing target | Provides `ExecutionEnvironment` protocol. New `OmniContainer` depends on it for the protocol; alternatively, extract `ExecutionEnvironment` to `OmniVFS` to avoid the reverse dependency. |
| No new Swift package dependencies besides WasmKit | — | blink is vendored C, not a Swift package |

### Dependency Direction Note

`OmniAIAgent` currently owns the `ExecutionEnvironment` protocol. `OmniContainer` must conform to it but should not pull in all of `OmniAIAgent`'s dependencies (OmniAICore, OmniMCP). Two options:

1. **Extract `ExecutionEnvironment` to `OmniVFS`** — Move `ExecutionEnvironment.swift`, `ExecResult`, `DirEntry`, `GrepOptions`, `ToolError` from `OmniAIAgent` to `OmniVFS`. `OmniAIAgent` depends on `OmniVFS` for the protocol. `OmniContainer` depends on `OmniVFS`. Clean layering.

2. **Keep protocol in `OmniAIAgent`, add OmniContainer dep** — `OmniContainer` depends on `OmniAIAgent`. This creates a heavier dependency chain (`OmniContainer` → `OmniAIAgent` → `OmniAICore` → `OmniHTTP`). Not ideal.

**Recommendation**: Option 1. The protocol and its associated types are pure value types with no dependencies beyond Foundation. They belong in the lowest-level module.

```
OmniVFS  ←  OmniContainer  ←  OmniAIAgent
  │                                │
  └── ExecutionEnvironment ────────┘
      (protocol lives here)
```

## Open Questions

1. **blink embedding strategy**: Should we vendor blink source (full control, hermetic SPM builds, ~30K LOC C to maintain) or build it externally and shell out (simpler integration, loses VFS callback interception)? The draft assumes vendoring with the fallback strategy of `BLINK_OVERLAYS` + temp directory if callback interception proves impractical. **Decision needed before Phase 4 begins.**

2. **WasmKit filesystem pluggability**: Does WasmKit's `WASIBridgeToHost` expose a protocol for custom filesystem backends, or only accept host directory paths for preopens? If the latter, we need the materialization fallback (write VFS to temp dir, point WasmKit there). **Needs prototyping in Phase 3.**

3. **ExecutionEnvironment extraction**: Should we move `ExecutionEnvironment` and its associated types to `OmniVFS` (clean layering, small refactor) or add a new micro-module `OmniExecution` (zero risk of breaking existing imports via `@_exported`)? **Decision needed before Phase 2.**

4. **Alpine rootfs distribution**: Download on first use (requires network, adds latency to first container start) vs. bundle a minirootfs tar in SPM resources (adds ~5MB to package, always available)? Draft assumes download-on-first-use with disk caching. Could also support both: bundled for tests, downloaded for production.

5. **Control file pattern**: Wanix implements "actions as files" (`ctl` files, `FuncFile` that execute on read). Should `OmniVFS` support this pattern for container management (e.g., write "stop\n" to `container/42/ctl` stops it), or use conventional Swift API only? Draft defers control files — conventional API is sufficient for Sprint 005. Can be added later if the Plan 9 philosophy is desired.

6. **Networking**: Sprint 005 intentionally excludes container networking (no virtual interfaces, no port forwarding). All execution is filesystem + process. Confirm this scope boundary.

7. **blink on aarch64 macOS performance**: blink emulates x86-64 on ARM. Alpine x86-64 ELF binaries run through double emulation (blink's JIT on ARM). Alternatively, use Alpine aarch64 rootfs and a native execution path on macOS. Draft targets x86-64 only (blink's primary use case). Native aarch64 path can be a follow-up.

8. **Scope phasing**: If this sprint is too large, should we split as: Sprint 005a (OmniVFS only) + Sprint 005b (OmniContainer + engines)? The draft is written as one sprint but with phase gates that allow early delivery of Phases 1-2 without Phases 3-4.
