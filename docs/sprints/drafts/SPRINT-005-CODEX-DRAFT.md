# Sprint 005: OmniVFS + OmniContainer — Wanix-Inspired Container Runtime

## Overview

Sprint 005 adds a container-backed execution backend to `swift-omnikit` without replacing the existing `ExecutionEnvironment` abstraction. The implementation should stay aligned with the current architecture: `OmniAIAgent` continues to own the agent-facing execution protocol, while new lower-level targets provide a virtual filesystem, container lifecycle, and runtime adapters for Linux ELF and WASI workloads.

The guiding reference is Wanix: namespaces are first-class, copy-on-write layering is the default execution model, and capabilities explicitly control what gets mounted into a container. The key translation into Swift is that mutable orchestration state lives behind actors, but the filesystem and runtime bridges must expose synchronous, thread-safe operations because both blink and WasmKit invoke filesystem hooks synchronously.

This sprint should deliver a vertical slice, not just a VFS library. The end state is: an agent session can opt into a container backend, get an Alpine-like Linux userland rooted in a copy-on-write namespace, run shell commands through blink, run WASI binaries through WasmKit, and preserve selected filesystem state across restarts. To keep scope bounded, the sprint should not extract `ExecutionEnvironment` into a new shared target; that refactor would ripple through most of `OmniAIAgent` and is not required to ship the runtime.

## Use Cases

1. **Agent-safe Linux shell execution**: A coding session runs `/bin/sh -lc ...` inside an Alpine rootfs instead of on the host, so package installs, shell scripts, and build tools do not mutate the host directly.
2. **WASI tool acceleration**: A command resolves to a `.wasm` binary and is executed through WasmKit using the same mounted workspace and stdio streams as the Linux shell flow.
3. **Persistent workspace + ephemeral root**: `/workspace` and selected container volumes survive across runs, while `/` remains copy-on-write on top of a cached Alpine base image.
4. **Per-exec namespace isolation**: A container can clone its namespace for a single exec, add or remove temporary binds, then discard those changes without mutating the parent container view.
5. **Agent integration without protocol churn**: `CodingAgent`, `OmniAICode`, and Attractor can choose `LocalExecutionEnvironment` or `ContainerExecutionEnvironment` through configuration instead of duplicating environment logic.

## Architecture

### Reference Mapping

Wanix and Apptron should be treated as behavioral references, not code to transliterate:

- `vfs.NS` becomes `NamespaceActor` + immutable `NamespaceSnapshot`.
- `cowfs.FS` becomes `CopyOnWriteFileSystem` with persisted whiteouts.
- `task.Resource` becomes `ExecSession`, which clones a namespace and owns stdio/process state for one execution.
- `cap.Service` becomes typed `ContainerCapability` installers instead of a generic file-only control plane.
- `ControlFile` / `FieldFile` become a narrow debug mount under `/.omni`, not the primary public API.

### High-Level Components

```text
+---------------------------+
| OmniAIAgent Session       |
| tools / prompts / loop    |
+-------------+-------------+
              |
              v
+---------------------------+
| ContainerExecutionEnv     |
| ExecutionEnvironment      |
| adapter in OmniAIAgent    |
+-------------+-------------+
              |
              v
+---------------------------+        +----------------------+
| ContainerInstance actor   |<------>| ImageStore actor     |
| cwd/env/process list      |        | rootfs cache/checks  |
+-------------+-------------+        +----------------------+
              |
              v
+---------------------------+
| NamespaceActor            |
| bind / unbind / clone     |
+-------------+-------------+
              |
              v
+---------------------------+
| NamespaceSnapshot         |
| OmniVFS backends          |
| Mem / Disk / Map / Union  |
| Cow / Pipe / Debug        |
+-------+-------------+-----+
        |             |
        | ELF/sh      | WASI
        v             v
+---------------+   +----------------+
| BlinkRuntime  |   | WASIRuntime    |
| OmniBlinkInterop  | WasmKitWASI    |
+-------+-------+   +--------+-------+
        |                    |
        v                    v
     CBlink            WasmKit + WASI
```

### Swift Protocol Surface

