# SPRINT-005: OmniVFS + OmniContainer — Wanix-Inspired Container Runtime (blink + WasmKit)

## Overview

This sprint introduces four new SPM modules — `OmniExecution`, `OmniVFS`, `OmniContainer`, and `CBlinkEmulator` — to create a Wanix-inspired lightweight container runtime with Plan 9-style VFS namespaces, copy-on-write filesystem layering, and two-tier binary execution. ELF binaries (Alpine Linux userland) run through blink's x86-64 Linux syscall emulation; WASI binaries run through WasmKit at near-native speed. A binfmt-style dispatch hook inside the emulated Linux shell automatically routes `.wasm` executables to WasmKit, bypassing emulation.

The system implements the existing `ExecutionEnvironment` protocol via `ContainerExecutionEnvironment`, enabling sandboxed agent tool execution with zero Docker/VM dependencies. All file operations route through the container's VFS namespace — the host filesystem is never exposed unless explicitly bound. The VFS layer is synchronous and lock-protected by design; actor isolation is reserved for container lifecycle and image management only. This avoids the reentrancy deadlocks documented in the project memory for actor-based `Session`.

The sprint delivers a full vertical slice: VFS → Container → both runtime engines → agent integration. Phase gates allow early exit if blink or WasmKit integration proves intractable — Phases 0-2 are independently shippable.

## Use Cases

1. **Sandboxed agent tool execution**: An `OmniAgentsSDK` tool invokes `execCommand` on a `ContainerExecutionEnvironment` instead of `LocalExecutionEnvironment`. The command runs inside an Alpine-based container with its own VFS namespace. File writes are captured in a CowFS overlay — the base image is never mutated.

2. **Two-tier binary dispatch**: A container detects binary format by magic bytes. ELF binaries (`\x7fELF`) route to blink for full Linux syscall emulation; WASM binaries (`\0asm`) route to WasmKit for near-native WASI execution. The caller doesn't choose — `BinaryProbe` inspects the first 4 bytes and selects the engine.

3. **binfmt-style WASI escape**: When a guest shell (running in blink) tries to `execve()` a `.wasm` file, the blink exec hook detects the WASM magic, suspends the guest image load, and invokes WasmKit with the same argv/env/cwd/stdio. The `.wasm` binary runs at full speed in the host process, not through emulation.

4. **Composable filesystem layering**: A pipeline node constructs a custom VFS namespace: Alpine rootfs (read-only `TarFS`) → project files (read-only `DiskFS` bind) → scratch overlay (`MemFS` via `CowFS`). On container stop, the overlay can be serialized to disk for persistence or discarded.

5. **Per-exec namespace isolation**: When a container runs a command, it clones its namespace into an `ExecSession`. Temporary binds, cwd overrides, and WASI preopen shaping stay isolated — mutations don't affect the parent container namespace. Identical to Wanix's task namespace cloning.

6. **Persistent workspace + ephemeral root**: `/workspace` and selected volumes survive across container restarts via DiskFS binds. `/` remains copy-on-write on top of a cached Alpine base image. Container overlay state can optionally persist.

7. **Alpine package management**: With networking capability enabled, `apk add` works inside the container through blink, allowing installation of build tools, compilers, and utilities.

8. **Attractor pipeline integration**: An Attractor DOT node sets `execution_env=container` and `image=alpine:minirootfs`. The pipeline engine constructs a `ContainerExecutionEnvironment`, passes it to `CodingAgentBackend`, and all tool invocations run sandboxed.

## Architecture

### SPM Target Graph

```
                    ┌─────────────────────┐
                    │   OmniAIAgent       │
                    │   (imports protocol) │
                    └──────────┬──────────┘
                               │ depends on
                    ┌──────────▼──────────┐
                    │   OmniExecution     │◄─────────────────┐
                    │ (ExecutionEnvironment│                  │
                    │  ExecResult, DirEntry│                  │
                    │  GrepOptions)        │                  │
                    └──────────┬──────────┘                  │
                               │                             │
                    ┌──────────▼──────────┐                  │
                    │   OmniContainer     │──────────────────┘
                    │ (Container, Engines, │   conforms to
                    │  ContainerExecEnv)  │   ExecutionEnvironment
                    └──┬──────────────┬───┘
                       │              │
            depends on │              │ depends on
                       │              │
              ┌────────▼───┐   ┌──────▼──────────┐
              │  OmniVFS   │   │ CBlinkEmulator   │
              │ (Namespace, │   │ (vendored blink  │
              │  MemFS,     │   │  source + shim)  │
              │  CowFS,     │   └─────────────────┘
              │  UnionFS,   │
              │  MapFS,     │   External dep:
              │  DiskFS,    │   WasmKit (SPM)
              │  TarFS,     │
              │  PipeFS)    │
              └─────────────┘

Platform conditioning:
  OmniContainer, CBlinkEmulator → macOS + Linux only
  OmniVFS, OmniExecution → all platforms
```

