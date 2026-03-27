# SPRINT-008: The Agent Productization Mega Sprint — OmniSkills, Channel Policy, and Runtime Hardening

## Overview
Sprint 008 transforms `TheAgent` from a functional orchestrator into a complete, hardened operator product. It unifies fragmented tool execution into a first-class **OmniSkills** system that natively integrates with root sessions, OmniCodergen/CodergenBackend, ACP-backed workers, Attractor pipelines, and shell-tool environments. Beyond skills, the sprint implements critical runtime and productization features borrowed from reference projects (`openclaw`, `deer-flow`, `ai-agent-brain`, `picoclaw`, and `ai-assistant-core`), including channel pairing and policy, onboarding wizards, doctor diagnostics, rigorous supervision (timeouts/heartbeats), lightweight model routing, and proactive reflection memory. The sprint preserves the chief-of-staff contract, ensuring all user interaction remains centralized at the root.

## Use Cases
- **Write Once, Run Anywhere Skills**: An operator defines an `OmniSkill` manifest. The system automatically provisions its prompts, tools, and shell environments across root missions, Attractor pipelines, and remote ACP workers based on task relevance.
- **Secure Channel Onboarding**: A new user discovers the bot on Telegram. Instead of immediate access, they are guided through a secure pairing, onboarding, and allowlisting flow before interacting with the root control plane.
- **Resilient Worker Execution**: A remote worker executing a heavy Codergen task stalls. The root control plane detects missing heartbeats and graceful idle-timeouts, surfacing the issue to the operator instead of hanging silently.
- **Proactive Memory & Reflection**: The root agent reflects on completed missions in the background to build structured memory, allowing it to proactively offer relevant context in future operator sessions.
- **Runtime Diagnostics**: An operator types `/doctor` to quickly verify mesh connectivity, available ACP backends, loaded OmniSkills, and channel policy status.

## Architecture
- **OmniSkills Core**: A provider-neutral registry and manifest system designed to replace isolated `.claude/commands` and `activate_skill` patterns. It acts as a layered configuration engine, capable of injecting prompt augmentations, registering tools, and mounting shell environments across any worker execution context.
- **Channel Policy & Middleware (`openclaw` / `deer-flow`)**: Intercepts `IngressGateway` traffic to enforce workspace isolation, manage onboarding states, and ergonomically handle incoming file uploads/artifacts before they reach the `InteractionBroker`.
- **Supervision & Mesh Rigor (`ai-agent-brain`)**: Introduces strict lifecycle management to the mesh. `HTTPMeshClient` and remote workers emit heartbeats. `MissionCoordinator` enforces idle-aware timeouts and graceful recovery bounds.
- **Lightweight Routing (`picoclaw`)**: A pragmatic routing layer within the control plane that directs specific sub-tasks to optimal model providers based on session keys and capability profiles.
- **Reflection & Memory (`ai-assistant-core`)**: Background loops within `RootAgentRuntime` that analyze mission transcripts to synthesize durable, proactive memory, strictly scoped to the operator's workspace/tenant boundaries.
- **Swift 6 Adherence**: All architectural additions strictly use modern Swift concurrency (async/await, `@Sendable`, actor isolation) and modern Foundation APIs, completely avoiding third-party frameworks.

## Implementation
1. **OmniSkills Platform**:
   - Define the `OmniSkillManifest` schema (incorporating prompts, tool schemas, and environment needs).
   - Build `OmniSkillRegistry` to manage discovery and activation.
   - Implement injection adapters for `OmniCodergen`, `Attractor` pipelines, `ACP` backends, and `OmniAgentsSDK` shell execution.
2. **Ingress & Channel Policy**:
   - Update `HTTPIngressServer` and Telegram channels to route unauthorized users to an `OnboardingWizard`.
   - Implement `ChannelPolicyManager` to govern group vs. DM policies and explicit allowlists.
   - Add the `/doctor` diagnostic command to `RootAgentToolbox`.
3. **Supervision Hardening**:
   - Add heartbeat emission to `ChildWorkerManager` and mesh clients.
   - Implement stalled-mission detection and idle timeouts in `MissionCoordinator`.
4. **Reflection & Model Routing**:
   - Create a `ReflectionLoop` background task attached to the `RootAgentRuntime`.
   - Implement `ModelRouter` to allow lightweight selection of AI providers for specialized OmniSkills or tasks.
