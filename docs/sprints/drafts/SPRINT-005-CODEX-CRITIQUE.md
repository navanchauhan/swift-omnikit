# Sprint Draft Critique: SPRINT-005 (Codex Perspective)

## Overall

`SPRINT-005-CLAUDE-DRAFT.md` is the stronger starting point because it surfaces more of the real architectural seams and gives a much better test/risk picture. `SPRINT-005-GEMINI-DRAFT.md` is a useful outline, but it is still too abstract to run as the primary sprint plan for a greenfield subsystem this large.

Both drafts miss a few repo-specific realities from the current codebase:

- `ExecutionEnvironment` in `Sources/OmniAIAgent/Execution/ExecutionEnvironment.swift` is larger than read/write/list/exec. It also requires `grep`, `glob`, `initialize`, `cleanup`, `workingDirectory`, `platform`, and `osVersion`.
- Existing call sites treat `execCommand` as a shell-string interface, not an argv interface. Current code uses pipes and shell wrappers in places like `Sources/OmniAIAgent/Loop/Session.swift`, `Sources/OmniAIAgent/Subagents/WorktreeIsolation.swift`, `Sources/OmniAIAgent/Tools/CodexParityTools.swift`, and `Sources/OmniAIAgent/Tools/GeminiParityTools.swift`.
- The intent explicitly requires `MapFS`, and neither draft includes it.
- The package currently declares Apple-platform support in `Package.swift` for macOS, iOS, tvOS, watchOS, and visionOS. Any new container/blink targets need an explicit platform-guard strategy so the rest of the package does not regress.
- The intent requires `apk` install through blink and persistence across container restarts. Neither draft fully reconciles that with network restrictions, offline tests, and restart semantics.

## SPRINT-005-CLAUDE-DRAFT.md

### Strengths

- The phase breakdown is concrete enough to estimate and sequence work, which matters for a subsystem that spans new targets, new protocols, C interop, and integration tests.
- It is the only draft that seriously confronts the dependency-direction problem around `ExecutionEnvironment` ownership instead of pretending `ContainerExecutionEnvironment` can just be dropped into the existing tree without consequences.
- The test inventory is substantially stronger than Gemini's. It covers unit tests, integration tests, and some fallback strategies instead of only describing the happy path.
- It captures the important architectural fact that the container backend has to integrate through the current `ExecutionEnvironment` contract rather than inventing a parallel abstraction.
- It is also much better on risk articulation: blink vendoring, WasmKit compatibility, and sprint-size risk are all identified as first-class issues.

### Weaknesses

- It over-specifies unproven external seams. The custom `blink_exec` callback table and the direct WasmKit VFS adapter are written as if they already exist, but the intent itself still lists both as open questions. Those should be treated as feasibility spikes, not settled architecture.
- It leans heavily on `NSLock`, `DispatchQueue`, and `DispatchWorkItem`. That is out of step with this repo's explicit guidance to prefer modern Swift concurrency and avoid old-style GCD where possible.
- It quietly expands the sprint by proposing protocol extraction out of `OmniAIAgent` and possibly a new layering split. That may be the right long-term shape, but it is a separate refactor and needs to be called out as such.
- It omits `MapFS`, which is part of the intent's success criteria.
- It adds a `script` fallback through `/bin/sh` inside the container. That is plausible, but it is not in the intent and it changes the implementation surface materially.
- Even though the risk section says the sprint may need to split, the body still reads like one large end-to-end delivery. The plan needs a harder gate between "vertical slice" and "full runtime."

### Gaps in risk analysis

- The biggest missing risk is shell-compatibility. `execCommand` is string-based today, and current callers rely on shell behavior such as pipes, quoting, `nohup`, and shell wrappers. A simplistic "binary plus args" parser is not a drop-in replacement.
- The WasmKit mitigation is incomplete. A source-level `#if compiler(>=6.1)` does not solve the higher-level question of whether the dependency can be added cleanly under the current `swift-tools-version: 6.0` package setup.
- The platform regression risk is underplayed. The draft proves macOS and Linux targets, but it does not say how container-specific targets stay out of unsupported Apple-platform builds declared in `Package.swift`.
- The network model is contradictory. The intent requires `apk` install through blink, while the draft's security posture disables networking. The sprint needs an explicit answer: local package fixture, controlled network-enabled integration test lane, or defer `apk` install from the success criteria.
- The draft recommends moving `ExecutionEnvironment`-related types into a lower-level module, but it does not analyze the migration impact on existing imports and call sites. This matters because `ToolError` currently lives in `Sources/OmniAIAgent/Execution/LocalExecutionEnvironment.swift` and includes tool-specific cases like `editConflict`, `patchError`, and `timeout` that do not belong naturally in `OmniVFS`.

### Missing edge cases

- Symlink resolution across bind mounts and namespace boundaries.
- Whiteout behavior when a directory exists in the lower layer and is deleted or recreated in the overlay.
- Restart behavior, not just stop/destroy behavior. The intent explicitly asks for persistence across restarts.
- `readFile(path:offset:limit:)` semantics, binary-file behavior, and `listDirectory(path:depth:)` recursion behavior.
- Full `ExecutionEnvironment` parity for `grep`, `glob`, `initialize`, `cleanup`, `workingDirectory`, `platform`, and `osVersion`.
- Architecture mismatch cases such as x86-64 Alpine rootfs on arm64 macOS and aarch64 Linux.
- `apk` bootstrapping details: DNS/CA certs, repo configuration, package signatures, and whether tests are online or fixture-backed.