The new runtime should be organized around a small set of explicit protocols:

- `public protocol VFSFileSystem: Sendable`
  - Synchronous filesystem surface used by blink and WasmKit bridges.
  - Core operations: `open`, `stat`, `lstat`, `readDirectory`, `createDirectory`, `remove`, `rename`, `symlink`, `readlink`.
- `public protocol VFSHandle: AnyObject, Sendable`
  - Thread-safe open handle abstraction.
  - Core operations: `read`, `write`, `pread`, `pwrite`, `seek`, `truncate`, `flush`, `close`.
- `public protocol ContainerRuntime: Sendable`
  - Runtime adapter for one binary class.
  - Core operations: `canExecute(_:)` and `execute(_:)`.
- `public protocol ContainerCapability: Sendable`
  - Explicit authority to install a mount, volume, or network permission into a container namespace.
- `public protocol DerivedExecutionEnvironment: ExecutionEnvironment`
  - Additive protocol for creating a scoped environment with a different working directory.
  - `LocalExecutionEnvironment` and `ContainerExecutionEnvironment` should conform so subagents and worktrees preserve the selected backend.

The existing `ExecutionEnvironment` protocol stays where it is in `OmniAIAgent`. `ContainerExecutionEnvironment` is an adapter target/user of `OmniContainer`, not a dependency of it.

### Actor Boundaries

- `ImageStore` actor
  - Owns Alpine image metadata, download/extract state, and checksum verification.
  - Ensures concurrent sessions do not re-download or re-extract the same base image.
- `ContainerManager` actor
  - Owns the registry of running/stopped containers and persistent storage roots.
  - Allocates container IDs and serializes create/destroy operations.
- `ContainerInstance` actor
  - Owns mutable container state: guest cwd, env vars, capabilities, namespace root, running exec handles, persistence policy.
  - Produces one `ExecSession` per `execCommand`.
- `NamespaceActor`
  - Owns bind/unbind/mount order mutation.
  - Emits immutable `NamespaceSnapshot` values for runtimes.
- `BlinkBridgeState` and `WASISnapshotBridge`
  - Not actors.
  - Short-lived, synchronous bridge objects used during one exec.
  - Internal `final class @unchecked Sendable` with explicit locks is acceptable here because C callbacks and WASI hooks cannot `await`.

### Namespace Model

Each container mounts a root namespace roughly like this:

```text
/                      -> CopyOnWriteFileSystem(base: Alpine rootfs, overlay: container overlay)
/workspace             -> Host bind or persistent project volume
/tmp                   -> MemFileSystem
/home/omni             -> Persistent volume (optional)
/.omni                 -> MapFileSystem(debug files only)
```

`NamespaceActor.clone()` should behave like Wanix task namespace cloning: each `ExecSession` gets a snapshot it can mutate locally for that exec without mutating the container-wide mount table. This is how temporary binds, working-directory overrides, and WASI preopen shaping stay isolated.

`CopyOnWriteFileSystem` should persist whiteouts and rename chains in a hidden metadata directory inside the overlay, similar to Wanix `cowfs`:

- `.wh/deletes/<sha1>` stores tombstoned paths.
- `.wh/renames/<sha1>` stores rename source/destination pairs.

### Path Translation Rules

`ExecutionEnvironment.workingDirectory()` is already used by prompt builders, project-doc discovery, and skill loading with host `FileManager` APIs. Because of that, `ContainerExecutionEnvironment` should preserve the host workspace path as its reported working directory and maintain an internal guest mapping:

- Host cwd: `/Users/.../swift-omnikit`
- Guest cwd: `/workspace`

File and exec APIs must accept both forms:

- Host absolute paths under the bound workspace map to guest `/workspace/...`.
- Guest absolute paths (for example `/etc/os-release`) remain guest paths.
- Relative paths resolve against the current host workspace root, then map into the guest namespace.

`platform()` should report the guest platform (`linux`) because commands execute in Linux userland. `osVersion()` should report the guest distro first, then the host in parentheses, for example: `Alpine Linux 3.20 (host: Darwin 26.0.0)`.

### SPM Target Graph