5. **Codebase Modernization**:
   - Ensure all new `@Observable` types are correctly `@MainActor` isolated.
   - Audit and enforce modern `FormatStyle` and native Foundation API usage across the new modules.

## Files Summary
- **New Files**:
  - `Sources/OmniAgentsSDK/Skills/OmniSkillManifest.swift`
  - `Sources/OmniAgentsSDK/Skills/OmniSkillRegistry.swift`
  - `Sources/TheAgentControlPlane/Policy/ChannelPolicyManager.swift`
  - `Sources/TheAgentControlPlane/Policy/OnboardingWizard.swift`
  - `Sources/TheAgentControlPlane/Diagnostics/Doctor.swift`
  - `Sources/TheAgentControlPlane/Memory/ReflectionLoop.swift`
  - `Sources/TheAgentControlPlane/Routing/ModelRouter.swift`
- **Modified Files**:
  - `Sources/TheAgentControlPlane/RootAgentRuntime.swift` (Attach reflection and routing)
  - `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift` (Implement timeouts and supervision)
  - `Sources/TheAgentControlPlane/RootAgentToolbox.swift` (Add doctor tools)
  - `Sources/TheAgentIngress/IngressGateway.swift` (Hook in channel policy)
  - `Sources/OmniAgentMesh/Transport/HTTPMeshClient.swift` (Add heartbeats)
  - `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift` (Implement worker supervision)
  - `Sources/OmniAIAttractor/Handlers/CodingAgentBackend.swift` (Inject OmniSkills)
  - `Sources/OmniAIAgent/Tools/ToolRegistry.swift` (Refactor to use OmniSkills)

## Definition of Done
- `OmniSkills` can be loaded via manifest and seamlessly injected into root chat, Attractor workflows, and ACP/Codergen execution environments.
- Telegram ingress routes unverified users through a defined pairing/allowlist policy without exposing root runtime capabilities.
- Remote workers emit regular heartbeats; the control plane detects stalled missions and executes idle-timeouts.
- The `ReflectionLoop` successfully synthesizes and stores proactive memory at the end of a mission without leaking data across tenants.
- The `/doctor` command accurately maps mesh, worker, channel, and skill health.
- Unit and integration tests cover skill propagation, ingress policy, recovery behaviors, and concurrency rules.
- Code strictly complies with `AGENTS.md` (Swift 6, modern Foundation APIs, strict concurrency, no third-party libraries).

## Risks
- **Architectural Conflict**: OmniSkills must carefully bridge `OmniCodergen`, ACP, and `OmniAgentsSDK` without creating overlapping, conflicting plugin models.
- **Scope Creep**: Combining ingress policy, skill runtimes, and proactive memory into one sprint is ambitious; rigorous phasing is required.
- **Migration Issues**: Replacing fragmented systems like `.claude/commands` and `activate_skill` might break existing operator workflows if not smoothly transitioned.

## Security
- **Strict Tenant Isolation**: Channel policy, proactive memory, and reflection data must never leak across multi-user or workspace boundaries.
- **Default-Deny Ingress**: All new external ingress (like Telegram) must default to pairing-first or explicit allowlist-first policies.
- **Sandboxed Execution**: OmniSkills shell-environment mounts and tool implementations must remain within the scoped bounds of remote workers, avoiding privilege escalation to the root control plane.
- **Secret Management**: Diagnostics and reflection logs must aggressively sanitize output to prevent credentials or API keys from being recorded.

## Dependencies
- Existing Chief-of-Staff architecture (`RootAgentRuntime`, `MissionCoordinator`, `InteractionBroker`).
- Existing mesh and worker fabric (`HTTPMeshServer`, `ChildWorkerManager`).
- Existing Attractor pipelines and Codergen backend seams.
- Swift 6.0 Toolchain.

## Open Questions
1. What is the canonical OmniSkills package format: plain directory + manifest, signed archive, git source, registry reference, or all of the above?
2. Should OmniSkills activation be explicit per mission/task, automatically suggested by the root, or both?
3. How should skill content propagate into OmniCodergen and ACP-backed workers: prompt augmentation only, tool registration, shell environment mounts, or a layered combination?
4. Which operator/product features belong in this same sprint versus a follow-on: onboarding wizard, doctor diagnostics, web control UI, channel management UI?
5. What is the initial channel policy default for Telegram and future channels: pairing-first, explicit allowlist-first, or workspace-admin bootstrap?
6. Should reflection/proactive memory be root-driven only, or can workers contribute structured memory candidates that the root reviews and commits?
