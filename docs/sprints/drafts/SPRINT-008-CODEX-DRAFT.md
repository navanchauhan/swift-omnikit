# SPRINT-008: The Agent Productization Mega Sprint — OmniSkills, Channel Operations, Reflection, and Runtime Discipline

## Overview

Sprint 007 made `TheAgent` real: multi-user scope, normalized ingress, mission orchestration, remote artifacts, Attractor-backed worker execution, and bounded nested delegation all exist in source. Sprint 008 should turn that runtime into a durable operator product by borrowing the strongest missing pieces from the reference systems and fitting them into the architecture we already have instead of starting over.

The most important addition is **OmniSkills**: a provider-neutral skill system that unifies the repo’s fragmented skill surfaces into one installable, scoped, policy-aware runtime. OmniSkills must be compatible with the root `Session`, `OmniCodergen` / `CodergenBackend`, ACP-backed workers, Attractor workflows, and the shell-tool environment types already modeled in `OmniAgentsSDK`. That compatibility requirement is the core design constraint for the sprint.

Beyond OmniSkills, Sprint 008 should ship the productization and runtime-discipline work that the reference comparison exposed as still missing:

- OpenClaw-style Telegram pairing, allowlist policy, onboarding, and doctor flows
- DeerFlow-style skill packaging, activation ergonomics, uploads/artifacts staging, and harness middleware seams
- `ai-agent-brain`-style idle-aware timeouts, lifecycle heartbeats, watchdogs, and restart discipline
- PicoClaw-style lightweight model routing and cheap-vs-heavy execution policy
- `ai-assistant-core`-style reflection, memory extraction, and proactive notifications

The chief-of-staff contract remains fixed:

- the user talks to one root agent over Telegram/chat/API
- the root creates missions, chooses skills, and delegates
- workers and subagents can recurse internally
- only the root asks questions, requests approval, and reports completion

## Use Cases

1. **Telegram-first chief of staff**  
   A user DMs the bot, gets paired into a workspace, asks for work, and receives only meaningful progress, blocking questions, approval requests, and final output. Channel policy and onboarding happen before mission execution.

2. **Shared team workspace with bounded access**  
   A Telegram group is bound to one workspace. Only allowed users may activate the bot, mention-triggering is enabled by default, sensitive approvals are rerouted to DM, and the root maintains one scoped mission history for the team.

3. **Skill-driven implementation mission**  
   The root starts a code-change mission, activates an OmniSkill that injects prompt guidance, tools, shell environment assets, and Codergen overlays, then dispatches an Attractor-backed worker plan that uses the same skill package during `plan -> implement -> validate`.

4. **Recursive subagent work with stable policy**  
   A worker spawns child tasks or child workflows. Activated skills, lineage, workspace boundaries, and budget rules propagate downward automatically without letting child agents talk directly to the human.

5. **Cheap-vs-heavy routing**  
   The root uses a small model for short chat turns, a deeper model for planning, and a Codergen-oriented backend for implementation stages, based on explicit policy instead of ad hoc prompting.

6. **Runtime recovery instead of silent hanging**  
   A long-running ACP or Attractor worker stalls. The control plane sees missing activity heartbeats, distinguishes “tool still alive” from “LLM wedged,” retries where safe, and escalates to the root inbox when the budget is exhausted.

7. **Skill-aware doctor and operator diagnostics**  
   The operator can ask the root to diagnose the system and get one report that covers ingress health, pairing state, mesh connectivity, worker capabilities, active skills, model routes, artifact access, and stalled missions.

8. **Reflection and proactive follow-up**  
   Completed missions generate structured memory candidates and optional follow-up suggestions. The root stores only workspace-scoped approved memory and can notify the user later when a background mission or monitor completes.

## Architecture

### 1. OmniSkills as the canonical skill substrate

Create a new repo-owned `OmniSkills` module instead of extending provider-specific skill behavior piecemeal. The canonical package is a directory or zip archive with a manifest plus optional assets:

```text
skill.json
prompt.md
tools/
shell/
codergen/
attractor/
artifacts/
```

The manifest should describe:

- identity: `skillID`, `version`, `displayName`, `summary`
- scope: `system`, `workspace`, or `mission`
- activation policy: explicit-only, suggested, or auto-eligible
- compatibility surfaces: `root_prompt`, `tool_registry`, `shell_env`, `codergen`, `acp`, `attractor`
- required capabilities: filesystem, network, MCP tools, secrets, domains
- delivery artifacts: docs, templates, prompt snippets, zipped shell assets
- budget hints: preferred model tier, timeout class, expected cost class

OmniSkills is not just “prompt snippets.” It is a compiled runtime package that can produce:

- prompt overlays for the root `Session`
- provider-specific skill exposure for Anthropic/Gemini parity
- tool registrations for root/worker/MCP execution
- `ShellToolLocalSkill` or `ShellToolContainerSkill` payloads for `OmniAgentsSDK`
- Codergen overlays injected into `PipelineContext`
- Attractor node/graph skill context

### 2. Compatibility bridge instead of replacement

The current repo already has multiple skill seams:

- Anthropic prompt skill loading from `.claude/commands`
- Gemini `activate_skill`
- `ShellToolLocalSkill` and `ShellToolContainerSkill` in `OmniAgentsSDK`
- `CodergenBackend` and `PipelineContext` in Attractor
- ACP worker MCP tool registry

Sprint 008 should converge them behind OmniSkills while keeping short-term compatibility:

- `.claude/commands` becomes a legacy import source into the OmniSkills registry
- Gemini `activate_skill` loads from OmniSkills instead of a separate file search
- `claudeSkillTool()` invokes OmniSkills activation
- shell-tool skill models remain the transport format for local/container execution
- `CodergenHandler`, `CodingAgentBackend`, `ACPAgentBackend`, and `AttractorTaskExecutor` read the same activated skill bundle

The rule is simple: **one manifest, many projections**.

### 3. Mission-preparation pipeline

Borrow DeerFlow’s harness idea, but fit it to the existing root mission runtime instead of introducing another top-level orchestrator. Add a lightweight mission-preparation pipeline in the control plane:

1. ingress normalization
2. workspace/channel policy checks
3. attachment staging
4. skill suggestion / activation resolution
5. budget + model route selection
6. mission execution policy selection

This is not a generic plugin free-for-all. It is a fixed, testable sequence that prepares the root runtime and workers for mission execution.

### 4. Telegram product boundary

Borrow OpenClaw’s operational posture:

- DM policy defaults to `pairing`
- group policy defaults to `allowlist`
- shared groups default to `requireMention = true`
- pairing approvals and group/user allowlists are durable workspace policy
- onboarding is explicit instead of implicit
- operator diagnostics include channel and pairing repair hints

Telegram-specific state stays in `ChannelBinding`, pairing records, and delivery receipts. Mission logic remains transport-neutral.

### 5. Runtime discipline and supervision

Borrow the runtime rigor from `ai-agent-brain` and the Elixir-style supervision lesson discussed earlier:

- wall-clock timeout, idle timeout, and activity heartbeat are different signals
- root sessions, workers, and Attractor stages emit lifecycle events
- heartbeats occur on model-start, first-token, tool-start, tool-end, progress, and completion
- a watchdog distinguishes “slow but alive” from “hung”
- restart policy is explicit on mission stages and tasks
- escalation always goes back to the root inbox

This sprint should also add a small process-level supervisor executable or service library so the runtime can rebuild mission ownership after a crash, not just individual tasks.

### 6. Reflection and proactive memory

Borrow `ai-assistant-core`’s reflection loop, but keep it workspace-scoped and root-controlled:

- workers may emit memory candidates
- only the root commits memory
- reflection produces structured memory, follow-up reminders, and suggestion candidates
- proactive notifications reuse the existing interaction and delivery layer

### 7. Deterministic model routing