The new package graph should stay acyclic and platform-aware:

```text
OmniAIAgent
├─ OmniAICore
├─ OmniMCP
└─ OmniContainer               [macOS/Linux only]
   ├─ OmniVFS
   ├─ OmniBlinkInterop         [macOS/Linux only]
   │  └─ CBlink
   ├─ SystemPackage
   └─ WasmKitWASI / WASI       [compat fork or pinned revision]

OmniAICode
└─ OmniAIAgent

OmniAIAttractor
└─ OmniAIAgent
```

Recommended target additions:

- New library targets:
  - `OmniVFS`
  - `OmniContainer`
  - `OmniBlinkInterop`
- New C target:
  - `CBlink`
- New test targets:
  - `OmniVFSTests`
  - `OmniContainerTests`

Important package constraints:

- `OmniContainer`, `OmniBlinkInterop`, and `CBlink` must be conditionally depended on from `OmniAIAgent` only for `.macOS` and `.linux` so iOS/tvOS/watchOS/visionOS builds remain unaffected.
- `Package.swift` needs a direct `swift-system` dependency because the WasmKit bridge uses `SystemPackage.FileDescriptor`.
- WasmKit upstream currently requires newer package/platform settings than this repository. The sprint must therefore either:
  - pin a compatible fork/revision, or
  - gate the WasmKit-backed path behind a compile-time feature while still shipping the VFS/container core.

### WasmKit WASI Filesystem Bridging

There are two bridging layers to plan for:

1. **Preferred direct bridge**
   - Implement `OmniWASIFileSystem`, `OmniWASIDirectory`, and `OmniWASIFile`.
   - These types wrap a `NamespaceSnapshot` and `VFSHandle`s directly.
   - Preopens map guest paths such as `/`, `/workspace`, and `/tmp` to container namespace paths.
   - `WASIRuntime` creates `WASIBridgeToHost`, links it to a WasmKit `Store`, then calls `start(_:)`.

2. **Sprint-safe fallback bridge**
   - Snapshot the relevant namespace subtrees into WasmKit `MemoryFileSystem`.
   - Run the module with ordered preopens and pipe-backed stdio.
   - Diff the mutated memory tree back into the container overlay after execution.

The direct bridge is architecturally correct, but the current WasmKit `WASI` sources keep the relevant filesystem extension points package-internal. That means Sprint 005 should budget one of these approaches explicitly:

- maintain a small compatibility fork exposing the filesystem bridge types needed for direct OmniVFS-backed WASI, or
- ship the snapshot/write-back path first and keep the direct bridge behind a follow-up feature flag.

For the sprint draft, the implementation should assume the fallback path is always available so the runtime is not blocked on the upstream visibility issue.

### blink C Interop

blink is CLI-first, so the integration should not try to call `main()` from Swift. Instead, add a narrow C shim that turns blink into a library-style runtime for this package:

```text
Swift BlinkRuntime
   |
   | retained opaque context pointer
   v
omni_blink_run(...)
   |
   +-- initialize blink runtime state
   +-- register omni_vfs_system (custom VfsOps)
   +-- mount container root at /
   +-- set exec hook for binfmt dispatch
   +-- run initial program (/bin/sh -lc ...)
```

The shim should expose a small API surface from `CBlink`:

- `omni_blink_run`
- `omni_blink_cancel`
- `omni_blink_last_error`
- `omni_blink_register_vfs`

The custom `VfsOps` table should forward the operations required for Alpine shell execution:

- path ops: `Open`, `Access`, `Stat`, `Readlink`, `Mkdir`, `Unlink`, `Rename`, `Symlink`
- file ops: `Read`, `Write`, `Pread`, `Pwrite`, `Seek`, `Ftruncate`, `Fsync`, `Close`, `Dup`
- dir ops: `Opendir`, `Readdir`, `Closedir`
- process/pipe ops: `Pipe`, `Pipe2`
- socket ops: `Socket`, `Connect`, `Sendmsg`, `Recvmsg`
  - gated by `ContainerCapability.network`

