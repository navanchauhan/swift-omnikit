# SPRINT-005 Gemini Critique

## Claude Draft (`SPRINT-005-CLAUDE-DRAFT.md`)

### Strengths
- **VFS Protocol Hierarchy:** Extremely well-defined protocol hierarchy (`VFS`, `VFSReadDirFS`, `VFSResolveFS`, etc.) that cleanly maps Wanix concepts to Swift.
- **Concurrency Architecture:** Clear and explicit rules for actor isolation, value types (`VFSNamespace`), and lock-protected classes (`MemFS`, `CowFS`), adhering strictly to Swift 6 concurrency requirements.
- **C Interop Strategy:** The `blink_fs_callbacks_t` strategy is solid, ensuring synchronous execution without bridging to Swift's async/await pool, avoiding reentrancy deadlocks.
- **Testing & DoD:** Highly actionable, with specific `swift build` and `swift test` commands, compiler flags, and phase gates.

### Weaknesses
- **Protocol Relocation:** Proposes moving `ExecutionEnvironment` out of `OmniAIAgent` to `OmniVFS` to resolve dependency direction. This causes unnecessary churn across the codebase and breaks encapsulation.
- **Path Mapping:** Does not detail how host paths from the existing `LocalExecutionEnvironment` callers are mapped into the container's VFS (e.g., mapping host `cwd` to guest `/workspace`).
- **Memory Buffer Allocation:** Hardcodes `1_048_576` (1MB) buffers for stdout/stderr in the blink C interop, which will crash or silently truncate on large outputs.

### Gaps in Risk Analysis
- **Memory Limits:** No analysis of how unbounded writes to `MemFS` or `CowFS` overlays are constrained, risking OOM kills.
- **Signal Handling:** Doesn't consider how blink's internal signal handling might conflict with Swift's concurrency runtime or main thread.

### Missing Edge Cases
- **Symlink Escapes:** Resolving absolute symlinks inside the container (e.g., `ln -s / /tmp/root`) and ensuring they don't break out of the namespace.
- **PipeFS Blocking:** Handling of blocking reads/writes in `PipeFS` and how it interacts with container cancellation.

### Definition of Done Completeness
- Very comprehensive. Captures Swift 6 strict concurrency checks and specific tests.
- *Missing:* Validation of stream timeouts and Swift `Task` cancellation during `blink` execution.

### Architectural Soundness
- Highly sound VFS design. However, the architectural recommendation to relocate `ExecutionEnvironment` violates the intent of integrating into the existing system with minimal disruption.

---

## Codex Draft (`SPRINT-005-CODEX-DRAFT.md`)

### Strengths
- **Dependency Graph Integrity:** Correctly keeps `ExecutionEnvironment` in `OmniAIAgent` and introduces `ContainerExecutionEnvironment` as an adapter, avoiding protocol churn.
- **Path Translation:** Excellent conceptualization of path mapping (host `/Users/...` to guest `/workspace`), which is crucial for backwards compatibility with existing agents.
- **Environment Scoping:** Introduces `DerivedExecutionEnvironment` to cleanly handle subagent and worktree isolation.
- **Binfmt Escape:** The hook for WASI escape is elegantly integrated into the execution flow.

### Weaknesses
- **WASI Fallback Bridge:** The proposed "Sprint-safe fallback bridge" (snapshotting namespace subtrees into WasmKit's `MemoryFileSystem` and diffing back) is highly inefficient, complex, and breaks real-time filesystem sharing.
- **VFS Definition:** VFS protocols are too broadly defined (`VFSFileSystem`, `VFSHandle`) compared to Claude's granular Plan 9-style interfaces, potentially leading to monolithic implementations.
- **Blink Integration Details:** Glosses over the exact C interop mechanics (just an opaque `omni_blink_run`), underestimating the complexity of wiring blink's internal syscalls to Swift.

### Gaps in Risk Analysis
- **Concurrency Safety:** Less detailed on how the VFS will achieve `@unchecked Sendable` safely under heavy concurrent access compared to the Claude draft.
- **Cancellation Propagation:** Mentions cancellation but doesn't detail how a Swift `Task` cancellation propagates into the blocking C `omni_blink_run` call.

### Missing Edge Cases
- **Guest Shell Failure:** What happens if `/bin/sh` is missing from the Alpine rootfs or fails to boot?
- **Host Leakage in Glob/Grep:** If path translation isn't perfect, `glob` and `grep` might accidentally traverse the host filesystem instead of the guest.

### Definition of Done Completeness
- Good conceptual coverage but lacks the specific, actionable compilation and test commands found in the Claude draft.
- *Missing:* Explicit Swift 6 concurrency verification steps.

### Architectural Soundness
- The adapter pattern and path translation rules are architecturally superior for integrating into the existing `swift-omnikit` project.
- The WASI fallback bridge is architecturally unsound and should be avoided in favor of a direct VFS adapter, even if it requires a WasmKit fork.

---

## Synthesis & Recommendations for Final Plan

1. **Adopt Codex's Integration Architecture:** Keep `ExecutionEnvironment` in `OmniAIAgent` and use the Adapter pattern + Path Translation rules. Include `DerivedExecutionEnvironment`.
2. **Adopt Claude's VFS Design:** Use Claude's granular `VFSReadDirFS`, `VFSResolveFS`, etc., and the explicit `MemFS`/`CowFS`/`DiskFS` lock-based concurrency model.
3. **Adopt Claude's C Interop Model:** Use explicit `blink_fs_callbacks_t` rather than Codex's generic `omni_blink_run`. Fix the 1MB buffer issue by using stream-backed outputs (e.g. `PipeFS`) instead of fixed arrays.
4. **Reject the WASI Snapshot Fallback:** Do not implement Codex's snapshot/write-back bridge. Require a direct VFS-to-WASI adapter, utilizing a pinned WasmKit fork if necessary.
5. **Add Constraints to MemFS:** Explicitly define how `MemFS` handles capacity limits to avoid unbound memory usage.