### VFS Protocol Hierarchy

Translating Wanix's Go interface tower into Swift protocols. All VFS protocols are synchronous and `Sendable` — no actors, no async. This is critical because blink's C callbacks and WasmKit's WASI hooks cannot `await`.

```swift
// ── Core read-only protocols ──────────────────────────
public protocol VFS: Sendable {
    func open(_ path: String) throws -> VFSFile
}

public protocol VFSFile: Sendable {
    func stat() throws -> VFSFileInfo
    func read(into buffer: inout [UInt8], count: Int) throws -> Int
    func close() throws
}

public protocol VFSReadDirFS: VFS {
    func readDir(_ path: String) throws -> [VFSDirEntry]
}

public protocol VFSStatFS: VFS {
    func stat(_ path: String) throws -> VFSFileInfo
}

public protocol VFSResolveFS: VFS {
    func resolveFS(_ path: String) throws -> (any VFS, String)
}

// ── Mutable protocols ─────────────────────────────────
public protocol VFSMutableFS: VFS {
    func createFile(_ path: String, data: [UInt8]) throws
    func mkdir(_ path: String) throws
    func remove(_ path: String) throws
    func writeFile(_ path: String, data: [UInt8]) throws
    func rename(from: String, to: String) throws
    func symlink(target: String, link: String) throws
}

// ── File handle extensions ────────────────────────────
public protocol VFSWritableFile: VFSFile {
    func write(_ data: [UInt8]) throws -> Int
}

public protocol VFSSeekableFile: VFSFile {
    func seek(offset: Int64, whence: SeekWhence) throws -> Int64
    func pread(into buffer: inout [UInt8], count: Int, offset: Int64) throws -> Int
    func pwrite(_ data: [UInt8], offset: Int64) throws -> Int
}

public protocol VFSFullFS: VFSReadDirFS, VFSStatFS, VFSMutableFS, VFSResolveFS {}
```

### Namespace (Plan 9 Bind Semantics)

```
┌──────────────────────────────────────────────────────────┐
│                    VFSNamespace                            │
│  bindings: [String: [BindTarget]]                         │
│                                                           │
│  bind(src, srcPath, dstPath, mode: .before/.after/.rep)   │
│  unbind(dstPath)                                          │
│  resolveFS(path) → (VFS, resolvedPath)                    │
│  clone() → VFSNamespace                                   │
│                                                           │
│  Container root namespace:                                │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ "."         → CowFS(base: TarFS(alpine), overlay)  │  │
│  │ "workspace" → DiskFS(host project dir)              │  │
│  │ "tmp"       → MemFS()                               │  │
│  │ "home/omni" → DiskFS(persistent volume)             │  │
│  └─────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

`VFSNamespace` is a `struct` (value type, cloneable). Path resolution is a pure function — no async, no suspension points. Thread safety for concurrent mutation is handled by the `ContainerActor` which serializes namespace mutations. Bind modes match Wanix:

| Mode | Behavior |
|------|----------|
| `.after` | New binding prepended (checked first) |
| `.before` | New binding appended (checked last) |
| `.replace` | Replaces all existing bindings at path |

### Container Architecture

```
┌─────────────────────────────────────────────────────┐
│                   ContainerActor                     │
│  state: .created | .running | .stopped | .destroyed │
│  namespace: VFSNamespace                             │
│  config: ContainerSpec                               │
│  capabilities: [ContainerCapability]                 │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │              ExecSession                      │   │
│  │  cloned namespace + stdio pipes + process     │   │
│  │                                               │   │
│  │  ┌─────────────┐    ┌──────────────────┐     │   │
│  │  │ BinaryProbe │    │ Runtime Dispatch  │     │   │
│  │  │ 7f454c46→ELF│    │                   │     │   │
│  │  │ 0061736d→WSM│    │ ELF  → BlinkRT   │     │   │
│  │  │ #!→ script  │    │ WASM → WasmRT    │     │   │
│  │  └─────────────┘    │ #!   → blink /sh │     │   │
│  │                      └──────────────────┘     │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### Concurrency Architecture

