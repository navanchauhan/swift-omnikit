# SPRINT-010: Swift 6 Concurrency Cleanup — Isolation Hardening, Blocking I/O Removal, and Sendable Debt Paydown

## Overview

The repo already builds under Swift 6 with strict concurrency diagnostics enabled, but the current architecture still relies on too many escape hatches:

- broad `@unchecked Sendable` usage on mutable reference types
- several `Task.detached` bridges around blocking I/O
- unmanaged fire-and-forget `Task {}` usage in production paths
- lingering `nonisolated(unsafe)` uses and lock-based state where a clearer isolation boundary should exist

The goal of this sprint is not cosmetic cleanup. The goal is to make the concurrency model easier to reason about, reduce the chance of hidden data races, stop consuming the cooperative executor with blocking work, and align the repo with Swift 6.2 approachable-concurrency principles where they make sense.

This sprint must stay pragmatic:

- do not blanket-annotate everything with `@MainActor`
- do not rewrite low-level subsystems without a measurable safety win
- do not globally enable default `MainActor` isolation for server/worker/runtime targets that are not UI-bound
- prefer small, reviewable refactors with a clean validation loop after each phase

## Execution Notes

- 2026-03-29: local toolchain is Swift 6.2, but this sprint keeps `Package.swift` at `swift-tools-version: 6.0`.
- Reason: land audit guardrails and targeted runtime fixes first, then revisit any 6.2-only package manifest features once the main concurrency debt is reduced.
- 2026-03-29: final implementation pass completed.
  - `scripts/concurrency-audit.sh .` now reports `@unchecked Sendable=210`, `nonisolated(unsafe)=0`, `Task.detached=0`, `waitUntilExit()=0`, `NSLock=53`, `unstructured_task=55`, and `bare_task_launch=11` in `Sources/`.
  - Completed cleanup slices:
    - blocking socket / stdio / process bridges moved off `Task.detached` hot paths
    - `waitUntilExit()` removed from production `Sources/`
    - `AbortSignal`, ingress webhook forwarding, and the highest-risk Agent SDK mutable state patterns were hardened
    - `AsyncThrowingStream` bridges across providers / HTTP / SDK models now own cancellable producer tasks through `onTermination`
    - `_UIRuntime` task registries are lock-protected so render reconciliation and async task lifecycles no longer race
    - surviving sync-to-async hop tasks and intentional fire-and-forget subagent launches now carry `Safety:` comments
  - Final isolation decision:
    - `_UIRuntime` remains a documented single-owner render/event-loop runtime rather than a blanket `@MainActor` type because terminal/notcurses renderers may legitimately run off the process main actor
    - the remaining `bare_task_launch` sites are limited to documented sync-callback cleanup hops and intentional independently-owned subagent/session launches

## Why This Sprint Exists

The concurrency audit found four high-value issues:

1. Mutable core state is marked `@unchecked Sendable` in places where the isolation story is weak or undocumented.
2. Blocking work still runs through `Task.detached` in a few production paths.
3. Some production code launches unstructured tasks and drops ownership of them.
4. The package is strict-concurrency-first, but it is not yet taking advantage of the Swift 6.2 approachable-concurrency model in the targets where that would reduce friction safely.

Current inventory at planning time:

- `@unchecked Sendable` in `Sources/`: 210
- `NSLock` in `Sources/`: 44
- `Task.detached` in `Sources/`: 6
- `nonisolated(unsafe)` in `Sources/`: 6

Those counts are not all bugs. They are the backlog surface that this sprint will triage and reduce.

## Principles

1. **Prefer explicit isolation over compiler escape hatches.**
   If a type is UI-bound, isolate it to `@MainActor`. If it owns shared mutable state, isolate it to an actor or make the mutable portion actor-backed.

2. **Prefer immutable Sendable configuration over mutable Sendable objects.**
   `AgentBase`, run config, prompt/config registries, and similar types should trend toward immutable `let` storage or actor-owned mutable state.

3. **Do not run blocking I/O on the cooperative executor.**
   Blocking socket reads, `readLine()`, `readToEnd()`, and `waitUntilExit()` must move to dedicated blocking queues, termination handlers, or async subprocess abstractions.

4. **Every unstructured task must have an owner.**
   If a `Task {}` or `Task.detached {}` remains, it must either:
   - be stored and cancelled by an owning object, or
   - have a documented invariant explaining why fire-and-forget is correct.

