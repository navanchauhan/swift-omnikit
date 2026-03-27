# Sprint 007 Merge Notes

## Inputs

- `docs/sprints/drafts/SPRINT-007-INTENT.md`
- `docs/sprints/drafts/SPRINT-007-CLAUDE-DRAFT.md`
- `docs/sprints/drafts/SPRINT-007-CLAUDE-CRITIQUE.md`
- `docs/sprints/drafts/SPRINT-007-CODEX-DRAFT.md`
- `docs/sprints/drafts/SPRINT-007-CODEX-CRITIQUE.md`
- `docs/sprints/drafts/SPRINT-007-GEMINI-DRAFT.md`
- `docs/sprints/SPRINT-007.md` (initial repo-grounded draft used as baseline during critique/merge)
- `docs/sprints/drafts/SPRINT-007-GEMINI-CRITIQUE.md`

## Model Run Notes

- Codex run completed successfully with `gpt-5.4` and `model_reasoning_effort="xhigh"`.
- Gemini run completed successfully with `gemini-3.1-pro-preview-customtools`.
- Claude Opus completed successfully on retry, but only after switching to a tool-enabled `--bare --no-session-persistence` invocation with an explicit single-session/no-Agent instruction. Earlier tool-enabled retries hung in an internal loop without emitting a usable draft.
- The previously-missing Claude and Codex cross-critique artifacts were generated afterward as `SPRINT-007-CLAUDE-CRITIQUE.md` and `SPRINT-007-CODEX-CRITIQUE.md`.

### Claude draft strengths

- Best concrete migration detail for carrying Sprint 006 forward with a backward-compatible scoped session key.
- Strong push to keep raw task-level tools operational as a fallback even after mission-level orchestration becomes the default.
- Useful default stance that sensitive approvals and blocking questions originating in shared chats should route to private DM delivery unless a workspace explicitly opts into in-channel handling.
- Clear file-level mapping for `InteractionRequest`/`InteractionResponse`, `MissionReconciler`, and `RootSupervisor` style recovery work.

## Strongest Draft Contributions

### Codex draft strengths

- Best articulation of the mission-runtime layer above Sprint 006’s task fabric.
- Strongest treatment of mission lineage, supervision, and artifact transport as first-class concerns.
- Good explanation of Attractor placement as a worker-side structured workflow engine rather than the root runtime.
- Clear repo-aware file/module targeting without inventing a separate architecture.

### Gemini draft strengths

- Best concise narrative for why the root must remain the only user-facing persona.
- Good emphasis on identity/workspace isolation as a foundational concern.
- Clean summary of Telegram ingress, root-brokered approvals, and recursive delegation.
- Useful simplification pressure against overcomplicating phase structure.

### Baseline draft strengths

- Most execution-ready phased plan.
- Best durable-domain and state-root mapping.
- Strongest file summary and definition-of-done coverage.
- Best explicit mapping between ingress, missions, workers, and storage.

## Critiques Accepted

- Remove false precision from phase effort percentages.
- Add explicit Telegram transport edge cases:
  - long-response chunking / fallback delivery
  - callback-query/webhook acknowledgement decoupled from mission-state transitions
  - unsupported media handling policy
- Add explicit Sprint 006 local-state migration proof to the plan and Definition of Done.
- Add workspace budget/rate-limit policy, not just identity isolation.
- Add bounded-recursion failure proof to the Definition of Done.
- Add artifact size/retention and large-output transport constraints to the plan.
- Add backward-compatible scoped session-key migration detail instead of leaving the Sprint 006 session transition hand-wavy.
- Keep raw task-level orchestration as a documented fallback alongside the new mission-level default.
- Make private-DM delivery the default for sensitive approvals originating from shared chats, while leaving in-channel exceptions as a policy question.
- Add an explicit per-scope runtime/session ownership layer instead of assuming scoped store keys alone solve concurrent root-session isolation.
- Add mention-gated group handling and a DM-bootstrap fallback path for approvals that must reroute out of shared chats.
- Take a firmer position that code-change mission stages should reuse `ChangeCoordinator`, while leaving the exact handoff API as the remaining open question.

## Critiques Rejected or Softened

- Do not collapse the ingress work back into a purely monolithic `TheAgentControlPlane` namespace by default. Keeping explicit ingress/Telegram modules is worth the boundary clarity as long as target sprawl stays controlled.
- Do not demote Attractor to a vague “optional later” integration. It should stay in Sprint 007 as a defined worker execution mode, but not as the default path for atomic tasks.
- Do not treat serialized `SessionScope` as the whole runtime-isolation story. Keep it as a storage/migration tactic paired with explicit runtime ownership.
- Do not let shared-chat approval reroute assume a DM channel always exists. Missing DM bootstrap must be handled explicitly.

## Final Merge Direction

- Keep the baseline Sprint 007 document as the execution spine.
- Fold in Claude’s scoped-session migration detail, task-level fallback stance, and default-DM approval routing rule.
- Fold in Codex’s mission-runtime framing and Attractor placement nuance.
- Fold in Gemini’s succinct chief-of-staff and isolation framing.
- Fold in the new critique deltas around runtime/session registry, mention-gated group handling, DM bootstrap fallback, and `ChangeCoordinator` reuse.
- Carry forward the newly accepted edge cases and DoD proofs into the final sprint.
