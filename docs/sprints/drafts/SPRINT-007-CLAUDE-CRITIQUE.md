# Sprint 007 Draft Critique

## 1. Codex Draft

### Strengths

- **Exhaustive model catalog.** The Codex draft enumerates every new model type (`User`, `Workspace`, `Channel`, `ChannelBinding`, `Mission`, `MissionStep`, `InteractionRequest`, `ApprovalDecision`, `ArtifactReference`, `DelegationLineage`) up front. This gives implementors a clear data-model contract before writing code.
- **Principled Attractor placement.** The draft correctly positions `OmniAIAttractor` as a worker-side structured execution option rather than the global runtime, with explicit rules about when it should and should not be used. This directly satisfies the intent constraint.
- **Security section is thorough.** It covers replay/idempotency, ingress provenance, least-privilege artifact retrieval, approval attribution, and secret externalization — more ground than either of the other drafts.
- **Root-only persona enforcement.** The "root runtime contract" section is clear and disciplined: workers never talk to humans, only the root does.
- **Faithful to Sprint 006 substrate.** The document explicitly frames itself as additive to Sprint 006 stores, transport, and worker wiring rather than a competing architecture.

### Weaknesses

- **No phased implementation plan.** The nine implementation sections are flat and equal-weight. There's no sequencing, no dependency ordering, and no "shippable slice" concept. A developer reading this cannot tell what to build first, or which piece is testable independently. This is the draft's most serious flaw — the intent document demands a "phased implementation plan" and the Codex draft doesn't deliver one.
- **File summary is vague.** The files listed are mostly modifications of existing files with prose descriptions, but no new-file list is crisp. The new module areas (`Ingress/`, `Identity/`, `Missions/`) are listed at the bottom as directories without concrete filenames. Compare to the Claude draft, which provides exact file-by-file tables per phase.
- **Use cases are wordy but not concrete.** UC3 says "a worker uses `OmniAIAttractor` to run `plan -> implement -> validate`" but never says which DOT graph or how the task brief signals Attractor execution. UC7 describes approval routing but doesn't specify whether it applies in DMs, groups, or both.
- **Open questions are nearly identical to the intent document.** All 8 open questions are restated from the intent document's open questions without the draft offering any opinion or recommended default. A good draft should narrow uncertainty, not echo it.
- **Definition-of-done lacks measurable criteria.** Items like "recursive delegation remains functional" and "the sprint lands as an additive evolution" are subjective. There's no mention of Swift 6 strict concurrency compliance, no mention of zero-warning compilation, no concrete depth/fan-out defaults.

### Gaps in Risk Analysis

- **No risk for schema migration breakage.** The draft adds 10+ new model types and retrofits `workspace_id` into existing stores, but doesn't mention backward-compatibility concerns with existing `sessionID`-based schemas — a risk the Claude draft correctly flags as High/High.
- **No risk for Telegram rate limiting.** Multi-user Telegram usage will hit Bot API rate limits; not addressed.
- **No risk for mission plan quality.** The root model generates mission plans from natural language — the plans could be nonsensical or under-decomposed. Not acknowledged.
- **No risk for approval deadlocks.** A worker waiting indefinitely for a human approval that's never answered.

### Missing Edge Cases