The C bridge should store an opaque Swift-owned context pointer in the mount/device state, and every callback should round-trip through exported Swift symbols using plain C ABI types. The bridge state holds a locked table of `UInt64 -> any VFSHandle` so blink file descriptors can map to Swift handle instances for the lifetime of one exec.

### binfmt-Style WASI Escape

Apptron’s most useful idea for this sprint is not the browser-specific plumbing, but the runtime escape hatch: some binaries should not stay inside the emulated Linux process.

The dispatch path should be:

```text
execCommand("tool.wasm --help")
  -> BlinkRuntime starts /bin/sh -lc ...
  -> guest shell issues execve("tool.wasm", ...)
  -> blink exec hook probes file header via NamespaceSnapshot
       - 0x7F 'E' 'L' 'F'  -> continue through blink LoadProgram
       - 0x00 'a' 's' 'm' -> suspend/terminate current guest image load
                              and invoke WASIRuntime with same argv/env/cwd/stdio
       - "#!"             -> let shell/interpreter resolution continue normally
```

This is the cleanest way to keep one command surface while supporting two execution engines. The hook does not need a general Linux `binfmt_misc` clone; it only needs to classify the next executable image before blink loads it.

## Implementation

### Phase 0: Package Graph + Compatibility Spikes (~10% of effort)

**Files:**

- `Package.swift` — add new targets, package dependencies, and conditional platform dependencies
- `Sources/CBlink/include/module.modulemap` — expose the narrow blink shim module to Swift
- `Sources/CBlink/include/omni_blink_shim.h` — public C shim header
- `Sources/CBlink/omni_blink_shim.c` — library-style blink entrypoint and VFS registration glue
- `Sources/CBlink/vendor/blink/` — vendored blink sources/headers plus committed config header
- `Sources/OmniContainer/Compatibility/WasmKitCompatibility.swift` — compile-time guards and bridge capability checks

**Tasks:**

- [ ] Add `OmniVFS`, `OmniContainer`, `OmniBlinkInterop`, and `CBlink` targets, plus `OmniVFSTests` and `OmniContainerTests`
- [ ] Add direct `swift-system` dependency and conditional macOS/Linux dependency edges from `OmniAIAgent` to `OmniContainer`
- [ ] Vendor the blink source subset needed by the shim and commit a checked-in config header for supported hosts
- [ ] Confirm whether a WasmKit compatibility fork/pinned revision is required; if yes, wire the package to that revision before Phase 3 starts
- [ ] Add feature flags so the package still builds on unsupported platforms even when container targets are absent

### Phase 1: OmniVFS Core (~25% of effort)

**Files:**

- `Sources/OmniVFS/VFSPath.swift` — normalized path representation and helpers
- `Sources/OmniVFS/VFSMetadata.swift` — metadata and directory entry types
- `Sources/OmniVFS/VFSFileSystem.swift` — `VFSFileSystem` protocol
- `Sources/OmniVFS/VFSHandle.swift` — `VFSHandle` protocol
- `Sources/OmniVFS/Namespace/BindMode.swift` — before/after/replace bind semantics
- `Sources/OmniVFS/Namespace/NamespaceActor.swift` — bind/unbind/clone owner
- `Sources/OmniVFS/Namespace/NamespaceSnapshot.swift` — immutable runtime-facing mount table
- `Sources/OmniVFS/Backends/MemFileSystem.swift` — in-memory FS
- `Sources/OmniVFS/Backends/DiskFileSystem.swift` — host disk-backed FS for bind mounts and persistence
- `Sources/OmniVFS/Backends/MapFileSystem.swift` — map-backed synthetic tree
- `Sources/OmniVFS/Backends/UnionFileSystem.swift` — ordered union mount view
- `Sources/OmniVFS/Backends/CopyOnWriteFileSystem.swift` — base + overlay + whiteouts
- `Sources/OmniVFS/Backends/PipeFileSystem.swift` — stdio and IPC pipes
- `Sources/OmniVFS/Debug/ComputedFileSystem.swift` — debug-only computed/control files under `/.omni`
- `Tests/OmniVFSTests/NamespaceTests.swift`
- `Tests/OmniVFSTests/UnionFileSystemTests.swift`
- `Tests/OmniVFSTests/CopyOnWriteFileSystemTests.swift`
- `Tests/OmniVFSTests/PipeFileSystemTests.swift`

