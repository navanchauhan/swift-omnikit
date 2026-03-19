# Sprint 005 Draft: OmniVFS + OmniContainer

## Overview
This sprint introduces **OmniVFS**, a Plan 9-inspired Virtual File System, and **OmniContainer**, a lightweight container runtime powered by WasmKit (for WASI) and blink (for x86-64 Linux ELF binaries). The goal is to provide a robust, cross-platform (macOS/Linux), in-memory and persistent sandbox for agent-driven execution within `swift-omnikit`. This system will seamlessly integrate into the existing `ExecutionEnvironment` abstraction.

## Use Cases
- **Sandboxed Agent Tool Execution:** Provide agents with a secure, ephemeral filesystem and execution environment without relying on external Docker daemons.
- **Two-Tier Execution:** Support standard Alpine Linux tooling (via `blink`) and fast, near-native sandboxed tools (via `WasmKit` and WASI).
- **Filesystem Persistence & Versioning:** Use CowFS (Copy-On-Write) to overlay ephemeral changes over base images (e.g., an Alpine rootfs), ensuring fast container resets.

## Architecture

### OmniVFS
OmniVFS adopts a protocol-oriented architecture (similar to Go's `fs.FS` and `wanix`):
- `VFSNode`: Protocol for file/directory nodes.
- `VFSNamespace`: Protocol for a mountable filesystem.
- `OmniVFS`: The namespace manager handling Plan 9-style `bind` semantics (resolving paths, unions).
- File Systems: `MemFS` (in-memory), `CowFS` (Copy-On-Write), `UnionFS` (merged directories), `DiskFS` (mapped to local disk).

### OmniContainer
- `Container`: Represents a sandboxed execution context holding a root `OmniVFS` namespace and environment variables.
- `ContainerExecutionEnvironment`: A new implementation of the `ExecutionEnvironment` protocol that routes file I/O and process execution into the `Container`.
- `Engine`: The execution layer. Detects binary signatures (ELF vs WASM).
  - **ELF Engine:** Utilizes a vendored/SPM-wrapped `blink` to execute x86-64 Linux binaries.
  - **WASI Engine:** Utilizes `WasmKit` to run WebAssembly binaries with filesystem access mapped to `OmniVFS`.

```ascii
+-------------------------------------------------+
| OmniAIAgent Tool Context / ExecutionEnvironment |
+-------------------------------------------------+
                         |
+-------------------------------------------------+
| ContainerExecutionEnvironment                   |
+-------------------------------------------------+
      |                                |
+-----------+                    +-----------+
| OmniVFS   |                    | Execution |
+-----------+                    +-----------+
| - Bind()  |                    | - blink   |--> [ Alpine ELF ]
| - Resolve |                    | - WasmKit |--> [ WASI       ]
+-----------+                    +-----------+
      |
+--------------------------------------+
| CowFS / MemFS / DiskFS / UnionFS     |
+--------------------------------------+
```

## Implementation Phases

### Phase 1: OmniVFS Core
Define the protocol suite and basic in-memory filesystems.
- **Tasks:**
  - Define `VFSNamespace`, `VFSNode`, `VFSFile`, `VFSDirectory` protocols.
  - Implement `MemFS` (in-memory directory and file structures).
  - Implement namespace binding and path resolution (`OmniVFS` namespace).
  - Implement `UnionFS` and `CowFS` (Copy-On-Write overlays).
- **Files:**
  - `Sources/OmniVFS/Protocols.swift`
  - `Sources/OmniVFS/MemFS.swift`
  - `Sources/OmniVFS/CowFS.swift`
  - `Sources/OmniVFS/UnionFS.swift`
  - `Sources/OmniVFS/Namespace.swift`

### Phase 2: OmniContainer & Environment Integration
Bridge the VFS into the existing agent execution model and establish container lifecycle primitives.
- **Tasks:**
  - Define `Container` and `ContainerImage` structures.
  - Implement `ContainerExecutionEnvironment` conforming to `ExecutionEnvironment` (for VFS operations).
  - Create a mock `Engine` for initial process execution testing.
- **Files:**
  - `Sources/OmniContainer/Container.swift`
  - `Sources/OmniContainer/Engine.swift`
  - `Sources/OmniAIAgent/Execution/ContainerExecutionEnvironment.swift`

### Phase 3: WasmKit Integration (WASI)
Integrate WasmKit to run `.wasm` files securely within the VFS.
- **Tasks:**
  - Add `WasmKit` SPM dependency (ensure Swift 6 tools-version compatibility).
  - Implement WASI bridge mapping WasmKit's filesystem calls to `OmniVFS`.
  - Wire binary detection ("\0asm") to the WasmKit engine.
- **Files:**
  - `Sources/OmniContainer/Engines/WasmEngine.swift`
  - `Sources/OmniContainer/Engines/WASIBridge.swift`
  - `Package.swift` (update)

### Phase 4: blink Integration (ELF)
Wrap and integrate the blink emulator for x86-64 Linux execution.
- **Tasks:**
  - Add `CBlinkEmulator` as a C/system target in `Package.swift`.
  - Implement bridging from Swift to blink's C entry points.
  - Implement VFS interception for blink (hooking into `BLINK_OVERLAYS` or patching its sys_open/sys_read equivalents to route to `OmniVFS`).
  - Wire binary detection (ELF magic bytes) to the blink engine.
- **Files:**
  - `Sources/CBlinkEmulator/` (shim headers and C bridging)
  - `Sources/OmniContainer/Engines/BlinkEngine.swift`

## Definition of Done
- `OmniVFS` and `OmniContainer` modules are created and integrated into `Package.swift`.
- Comprehensive Unit Tests for `OmniVFS` (Bind, Resolve, CowFS, UnionFS).
- `ContainerExecutionEnvironment` successfully routes `readFile`, `writeFile`, `listDirectory` to the VFS.
- Integration test demonstrating a container pulling a minimal Alpine rootfs, caching it, overlaying a CowFS, and executing an ELF binary via `blink`.
- Integration test running a WASI binary via `WasmKit`.
- Full Swift 6 strict concurrency compliance (`Sendable` protocols, actor-isolated mutable state).

## Risks & Mitigations
- **Blink File System Hooking:** Intercepting blink's filesystem calls from C back into Swift's `OmniVFS` could be challenging.
  *Mitigation:* Start with `BLINK_OVERLAYS` (blink's built-in chroot/overlay feature pointing to a local host directory) if direct syscall interception is too complex for this sprint.
- **WasmKit Swift 6 Compatibility:** WasmKit requires Swift 6.1+.
  *Mitigation:* Validate build against Swift 6.0 (`swift-tools-version: 6.0`); use `#if compiler(>=6.0)` checks or fetch a compatible WasmKit branch if needed.
- **Actor Reentrancy in VFS:** VFS resolution operations crossing actor boundaries can lead to deadlocks or reentrancy issues.
  *Mitigation:* Keep core VFS state lock-free or use standard GCD concurrent queues/structs for synchronous path resolution, reserving actors only for high-level container lifecycle management.

## Security Considerations
- Ensure paths resolved in `OmniVFS` cannot escape their mount roots (prevent `../` traversal escapes).
- Limit blink memory allocation and process capabilities to prevent host resource exhaustion.
- Enforce strict `Sendable` types for anything crossing the WasmKit or blink boundary.

## Dependencies
- `WasmKit` (Swift WASM Runtime)
- `blink` (x86-64 Linux Syscall Emulator)

## Open Questions
1. **blink C Interop:** Will we vendor blink's source directly into `Sources/CBlinkEmulator` or build it externally and link a static library? Vendoring is easier for SPM distribution.
2. **Alpine Rootfs Management:** Should the initial Alpine minirootfs be downloaded at runtime or bundled into the SPM package resources? Downloading dynamically reduces package size.
3. **Execution Environment Migration:** Should `LocalExecutionEnvironment` be completely deprecated eventually, or kept as a fallback for trusted host tools?
