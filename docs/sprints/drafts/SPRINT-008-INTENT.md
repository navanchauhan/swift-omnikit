# Sprint 008 Intent: The Agent Productization Mega Sprint — OmniSkills, Channel Policy, and Runtime Hardening

## Seed

Borrow everything relevant from `references/{ai-assistant-core,ai-agent-brain,deer-flow,openclaw,picoclaw}` into the next mega sprint for `TheAgent`. The sprint should turn the current runtime into a more complete product by adding the missing operator/runtime/channel pieces, and it must include a first-class `OmniSkills` system that is compatible with the existing OmniCodergen and worker execution stack.

## Context

- Sprint 006 and Sprint 007 already established the durable root/worker mesh, scoped multi-user runtime, Telegram/API ingress path, Attractor-backed worker execution, artifact transport, and bounded recursive delegation.
- The repo already has fragmented skill-related behavior: Anthropic prompt generation loads `.claude/commands`, Gemini has an `activate_skill` tool, and `OmniAgentsSDK` already models local/container shell-tool skills, but there is no unified provider-neutral skill runtime or package.
- The chief-of-staff model is now real: `RootAgentRuntime`, `MissionCoordinator`, `InteractionBroker`, `IngressGateway`, `HTTPMeshServer`, and worker Attractor/ACP execution are all live seams that a new sprint must reuse instead of replacing.
- The strongest reference gaps are productization and runtime discipline rather than basic orchestration: OpenClaw-style channel pairing/policy/onboarding/doctor, DeerFlow-style skills and middleware ergonomics, ai-agent-brain-style timeout/heartbeat/supervision rigor, PicoClaw-style lightweight model routing, and ai-assistant-core-style reflection/proactive memory.
- Repo and project constraints still matter: root-only user interaction, Attractor as a worker execution mode instead of the universal runtime, multi-user workspace/channel isolation, and no third-party framework additions without asking first.

## Recent Sprint Context

- `adb5ced` implemented Sprint 007 runtime work: scoped chief-of-staff runtime, Telegram ingress, remote artifacts, mission orchestration, Attractor worker execution, and nested delegation tests.
- `6c1bf58` implemented Sprint 006 control plane and worker fabric: durable mesh/control plane, remote workers, ACP worker support, and control-plane state.
- `a655ed4` added Codex and Claude ACP backends, which matters because OmniSkills must compose cleanly with ACP-backed and Codergen-backed execution, not just the root chat loop.

## Relevant Codebase Areas

- Root mission runtime and orchestration:
  - `Sources/TheAgentControlPlane/RootAgentRuntime.swift`
  - `Sources/TheAgentControlPlane/RootAgentToolbox.swift`
  - `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift`
  - `Sources/TheAgentControlPlane/Interaction/InteractionBroker.swift`
- Multi-user ingress and Telegram edge:
  - `Sources/TheAgentIngress/IngressGateway.swift`
  - `Sources/TheAgentIngress/HTTPIngressServer.swift`
  - `Sources/TheAgentTelegram/*`
  - `Sources/OmniAgentMesh/Models/IdentityModels.swift`
- Worker/runtime fabric:
  - `Sources/OmniAgentMesh/Transport/HTTPMeshServer.swift`
  - `Sources/OmniAgentMesh/Transport/HTTPMeshClient.swift`
  - `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift`
  - `Sources/TheAgentWorker/WorkerExecutorFactory.swift`
- Attractor and Codergen seams:
  - `Sources/OmniAIAttractor/Handlers/CodergenHandler.swift`
  - `Sources/OmniAIAttractor/Handlers/CodingAgentBackend.swift`
  - `Sources/OmniAIAttractor/Engine/PipelineEngine.swift`
- Existing skill/tool seams that should converge into OmniSkills:
  - `Sources/OmniAIAgent/Providers/AnthropicProfile.swift`
  - `Sources/OmniAIAgent/Tools/GeminiParityTools.swift`
  - `Sources/OmniAIAgent/Tools/ToolRegistry.swift`
  - `Sources/OmniAgentsSDK/Tool.swift`