**Tasks:**

- [ ] Implement synchronous, thread-safe VFS protocols usable from C and WASI callbacks
- [ ] Implement Wanix-style namespace bind ordering and namespace cloning through `NamespaceActor`
- [ ] Implement union directory synthesis so multiple mounts appear as one logical directory
- [ ] Implement copy-on-write whiteouts and rename persistence in the overlay metadata directory
- [ ] Add a narrow computed/debug mount (`/.omni`) instead of exposing control files as the primary API
- [ ] Cover bind/unbind, clone isolation, symlink resolution, union ordering, and copy-on-write behavior with unit tests

### Phase 2: Container Lifecycle + Images (~20% of effort)

**Files:**

- `Sources/OmniContainer/ContainerID.swift` — stable IDs for containers and images
- `Sources/OmniContainer/ContainerSpec.swift` — image, mounts, env, cwd, persistence, runtime options
- `Sources/OmniContainer/ContainerCapabilities.swift` — capability model for mounts and network
- `Sources/OmniContainer/ContainerExecRequest.swift` — one exec invocation
- `Sources/OmniContainer/ContainerExecResult.swift` — runtime-neutral process result
- `Sources/OmniContainer/ContainerManager.swift` — registry actor
- `Sources/OmniContainer/ContainerInstance.swift` — per-container actor
- `Sources/OmniContainer/ExecSession.swift` — per-exec namespace/stdio/process state
- `Sources/OmniContainer/ImageStore.swift` — image download, cache, checksum verification, extraction
- `Sources/OmniContainer/BinaryProbe.swift` — ELF / WASI / script detection
- `Sources/OmniContainer/Mounts/ContainerCapability.swift` — capability protocol
- `Sources/OmniContainer/Mounts/WorkspaceMountCapability.swift`
- `Sources/OmniContainer/Mounts/PersistentVolumeCapability.swift`
- `Sources/OmniContainer/Mounts/TmpfsCapability.swift`
- `Sources/OmniContainer/Mounts/DebugMountCapability.swift`
- `Tests/OmniContainerTests/ContainerLifecycleTests.swift`
- `Tests/OmniContainerTests/ImageStoreTests.swift`

**Tasks:**

- [ ] Define `ContainerSpec` so the runtime can be constructed without any `OmniAIAgent` dependency
- [ ] Implement `ImageStore` actor with workspace-scoped cache layout under `.omni/containers`
- [ ] Fetch and checksum-verify Alpine minirootfs archives before extraction
- [ ] Create a root namespace using `CopyOnWriteFileSystem(base: imageRoot, overlay: containerOverlay)`
- [ ] Install workspace, tmpfs, and debug mounts through typed capabilities
- [ ] Clone the namespace per `ExecSession`, mirroring Wanix task namespace semantics
- [ ] Support container persistence modes: ephemeral, overlay-persistent, and named-volume

### Phase 3: WasmKit Runtime (~15% of effort)

**Files:**

- `Sources/OmniContainer/Runtimes/ContainerRuntime.swift` — shared runtime protocol
- `Sources/OmniContainer/Runtimes/WASIRuntime.swift` — WasmKit-backed runtime adapter
- `Sources/OmniContainer/Runtimes/WASISnapshotBridge.swift` — snapshot/write-back bridge for `MemoryFileSystem`
- `Sources/OmniContainer/Runtimes/WASIStdio.swift` — pipe-backed stdio helpers
- `Sources/OmniContainer/Runtimes/WASIPreopenMap.swift` — guest path preopen mapping
- `Tests/OmniContainerTests/WASIRuntimeTests.swift`

**Tasks:**

