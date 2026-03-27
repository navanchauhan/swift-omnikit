# Sprint Draft Critique: Sprint 008 (Codex)

## `SPRINT-008-CLAUDE-DRAFT.md`

### Strengths

- Best concrete position on the OmniSkills package format. Naming the manifest `omniskill.json` and treating the plain local directory as the canonical v1 format reduces scope and gives the sprint a crisp implementation target.
- Strongest compatibility story for the fragmented current skill surfaces. The draft correctly centers `.claude/commands`, Gemini `activate_skill`, shell-tool skill models, ACP, and Codergen as projections into one runtime instead of parallel systems.
- The channel-policy section is sharper than the Gemini draft and more product-ready than the first Codex pass. Pairing-first, invitation codes, onboarding as a finite state machine, and redacted doctor output are good concrete decisions.
- The supervision section is materially useful. It distinguishes worker staleness, mission idle timeout, restart bounds, and dead-letter escalation instead of treating “timeout” as one bucket.
- Reflection is scoped correctly: root-owned memory, workspace isolation, and deterministic retrieval instead of speculative worker-managed memory writes.

### Weaknesses

- It buries OmniSkills under `Sources/OmniAgentsSDK/Skills/`, which makes the skill system feel like an SDK feature rather than a repo-wide runtime subsystem. A dedicated `OmniSkills` target is a cleaner long-term ownership boundary.
- The draft is slightly too conservative on installation sources. Local-directory-first is right, but local archive support is cheap and useful enough to include without waiting for a follow-on sprint.
- It underplays attachment staging and mission-preparation seams. DeerFlow’s strongest borrowings are not only skills but also harness preparation and artifact staging, and the draft mostly keeps those implicit.
- The end-to-end execution story is good, but the file plan is less explicit than the final repo sprint style in places. A few new modules appear late in the document instead of earlier in the architecture spine.

### Missing Edge Cases

- Workspace-scoped skill version pinning during concurrent missions.
- Replay/idempotency when a skill-enabled child task is re-dispatched after a restart.
- Skill approval behavior when a worker requests a new high-privilege skill mid-mission.
- Remote worker proof that exercises the same skill through both ACP and Attractor paths.

## `SPRINT-008-GEMINI-DRAFT.md`

### Strengths

- Good high-level summary of the five major workstreams: OmniSkills, channel policy, supervision, routing, and reflection.
- Correctly identifies that the chief-of-staff contract and multi-user isolation should remain the non-negotiable product boundary.
- Keeps useful simplification pressure on the sprint so it does not become an uncontrolled platform rewrite.

### Weaknesses

- Still too abstract to execute as the main sprint document. It points at the right problem areas but does not name enough repo seams, storage changes, or compatibility boundaries.
- OmniSkills is described more as a concept than an exact runtime package. The draft does not make sufficiently concrete decisions about manifest naming, activation records, or projection targets.
- It does not say enough about legacy coexistence with `.claude/commands` and Gemini skill files.
- It under-specifies how Codergen, ACP, and Attractor all receive the same skill activation.

### Missing Edge Cases

- Scoped skill activation records surviving restart and replay.
- Pairing/onboarding behavior when a shared-chat approval must reroute to DM.
- Skill-aware model routing at task dispatch rather than only at root prompt time.
- Process-level supervision and durable dead-letter inspection.

## Conclusion

### Definitely Merge Into Final Sprint 008

- Claude’s `omniskill.json` naming and local-directory-first package stance.
- Claude’s pairing-first onboarding, doctor, and redacted admin diagnostic posture.
- Claude’s heartbeat, staleness, idle-timeout, and dead-letter framing.
- Gemini’s simplification pressure and clear chief-of-staff boundary.
- A dedicated `OmniSkills` target plus explicit mission-preparation, attachment-staging, and external supervision seams from the Codex draft.

### Reject Or Soften

- Do not bury OmniSkills entirely inside `OmniAgentsSDK`; keep it as its own repo-level runtime module and let SDK types be one projection target.
- Do not leave attachment staging implicit; make it an explicit ingress/control-plane concern.
- Do not defer all packaged installation forms; local archive support is reasonable in the same sprint, while remote registries can wait.