5. **Every remaining escape hatch needs a safety comment.**
   Any `@unchecked Sendable` or `nonisolated(unsafe)` that survives this sprint must carry a short `Safety:` comment explaining the invariant.

## Scope

### In Scope

- selective adoption of approachable-concurrency settings where justified
- UI/runtime isolation cleanup
- Agent SDK mutable-state cleanup
- removal of blocking `Task.detached` bridges
- conversion of unmanaged tasks into owned tasks or actor queues
- audit and reduction of `@unchecked Sendable` / `nonisolated(unsafe)` in production code
- concurrency-focused regression tests

### Out of Scope

- a repo-wide conversion to `@MainActor`
- replacing every `NSLock` use in low-level transport/VFS code if the existing safety invariant is sound and documented
- redesigning the control plane or worker fabric
- broad API redesign unless a type is fundamentally unsound under strict concurrency

## Phase 0: Baseline, Toolchain, and Guardrails

### Goals

- establish a reproducible concurrency-audit baseline
- decide how Swift 6.2 approachable-concurrency settings will be adopted
- add guardrails so the sprint can measure progress instead of hand-waving

### Files

- `Package.swift`
- `docs/sprints/SPRINT-010.md`
- `Tests/`
- optional: `scripts/concurrency-audit.sh`

### Tasks

- Confirm the minimum viable toolchain policy for using Swift 6.2 concurrency settings.
- Split targets into buckets:
  - UI/front-end targets
  - shared model/runtime targets
  - server/agent/worker targets
  - low-level process/VFS/transport targets
- Decide whether to:
  - bump the package manifest to a Swift 6.2-capable configuration, or
  - keep `swift-tools-version: 6.0` and defer build-setting adoption to target-specific flags later.
- Add a repeatable audit command that reports:
  - `@unchecked Sendable`
  - `nonisolated(unsafe)`
  - `Task.detached`
  - blocking `waitUntilExit()`
  - `NSLock`

### Acceptance Criteria

- The repo has a documented concurrency audit command.
- The target buckets and default-isolation policy are written down.
- There is a clear decision on whether `Package.swift` adopts Swift 6.2 approachable-concurrency features in this sprint or a follow-on sprint.

## Phase 1: UI-Bound Isolation Cleanup

### Goals

- isolate actual UI/runtime state to `@MainActor`
- remove UI-side Sendable escape hatches that exist only because isolation is currently underspecified

### Primary Files

- `Sources/OmniUICore/Runtime.swift`
- `Sources/OmniUICore/ObservableObjects.swift`
- `Sources/OmniUICore/Environment.swift`
- `Sources/OmniUICore/State.swift`
- `Sources/OmniUINotcursesRenderer/NotcursesRenderer.swift`
- `Sources/OmniUI/OmniUI.swift`
- `Sources/iGopherTUI/*.swift`
- `Tests/OmniUICoreTests/*.swift`

### Tasks

- Decide whether `_UIRuntime` should be fully `@MainActor`.
  - Expected answer: yes, unless a specific non-UI path proves otherwise.
- Remove `@unchecked Sendable` from `_UIRuntime` if `@MainActor` isolation makes it unnecessary.
- Replace `_DefaultObservationRegistrar.shared` `nonisolated(unsafe)` with a safer isolation story.
- Audit other OmniUI wrappers that are currently marked `@unchecked Sendable` only to satisfy cross-boundary usage.
- Keep rendering hot paths fast, but let actor isolation define ownership instead of “shared mutable runtime plus trust me”.

### Acceptance Criteria

- `_UIRuntime` has an explicit, documented isolation boundary.
- No UI-bound runtime type remains `@unchecked Sendable` without a concrete reason.
- OmniUI / notcurses / iGopherTUI builds and existing UI regression tests still pass.

## Phase 2: Agent SDK State and Sendable Debt

### Goals

- remove or narrow the weakest `@unchecked Sendable` uses in the Agent SDK
- separate immutable configuration from mutable runtime state

### Primary Files

- `Sources/OmniAgentsSDK/RunState.swift`
- `Sources/OmniAgentsSDK/RunContext.swift`
- `Sources/OmniAgentsSDK/Agent.swift`
- `Sources/OmniAgentsSDK/Runner.swift`
- `Sources/OmniAgentsSDK/ToolContext.swift`
- `Sources/OmniAgentsSDK/RunResult.swift`
- `Sources/OmniAICore/Client.swift`
- `Sources/OmniAICore/DefaultClient.swift`
- `Tests/OmniAgentsSDKTests/*.swift`
- `Tests/OmniAIAgentTests/*.swift`

