# Sprint 006 Merge Notes

## Real Draft Inputs

- `docs/sprints/drafts/SPRINT-006-CLAUDE-DRAFT.real.md`
- `docs/sprints/drafts/SPRINT-006-CODEX-DRAFT.real.md`
- `docs/sprints/drafts/SPRINT-006-GEMINI-DRAFT.md`

The remerge uses the **real** Claude Opus and Codex drafts, not the earlier synthetic fallback drafts.

## Draft Strengths

### Claude Opus Draft

- Strongest **type-level enforcement** ideas:
  - explicit `ContextSlice`
  - `ContextFilter`
  - `FabricJob` / `FabricEnvelope` models
  - `DeployFence` as a distinct boundary
- Best articulation of **hard rule enforcement** rather than only high-level principles.
- Strongest emphasis on **compatibility-preserving migration**: root may still answer directly, workers own delegated execution, and child work is explicitly filtered.
- Best test-driven framing for Phase 1 delivery.

### Codex Draft

- Strongest **repo-specific execution plan**.
- Best reuse of existing modules:
  - `OmniAIAgent`
  - `OmniAgentsSDK`
  - `OmniACP`
  - `OmniMCP`
  - `OmniAIAttractor`
  - Sprint 005 runtime modules
- Best overall phased sequencing across the full program.
- Best persistence and deployment guidance:
  - SQLite-backed stores
  - `.ai/the-agent/` state root
  - split job / artifact / deployment stores
  - PR-only default for self-modification
- Best transport split:
  - HTTP for registration/admin/artifact metadata
  - WebSocket for long-lived worker sessions and streaming

### Gemini Draft

- Cleanest high-level topology and persistence-boundary framing.
- Useful concise statement of root/worker/deploy separation.

## Valid Critiques Accepted

1. **Codex should be the structural merge base**: Accepted. It is the most executable and most aligned with the current repository layout.
2. **Claude’s stronger type and boundary ideas should be integrated selectively**: Accepted. `ContextSlice`, explicit deploy fencing, and hard rule enforcement improve the plan materially.
3. **The final result should be one canonical mega sprint, but internally phased**: Accepted. The final doc is now one mega sprint with six execution phases instead of multiple future sprint specs.
4. **ACP must remain edge-only**: Accepted.
5. **No new transport stack by default**: Accepted. Reuse current repo HTTP/WebSocket infrastructure first.
6. **Current local subagent semantics should be preserved as compatibility shims during migration**: Accepted.
7. **PR-only should be the default first self-modification policy**: Accepted.

## Valid Critiques Rejected

1. **Claude’s `OmniFabric` rename as the canonical package/module name**: Rejected for now. The final sprint keeps the architecture-note naming (`TheAgent*`, `OmniAgent*`) as the open question rather than forcing a rename.
2. **Claude’s WebSocket-only internal mesh assumption**: Rejected. The final sprint keeps the more practical split transport shape from Codex.
3. **Treating Phase 1 only as the full Sprint 006 deliverable**: Rejected. Sprint 006 remains the mega sprint for the full program, even though it defines a narrow first shipping slice.

## Interview Refinements Applied

The user’s requirements were already explicit:

1. The root agent is the only user-facing interface across text, chat, and audio.
2. Background work should run independently and notify back through the root.
3. Workers may run on different machines and compute classes.
4. Workers may spawn child workers.
5. The system must support self-modification, automated review, scenario testing, deploy, rollback, and retry.
6. Failed deploys must not lose unrelated background tasks.

## Merge Strategy

- **Base**: real Codex draft
- **Integrated from real Claude draft**:
  - stronger context-slice and filtering language
  - stronger deploy fence / job-lifecycle separation
  - stronger compatibility-shim framing
  - stronger hard-rule language
- **Retained from Gemini**:
  - clear top-level topology
  - simple persistence-boundary framing

## Final Result

The final `docs/sprints/SPRINT-006.md` now:

- frames Sprint 006 as the **single canonical mega sprint**
- defines the implementation arc as **six internal execution phases**
- keeps Codex’s repo-specific execution order
- adds Claude’s better safety and context-boundary ideas
- keeps the user-visible root/notification model explicit
- keeps PR-only self-modification as the initial default