Borrow PicoClaw’s simple rule-based routing instead of making routing a fuzzy prompt problem. Start with explicit tiers:

- `chat_light`
- `chat_deep`
- `planner`
- `implementer`
- `reviewer`
- `vision`
- `codergen`

Routing policy should consider:

- mission stage
- activated skills
- workspace policy
- expected budget class
- whether the task is root-local or worker-remote

## Implementation

### Phase 1: OmniSkills Core and Package Format

**Goals**
- create the canonical OmniSkills module
- define manifest, installation, activation, and projection model
- preserve backward compatibility with existing skill seams

**Files**
- `Package.swift`
- `Sources/OmniSkills/OmniSkillManifest.swift`
- `Sources/OmniSkills/OmniSkillPackage.swift`
- `Sources/OmniSkills/OmniSkillRegistry.swift`
- `Sources/OmniSkills/OmniSkillInstaller.swift`
- `Sources/OmniSkills/OmniSkillActivation.swift`
- `Sources/OmniSkills/OmniSkillPolicy.swift`
- `Sources/OmniSkills/OmniSkillProjection.swift`
- `Sources/OmniSkills/Legacy/ClaudeCommandImporter.swift`
- `Sources/OmniSkills/Legacy/GeminiSkillImporter.swift`
- `Tests/OmniSkillsTests/OmniSkillManifestTests.swift`
- `Tests/OmniSkillsTests/OmniSkillInstallerTests.swift`
- `Tests/OmniSkillsTests/OmniSkillProjectionTests.swift`

**Tasks**
- Define `skill.json` schema, versioning, and optional asset layout.
- Support installation from local directory, local zip, and git checkout path for v1. Defer remote registry hosting.
- Add per-workspace and per-system skill stores with version pinning.
- Preserve import compatibility for `.claude/commands` and existing Gemini skill files.
- Add activation records so every mission can answer “which skills were active and why?”
- Add policy flags for network/filesystem/tool approvals at the skill level.

### Phase 2: Root Runtime, Provider Bridges, and Shell Environment Compatibility

**Goals**
- make OmniSkills usable in the root loop and provider-specific profiles
- compile skills into shell-tool environments
- keep provider parity tools aligned

**Files**
- `Sources/OmniAIAgent/Providers/AnthropicProfile.swift`
- `Sources/OmniAIAgent/Providers/ClaudeSystemPrompt.swift`
- `Sources/OmniAIAgent/Tools/ClaudeParityTools.swift`
- `Sources/OmniAIAgent/Tools/GeminiParityTools.swift`
- `Sources/OmniAIAgent/Tools/ToolRegistry.swift`
- `Sources/OmniAgentsSDK/Tool.swift`
- `Sources/TheAgentControlPlane/RootAgentRuntime.swift`
- `Sources/TheAgentControlPlane/RootAgentToolbox.swift`
- `Sources/TheAgentControlPlane/Skills/SkillSuggestionEngine.swift`
- `Sources/TheAgentControlPlane/Skills/WorkspaceSkillStore.swift`
- `Tests/TheAgentControlPlaneTests/OmniSkillActivationTests.swift`
- `Tests/OmniAgentsSDKTests/ShellSkillCompatibilityTests.swift`

**Tasks**
- Replace direct provider skill loading with OmniSkills projections.
- Make `claudeSkillTool()` and `activate_skill` resolve from the same registry.
- Add root mission tools: `list_skills`, `install_skill`, `activate_skill`, `deactivate_skill`, `skill_status`.
- Compile skills into `ShellToolLocalSkill` and `ShellToolContainerSkill` payloads where required.
- Add automatic skill suggestion based on mission type, but require explicit activation record before use.
- Keep the user interaction model root-only: skill installation that needs approval must surface through the root inbox.

### Phase 3: Codergen, ACP, Attractor, and Worker Integration

**Goals**
- make OmniSkills first-class in implementation workers
- unify prompt/tool/environment propagation across Codergen and ACP paths
- keep Attractor as the worker execution mode for compound work

