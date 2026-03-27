# Sprint Draft Critique: Sprint 008 (Claude)

## `SPRINT-008-CODEX-DRAFT.md`

### Strengths

- This is the most execution-ready draft. It maps Sprint 008 onto the real repo seams that matter: `AnthropicProfile`, `GeminiParityTools`, `Tool.swift`, `CodergenHandler`, `ACPWorkerSession`, `ToolRegistry`, `MissionCoordinator`, `RootAgentRuntime`, `IngressGateway`, and the worker executors.
- The dedicated `OmniSkills` target is the right ownership boundary. Skills affect the entire runtime, not just SDK-facing shell environments, and the draft reflects that.
- The best parts of DeerFlow that are actually relevant here are kept: mission preparation, attachment staging, and packaging ergonomics. It does not try to import DeerFlow’s entire application stack.
- The sprint correctly keeps Attractor as the structured worker path rather than turning it into the root runtime.
- The live-proof requirements are stronger than the other drafts. They explicitly demand an OmniSkill affecting remote ACP or Attractor execution, not just a local happy path.

### Weaknesses

- The package-format scope is a little too ambitious. Local directory plus local archive support is fine, but git checkout installation in v1 is optional and may distract from the core runtime compatibility work.
- The draft adds many new modules quickly: `AttachmentStager`, `TheAgentSupervisor`, multiple policy and memory modules, and a broad file table. That is fine for a mega sprint, but phase ordering must stay strict or the execution will sprawl.
- The routing and reflection sections are good, but the draft initially allowed worker-proposed memory candidates. That is riskier than necessary. Root-only synthesis from mission artifacts is safer and simpler.
- Some of the model-routing detail assumes a slightly more mature operator-policy surface than exists today. The sprint should implement the router and default tables, not overbuild UI around them yet.

### Missing Edge Cases

- Coexistence window for legacy `.claude/commands` and Gemini skill files during migration.
- Approval semantics when a skill install or activation needs elevated permission in a shared workspace.
- Workspace-scoped skill version conflicts during concurrent missions.
- How archive-installed skills are verified before activation.

## `SPRINT-008-GEMINI-DRAFT.md`

### Strengths

- Good concise framing of the five main areas that need to land.
- Correctly preserves the one-front-door chief-of-staff contract and multi-user boundaries.
- Useful pressure against overcomplicating the plan or inventing unnecessary subsystems.

### Weaknesses

- Too abstract to serve as the execution spine.
- Not enough file-level detail for OmniSkills compatibility with Codergen, ACP, and Attractor.
- Not enough migration or coexistence detail for the current skill surfaces.
- Supervision and doctor concepts are mentioned, but not mapped onto concrete control-plane and mesh files.

## Conclusion

### Definitely Merge Into Final Sprint 008

- Codex’s file-accurate phase plan and dedicated `OmniSkills` target.
- Codex’s explicit mission-preparation and attachment-staging seams.
- Gemini’s simplification pressure and insistence on preserving the chief-of-staff product boundary.
- A stricter root-only reflection authority model from the Claude draft.
- A conservative package-format decision: canonical local directory with `omniskill.json`, plus optional local archive support; remote registries deferred.

### Reject Or Soften

- Do not let routing, reflection, and operator diagnostics grow into a parallel admin product inside the same sprint.
- Do not allow worker-written memory candidates or silent auto-activation of privileged skills.
- Do not require remote registry or hosted-skill infrastructure in this sprint.