- Telegram duplicate/replay messages (the security section mentions idempotency keys but the implementation doesn't wire them)
- `MissionCoordinator` vs. existing `ChangeCoordinator` boundary — what happens when a mission step is a code-change flow that `ChangeCoordinator` already handles?
- Telegram group mention parsing — how does the bot know when it's being addressed in a noisy group?
- Artifact size limits — no mention of large binary artifacts crashing in-memory transport

### Definition-of-Done Completeness

**Incomplete.** Missing: Swift 6 strict concurrency compliance, concrete numeric defaults for delegation bounds, store isolation provability (e.g., fuzz tests), specific Telegram features supported (DMs vs. groups), and any performance/latency baseline.

---

## 2. Gemini Draft

### Strengths

- **Concise and well-structured.** At roughly half the length of the Codex draft, it covers the same territory more efficiently. The use of tables for risks is clean.
- **Phased implementation.** Three clear phases (Identity/Ingress → Chief-of-Staff → Workers/Attractor) give a buildable sequence. Phase 1 is independently shippable and testable.
- **Practical Telegram noise mitigation.** Explicitly calls out `@botname` mention-parsing for group routing, which neither the Codex draft nor the intent document addresses.
- **Approval deadlock risk.** The Gemini draft is the only one to call out the scenario where a user never responds to an approval request, and proposes timeout-based resolution.
- **Artifact payload size risk.** Correctly flags that fetching large binaries could crash the control plane and proposes streaming/size limits.
- **Swift 6 strict concurrency in DoD.** Explicitly requires zero-warning compilation.

### Weaknesses

- **Thin on new model types.** The draft mentions only `Identity.swift` for Users and Workspaces. There's no `MissionRecord`, `MissionStep`, `InteractionRequest`, `InteractionResponse`, `ApprovalDecision`, `DelegationLineage`, or `ArtifactReference` type definition. The data model is implicit rather than explicit, which makes it harder to validate completeness.
- **Attractor integration is underspecified.** Phase 3 says "Integrate `PipelineEngine` into `WorkerExecutorFactory`" but doesn't describe how the task brief signals Attractor execution, how `WaitHumanHandler` bridges to the interaction broker, or how pipeline artifacts are mirrored to the mesh. There's no mention of `MeshBridgedInterviewer` or any bridging abstraction.
- **File summary is incomplete.** Only 5 new files listed, with no test files for mission coordination, interaction brokering, Attractor bridging, delegation policy, or end-to-end scenarios. A sprint this size needs at minimum 10-15 new test files.
- **No restart/recovery design.** The Codex and Claude drafts both describe explicit recovery mechanisms (mission reconciler, pending interaction replay, worker reconnect). The Gemini draft has no recovery section and no recovery-related DoD item.
- **Identity model is underspecified.** It says "retrofitted with `workspace_id` and `user_id` dimensions" but doesn't describe a `Channel` concept, `ChannelBinding`, or `SessionScope`. Without channels, Telegram group vs. DM vs. topic routing has no clean model, and shared-workspace conversation isolation is undefined.
- **No `ChangeCoordinator` integration mentioned.** The existing `ChangeCoordinator` handles code change flows. The mission coordinator will need to interop with it, but this boundary is not discussed.
- **Open questions are again nearly verbatim from the intent.** Same critique as Codex — the draft should narrow uncertainty, not mirror it.

### Gaps in Risk Analysis

- **No schema migration risk.** Same gap as Codex.
- **No mission plan quality risk.** Same gap.
- **No Telegram rate limit risk.**
- **No recovery failure risk.** The draft doesn't discuss restart scenarios at all, so naturally doesn't risk-assess them.
- **No risk around `InteractionBroker` being a single point of failure.** If the broker drops or misroutes a message, the user/worker handshake breaks silently.

### Missing Edge Cases

- Telegram long-poll duplicate message handling (`update_id` tracking)
- Interaction request timeout configuration (the approval timeout is mentioned in risks but not in the implementation or DoD)
- Workspace auto-creation from Telegram group joins
- Child task artifact visibility when the parent mission spans multiple workers
- What happens when a worker emits an `InteractionRequest` but the user's Telegram session is unreachable?

### Definition-of-Done Completeness

**Partial.** Covers the happy path (Telegram works, Attractor works, recursion bounded, Swift 6 clean) but missing: restart/recovery verification, interaction broker round-trip, cross-machine artifact visibility, workspace isolation proof, pending interaction durability, and end-to-end scenario test.

---

## 3. Claude Draft (for reference comparison)

The Claude draft was also provided. Brief assessment for comparison:

### Strengths

- **Most implementation-ready.** Per-phase file tables with exact filenames, Create/Modify annotations, and concrete task checklists with `[ ]` items. A developer could start coding from this document immediately.
- **Concrete `SessionScope` design.** Specifies serialization format (`"\(userID):\(workspaceID):\(channelID)"`), backward-compatibility strategy, and migration approach. Neither Codex nor Gemini provides this.
- **`MeshBridgedInterviewer` is explicitly designed.** The Claude draft defines how Attractor's `Interviewer` protocol bridges to the interaction broker — the most important Attractor integration detail, and the one the Gemini draft omits entirely.
- **Best risk table.** Likelihood/Impact ratings, concrete mitigations for each, and schema migration flagged as High/High.
- **`ChangeCoordinator` boundary addressed.** Open Question 7 explicitly asks how `MissionCoordinator` and `ChangeCoordinator` relate, with a recommended approach (delegation, not replacement).
- **Artifact push strategy analyzed.** Eager vs. lazy, with a concrete size-threshold recommendation (10 MB).

### Weaknesses

- **Very long.** At ~420 lines it risks becoming the spec nobody reads end-to-end.
- **Phase 2 Telegram is long-poll only.** Webhook support deferred, which is fine for dev but limits production deployment.
- **`MissionPlan` is model-generated.** Relies on the root LLM to produce structured plans from natural language, which is inherently fragile. The draft mentions this risk but the mitigation (plan templates) is vague.
- **No explicit idempotency mechanism for ingress.** The Codex draft mentions idempotency keys; the Claude draft mentions `update_id` tracking but doesn't generalize it to the `IngressTransport` protocol.

---

## Concluding Recommendations

### Ideas That Should Definitely Be Merged Into Final Sprint 007

1. **Claude's phased implementation structure with per-file task tables.** This is the most actionable format. The final sprint should use 4-5 ordered phases with explicit file/task checklists. The Codex and Gemini drafts' flat or 3-phase structures are insufficient for a sprint of this scope.

2. **Codex's exhaustive model catalog.** The 11 new model types (`User`, `Workspace`, `Channel`, `ChannelBinding`, `Membership`, `Mission`, `MissionStep`, `InteractionRequest`, `ApprovalDecision`, `ArtifactReference`, `DelegationLineage`) should appear in the final spec's architecture section so the data model is reviewable before implementation starts.

3. **Gemini's `@botname` group mention parsing.** This is a real-world Telegram UX concern that the other drafts overlook. The final spec should mandate mention-gated group handling.

4. **Gemini's approval deadlock timeout and artifact size-limit risks.** These are concrete production failure modes. The final spec should include both in the risk table with mitigations wired into the implementation phases.

5. **Claude's `MeshBridgedInterviewer` design.** This is the critical integration point between `OmniAIAttractor` human gates and the root interaction broker. It must be in the final spec with enough detail to implement: the `Interviewer` protocol conformance, the `InteractionRequest` emission, and the response wait mechanism.

6. **Claude's `SessionScope` backward-compatible serialization.** The existing codebase uses flat `sessionID` strings everywhere. A concrete migration strategy must be in the final spec to avoid breaking Sprint 006 stores.

7. **Claude's `ChangeCoordinator` boundary recommendation.** `MissionCoordinator` should delegate to `ChangeCoordinator` for code-change steps, not replace it. This preserves existing Sprint 006 investment.

8. **Codex's security section breadth.** Replay protection, idempotency keys, secret externalization, least-privilege artifact access, and approval attribution should all appear in the final security section.

9. **Restart/recovery as a first-class concern** (from both Codex and Claude). The Gemini draft's omission of recovery is disqualifying for that section — the final spec must include mission checkpoint replay, pending interaction re-delivery, and orphan mission reconciliation.

10. **Swift 6 strict concurrency zero-warning DoD item** (from Gemini). This belongs in the final DoD as a hard gate.

### Ideas That Should Be Rejected or Softened

1. **Codex's flat implementation structure.** Nine equal-weight, unordered implementation sections with no phasing is unacceptable for a sprint this large. Reject in favor of Claude's phased approach.

2. **Gemini's underspecified Attractor integration.** "Integrate `PipelineEngine` into `WorkerExecutorFactory`" without describing the bridging abstraction, task-brief signaling, or artifact mirroring is too thin. Reject and replace with Claude's Phase 4 Attractor design.

3. **Gemini's missing `Channel` concept.** A two-dimensional identity model (`user_id`, `workspace_id`) without channels cannot support Telegram group topics or multi-thread workspace conversations. Reject and use the three-dimensional model (`UserID`, `WorkspaceID`, `ChannelID`) from Claude/Codex.

4. **Codex's open questions as-is.** All 8 are restated from the intent document. The final spec should either resolve each question with a recommended default or explicitly defer it with a stated fallback. Echoing the intent's uncertainty is not useful.

5. **All three drafts' tendency to echo the intent's open questions verbatim.** The final sprint must take a position. Recommended defaults: (a) DMs-first with groups as a fast-follow within the sprint; (b) shared-chat approvals route to private DM by default; (c) `maxDepth=5`, `maxFanOut=10`, default timeout 1 hour; (d) mission plan visible to root prompt, interaction queue hidden; (e) HTTP API ingress deferred to Sprint 008; (f) Attractor triggered by `attractor-pipeline` capability tag in task brief.

6. **Gemini's 5-file new-file list.** Woefully inadequate for this sprint's scope. The final spec should have ~20-25 new files (closer to Claude's list) plus ~15 modified files.

7. **Codex's module-level-only new directories** (`Ingress/`, `Identity/`, `Missions/`). Listing directories without concrete filenames prevents review. Replace with per-file listings.