## Constraints

- Must follow project conventions from `AGENTS.md`, especially root-only interaction, modern Swift concurrency, and no third-party frameworks without explicit approval.
- Must integrate with the current Sprint 006/007 architecture instead of replacing it wholesale.
- Must keep Attractor as a worker-side structured execution mode, not the mesh protocol or universal root runtime.
- Must keep user interaction centralized at the root control plane; workers and subagents cannot become user-facing.
- Must preserve multi-user workspace/channel isolation and durable restart/recovery semantics.
- Must make OmniSkills compatible with existing OmniCodergen/CodergenBackend, ACP worker execution, and shell-tool skill models already present in `OmniAgentsSDK`.

## Success Criteria

This sprint is successful if it produces one implementable mega sprint that:

- turns `TheAgent` from a good runtime into a better operator-facing product;
- adds a first-class `OmniSkills` platform with manifests, installation/activation/runtime policy, and compatibility with root sessions, worker tasks, Attractor pipelines, ACP/Codergen execution, and shell-tool environments;
- pulls in the relevant reference learnings for channel security/policy, onboarding, doctor/diagnostics, observability, supervision, model routing, and reflection;
- keeps the chief-of-staff contract intact: one user-facing agent, everything else internal;
- is concrete enough to implement phase-by-phase with explicit files, tests, proofs, and operational acceptance criteria.

## Verification Strategy

- Reference implementation:
  - `references/openclaw` for channel policy, pairing, routing, onboarding/doctor, and Telegram operational behavior.
  - `references/deer-flow` for skill/harness ergonomics, middleware shape, uploads/artifacts, and sandbox/tool composition.
  - prior `ai-agent-brain` notes for idle-aware timeout hooks, observability, and supervision semantics.
  - `references/picoclaw` for lightweight model routing and session-key/routing pragmatism.
  - `references/ai-assistant-core` for reflection/proactive memory loops.
- Spec/documentation:
  - existing sprint docs `docs/sprints/SPRINT-007.md`
  - `docs/agent-fabric-architecture.md`
  - `docs/the-agent-runtime-runbook.md`
- Edge cases identified:
  - skill activation working across provider-specific and provider-neutral runtimes
  - workspace-scoped skill isolation and permissions
  - Telegram DM vs group policy boundaries
  - long-running orchestrator stalls without visible heartbeats
  - worker/subagent recursion combined with skill/tool injection
  - reflection or proactive notifications leaking across tenants
- Testing approach:
  - unit tests for skill manifests, registry, activation, policy, and model routing
  - integration tests for root/worker/Attractor/ACP skill propagation
  - ingress tests for pairing/allowlist/group policy and delivery behavior
  - recovery/observability tests for retries, idle timeouts, and heartbeats
  - live-proof requirements for Telegram + remote worker + skill-enabled mission execution

## Uncertainty Assessment

- Correctness uncertainty: Medium — the reference directions are clear, but OmniSkills must bridge several existing partially-overlapping systems without regressions.
- Scope uncertainty: High — this is a broad productization sprint touching runtime, ingress, worker execution, skills, and operator UX.
- Architecture uncertainty: High — the biggest design question is how far OmniSkills should reach into prompt-time guidance, tool registration, shell environments, Codergen contexts, and worker policies without becoming a second conflicting plugin model.

## Open Questions

1. What is the canonical OmniSkills package format: plain directory + manifest, signed archive, git source, registry reference, or all of the above?
2. Should OmniSkills activation be explicit per mission/task, automatically suggested by the root, or both?
3. How should skill content propagate into OmniCodergen and ACP-backed workers: prompt augmentation only, tool registration, shell environment mounts, or a layered combination?
4. Which operator/product features belong in this same sprint versus a follow-on: onboarding wizard, doctor diagnostics, web control UI, channel management UI?
5. What is the initial channel policy default for Telegram and future channels: pairing-first, explicit allowlist-first, or workspace-admin bootstrap?
6. Should reflection/proactive memory be root-driven only, or can workers contribute structured memory candidates that the root reviews and commits?