| Type | Isolation | Rationale |
|------|-----------|-----------|
| `VFSNamespace` | `struct` (value type) | Pure function resolution. Cloned per-exec. |
| `MemFS`, `CowFS` | `final class: @unchecked Sendable` + `NSLock` | Interior mutability. Lock-based to keep VFS sync. |
| `DiskFS`, `TarFS` | `final class: Sendable` | DiskFS delegates to OS (thread-safe). TarFS immutable after init. |
| `UnionFS`, `MapFS` | `struct: Sendable` | Immutable composition of child filesystems. |
| `ContainerActor` | `actor` | Serializes lifecycle (create/start/stop/destroy) and namespace mutations. |
| `ImageStore` | `actor` | Serializes rootfs fetch/cache/extraction. |
| `BlinkRuntime` | `final class: Sendable` | Stateless — each exec spawns blink process on dedicated DispatchQueue (not cooperative pool). |
| `WasmEngine` | `final class: Sendable` | Stateless — each exec instantiates WasmKit module. |
| `ContainerExecutionEnvironment` | `final class: Sendable` | Holds reference to ContainerActor. All methods await actor. |
| `BlinkBridgeState` | `final class: @unchecked Sendable` + `NSLock` | Short-lived, synchronous C callback context. Locked fd table. |

### Path Translation Rules

`ContainerExecutionEnvironment` maintains dual-path mapping:

- Host cwd: `/Users/.../swift-omnikit` (reported by `workingDirectory()`)
- Guest cwd: `/workspace`

Translation rules:
- Host absolute paths under the bound workspace → guest `/workspace/...`
- Guest absolute paths (e.g., `/etc/os-release`) → remain guest paths
- Relative paths → resolve against host workspace root, then map into guest namespace

`platform()` reports `"linux"` (guest). `osVersion()` reports `"Alpine Linux 3.21 (host: Darwin 26.0.0)"`.

### blink Integration Strategy (BLINK_OVERLAYS)

For Sprint 005, blink runs as an embedded process using the `BLINK_OVERLAYS` environment variable for filesystem virtualization:

1. Before each exec, materialize the container's VFS namespace to a temp directory on host
2. Set `BLINK_OVERLAYS=/path/to/materialized/rootfs`
3. Run blink with the command
4. After exec, diff the materialized directory against the original and apply changes back to the CowFS overlay
5. Clean up temp directory

This avoids the complexity of patching blink's syscall internals while still providing full Alpine compatibility. Custom VFS callbacks (direct C interop) are deferred to a follow-up sprint.

The binfmt-style WASI escape works at the `execCommand` level: when the command resolves to a `.wasm` file, `BinaryProbe` detects the magic bytes and routes directly to WasmKit before blink is invoked.

### WasmKit WASI Filesystem Bridge

WasmKit's WASI filesystem extension points are package-internal. Sprint 005 uses a snapshot/write-back bridge:

1. Snapshot relevant namespace subtrees (`/`, `/workspace`, `/tmp`) into WasmKit's `MemoryFileSystem`
2. Run the WASI module with ordered preopens and pipe-backed stdio
3. Diff the mutated memory tree back into the container's CowFS overlay

A direct VFS→WASI adapter (via WasmKit fork exposing filesystem protocols) is planned as a follow-up.

### Networking (Capability-Gated)

Basic outbound TCP/DNS is supported, gated behind `ContainerCapability.network`:

- When enabled: blink's socket syscalls are allowed, `apk add` works
- When disabled (default): socket syscalls return EACCES
- DNS resolution via host's resolver (blink passes through to host network stack via BLINK_OVERLAYS)

## Implementation

### Phase 0: Feasibility Spikes + Package Graph (~10% of effort)

Validate the two riskiest integration points before committing to full scope.

**Files:**
- `Package.swift` — Add all new targets, dependencies, conditional platform guards
- `Sources/OmniExecution/ExecutionEnvironment.swift` — Extracted protocol + value types
- `Sources/OmniExecution/ExecResult.swift` — Moved from OmniAIAgent
- `Sources/OmniExecution/DirEntry.swift` — Moved from OmniAIAgent
- `Sources/OmniExecution/GrepOptions.swift` — Moved from OmniAIAgent
- `Sources/CBlinkEmulator/include/blink_shim.h` — Minimal C shim header
- `Sources/CBlinkEmulator/blink_shim.c` — Minimal shim wrapping blink
- `Sources/CBlinkEmulator/vendor/blink/` — Vendored blink source subset

