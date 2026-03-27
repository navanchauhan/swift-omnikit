# Sprint Draft Critique: Sprint 008 (Gemini)

## `SPRINT-008-CODEX-DRAFT.md`

### Strengths

- Strongest repo alignment. It names the real control-plane, worker, Attractor, provider, and SDK seams instead of describing a generic agent platform.
- Best treatment of OmniSkills as a projection system rather than a second plugin framework.
- Clear definition-of-done coverage for live proof, remote worker behavior, and workspace-scoped skill isolation.
- Good inclusion of attachment staging, doctor, and supervision as product features rather than vague future work.

### Weaknesses

- The first pass is broad enough to risk phase slippage if the team treats every file in the summary as equal priority.
- The separate supervisor executable is defensible, but it increases operational scope; it should remain later-phase work, not block OmniSkills core.
- The package format and installation sources need sharper constraints so the sprint does not drift into registry/distribution design.

## `SPRINT-008-CLAUDE-DRAFT.md`

### Strengths

- Best concrete decisions on manifest naming (`omniskill.json`), pairing-first defaults, and root-only reflection authority.
- Strong operational clarity around invitation codes, redacted diagnostics, and dead-letter behavior.
- Stronger than the Codex draft on limiting v1 scope and avoiding hosted registry work too early.

### Weaknesses

- Puts OmniSkills under `OmniAgentsSDK`, which weakens ownership clarity because skills affect far more than shell-tool environments.
- Less explicit than the Codex draft about attachment staging, mission-preparation, and the repo’s final sprint file layout.
- The live-proof and migration requirements are present but less forceful than they should be for a mega sprint.

## Conclusion

### Definitely Merge Into Final Sprint 008

- Codex’s implementation spine, file plan, and live-proof bar.
- Claude’s `omniskill.json` naming, local-first package stance, and stricter reflection/security posture.
- Keep supervisor and routing work, but order them after OmniSkills core and compatibility bridges.
- Preserve the chief-of-staff contract and multi-user workspace isolation as the organizing principle for every phase.

### Reject Or Soften

- Do not let OmniSkills live only inside `OmniAgentsSDK`.
- Do not make remote skill registries or rich admin UIs part of Sprint 008.
- Do not overfit channel policy into Telegram-only abstractions; keep the policy layer transport-neutral even if Telegram is the first concrete surface.