### Definition of Done completeness

- This is the better DoD of the two drafts, but it is still incomplete against the intent.
- It should explicitly include `MapFS`.
- It should require full `ExecutionEnvironment` conformance, not just read/write/list/exec happy paths.
- It should require the exact integration proof from the intent: create a container from Alpine, install a package via `apk`, run a WASI binary, restart the container, and verify persisted state.
- It should add pass/fail criteria for platform support: either the new container targets are conditionally excluded from unsupported Apple platforms, or those package builds are kept green.
- It should make the phase split concrete. If blink or WasmKit feasibility fails, the draft needs to say what still counts as Sprint 005 done versus what moves to Sprint 006.

### Architectural soundness

- This is the more architecturally serious draft, but it is not execution-ready as written.
- The `OmniVFS` / `OmniContainer` split is directionally good.
- The dependency-direction analysis is valuable, but the draft needs a firm decision before implementation starts.
- The concurrency plan is not well aligned with repo conventions, and the blink/WasmKit seams are treated as implementation details instead of architectural unknowns.
- Actionable fix: add a Phase 0 spike with three explicit deliverables before the main sprint:
  - prove a minimal blink path for one static ELF binary,
  - prove whether WasmKit can mount a custom filesystem without host materialization,
  - decide where `ExecutionEnvironment` lives without dragging tool-specific errors into `OmniVFS`.

## SPRINT-005-GEMINI-DRAFT.md

### Strengths

- The structure is clean and easy to scan.
- The phase order is directionally sensible: VFS first, environment integration second, engines after that.
- It correctly identifies blink filesystem interception and WasmKit compatibility as real risks instead of burying them.
- As a merge input, its brevity is useful because it does not overcommit to speculative design too early.

### Weaknesses

- It is too high-level to be executable for a sprint of this size. There is not enough detail to estimate, sequence, or validate the work.
- It does not tie the plan tightly enough to this repo's actual interfaces and targets.
- It places `ContainerExecutionEnvironment` under `Sources/OmniAIAgent/Execution/`, which makes the dependency layering murky and pushes container-specific concerns upward into the agent module without discussing the impact.
- It omits major intent-specified primitives and behaviors: `MapFS`, `PipeFS`, namespace cloning, explicit image manager/rootfs cache design, and persistence implementation details.
- The WasmKit mitigation is technically wrong as written. `#if compiler(>=6.0)` does not address a stated 6.1 minimum.
- The blink plan says "C/system target" as if those are interchangeable. For vendored code they are not.

### Gaps in risk analysis

- It does not discuss full `ExecutionEnvironment` parity beyond three file APIs.
- It does not discuss shell compatibility, even though current `execCommand` call sites rely on shell features.
- It does not discuss the package's broader platform matrix or how to keep non-macOS/Linux products building.
- It does not discuss Alpine/image distribution, checksum verification, cache corruption handling, or test fixture strategy.
- It does not discuss the `apk` plus networking contradiction.
- It does not discuss dependency direction if `OmniContainer` needs to conform to a protocol currently owned by `OmniAIAgent`.

### Missing edge cases

- `readFile` offset/limit behavior, binary-file handling, and `listDirectory` depth semantics.
- `grep`, `glob`, `initialize`, `cleanup`, `workingDirectory`, `platform`, and `osVersion`.
- Symlink traversal, whiteouts, union precedence, bind replacement order, and concurrent namespace mutation.
- Persistence across restart, not just overlay existence.
- Rootfs architecture mismatch and cross-architecture runtime behavior.
- Test isolation for online image downloads and `apk` package installation.

### Definition of Done completeness

- Incomplete for this intent.
- It omits `MapFS`, `PipeFS`, image caching details, Linux aarch64 validation, and the exact integration workflow from the intent.
- It lacks explicit build/test commands and does not say that existing targets must remain green.
- It does not require a full `ExecutionEnvironment` conformance suite.
- As written, it would allow the sprint to "finish" with an outline implementation that still cannot replace `LocalExecutionEnvironment` in real tool flows.

### Architectural soundness

- Conceptually reasonable, but still a placeholder architecture rather than a defensible one.
- The high-level separation of VFS, container, and engines is fine.
- The unresolved dependency direction, weak concurrency story, and missing feasibility gates around blink and WasmKit make it unsafe as the primary implementation plan.
- Actionable fix: treat this draft as a merge input, not the base sprint. To become usable, it needs:
  - a concrete dependency graph,
  - a full `ExecutionEnvironment` contract matrix,
  - a rootfs/image lifecycle design,
  - explicit feasibility gates for blink and WasmKit,
  - a platform-guard strategy for the rest of the package.

## Recommendation

Use the Claude draft as the primary merge base, but trim its speculative API design and force an explicit Phase 0 feasibility gate before committing to the full sprint scope. Pull Gemini's concise phasing and readability into the merged plan, but not its current level of abstraction.