**Tasks:**
- [ ] Create `OmniExecution` module with `ExecutionEnvironment`, `ExecResult`, `DirEntry`, `GrepOptions` extracted from `OmniAIAgent`
- [ ] Update `OmniAIAgent` to depend on `OmniExecution` instead of owning the protocol
- [ ] Add `OmniVFS`, `OmniContainer`, `CBlinkEmulator` target stubs to `Package.swift`
- [ ] Add WasmKit dependency (pinned revision or compatible fork if needed)
- [ ] Add conditional platform guards: `OmniContainer` + `CBlinkEmulator` macOS/Linux only
- [ ] Verify `swift build` passes for all existing targets on all platforms
- [ ] **Spike: blink** — Vendor minimal blink source, compile under SPM, run `/bin/busybox echo hello` against an Alpine minirootfs via `BLINK_OVERLAYS`. Measure latency on Apple Silicon.
- [ ] **Spike: WasmKit** — Instantiate a WASI hello-world module, verify `WASIBridgeToHost` API, test `MemoryFileSystem` snapshot approach
- [ ] **Gate decision**: If either spike fails, descope that engine to Sprint 006

**Guard check:**
```bash
swift build 2>&1 | grep -c 'error:'  # 0 — no regressions
```

### Phase 1: OmniVFS — Core VFS Protocols and Filesystems (~25% of effort)

**Files:**
- `Sources/OmniVFS/Types.swift` — VFSFileInfo, VFSDirEntry, VFSError, BindMode, VFSFileMode, SeekWhence
- `Sources/OmniVFS/Protocols.swift` — VFS, VFSFile, VFSReadDirFS, VFSStatFS, VFSResolveFS, VFSMutableFS, VFSWritableFile, VFSSeekableFile, VFSFullFS
- `Sources/OmniVFS/PathUtils.swift` — validPath, cleanPath, joinPath, matchPaths, fnmatch-style glob
- `Sources/OmniVFS/MemFS.swift` — In-memory mutable filesystem (configurable memory cap)
- `Sources/OmniVFS/DiskFS.swift` — Host-directory-backed filesystem with path traversal guard
- `Sources/OmniVFS/TarFS.swift` — Read-only tar-archive filesystem (zero-copy slicing)
- `Sources/OmniVFS/CowFS.swift` — Copy-on-write overlay with `.wh.<name>` whiteout files
- `Sources/OmniVFS/UnionFS.swift` — Merged read-only filesystem (deduplication, ordering)
- `Sources/OmniVFS/MapFS.swift` — Dictionary-based synthetic filesystem, auto-synthesizes parent dirs
- `Sources/OmniVFS/PipeFS.swift` — Bidirectional pipe pair for stdio (LockedRingBuffer-backed)
- `Sources/OmniVFS/Namespace.swift` — VFSNamespace struct with bind/unbind/resolveFS/clone. Resolution depth limit of 64 for cycle prevention. Symlink resolution within namespace only.

**Tasks:**
- [ ] Implement all VFS protocols as described in Architecture section
- [ ] Implement all filesystem backends with `Sendable` conformances
- [ ] MemFS: configurable `maxBytes` cap, reject writes when exceeded
- [ ] CowFS: whiteout files (`.wh.<name>`) matching OCI/Docker convention
- [ ] Namespace: Wanix-style bind ordering, per-exec cloning, synthesized parent directories
- [ ] PathUtils: reject `..` components, enforce `ValidPath` rules, fnmatch for glob
- [ ] All backends are synchronous — no async, no actors within OmniVFS

**Guard check:**
```bash
swift build --target OmniVFS 2>&1 | grep -c 'error:'  # 0
```

### Phase 2: OmniContainer — Container Lifecycle + Image Management (~20% of effort)

**Files:**
- `Sources/OmniContainer/ContainerSpec.swift` — Image ref, env vars, cwd, resource limits, mount binds, capabilities, persistence mode
- `Sources/OmniContainer/ContainerState.swift` — State enum, ContainerID (UUID-based)
- `Sources/OmniContainer/ContainerCapability.swift` — Capability protocol + built-ins: .network, .workspace(hostPath), .persistentVolume(name), .tmpfs, .debugMount
- `Sources/OmniContainer/ContainerActor.swift` — Core actor: lifecycle, namespace assembly, exec dispatch
- `Sources/OmniContainer/ExecSession.swift` — Per-exec: cloned namespace, stdio pipes, process state
- `Sources/OmniContainer/BinaryProbe.swift` — Magic-byte detection: ELF/WASM/script
- `Sources/OmniContainer/ImageStore.swift` — Actor: Alpine rootfs fetch, SHA256 verification, disk cache (~/.omnikit/images/), version pinning manifest
- `Sources/OmniContainer/ContainerExecutionEnvironment.swift` — ExecutionEnvironment conformance with path translation

