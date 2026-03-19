# Sprint 005 Intent: OmniVFS + OmniContainer — Wanix-Inspired Container Runtime (blink + WasmKit)

## Seed

Integrate blink (x86-64 Linux syscall emulator) + WasmKit (Swift WASM runtime) into swift-omnikit to create a Wanix-inspired lightweight container runtime. The goal is in-memory containers with Alpine Linux support, file-backed persistence, no Docker/VMs, cross-platform (macOS + Linux). Two-tier execution: ELF binaries via blink (full Alpine compat), WASI binaries via WasmKit (near-native speed).

## Context

- `swift-omnikit` is Swift 6 (`swift-tools-version: 6.0`) with strict concurrency (`-warn-concurrency`, `-strict-concurrency=complete`, actor data race checks in debug). 25 modules, ~69K LOC.
- Existing `ExecutionEnvironment` protocol in `OmniAIAgent` abstracts filesystem ops (readFile, writeFile, execCommand, grep, glob) with `LocalExecutionEnvironment` as the concrete implementation using `FileManager`/`Process`.
- `OmniAgentsSDK` has actor-based `Session`, tool system with `@Sendable` async closures, and `ToolContext` — natural integration point for sandboxed container execution.
- No VFS or container module exists yet. This is greenfield within an established architecture.
- Reference implementations studied: Wanix (Plan 9-style VFS with per-process namespaces, cowfs, control files, capability system) and Apptron (extends Wanix with cowfs layers, IDBFS persistence, syncfs, binfmt-style WASM escape from emulated Linux).

## Recent Sprint Context

- SPRINT-001 through SPRINT-003: completed (core agent, attractor, stream timeout).
- SPRINT-004: OmniACP family + Attractor ACP backend (planned, introduces protocol/transport patterns).
- Recent commits: model cost updates, Swift safety hardening, OmniMCP extraction, SwiftUI parity audit, WebSocket/HTTP+SSE transport support.

## Relevant Codebase Areas

- `Package.swift` — module topology, dependency management, Swift 6 settings
- `Sources/OmniAIAgent/Execution/ExecutionEnvironment.swift` — protocol to implement for container backend
- `Sources/OmniAIAgent/Execution/LocalExecutionEnvironment.swift` — reference implementation (625 lines)
- `Sources/OmniAgentsSDK/Tool.swift` — tool system that would invoke container exec
- `Sources/OmniAgentsSDK/ToolContext.swift` — context passed to tools
- `references/wanix/` — VFS architecture reference (vfs/, fs/, task/, cap/)
- `references/apptron/` — container/persistence reference (boot.go, cowfs, syncfs)

## External Dependencies

- **WasmKit** (`https://github.com/swiftwasm/WasmKit`) — Swift WASM runtime, WASI Preview 1, SPM-compatible, Swift 6.1+ minimum
- **blink** (`https://github.com/jart/blink`) — x86-64 Linux syscall emulator, C11, ~221KB binary, JIT on x86-64/aarch64, 150+ Linux syscalls including fork/clone, `BLINK_OVERLAYS` for filesystem virtualization

## Constraints

- Must follow Swift 6 strict concurrency: all public types `Sendable`, mutable state actor-isolated.
- Must not regress existing `ExecutionEnvironment` consumers or `OmniAIAgent` tool flows.
- blink is C code — needs a C target or system library wrapper in the SPM package graph.
- WasmKit requires Swift 6.1+ — verify compatibility with our Swift 6.0 tools-version.
- Cross-platform: must compile and work on macOS (arm64) and Linux (x86-64, aarch64).
- Alpine rootfs (~5MB minirootfs tarball) needs a fetch/cache/extraction strategy.
- Must be embeddable — no daemon processes, no root/sudo required.

## Success Criteria

1. **OmniVFS module** — Plan 9-style namespace/bind/resolve, CowFS, MapFS, UnionFS, MemFS, DiskFS, PipeFS primitives. All protocol-based and composable.
2. **OmniContainer module** — Container lifecycle (create/start/exec/stop/destroy), image management (Alpine rootfs fetch + layer caching), two-tier execution (blink for ELF, WasmKit for WASI), binfmt-style binary detection.
3. **ContainerExecutionEnvironment** — Implements `ExecutionEnvironment` protocol, routes all file/exec ops through the container's VFS namespace.
4. **Integration test** — Create a container from Alpine base image, install a package via `apk` (through blink), run a WASI binary (through WasmKit), verify file persistence across container restarts.
5. **`swift build` passes** for all new and existing targets on macOS and Linux.

## Verification Strategy

- Reference architecture: Wanix VFS (namespace resolution, bind semantics, union directory merging) and Apptron (cowfs layering, persistence model, binfmt escape).
- Unit tests: VFS bind/resolve/unbind, CowFS read-through and write-overlay, namespace cloning, binary magic byte detection.
- Integration tests: blink executing simple Alpine ELF binary (e.g., `/bin/busybox echo hello`), WasmKit executing a WASI hello-world, container lifecycle create→exec→stop→destroy.
- Edge cases: symlink resolution across namespace boundaries, concurrent access to shared CowFS layers, blink process cleanup on container stop, WASI module with filesystem access through VFS.

## Uncertainty Assessment

- **Correctness uncertainty: Medium** — Wanix is well-studied but translating Go VFS semantics to Swift protocols requires careful design. blink embedding is uncharted in Swift.
- **Scope uncertainty: High** — This is a large new subsystem (VFS + container + two execution engines). Phasing is critical to avoid unbounded scope.
- **Architecture uncertainty: Medium** — VFS protocol design is clear from Wanix reference, but blink C interop and WasmKit WASI filesystem bridging need prototyping.

## Open Questions

1. **blink embedding strategy**: Should blink be compiled as a static C library linked via a `CBlinkEmulator` SPM system/C target, or vendored as source files? How do we intercept/redirect its filesystem syscalls to our VFS?
2. **WasmKit WASI filesystem bridge**: WasmKit's `WASIBridgeToHost` provides host filesystem access — can we substitute our VFS namespace as the WASI filesystem root? What's the customization API?
3. **Alpine rootfs distribution**: Bundle a minirootfs in the package resources? Download on first use? OCI registry pull?
4. **Scope phasing**: Should Sprint 005 focus on OmniVFS only and defer blink/WasmKit integration to Sprint 006? Or deliver a vertical slice end-to-end?
5. **blink on aarch64 macOS**: blink emulates x86-64 — Alpine x86-64 ELF binaries would run through blink's emulation on ARM Macs. Is the performance acceptable, or should we also support Alpine aarch64 rootfs with a native execution path?
6. **Control file pattern**: Should OmniVFS implement Wanix's "actions as files" pattern (FuncFile/ControlFile), or use a more conventional Swift API surface with the VFS as a data layer only?
7. **Networking**: Does Sprint 005 need any container networking (virtual interfaces, port forwarding), or is filesystem + process execution sufficient for the initial use case?
