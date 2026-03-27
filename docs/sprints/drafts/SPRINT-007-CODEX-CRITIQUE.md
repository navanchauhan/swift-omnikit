# Sprint Draft Critique: Sprint 007 (Codex)

## `SPRINT-007-CLAUDE-DRAFT.md`

### Strengths

- This is the more execution-ready draft. It maps work onto real repo seams: `RootAgentServer`, `RootAgentRuntime`, `RootAgentToolbox`, `JobStore`, `ConversationStore`, `HTTPMeshServer`/`HTTPMeshClient`, `LocalTaskExecutor`, and `ChildWorkerManager`.
- It correctly recognizes the current mismatch between Sprint 006's task fabric and the desired mission runtime. The discussion of raw task tools vs mission orchestration matches the current `delegate_task` / `wait_for_task` toolbox in `Sources/TheAgentControlPlane/RootAgentToolbox.swift`.
- It places `OmniAIAttractor` in the right part of the system: worker-side structured execution, not the universal root runtime.
- Its DoD and risk sections are materially stronger than Gemini's. Restart recovery, Telegram duplicate-update handling, artifact transport, and approval routing are all called out.

### Weaknesses

- The biggest repo seam is still under-specified: `RootAgentRuntime` and `RootAgentServer` are single-session objects today, backed by one `Session`, one `RootConversation`, and one `NotificationInbox`. Adding `SessionScope` to store rows is not enough; the sprint needs a runtime/session registry or another explicit per-channel session ownership model.
- It creates a large new mission stack (`MissionCoordinator`, `MissionReconciler`, mission tools) without deciding how it coexists with `Sources/TheAgentControlPlane/Changes/ChangeCoordinator.swift`, which already owns implement/review/scenario orchestration.
- Treating serialized `SessionScope` as the replacement for today's `sessionID` / `rootSessionID` semantics is too loose. `TaskRecord.rootSessionID` currently means root ownership, not tenant identity or channel routing.
- `RootSupervisor` feels like scope creep for Sprint 007's first vertical slice.

### Gaps In Risk Analysis

- No explicit migration risk for existing Sprint 006 `.ai/the-agent/` state and the current single `root` session.
- No explicit risk around mission replay creating duplicate child tasks or duplicate side effects after restart/re-plan.
- No explicit Telegram DM bootstrap risk: approval reroute to a private DM fails if the user never started the bot in DM.

### Missing Edge Cases

- Two active chats hitting one control-plane process while one root `Session` is already mid-turn.
- The same user active in both DM and group/topic channels inside one workspace: what is workspace-scoped vs channel-scoped?
- Worker-side `Interviewer.inform(...)` style notices, not just blocking approval/question flows.
- Metadata-only artifact publication when the producing worker later goes offline.

### Definition-Of-Done Completeness

- A migration proof from Sprint 006 state to the new scoped schema.
- A proof that per-scope root sessions cannot cross-talk under concurrent ingress load.
- An explicit rule for when `ChangeCoordinator` is reused vs bypassed.
- A delivery fallback for approvals that cannot be sent via Telegram DM.

## `SPRINT-007-GEMINI-DRAFT.md`

### Strengths

- It is directionally correct on the big architectural choices: root as sole persona, transport-agnostic ingress, worker-side Attractor execution, recursive delegation, and remote artifact visibility.
- The draft stays reasonably close to existing top-level modules instead of inventing a second architecture.
- Its risk section usefully calls out shared-group noise, approval deadlocks, workspace leakage, and large artifact payloads.

### Weaknesses

- It is too abstract to execute as the main sprint document. Important repo seams are missing from the plan: `TaskEvent`, `ConversationModels`, `HTTPMeshProtocol`, `RootConversation`, `NotificationInbox`, and the existing task-tool surface in `RootAgentToolbox`.
- It puts recursion and budget enforcement in `RootScheduler`, but durable child delegation currently happens in `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift`. That is the stronger enforcement point.
- It frames Attractor integration mostly as `WorkerExecutorFactory` work, but real execution currently flows through `LocalTaskExecutor` inside `WorkerDaemon`.
- It omits `ChangeCoordinator`, even though this repo already has an implement/review/scenario path that Sprint 007 should either reuse or explicitly supersede.
- It talks about remote artifacts and mission orchestration without enough concrete model/store/protocol work to support them.

### Gaps In Risk Analysis

- No migration risk for existing Sprint 006 state.
- No multi-session runtime ownership risk for `RootAgentRuntime`.
- No restart/replay/idempotency risk for approvals or mission recovery.
- No Telegram-specific delivery constraints beyond group noise.

### Missing Edge Cases

- Parallel conversations from different chats sharing one root process.
- Topic-aware routing vs plain group routing.
- Approval delivery when the user has no DM thread with the bot.
- Artifact fetch failure when the producing worker is unreachable.
- Compatibility of existing `delegate_task` / `wait_for_task` flows after mission orchestration lands.

### Definition-Of-Done Completeness

- Store/schema migration from Sprint 006.
- Topic-aware Telegram routing and approval return-paths.
- Restart recovery for missions and pending approvals.
- Mesh-level artifact round-trip tests.
- Child depth/fan-out enforcement in `ChildWorkerManager`.
- Preservation of the current task-level toolbox alongside mission mode.

## Conclusion

### Definitely Merge Into Final Sprint 007

- Claude's phased, file-level execution plan.
- Claude's stronger DoD, restart/recovery coverage, remote artifact protocol, and Telegram `update_id` durability.
- Gemini's simpler statement that `OmniAIAttractor` is an optional worker execution path, not the universal runtime.
- Gemini's group-noise mitigation and approval-timeout concerns.
- One missing repo-specific item from both drafts: explicit per-scope runtime/session ownership around `RootAgentRuntime`, plus a clear reuse boundary for `ChangeCoordinator`.

### Reject Or Soften

- Claude's use of serialized `SessionScope` as the full answer to every current `sessionID` / `rootSessionID` use. Keep it as a migration/storage tactic, not the whole domain model.
- Claude's `RootSupervisor` unless the sprint scope is intentionally expanded.
- Gemini's placement of recursion policy in `RootScheduler`; hard limits belong in `ChildWorkerManager` and child-lineage code.
- Gemini's implication that core `PipelineEngine` changes are the main integration path; prefer adapter code around `Interviewer`, `LocalTaskExecutor`, and mesh transport first.
- Any assumption in either draft that Telegram DM reroute is always available.