**Tasks:**
- [ ] `ImageStore`: download Alpine minirootfs (pinned version 3.21 + SHA256), cache to `~/.omnikit/images/`, verify on load, return `TarFS`
- [ ] `ContainerActor`: assemble root namespace (CowFS(TarFS + MemFS overlay)), install capabilities as binds
- [ ] `ExecSession`: clone namespace, create PipeFS stdio, dispatch via BinaryProbe
- [ ] `ContainerExecutionEnvironment`: implement ALL `ExecutionEnvironment` methods:
  - `readFile` / `writeFile` / `fileExists` / `listDirectory` → VFS namespace
  - `execCommand` → parse command string (preserving shell semantics via blink `/bin/sh -lc`), dispatch to engine
  - `grep` → in-VFS regex search over readDir + readFile
  - `glob` → in-VFS fnmatch over directory tree walk
  - `initialize` → create container, pull image if needed
  - `cleanup` → stop container, optionally persist overlay
  - `workingDirectory` → host path (with internal guest mapping)
  - `platform` → `"linux"`
  - `osVersion` → `"Alpine Linux 3.21 (host: Darwin X.Y.Z)"`
- [ ] Path translation: host paths under workspace → guest `/workspace/...`, guest absolute paths pass through
- [ ] Container persistence modes: ephemeral (overlay discarded), overlay-persistent (overlay serialized to DiskFS)

**Guard check:**
```bash
swift build --target OmniContainer 2>&1 | grep -c 'error:'  # 0
```

### Phase 3: WasmKit Engine (~15% of effort)

**Files:**
- `Sources/OmniContainer/Engines/ContainerRuntime.swift` — Shared runtime protocol: `canExecute(_ data: [UInt8]) -> Bool`, `execute(...)  async throws -> ExecResult`
- `Sources/OmniContainer/Engines/WasmEngine.swift` — WasmKit WASI execution
- `Sources/OmniContainer/Engines/WASISnapshotBridge.swift` — Snapshot/write-back bridge (namespace subtrees → MemoryFileSystem → diff back)
- `Sources/OmniContainer/Engines/WASIStdio.swift` — PipeFS-backed stdin/stdout/stderr for WASI

**Tasks:**
- [ ] `WasmEngine`: parse WASM module, configure WASIBridgeToHost with preopens, call `_start`, capture exit code
- [ ] `WASISnapshotBridge`: snapshot `/`, `/workspace`, `/tmp` into MemoryFileSystem before exec; diff writes back into CowFS overlay after exec. Size threshold: skip files > 10MB during snapshot.
- [ ] Stdio: PipeFS endpoints for stdin/stdout/stderr, wire to WASIBridgeToHost
- [ ] Gate behind `#if compiler(>=6.1)` if WasmKit requires it; provide `StubWasmEngine` returning `.notSupported` on older toolchains

**Guard check:**
```bash
swift build --target OmniContainer 2>&1 | grep -c 'error:'  # 0
```

### Phase 4: blink Engine + C Interop (~20% of effort)

**Files:**
- `Sources/CBlinkEmulator/include/blink_shim.h` — Public C header: `blink_exec_with_overlays()`
- `Sources/CBlinkEmulator/blink_shim.c` — Thin wrapper: set up BLINK_OVERLAYS, fork+exec blink, capture output
- `Sources/CBlinkEmulator/vendor/blink/` — Vendored blink source tree (interpreter core, syscall handlers; exclude test/, JIT if problematic)
- `Sources/CBlinkEmulator/vendor/blink/config.h` — Committed config header for macOS arm64 + Linux x86-64/aarch64
- `Sources/OmniContainer/Engines/BlinkRuntime.swift` — Swift wrapper: materialize VFS, invoke blink, sync changes back
- `Sources/OmniContainer/Engines/BlinkVFSSync.swift` — VFS ↔ host temp directory materialization and diff-back

**Tasks:**
- [ ] Vendor blink source subset needed for interpreter + syscall emulation
- [ ] Commit generated `config.h` for target platforms (macOS arm64, Linux x86-64, Linux aarch64)
- [ ] `blink_shim.c`: library-style entry point that accepts overlays path, argv, envp, captures stdout/stderr via pipe
- [ ] `BlinkRuntime`:
  1. Materialize namespace to temp dir via `BlinkVFSSync.materialize(namespace:)`
  2. Set `BLINK_OVERLAYS=<temp_dir>`
  3. Execute blink on dedicated DispatchQueue (not cooperative thread pool)
  4. Apply timeout via DispatchWorkItem cancellation
  5. Read stdout/stderr from pipes (streaming via PipeFS, not fixed buffers)
  6. Diff temp dir back into CowFS overlay via `BlinkVFSSync.syncBack()`
  7. Clean up temp dir