**Files**
- `Sources/OmniAIAttractor/Handlers/CodergenHandler.swift`
- `Sources/OmniAIAttractor/Handlers/CodingAgentBackend.swift`
- `Sources/OmniAIAttractor/Handlers/ACPAgentBackend.swift`
- `Sources/OmniAIAttractor/Engine/PipelineEngine.swift`
- `Sources/TheAgentWorker/Attractor/AttractorTaskExecutor.swift`
- `Sources/TheAgentWorker/Attractor/AttractorWorkflowTemplate.swift`
- `Sources/TheAgentWorker/WorkerExecutorFactory.swift`
- `Sources/TheAgentWorker/ACP/ACPWorkerSession.swift`
- `Sources/TheAgentWorker/MCP/ToolRegistry.swift`
- `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift`
- `Tests/TheAgentWorkerTests/OmniSkillCodergenBridgeTests.swift`
- `Tests/TheAgentWorkerTests/OmniSkillACPBridgeTests.swift`
- `Tests/TheAgentWorkerTests/OmniSkillNestedDelegationTests.swift`

**Tasks**
- Extend `PipelineContext` with activated skill bundle metadata.
- Let Attractor graph or node attributes declare required skills by ID/version.
- Inject skill prompt overlays and artifacts into `CodergenBackend` runs.
- Allow ACP workers to expose skill-provided tools via the worker MCP registry.
- Carry active skills, workspace scope, lineage, and budgets through child tasks and child workflows.
- Add a fail-closed rule: workers may request extra skill activation, but only the root can approve and record it.

### Phase 4: Channel Policy, Pairing, Onboarding, and Doctor

**Goals**
- make Telegram usable as a real product surface
- add policy, onboarding, and diagnostics from the OpenClaw playbook
- keep it multi-user and workspace-safe

**Files**
- `Sources/TheAgentControlPlane/Policy/ChannelPolicyManager.swift`
- `Sources/TheAgentControlPlane/Policy/PairingStore.swift`
- `Sources/TheAgentControlPlane/Policy/WorkspaceAllowlist.swift`
- `Sources/TheAgentControlPlane/Onboarding/OnboardingWizard.swift`
- `Sources/TheAgentControlPlane/Diagnostics/DoctorService.swift`
- `Sources/TheAgentControlPlane/Diagnostics/DoctorReport.swift`
- `Sources/TheAgentIngress/IngressGateway.swift`
- `Sources/TheAgentIngress/HTTPIngressServer.swift`
- `Sources/TheAgentTelegram/TelegramWebhookHandler.swift`
- `Sources/TheAgentTelegram/TelegramPollingRunner.swift`
- `Sources/TheAgentTelegram/TelegramBotClient.swift`
- `Sources/TheAgentTelegram/TelegramDeliveryFormatter.swift`
- `Sources/TheAgentControlPlane/main.swift`
- `Tests/TheAgentIngressTests/TelegramPairingTests.swift`
- `Tests/TheAgentIngressTests/TelegramPolicyTests.swift`
- `Tests/TheAgentControlPlaneTests/DoctorServiceTests.swift`

**Tasks**
- Add DM policy: `pairing`, `allowlist`, `open`, `disabled`.
- Add group policy: allowlisted group bindings, per-group user allowlists, `requireMention`, optional ambient mode.
- Implement pairing codes and approval flow for first-contact DMs.
- Add onboarding and recovery prompts for “start a DM first” cases.
- Add `doctor` reporting for channel policy, webhook or polling health, worker reachability, skill registry state, and stalled missions.
- Keep Telegram-specific config and IDs out of mission logic.

### Phase 5: Supervision, Heartbeats, Watchdogs, and Delivery Discipline

**Goals**
- harden the runtime against stalls and partial failures
- distinguish alive vs dead vs blocked execution
- make restart and escalation explicit

