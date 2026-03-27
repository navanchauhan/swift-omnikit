# Sprint 008 Merge Notes

## Inputs

- `docs/sprints/drafts/SPRINT-008-INTENT.md`
- `docs/sprints/drafts/SPRINT-008-CLAUDE-DRAFT.md`
- `docs/sprints/drafts/SPRINT-008-CLAUDE-CRITIQUE.md`
- `docs/sprints/drafts/SPRINT-008-CODEX-DRAFT.md`
- `docs/sprints/drafts/SPRINT-008-CODEX-CRITIQUE.md`
- `docs/sprints/drafts/SPRINT-008-GEMINI-DRAFT.md`
- `docs/sprints/drafts/SPRINT-008-GEMINI-CRITIQUE.md`
- `docs/sprints/SPRINT-008.md`
- `docs/sprints/SPRINT-007.md`
- wiki notes:
  - `swift-omnikit-reference-comparison-2026-03-24`
  - `swift-omnikit-agent-fabric-mega-sprint-merge-2026-03-24`

## Model Run Notes

- Gemini draft completed successfully and provided the initial high-level framing for OmniSkills, channel policy, supervision, routing, and reflection.
- Claude Opus eventually completed successfully with tools still enabled, but only after a constrained read-only print-mode invocation. Broad tool-enabled prompt runs hung for a long time without emitting a file. The successful pattern was `--bare --no-session-persistence --tools default --allowedTools Read` plus an explicit “no agents / no plan mode / read only the specified files” instruction.
- The earlier `codex exec` run spent too much time exploring the repo instead of drafting. The final Codex draft was then written directly in the repo-grounded planning pass to preserve xhigh-style specificity and keep the document aligned with the project’s sprint-file conventions.

## Strongest Draft Contributions

### Claude draft strengths

- Best concrete manifest decision: `omniskill.json` as the canonical OmniSkills manifest name.
- Strongest pairing-first, onboarding, and redacted doctor posture.
- Best runtime discipline details around stale workers, idle timeout, and dead-letter behavior.
- Best simplification of reflection authority: root-owned memory synthesis, no direct worker memory writes.

### Codex draft strengths

- Best execution spine and repo file targeting.
- Strongest articulation of OmniSkills as a dedicated runtime module that projects into root, workers, ACP, Attractor, and shell-tool environments.
- Best treatment of mission-preparation, attachment staging, live proof, and external supervision.
- Strongest definition of done for remote worker and skill propagation proofs.

### Gemini draft strengths

- Best concise summary of the product goal: one user-facing chief-of-staff agent with internal workers and recursive delegation.
- Good simplification pressure against turning Sprint 008 into a total architecture rewrite.
- Useful framing that OmniSkills, channel policy, supervision, routing, and reflection are the five primary workstreams.

## Critiques Accepted

- Rename the canonical manifest from generic `skill.json` to `omniskill.json`.
- Keep a dedicated `OmniSkills` runtime module instead of burying the entire feature under `OmniAgentsSDK`.
- Treat the plain local directory as the canonical package format for v1, while allowing local archive support; defer hosted registries.
- Make legacy `.claude/commands` and Gemini skill files explicit import/coexistence paths instead of assuming a clean replacement cutover.
- Keep pairing-first defaults, mention-gated shared channels, onboarding, and doctor as first-class product work in the same sprint.
- Keep attachment staging as an explicit ingress/control-plane concern rather than an implied side effect of mission execution.
- Adopt the stricter reflection posture: workers contribute artifacts and transcripts, but the root alone synthesizes memory candidates and commits memory.
- Keep the external/process-level supervision seam in the sprint, but order it after OmniSkills core and compatibility bridges so it does not block the primary runtime work.

## Critiques Rejected or Softened

- Do not collapse OmniSkills into a provider-specific or SDK-only implementation. The whole point of the sprint is unification across runtimes.
- Do not add hosted skill registries, signed distribution, or rich admin UI surfaces in Sprint 008. Local install plus archive support is enough.
- Do not let routing become a fuzzy model-chooses-model feature. Keep it deterministic and policy-driven.
- Do not let reflection become worker-authored memory writes.

## Final Merge Direction

- Keep `docs/sprints/SPRINT-008.md` as the execution spine.
- Use the Codex draft’s phase structure and file mapping as the main implementation plan.
- Fold in Claude’s `omniskill.json` naming, local-first package stance, pairing/onboarding details, dead-letter discipline, and root-only reflection authority.
- Fold in Gemini’s simplification pressure and explicit preservation of the chief-of-staff product boundary.
- Treat Sprint 008 as the productization mega sprint above Sprint 007:
  - OmniSkills core and compatibility bridges first
  - channel policy, onboarding, and doctor second
  - supervision hardening third
  - routing and reflection fourth
  - live proof and docs last