- [ ] Networking: when `ContainerCapability.network` is enabled, blink inherits host network. When disabled, set `BLINK_DISABLE_NETWORKING` or block socket syscalls.
- [ ] binfmt dispatch at `ExecSession` level: if command resolves to `.wasm` file, route to WasmEngine before invoking blink

**Guard check:**
```bash
swift build --target CBlinkEmulator 2>&1 | grep -c 'error:'  # 0
swift build --target OmniContainer 2>&1 | grep -c 'error:'  # 0
```

### Phase 5: Agent Integration + CLI (~10% of effort)

**Files:**
- `Sources/OmniAIAgent/Execution/ExecutionBackend.swift` — Backend selection: `.local` | `.container(spec:)`
- `Sources/OmniAIAgent/CodingAgent.swift` — Modify: backend-aware environment factory
- `Sources/OmniAICode/main.swift` — Modify: add `--container`, `--image`, `--network` flags
- `Sources/OmniAIAttractor/Handlers/CodingAgentBackend.swift` — Modify: backend injection via node config

**Tasks:**
- [ ] Add `ExecutionBackend` configuration without breaking existing callers
- [ ] `CodingAgent` creates `ContainerExecutionEnvironment` when backend is `.container`
- [ ] CLI flags: `--container` (enable), `--image alpine:minirootfs` (default), `--network` (enable outbound)
- [ ] Attractor: `execution_env=container` node attribute triggers container backend
- [ ] Verify subagents and worktrees preserve selected backend

### Phase 6: Tests (~effort distributed across phases)

**Files:**
- `Tests/OmniVFSTests/MemFSTests.swift` — CRUD, path validation, concurrent access, memory cap enforcement
- `Tests/OmniVFSTests/CowFSTests.swift` — Read-through, write overlay, whiteout on delete, directory merge
- `Tests/OmniVFSTests/UnionFSTests.swift` — Merged listings, dedup, priority ordering
- `Tests/OmniVFSTests/MapFSTests.swift` — Key-path mapping, synthesized parents
- `Tests/OmniVFSTests/TarFSTests.swift` — Parse test tar, read files, stat, readDir
- `Tests/OmniVFSTests/NamespaceTests.swift` — bind/unbind, BindMode semantics, resolveFS, clone independence, cycle detection (depth 64), symlink containment
- `Tests/OmniVFSTests/PipeFSTests.swift` — Write-then-read, close propagation
- `Tests/OmniVFSTests/PathUtilsTests.swift` — validPath, cleanPath, traversal rejection, glob matching
- `Tests/OmniContainerTests/BinaryProbeTests.swift` — ELF/WASM/script detection, non-seekable input
- `Tests/OmniContainerTests/ContainerLifecycleTests.swift` — State machine, invalid transitions
- `Tests/OmniContainerTests/ContainerExecEnvTests.swift` — Full ExecutionEnvironment conformance: readFile, writeFile, fileExists, listDirectory, grep, glob, workingDirectory, platform, osVersion
- `Tests/OmniContainerTests/ImageStoreTests.swift` — Cache hit/miss, SHA256 verification, corrupt archive handling
- `Tests/OmniContainerTests/Integration/WasmIntegrationTests.swift` — WASI hello-world through VFS, stdout capture. Gated: `#if compiler(>=6.1)`
- `Tests/OmniContainerTests/Integration/BlinkIntegrationTests.swift` — `/bin/busybox echo hello` through BLINK_OVERLAYS, stdout capture
- `Tests/OmniContainerTests/Integration/ContainerEndToEndTests.swift` — Full lifecycle: create → exec shell command → verify output → create file → verify persistence → stop → restart → verify persisted file still exists
- `Tests/OmniContainerTests/Integration/ApkInstallTests.swift` — `apk add curl` with network capability. Gated: `OMNIKIT_NETWORK_TESTS=1` env var
- `Tests/OmniAIAgentTests/ContainerExecutionEnvironmentTests.swift` — Agent-side adapter, path translation, backend selection

## Files Summary