- [ ] Detect WASI executables by magic bytes and route them to `WASIRuntime`
- [ ] Implement the guaranteed-available bridge path using WasmKit `MemoryFileSystem`
- [ ] Snapshot `/`, `/workspace`, and `/tmp` preopens into the memory bridge and diff writes back into the container overlay
- [ ] Wire pipe-backed stdin/stdout/stderr using `SystemPackage.FileDescriptor`
- [ ] Link WASI host imports to WasmKit and call `_start` via `WASIBridgeToHost.start(_:)`
- [ ] If the compatibility fork is ready, add the direct `OmniWASIFileSystem` path behind the same `WASIRuntime`
- [ ] Cover relative path resolution, stdio capture, and write-back behavior with tests

### Phase 4: blink Runtime + C Interop (~20% of effort)

**Files:**

- `Sources/OmniBlinkInterop/BlinkRuntime.swift` — Swift runtime wrapper
- `Sources/OmniBlinkInterop/BlinkBridgeState.swift` — locked handle table and callback context
- `Sources/OmniBlinkInterop/BlinkExecHook.swift` — binfmt dispatch hook
- `Sources/OmniBlinkInterop/BlinkProcessIO.swift` — stdio/cancellation bridge
- `Sources/CBlink/include/omni_blink_shim.h` — shim function declarations
- `Sources/CBlink/omni_blink_shim.c` — runtime setup, VFS registration, exec hook
- `Sources/CBlink/vendor/blink/` — vendored C sources and headers
- `Tests/OmniContainerTests/BlinkRuntimeTests.swift`

**Tasks:**

- [ ] Expose a library-style `omni_blink_run` API instead of invoking `main()`
- [ ] Register a custom blink `VfsSystem` backed by `NamespaceSnapshot`
- [ ] Implement the `VfsOps` surface required by Alpine shell execution and copy-on-write overlays
- [ ] Gate socket operations behind `ContainerCapability.network`
- [ ] Patch or wrap blink’s exec path so `.wasm` binaries escape to `WASIRuntime`
- [ ] Add cancellation and timeout wiring so `ExecutionEnvironment.execCommand(timeoutMs:)` can terminate the guest process tree cleanly
- [ ] Keep a host-materialized `BLINK_OVERLAYS` fallback path for the first end-to-end slice if the custom `VfsOps` surface is still incomplete
- [ ] Validate `/bin/busybox echo hello`, `/bin/sh -lc`, and an `apk add` flow (network-enabled test only)

### Phase 5: OmniAIAgent Adapter + CLI Integration (~10% of effort)

**Files:**

- `Sources/OmniAIAgent/Execution/ExecutionBackend.swift` — local vs container backend selection
- `Sources/OmniAIAgent/Execution/ContainerExecutionEnvironment.swift` — adapter implementing `ExecutionEnvironment`
- `Sources/OmniAIAgent/Execution/LocalExecutionEnvironment.swift` — conform to `DerivedExecutionEnvironment`
- `Sources/OmniAIAgent/CodingAgent.swift` — backend-aware environment factory
- `Sources/OmniAICode/main.swift` — CLI flags for backend/image/persistence/network
- `Sources/OmniAIAttractor/Handlers/CodingAgentBackend.swift` — backend injection
- `Sources/OmniAIAgent/Subagents/SubAgentTools.swift` — preserve backend in subagents
- `Sources/OmniAIAgent/Subagents/WorktreeIsolation.swift` — preserve backend for worktree children
- `Tests/OmniAIAgentTests/ContainerExecutionEnvironmentTests.swift`

**Tasks:**

- [ ] Add an `ExecutionBackend` configuration surface without breaking existing callers
- [ ] Implement `ContainerExecutionEnvironment` as an actor-backed adapter over `ContainerInstance`
- [ ] Preserve host-path `workingDirectory()` semantics while translating host paths to guest `/workspace` internally
- [ ] Implement `readFile`, `writeFile`, `listDirectory`, `grep`, and `glob` directly over OmniVFS instead of shelling out
- [ ] Return guest platform metadata in prompts without breaking project-doc and skill discovery
- [ ] Add CLI/backend flags to `OmniAICode` and backend selection in Attractor
- [ ] Ensure subagents and worktrees preserve the selected execution backend instead of silently dropping back to local execution

## Files Summary