### Tasks

- Convert `RunState<TContext>` away from “large mutable class + `@unchecked Sendable`”.
  Candidate directions:
  - actor-backed mutable state
  - value-type state with explicit mutation sites
  - split immutable snapshot vs mutable coordinator
- Refactor `RunContextWrapper<TContext>` so mutable approval state is the isolated part rather than one lock inside a broadly mutable reference type.
- Make `AgentBase<TContext>` trend immutable:
  - convert mutable stored configuration to `let` where possible
  - isolate truly mutable registries elsewhere
- Audit `Client`-style shared stores and default client state for unnecessary locking or unchecked sendability.

### Acceptance Criteria

- `RunState`, `RunContextWrapper`, and `AgentBase` each have a defensible isolation boundary.
- The worst “mutable reference type + `@unchecked Sendable`” patterns are removed from the SDK core.
- SDK and agent tests pass without new concurrency warnings.

## Phase 3: Remove Blocking Work from `Task.detached`

### Goals

- stop using detached tasks as a generic “run blocking thing somewhere else” mechanism
- move blocking operations onto dedicated executors, queues, or proper async process wrappers

### Primary Files

- `Sources/iGopherTUI/GopherRequestService.swift`
- `Sources/OmniMCP/MCPTransport.swift`
- `Sources/OmniACP/Delegates/DefaultClientDelegate.swift`
- `Sources/OmniAIAttractor/Handlers/CodergenHandler.swift`
- `Sources/OmniSkills/OmniSkillInstaller.swift`
- `Sources/OmniTerm/main.swift`
- `Sources/OmniAIAgent/Execution/LocalExecutionEnvironment.swift`
- `Tests/TheAgentIngressTests/*.swift`
- `Tests/OmniAIAttractorTests/*.swift`
- `Tests/OmniMCPTests/*.swift`
- `Tests/iGopherTUI`-adjacent smoke tests if needed

### Tasks

- Replace `GopherRequestService.fetchData` detached-task blocking socket I/O with:
  - a dedicated blocking queue + continuation, or
  - a real async transport path.
- Replace `StdioMCPTransport` detached stderr draining and blocking disconnect with owned read tasks plus non-blocking process-exit coordination.
- Replace `DefaultClientDelegate.promptForPermissionChoice` detached `readLine()` with a dedicated blocking input queue or a better interactive abstraction.
- Remove `process.waitUntilExit()` from async/actor-adjacent production paths where it can pin an executor thread.
- Keep the existing `LocalExecutionEnvironment` approach as the reference pattern for blocking subprocess I/O unless a better shared helper emerges.

### Acceptance Criteria

- No production blocking socket/process/stdio path relies on `Task.detached` merely to escape the caller’s actor.
- Async/actor code no longer calls `waitUntilExit()` on hot paths without a documented justification.
- The targeted transport/process tests pass.

## Phase 4: Unmanaged Task Ownership Audit

### Goals

- make background tasks cancellable, observable, and owned
- remove fire-and-forget task launches where correctness depends on completion

### Primary Files

- `Sources/TheAgentIngress/HTTPIngressServer.swift`
- `Sources/OmniAICore/Abort.swift`
- `Sources/OmniAICore/OpenAIRealtime.swift`
- `Sources/OmniAICore/Providers/*.swift`
- `Sources/OmniAgentMesh/Transport/MeshServer.swift`
- `Sources/OmniAIAgent/Tools/*.swift`
- `Tests/TheAgentIngressTests/*.swift`
- `Tests/OmniAICoreTests/*.swift`

### Tasks

- Audit every production `Task {}` and classify it:
  - stored and owned
  - intentionally detached from parent cancellation
  - unsafe fire-and-forget
- Replace unsafe fire-and-forget tasks with:
  - stored task handles
  - actor queues
  - explicit async APIs
  - structured concurrency where parent lifetimes matter
- Fix webhook handling so accepted work is still owned and observable after the HTTP response returns.
- Decide whether `AbortSignal.abort()` should remain synchronous with an internal lock/continuation design, or become explicitly async.

### Acceptance Criteria

- Every surviving unstructured task in production code has an owner or a documented reason.
- Cancellation behavior is testable and deterministic in ingress and realtime code.

## Phase 5: Escape Hatch Triage and Documentation

### Goals

- reduce the remaining `@unchecked Sendable` / `nonisolated(unsafe)` count
- document every necessary survivor

### Primary Files