| File | Action | Purpose |
|------|--------|---------|
| `Package.swift` | Modify | Add OmniExecution, OmniVFS, OmniContainer, CBlinkEmulator targets + WasmKit dep + platform guards |
| `Sources/OmniExecution/*.swift` (4 files) | Create | Extracted ExecutionEnvironment protocol + value types |
| `Sources/OmniAIAgent/Execution/ExecutionEnvironment.swift` | Delete | Moved to OmniExecution |
| `Sources/OmniAIAgent/**` | Modify | Update imports to use OmniExecution |
| `Sources/OmniVFS/*.swift` (11 files) | Create | VFS protocols, all filesystem backends, namespace, path utils |
| `Sources/CBlinkEmulator/**` | Create | Vendored blink source, C shim, config headers |
| `Sources/OmniContainer/*.swift` (8 files) | Create | Container spec/state/actor, capabilities, exec session, image store, binary probe, ContainerExecutionEnvironment |
| `Sources/OmniContainer/Engines/*.swift` (5 files) | Create | ContainerRuntime protocol, WasmEngine, WASISnapshotBridge, WASIStdio, BlinkRuntime, BlinkVFSSync |
| `Sources/OmniAIAgent/Execution/ExecutionBackend.swift` | Create | Backend selection surface |
| `Sources/OmniAIAgent/CodingAgent.swift` | Modify | Backend-aware environment factory |
| `Sources/OmniAICode/main.swift` | Modify | Container CLI flags |
| `Sources/OmniAIAttractor/Handlers/CodingAgentBackend.swift` | Modify | Container backend injection |
| `Tests/OmniVFSTests/*.swift` (8 files) | Create | VFS unit tests |
| `Tests/OmniContainerTests/*.swift` (4 files) | Create | Container unit tests |
| `Tests/OmniContainerTests/Integration/*.swift` (4 files) | Create | Integration tests (WASI, blink, E2E, apk) |
| `Tests/OmniAIAgentTests/ContainerExecutionEnvironmentTests.swift` | Create | Agent integration tests |

## Definition of Done

1. `swift build` passes with zero errors for all targets (OmniExecution, OmniVFS, OmniContainer, CBlinkEmulator) and all pre-existing targets on macOS arm64
2. `swift build` passes on Linux x86-64 (CI verification)
3. iOS/tvOS/watchOS/visionOS builds remain green — container targets conditionally excluded
4. All new Swift targets compile under Swift 6 strict concurrency with zero warnings
5. `@unchecked Sendable` permitted only on `MemFS`, `CowFS`, `BlinkBridgeState` with documented lock invariants
6. `swift test --filter OmniVFSTests` passes: MemFS CRUD + memory cap, CowFS read-through + whiteout, UnionFS merge + dedup, MapFS synthesized parents, TarFS parse + read, Namespace bind/unbind/resolve/clone + cycle detection, PipeFS read-write + close, PathUtils validation + traversal rejection
7. `swift test --filter OmniContainerTests` passes: BinaryProbe magic detection, Container lifecycle state machine, ContainerExecutionEnvironment full `ExecutionEnvironment` conformance (all methods), ImageStore cache + verification
8. Integration: WasmEngine executes a WASI hello-world binary through snapshot bridge, captures stdout
9. Integration: BlinkRuntime executes `/bin/busybox echo hello` through BLINK_OVERLAYS, captures stdout
10. Integration: Full container lifecycle — create → exec → file write → stop → restart → verify persistence
11. Integration (network-gated): `apk add curl` succeeds with network capability enabled
12. Performance baseline: blink `echo hello` completes in < 10s on Apple Silicon; VFS operations < 1ms
13. All pre-existing tests pass (`swift test` overall green, no regressions)
14. `ContainerExecutionEnvironment` is a drop-in replacement for `LocalExecutionEnvironment` — full protocol conformance including grep, glob, initialize, cleanup, workingDirectory, platform, osVersion

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **blink vendoring complexity**: blink's ~30K LOC C source assumes GNU Make build system with platform-specific config.h | High | High | Commit generated config headers per platform. Start with interpreter-only subset (disable JIT if Apple Hardened Runtime blocks MAP_JIT). Keep host-materialized BLINK_OVERLAYS as the guaranteed path. |
| **blink JIT on Apple Silicon**: Hardened Runtime blocks MAP_JIT without entitlement | High | Medium | Fall back to pure interpretation (10-50x slower than JIT but functional). Add `com.apple.security.cs.allow-jit` entitlement for development/test builds. For production, interpreter speed is acceptable for I/O-bound shell commands. |
| **WasmKit Swift version incompatibility**: requires 6.1+, project uses 6.0 tools-version | Medium | Medium | Gate behind `#if compiler(>=6.1)`. Provide StubWasmEngine. Track WasmKit compatibility. Pin revision. |
| **WasmKit filesystem APIs package-internal** | High | Medium | Ship snapshot/write-back bridge as Sprint 005 path. Direct VFS adapter via WasmKit fork planned for follow-up. |
| **Shell-string compatibility**: current execCommand callers rely on shell behavior (pipes, quoting, nohup) | Medium | High | Route all execCommand through blink's `/bin/sh -lc "<command>"`. This preserves shell semantics natively. |
| **Host/guest path confusion**: breaks prompt generation or project-doc discovery | Medium | High | Keep workingDirectory() host-facing. Test both host and guest absolute path inputs. |
| **Thread pool exhaustion from synchronous blink execution** | Medium | Medium | Execute blink on dedicated DispatchQueue outside cooperative thread pool. Match LocalExecutionEnvironment's Process pattern. |
| **BLINK_OVERLAYS materialization performance**: large workspaces cause slow sync | Medium | Medium | Materialize only namespace-bound paths (not entire host FS). Use hardlinks for read-only base layers. Skip files > 100MB. |
| **Scope exceeds single sprint** | Medium | Medium | Strict phase gating. Phases 0-2 independently shippable without binary execution. WasmKit and blink can independently fail and be descoped. |
| **Actor reentrancy in container lifecycle** | Low | High | VFS is synchronous structs. ContainerActor only for lifecycle. ExecSession clones namespace (value type). No nested actor calls. |
| **Alpine rootfs version drift** | Low | Low | Pin version 3.21 + SHA256 in ImageStore manifest. |
| **Platform regression on Apple non-macOS builds** | Medium | High | Conditional platform dependencies in Package.swift. `#if os(macOS) || os(Linux)` guards on container-specific files. |