| File | Action | Purpose |
|------|--------|---------|
| `Package.swift` | Modify | Add targets, dependencies, and conditional platform edges |
| `Sources/OmniVFS/VFSFileSystem.swift` | Create | Core VFS protocol |
| `Sources/OmniVFS/VFSHandle.swift` | Create | Open file handle protocol for runtime bridges |
| `Sources/OmniVFS/Namespace/NamespaceActor.swift` | Create | Mutable mount table owner |
| `Sources/OmniVFS/Namespace/NamespaceSnapshot.swift` | Create | Immutable runtime-facing namespace |
| `Sources/OmniVFS/Backends/MemFileSystem.swift` | Create | In-memory filesystem |
| `Sources/OmniVFS/Backends/DiskFileSystem.swift` | Create | Host disk-backed bind mount backend |
| `Sources/OmniVFS/Backends/MapFileSystem.swift` | Create | Synthetic directory tree backend |
| `Sources/OmniVFS/Backends/UnionFileSystem.swift` | Create | Ordered union mount backend |
| `Sources/OmniVFS/Backends/CopyOnWriteFileSystem.swift` | Create | Rootfs overlay implementation |
| `Sources/OmniVFS/Backends/PipeFileSystem.swift` | Create | Pipe-backed stdio/backend IPC |
| `Sources/OmniContainer/ContainerSpec.swift` | Create | Container configuration model |
| `Sources/OmniContainer/ContainerManager.swift` | Create | Container registry actor |
| `Sources/OmniContainer/ContainerInstance.swift` | Create | Per-container lifecycle actor |
| `Sources/OmniContainer/ImageStore.swift` | Create | Alpine image cache and extraction |
| `Sources/OmniContainer/BinaryProbe.swift` | Create | ELF/WASI/script dispatch |
| `Sources/OmniContainer/Runtimes/WASIRuntime.swift` | Create | WasmKit-backed runtime |
| `Sources/OmniContainer/Runtimes/WASISnapshotBridge.swift` | Create | Snapshot/write-back WASI FS bridge |
| `Sources/OmniBlinkInterop/BlinkRuntime.swift` | Create | Swift wrapper over the blink shim |
| `Sources/OmniBlinkInterop/BlinkBridgeState.swift` | Create | Locked C callback context and handle table |
| `Sources/CBlink/include/omni_blink_shim.h` | Create | C ABI exposed to Swift |
| `Sources/CBlink/omni_blink_shim.c` | Create | Library-style blink entrypoint and exec hook |
| `Sources/CBlink/vendor/blink/` | Create | Vendored blink sources/config |
| `Sources/OmniAIAgent/Execution/ExecutionBackend.swift` | Create | Environment backend selection surface |
| `Sources/OmniAIAgent/Execution/ContainerExecutionEnvironment.swift` | Create | Agent-facing adapter over the container runtime |
| `Sources/OmniAIAgent/CodingAgent.swift` | Modify | Build sessions with local or container backends |
| `Sources/OmniAICode/main.swift` | Modify | Expose container flags and runtime options |
| `Sources/OmniAIAttractor/Handlers/CodingAgentBackend.swift` | Modify | Allow container backend in Attractor |
| `Sources/OmniAIAgent/Subagents/SubAgentTools.swift` | Modify | Preserve backend for subagents |
| `Sources/OmniAIAgent/Subagents/WorktreeIsolation.swift` | Modify | Preserve backend in isolated worktrees |
| `Tests/OmniVFSTests/*` | Create | VFS unit coverage |
| `Tests/OmniContainerTests/*` | Create | Container/runtime integration coverage |
| `Tests/OmniAIAgentTests/ContainerExecutionEnvironmentTests.swift` | Create | Agent integration coverage |

## Definition of Done