**Files**
- `Sources/OmniAgentMesh/Models/TaskRecord.swift`
- `Sources/OmniAgentMesh/Models/TaskEvent.swift`
- `Sources/OmniAgentMesh/Models/MissionRecord.swift`
- `Sources/OmniAgentMesh/Stores/DeliveryStore.swift`
- `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift`
- `Sources/TheAgentControlPlane/Missions/MissionSupervisor.swift`
- `Sources/TheAgentControlPlane/Supervision/ActivityHeartbeat.swift`
- `Sources/TheAgentControlPlane/Supervision/TimeoutWatchdog.swift`
- `Sources/TheAgentControlPlane/Supervision/SupervisorService.swift`
- `Sources/TheAgentWorker/WorkerDaemon.swift`
- `Sources/TheAgentWorker/ACP/ACPExecutor.swift`
- `Sources/TheAgentWorker/Attractor/AttractorTaskExecutor.swift`
- `Sources/TheAgentControlPlane/Interaction/InteractionBroker.swift`
- `Sources/TheAgentSupervisor/main.swift`
- `Tests/TheAgentControlPlaneTests/TimeoutWatchdogTests.swift`
- `Tests/TheAgentControlPlaneTests/MissionRecoveryTests.swift`
- `Tests/TheAgentWorkerTests/WorkerHeartbeatTests.swift`

**Tasks**
- Add activity heartbeat events for root, ACP, Attractor, and tool lifecycle transitions.
- Separate wall-clock timeout, idle timeout, and retry budget.
- Add dead-letter and escalation semantics after retry exhaustion.
- Add a small supervisor executable that can restart the control plane or worker processes and rebuild state ownership.
- Ensure delivery receipts and mission transitions remain idempotent during replay or restart.

### Phase 6: Reflection, Memory, Model Routing, and Proactive Notifications

**Goals**
- make the root smarter between turns and across missions
- keep cost under control through deterministic routing
- add proactive but scoped follow-up behavior

**Files**
- `Sources/TheAgentControlPlane/Memory/ReflectionLoop.swift`
- `Sources/TheAgentControlPlane/Memory/MemoryCandidate.swift`
- `Sources/TheAgentControlPlane/Memory/WorkspaceMemoryStore.swift`
- `Sources/TheAgentControlPlane/Routing/ModelRouter.swift`
- `Sources/TheAgentControlPlane/Routing/ModelRoutePolicy.swift`
- `Sources/TheAgentControlPlane/Interaction/NotificationPlanner.swift`
- `Sources/OmniAgentMesh/Stores/ConversationStore.swift`
- `Sources/OmniAgentMesh/Stores/NotificationStore.swift`
- `Tests/TheAgentControlPlaneTests/ReflectionLoopTests.swift`
- `Tests/TheAgentControlPlaneTests/ModelRouterTests.swift`
- `Tests/TheAgentControlPlaneTests/ProactiveNotificationTests.swift`

**Tasks**
- Add a post-mission reflection pass that extracts workspace-scoped memory candidates.
- Allow workers to propose memory candidates, but require root approval before persistence.
- Add rule-based model routing keyed by mission stage, skill profile, and cost class.
- Add proactive notification planning for completed background missions and monitors.
- Keep reflective memory tenant-safe and auditable.

### Phase 7: Live Proof, Docs, and Migration Closure

**Goals**
- prove the entire product contract live
- document installation and operational expectations
- close migration from pre-OmniSkills behavior

**Files**
- `docs/agent-fabric-architecture.md`
- `docs/the-agent-runtime-runbook.md`
- `docs/omniacp.md`
- `docs/omniskills.md`
- `Tests/TheAgentIngressTests/TelegramLiveParityTests.swift`
- `Tests/TheAgentWorkerTests/OmniSkillRemoteWorkerProofTests.swift`

**Tasks**
- Run a Telegram live proof with pairing, mission execution, approval routing, and final reply.
- Run a remote worker proof where an activated OmniSkill reaches an ACP or Attractor worker and affects execution.
- Prove workspace isolation for system skill, workspace skill, and mission skill scopes.
- Document the migration path from legacy `.claude/commands` and Gemini skill files into OmniSkills packages.