## Security Considerations

- **Path traversal prevention**: PathUtils.validPath() rejects `..` components. DiskFS verifies resolved host path has root as prefix after symlink resolution. Symlinks inside VFS resolve within namespace only — a guest symlink to `/etc/passwd` resolves against the VFS root, not the host.
- **No host filesystem leakage**: ContainerExecutionEnvironment never delegates to host FileManager or Process for file operations. All routes through VFS namespace. Host paths exposed only via explicit DiskFS workspace bind.
- **Network capability gating**: Socket syscalls denied by default. `ContainerCapability.network` must be explicitly enabled. When disabled, `apk add` and outbound connections fail with EACCES.
- **blink process isolation**: blink runs in materialized overlay directory. Cannot access host paths outside the materialized tree. No raw host file descriptors exposed.
- **WASI sandboxing**: Preopens scoped to namespace subtrees. No ambient authority — WASM modules cannot access paths outside preopens.
- **Resource limits**: MemFS configurable maxBytes cap. Execution timeout per-command via DispatchWorkItem cancellation. ImageStore validates SHA256 before extraction.
- **No shell injection**: execCommand routes through blink's `/bin/sh -lc` inside the container. Host shell is never invoked.
- **Sensitive environment filtering**: Containers do not inherit host environment. Only explicitly passed env vars from ContainerSpec are available.

## Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| Swift 6.0 toolchain | Existing | `swift-tools-version: 6.0` |
| `swift-testing` | Existing | `@Test`, `#expect` for all new test targets |
| `Foundation` | System | Data, FileManager (DiskFS, ImageStore), NSLock, UUID, Process |
| **WasmKit** | **New** | `https://github.com/swiftwasm/WasmKit`, pinned revision. WASI Preview 1. May need `#if compiler(>=6.1)` gate. |
| **blink** (vendored) | **New** | `https://github.com/jart/blink`, vendored C source in CBlinkEmulator. No external package dependency. |
| **swift-system** | **New** | Required by WasmKit bridge for FileDescriptor types |

## Open Questions

1. **WasmKit direct filesystem bridge**: Can we expose WasmKit's filesystem protocols via a small fork? If yes, the snapshot/write-back bridge can be replaced with a direct VFS adapter. Needs prototyping in Phase 0 spike.

2. **blink JIT entitlement in CI**: Should CI builds include the JIT entitlement for faster blink execution, or should we validate interpreter-only performance as the baseline?

3. **Container storage location**: Should image cache and persistent overlays live in `~/.omnikit/` (user-global) or `.omnikit/` (workspace-local)? User-global saves disk for multi-project use; workspace-local is more self-contained.

4. **Alpine aarch64 rootfs**: Currently targeting x86-64 Alpine (blink's primary target). Should we also support Alpine aarch64 rootfs for native execution on Linux aarch64 (bypassing blink entirely)?

5. **LocalExecutionEnvironment deprecation path**: Should `LocalExecutionEnvironment` eventually be deprecated in favor of always using containers, or remain as a lightweight/trusted-host fallback permanently?

6. **Control file pattern**: Should OmniVFS eventually support Wanix-style "actions as files" (write "stop\n" to container/42/ctl)? Deferred from Sprint 005 but worth deciding on for the VFS design.

7. **Custom blink VFS callbacks**: After Sprint 005 ships with BLINK_OVERLAYS, should Sprint 006 invest in patching blink's syscall handlers to call Swift VFS directly? This eliminates materialization overhead but requires maintaining blink patches.