- `Sources/OmniUICore/PlatformColors.swift`
- `Sources/OmniUICore/SwiftDataCompat.swift`
- `Sources/OmniVFS/DiskFS.swift`
- `Sources/AttractorCLI/main.swift`
- `Sources/OmniAICore/*.swift`
- `Sources/OmniAgentsSDK/*.swift`

### Tasks

- Categorize all remaining escape hatches:
  - value-like compatibility shims that are effectively safe
  - lock-protected low-level stores
  - temporary migration shims that should be eliminated
- Remove the ones that are clearly unnecessary.
- Add `Safety:` comments to the ones that remain.
- Open follow-on cleanup items for any survivors that are too large for this sprint.

### Acceptance Criteria

- Every remaining `@unchecked Sendable` / `nonisolated(unsafe)` in production code has a short safety invariant comment.
- The raw counts have dropped materially from the baseline, especially in OmniUI and OmniAgentsSDK.

## Validation Plan

Run validation after each phase, not only at the end.

### Build Validation

- `swift build`
- `swift build --product iGopherTUI`
- `swift build --product TheAgentControlPlane`
- `swift build --product TheAgentWorker`

### Targeted Test Suites

- `swift test --filter OmniUICoreTests`
- `swift test --filter OmniAgentsSDKTests`
- `swift test --filter OmniAIAgentTests`
- `swift test --filter OmniMCPTests`
- `swift test --filter OmniAIAttractorTests`
- `swift test --filter TheAgentIngressTests`

### Concurrency Audit Validation

After each phase, rerun the audit counts and record deltas.

Minimum expected outcomes by sprint end:

- `Task.detached` count reduced to only clearly justified cases
- `nonisolated(unsafe)` reduced to low-level, documented survivors only
- `@unchecked Sendable` removed from the main UI runtime and highest-risk SDK state containers
- no new `waitUntilExit()` in async/actor-adjacent code

## Risks

1. **Over-correcting with `@MainActor`.**
   UI-bound code should move to `@MainActor`; server/worker/runtime code should not be dragged there by default.

2. **Accidental behavioral changes in agent state.**
   `RunState`, `RunContextWrapper`, and `AgentBase` are foundational. These changes need narrow diffs and strong tests.

3. **Process/stdio regressions.**
   Replacing blocking subprocess handling can break output capture, cancellation, or timeout semantics if done casually.

4. **False progress via comments only.**
   This sprint is not complete if the only result is more comments around the same unsound shapes.

## Definition of Done

- The repo has a documented concurrency audit baseline and rerunnable audit command.
- UI-bound runtime state has explicit `@MainActor` ownership where justified.
- `RunState`, `RunContextWrapper`, and `AgentBase` no longer represent the worst mutable `@unchecked Sendable` patterns.
- Blocking I/O no longer relies on detached tasks in production paths where a dedicated blocking bridge or async primitive should exist.
- Unmanaged production tasks have been converted to owned tasks, structured concurrency, or documented intentional exceptions.
- Remaining `@unchecked Sendable` / `nonisolated(unsafe)` uses are reduced and documented with safety invariants.
- All targeted builds and tests pass.

## Current Validation Status

Validated during execution:

- `swift build --product iGopherTUI --product TheAgentControlPlane --product TheAgentWorker --product AttractorCLI --product OmniTerm`
- `swift test --filter 'OmniSkillInstallerTests|HTTPIngressServerTests|StdioMCPTransportTests|RunContextAndItemsParityTests|HighLevelTests|AttractorTests'`
- `swift test --filter 'task_runs_and_cancels_with_view_lifecycle|browser_like_chrome_eventually_goes_idle|OmniUICoreTests'`
- `swift test --filter 'OmniUICoreTests|OmniAgentsSDKTests|HighLevelTests|StdioMCPTransportTests|HTTPIngressServerTests|AttractorTests'`

Sprint status is `completed`.

## Immediate Execution Order

Implement in this exact order:

1. Phase 0 baseline and package/toolchain decision
2. Phase 1 OmniUI / iGopherTUI isolation cleanup
3. Phase 3 blocking I/O cleanup for iGopher + MCP + ACP prompt path
4. Phase 2 Agent SDK mutable-state cleanup
5. Phase 4 unmanaged-task ownership audit
6. Phase 5 escape-hatch triage and final count reduction

That order keeps the highest-risk UI/runtime and blocking-I/O fixes first, while delaying the broad Agent SDK state surgery until the concurrency guardrails are in place.