## Files Summary

| File | Action | Purpose |
|------|--------|---------|
| `Package.swift` | Modify | Add `OmniSkills` and supervisor targets plus new tests |
| `Sources/OmniSkills/OmniSkillManifest.swift` | Create | Canonical OmniSkills manifest schema |
| `Sources/OmniSkills/OmniSkillRegistry.swift` | Create | Installed skill discovery and lookup |
| `Sources/OmniSkills/OmniSkillInstaller.swift` | Create | Install/uninstall/version pinning |
| `Sources/OmniSkills/OmniSkillActivation.swift` | Create | Mission/workspace activation records |
| `Sources/OmniSkills/OmniSkillProjection.swift` | Create | Compile skills into prompt/tool/shell/Codergen projections |
| `Sources/OmniSkills/Legacy/ClaudeCommandImporter.swift` | Create | Import `.claude/commands` into OmniSkills |
| `Sources/OmniSkills/Legacy/GeminiSkillImporter.swift` | Create | Import legacy Gemini skill files |
| `Sources/OmniAIAgent/Providers/AnthropicProfile.swift` | Modify | Replace bespoke skill loading with OmniSkills |
| `Sources/OmniAIAgent/Tools/GeminiParityTools.swift` | Modify | Resolve `activate_skill` through OmniSkills |
| `Sources/OmniAIAgent/Tools/ClaudeParityTools.swift` | Modify | Resolve skill tool through OmniSkills |
| `Sources/OmniAgentsSDK/Tool.swift` | Modify | Treat shell skills as an OmniSkills projection target |
| `Sources/TheAgentControlPlane/RootAgentRuntime.swift` | Modify | Root-side skill activation, routing, and reflection hooks |
| `Sources/TheAgentControlPlane/RootAgentToolbox.swift` | Modify | Skill, doctor, and routing tools |
| `Sources/TheAgentControlPlane/Skills/SkillSuggestionEngine.swift` | Create | Root-side skill recommendation engine |
| `Sources/OmniAIAttractor/Handlers/CodergenHandler.swift` | Modify | Pass OmniSkills into Codergen pipeline context |
| `Sources/OmniAIAttractor/Handlers/CodingAgentBackend.swift` | Modify | Apply skill overlays in coding-agent execution |
| `Sources/OmniAIAttractor/Handlers/ACPAgentBackend.swift` | Modify | Apply skill overlays in ACP execution |
| `Sources/TheAgentWorker/Attractor/AttractorTaskExecutor.swift` | Modify | Activate skills inside worker workflows |
| `Sources/TheAgentWorker/ACP/ACPWorkerSession.swift` | Modify | Expose skills to ACP-backed workers |
| `Sources/TheAgentWorker/MCP/ToolRegistry.swift` | Modify | Add skill-provided worker tools |
| `Sources/TheAgentControlPlane/Policy/ChannelPolicyManager.swift` | Create | Pairing, allowlist, mention, and channel rules |
| `Sources/TheAgentControlPlane/Onboarding/OnboardingWizard.swift` | Create | First-contact and recovery flows |
| `Sources/TheAgentControlPlane/Diagnostics/DoctorService.swift` | Create | Operator health report |
| `Sources/TheAgentControlPlane/Supervision/TimeoutWatchdog.swift` | Create | Idle-aware stall detection |
| `Sources/TheAgentSupervisor/main.swift` | Create | Process-level supervisor executable |
| `Sources/TheAgentControlPlane/Memory/ReflectionLoop.swift` | Create | Structured memory extraction after missions |
| `Sources/TheAgentControlPlane/Routing/ModelRouter.swift` | Create | Rule-based model routing |
| `docs/omniskills.md` | Create | OmniSkills package and operator guide |

## Definition of Done