- [ ] `OmniVFS`, `OmniContainer`, `OmniBlinkInterop`, and `CBlink` compile on macOS and Linux
- [ ] Existing non-container `OmniAIAgent` flows still build and run with `LocalExecutionEnvironment`
- [ ] `ContainerExecutionEnvironment` conforms to `ExecutionEnvironment` without breaking existing callers
- [ ] Namespace bind ordering, cloning, union semantics, whiteouts, and symlink resolution are covered by unit tests
- [ ] A container can boot from Alpine rootfs, run `/bin/sh -lc "echo hello"` through blink, and capture stdout/stderr
- [ ] A WASI binary can run through WasmKit with access to `/workspace` and `/tmp`
- [ ] A `.wasm` executable invoked from the Linux shell path is dispatched through the binfmt-style runtime escape
- [ ] Container overlay persistence survives stop/start when enabled
- [ ] `OmniAICode` can select the container backend through flags/configuration
- [ ] Tests for new targets pass, and existing `OmniAIAgentTests` do not regress

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| WasmKit direct filesystem bridging is blocked by package-internal APIs | High | High | Treat snapshot/write-back bridge as the guaranteed Sprint 005 path and isolate direct bridge work behind a compatibility fork or feature flag |
| Vendoring blink into SwiftPM is more complex than expected because upstream assumes `configure` + GNU Make | High | High | Commit a generated config header, narrow the shim ABI, and keep a `BLINK_OVERLAYS` materialization fallback for the first vertical slice |
| Host/guest path confusion breaks prompt generation or project-doc discovery | Medium | High | Keep `workingDirectory()` host-facing, translate paths internally, and test both host and guest absolute paths |
| Synchronous runtime callbacks violate Swift concurrency assumptions | Medium | High | Confine synchronous bridges to short-lived locked objects and keep all orchestration/lifecycle state actor-isolated |
| `apk add` requires networking and may widen sandbox scope too early | Medium | Medium | Gate sockets behind an explicit network capability and run the network-enabled integration test only when requested |
| Overlay write-back from snapshot-based WASI bridge loses edge cases | Medium | Medium | Limit Sprint 005 to regular files/directories/symlinks, document unsupported cases, and keep the direct bridge path planned for follow-up |
| Conditional target dependencies accidentally break Apple non-macOS builds | Medium | High | Use platform-conditioned dependencies in `Package.swift` and keep container-specific files guarded with `#if os(macOS) || os(Linux)` |

## Security Considerations

- Host mounts must be capability-driven and explicit. The default container should only see its rootfs, `/workspace`, `/tmp`, and `/.omni`.
- Network access must be denied by default. `apk add` and any outbound sockets require explicit capability enablement in `ContainerSpec`.
- Alpine rootfs downloads must be checksum-verified before extraction, and extracted caches must live in a package-owned directory (`.omni/containers`) rather than arbitrary host paths.
- The blink shim must not expose raw host file descriptors or unrestricted hostfs mounts to guest code except through explicitly installed capabilities.
- The WASI snapshot bridge must only materialize requested preopens, not the entire host workspace tree.
- Timeout and cancellation handling must terminate guest processes and flush/close pipe handles to avoid zombie state in the host process.

## Dependencies

- Existing `ExecutionEnvironment` abstraction in `Sources/OmniAIAgent/Execution/ExecutionEnvironment.swift`
- Existing `LocalExecutionEnvironment` behavior as the compatibility baseline
- Wanix semantics for namespace binding, copy-on-write layering, and per-task namespace cloning
- Apptron-inspired layering and runtime escape patterns
- A pinned WasmKit revision or compatibility fork that is acceptable for this package’s Swift/tools/platform matrix
- Vendored blink sources/configuration or a reproducible import strategy for building the shim
- Alpine minirootfs source URL plus checksum metadata

## Open Questions

1. Should Sprint 005 require a WasmKit compatibility fork up front, or is the snapshot/write-back WASI bridge acceptable as the shipped implementation?
2. Is `workingDirectory()` staying host-facing the right long-term contract, or should a future sprint split host and guest working-directory metadata explicitly?
3. Do we want the first persistent storage root to be workspace-local (`.omni/containers`) or user-cache-global (`~/Library/Caches` / `$XDG_CACHE_HOME`)?
4. Is the host-materialized blink fallback acceptable for the first Alpine vertical slice if the custom `VfsOps` path is not stable in time?
5. How much socket support do we actually need for Sprint 005: outbound-only for `apk`, or a broader Linux socket surface?
6. Should the `/.omni` debug mount expose Wanix-style control files in Sprint 005, or stay read-only and introspective until the API surface settles?
