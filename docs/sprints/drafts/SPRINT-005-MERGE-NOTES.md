# Sprint 005 Merge Notes

## Draft Strengths

### Claude Draft
- Best VFS protocol hierarchy — granular Plan 9-style protocols (VFS, VFSReadDirFS, VFSStatFS, VFSResolveFS, VFSMutableFS) with clear Wanix mapping
- Strongest concurrency architecture — explicit struct vs class vs actor decisions for each type, sync VFS to avoid reentrancy
- Most detailed C interop strategy — `blink_fs_callbacks_t` with `@convention(c)` thunks and VFSBridgeContext fd table
- Best test inventory — per-primitive unit tests + integration tests + guard checks per phase
- Correctly identified ExecutionEnvironment dependency direction problem

### Codex Draft
- Best integration architecture — keeps ExecutionEnvironment in place, adapter pattern for ContainerExecutionEnvironment
- Best path translation design — host cwd / guest cwd mapping with dual-path acceptance
- Best binfmt-style WASI escape design — detailed exec hook dispatch path from inside blink shell
- Most realistic WasmKit assessment — identified package-internal filesystem APIs as the real blocker, planned snapshot/write-back fallback
- Best agent integration phase — covered subagents, worktrees, CLI flags, Attractor backend injection
- Strongest DerivedExecutionEnvironment concept for subagent/worktree preservation

### Gemini Draft
- Clean, readable structure — good high-level overview for orientation
- Correctly identified the top 3 risks
- Conservative scope kept focus clear

## Valid Critiques Accepted

1. **Claude critique of Gemini**: Gemini draft too underspecified for implementation — accepted. Missing namespace cloning, binfmt dispatch, persistence, capabilities, path translation, PipeFS, MapFS.
2. **Claude critique of Codex**: Socket ops in VfsOps table is scope creep — REJECTED by user (user wants basic outbound networking for apk). DerivedExecutionEnvironment is premature — partially accepted, defer the protocol but implement the scoped-cwd method.
3. **Codex critique of Claude**: Over-specifies unproven C interop seams — accepted. Treat blink callback table as a future phase, start with BLINK_OVERLAYS per user decision. NSLock/DispatchQueue usage out of step with repo conventions — noted but unavoidable for synchronous C callbacks.
4. **Codex critique of Claude**: Missing MapFS — accepted, must include.
5. **Codex critique of both**: Shell compatibility for execCommand is a real risk — accepted. Current callers rely on shell behavior (pipes, quoting, nohup). Container adapter must support shell-string execution through blink's /bin/sh.
6. **Codex critique of both**: Phase 0 feasibility spike needed — accepted. Add explicit spike phase before committing to full scope.
7. **Gemini critique of Claude**: Protocol relocation causes unnecessary churn — accepted. User chose new micro-module OmniExecution instead.
8. **Gemini critique of Claude**: 1MB hardcoded stdout/stderr buffers will truncate — accepted. Use PipeFS-backed streaming instead of fixed buffers.
9. **Gemini critique of Codex**: WASI snapshot/write-back fallback is inefficient — noted but keeping it as the pragmatic Sprint 005 path. Direct VFS adapter behind WasmKit fork as follow-up.
10. **All critiques**: Missing resource limits for MemFS/CowFS — accepted, add configurable memory caps.

## Valid Critiques Rejected

1. **Gemini critique**: Reject the WASI snapshot fallback entirely — rejected. WasmKit's filesystem APIs are package-internal. The snapshot path is the guaranteed Sprint 005 delivery. Direct bridge requires a fork that may not be ready.
2. **Claude critique**: Remove socket ops entirely — rejected by user. User wants basic outbound networking for apk install, gated behind capability.
3. **Codex draft**: DerivedExecutionEnvironment as a protocol — deferred. Add scoped-cwd as a method on concrete types for Sprint 005.

## Interview Refinements Applied

1. **Scope**: Full vertical slice with phase gates for early exit
2. **ExecutionEnvironment**: New micro-module `OmniExecution` — protocol + value types (ExecResult, DirEntry, GrepOptions) live there. Both OmniAIAgent and OmniContainer depend on it.
3. **Blink strategy**: BLINK_OVERLAYS first (materialize VFS to temp dir). Custom VFS callbacks deferred to follow-up.
4. **Networking**: Basic outbound TCP/DNS for apk install, gated behind ContainerCapability.network. Integration test for `apk add` is in-scope.

## Merge Strategy

- **Base**: Claude draft (strongest VFS design, concurrency architecture, test coverage)
- **Integrate from Codex**: Path translation rules, binfmt escape design, agent integration phase, NamespaceActor→NamespaceSnapshot pattern, platform conditioning strategy, shell-string execCommand handling
- **Integrate from Gemini**: Cleaner ASCII diagrams, actor reentrancy as named risk
- **Modify per critiques**: Add Phase 0 spike, add MapFS, add resource limits, use BLINK_OVERLAYS instead of custom callbacks, use OmniExecution micro-module, add streaming stdout/stderr, add Alpine version pinning, rebalance effort estimates (blink = 30%), add performance baseline to DoD