- [ ] OmniSkills packages can be installed from local path or archive, version-pinned, and scoped to system, workspace, or mission.
- [ ] One OmniSkills activation path feeds the root session, Anthropic/Gemini parity tools, shell-tool environments, Codergen pipelines, ACP workers, and Attractor workflows.
- [ ] Existing `.claude/commands` and Gemini skill files can be imported or projected into OmniSkills without losing behavior.
- [ ] Root missions record which skills were activated, who approved them, and why.
- [ ] Telegram DM pairing, group allowlist policy, mention gating, and onboarding flows work with the existing multi-user workspace model.
- [ ] The operator can ask for a doctor report and get skill, ingress, routing, worker, and mission health in one root reply.
- [ ] Root, ACP, Attractor, and worker stages emit heartbeats and lifecycle events that support idle-aware timeout detection.
- [ ] Restart or retry after a stalled worker or process crash does not duplicate mission side effects or orphan approvals.
- [ ] Reflection writes only workspace-scoped memory and can produce proactive follow-up notifications through the root.
- [ ] Model routing chooses different execution tiers for chat, planning, coding, and validation based on explicit policy.
- [ ] A live Telegram proof shows pairing or allowlist onboarding, root mission orchestration, an OmniSkill-enabled worker mission, and final completion reporting.
- [ ] A remote worker proof shows an OmniSkill affecting ACP or Attractor execution on a separate host.
- [ ] Tests cover OmniSkills manifest parsing, projection, provider parity bridges, Codergen/ACP/Attractor propagation, Telegram policy, heartbeats, routing, and reflection isolation.

## Risks

- **OmniSkills becomes a second plugin system instead of the unifying one**  
  Mitigation: make every existing skill surface a projection or importer into OmniSkills rather than leaving parallel registries alive.

- **Too much product work in one sprint**  
  Mitigation: phase the sprint so OmniSkills core and compatibility land before product surfaces like doctor and onboarding.

- **Skill propagation is inconsistent between root and workers**  
  Mitigation: use one activation record plus one projection compiler, then test each target runtime against it.

- **Telegram policy grows too transport-specific**  
  Mitigation: keep channel policy and pairing state in control-plane policy stores, not inside mission logic.

- **Watchdog policy creates false positives on long-running jobs**  
  Mitigation: distinguish wall-clock budget from idle timeout and require activity-heartbeat coverage before enforcing aggressive restarts.

- **Reflection leaks tenant data**  
  Mitigation: root-only commit path, workspace mandatory on every candidate, and isolation tests that assert no cross-workspace memory reads.

## Security

- OmniSkills must declare required capabilities and default to least privilege.
- Skill-provided shell environments and MCP tools must never silently escalate permissions beyond the mission/workspace policy that activated them.
- Telegram DM and group access must fail closed by default until pairing or allowlist rules are satisfied.
- Approval and question flows remain root-owned even when triggered by skill behavior inside workers.
- Secrets required by skills, channels, ACP backends, or model routes must remain external configuration and must not be embedded in skill packages or logs.
- Reflection and doctor outputs must redact secrets, tokens, and private workspace details before model or user exposure.

## Dependencies

- Sprint 006 durable mesh/control-plane fabric
- Sprint 007 multi-user ingress, mission orchestration, artifact transport, and Attractor execution
- Existing `CodergenBackend`, ACP worker support, and `OmniAgentsSDK` shell skill environment models
- User-provided Telegram bot credentials and workspace bootstrap rules for live proof
- Provider credentials for the routing tiers actually configured in the deployment

## Open Questions

1. Should OmniSkills allow signed remote registries in the same sprint, or should v1 stay local-path and archive based only?
2. Which approval classes should be auto-rerouted from shared Telegram chats into DM by default once skill activation and doctor/admin flows exist?
3. Do we want `TheAgentSupervisor` as a separate binary from day one, or as a library/service that `launchd`/`systemd` can host?
4. Should reflection-generated proactive notifications require explicit workspace opt-in, or can they be enabled by default for owner-only personal workspaces?
