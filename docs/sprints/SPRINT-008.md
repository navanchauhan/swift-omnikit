# SPRINT-008: The Agent Productization Mega Sprint — OmniSkills, Channel Operations, Reflection, and Runtime Discipline

## Overview

Sprint 006 built the durable root/worker mesh. Sprint 007 made `TheAgent` a real chief-of-staff runtime with multi-user scope, mission orchestration, Telegram/API ingress, remote artifacts, Attractor-backed worker execution, and bounded recursive delegation. Sprint 008 is the productization and hardening sprint that turns that runtime into the thing the user can rely on as the only interface they need.

This sprint has one central technical addition: **OmniSkills**. The repo already has fragmented skill behavior across Anthropic prompt loading, Gemini `activate_skill`, shell-tool skill environments, and worker/Codergen seams. Sprint 008 replaces that fragmentation with one provider-neutral skill system that is installable, scoped, policy-aware, and compatible with:

- root `OmniAIAgent.Session` execution
- Anthropic and Gemini parity skill tooling
- `OmniAgentsSDK` shell-tool environments
- `OmniCodergen` / `CodergenBackend`
- ACP-backed workers
- Attractor worker workflows
- nested worker and subagent delegation

The rest of the sprint borrows the strongest missing pieces from the reference set:

- OpenClaw: pairing, allowlists, mention-gated groups, onboarding, doctor, channel repair posture
- DeerFlow: skill packaging, harness preparation stages, upload/artifact staging, operator ergonomics
- `ai-agent-brain`: idle-aware timeout discipline, lifecycle heartbeats, watchdogs, recovery semantics
- PicoClaw: cheap-vs-heavy model routing and lightweight deployment pragmatism
- `ai-assistant-core`: reflection, memory extraction, and proactive follow-up

The product contract does not change:

- the user interacts only with the root agent
- the root owns approvals, questions, and final replies
- workers and subagents may recurse internally
- all runtime policy, skills, and recovery semantics remain durable and workspace-scoped

## Execution Status

- Core Sprint 008 productization work is implemented in source and covered by the new OmniSkills, Telegram policy, doctor, supervision, routing, reflection, and remote-worker proof tests.
- Full package validation passed locally with `swift test --skip-build` after the Sprint 008 runtime and test updates.
- The only remaining environment-specific Definition of Done item is a credentialed live Telegram proof, which still requires a real bot token plus polling or webhook deployment.

## Use Cases

1. **Telegram DM chief of staff**  
   A user starts a DM with the bot, completes pairing or allowlist onboarding, asks for work, and receives only root-owned progress, approvals, questions, and final results.

2. **Shared workspace with policy boundaries**  
   A Telegram group or topic is bound to one workspace. Mention-gated activation, per-user allowlists, DM reroute for sensitive approvals, and workspace-scoped memory all work without cross-talk.

3. **Skill-driven mission execution**  
   The root installs or activates an OmniSkill, then starts a mission whose planning, implementation, validation, and worker execution all receive the same skill-defined prompt/tool/environment overlays.

4. **Codergen-compatible execution**  
   A worker runs a Codergen or ACP-backed implementation stage with skill-provided instructions, MCP tools, artifacts, and shell environment data, without inventing a parallel plugin model.

5. **Structured Attractor mission**  
   A worker executes a `plan -> implement -> validate` Attractor workflow whose nodes inherit mission lineage, active skills, budgets, and root-owned human gates.

6. **Runtime stall recovery**  
   A root model call, ACP session, or worker-side Attractor stage stops making progress. The watchdog detects idle timeout vs wall-clock exhaustion vs still-alive tool activity, then retries, escalates, or asks the root to replan.

7. **Doctor and operator diagnostics**  
   The operator asks the root to diagnose the system and gets one report covering ingress health, pairing state, worker reachability, skill registry state, routing policy, stalled missions, and artifact access.

8. **Reflection and proactive follow-up**  
   Completed missions produce structured memory candidates and optional future notifications without leaking data across workspaces or bypassing the root persona.

## Architecture

### Product Shape

Sprint 008 keeps the current topology:

- transport-agnostic ingress
- workspace/channel-scoped root runtime
- mission coordinator above the worker fabric
- local/ACP/Attractor worker execution modes
- root-owned interaction broker
- durable mesh and artifact stores

It adds four new product layers on top of that foundation:

1. **OmniSkills layer**  
   install, activate, and project skills across root, workers, Codergen, ACP, Attractor, and shell-tool environments

2. **Channel operations layer**  
   pairing, allowlists, mention gating, onboarding, doctor, and transport repair behavior

3. **Runtime discipline layer**  
   heartbeats, watchdogs, restart policy, external supervision, and replay-safe recovery

4. **Reflection and routing layer**  
   memory extraction, proactive notifications, and deterministic model routing

### OmniSkills

The canonical OmniSkill package is a directory or archive with a manifest plus optional assets:

```text
omniskill.json
prompt.md
tools/
shell/
codergen/
attractor/
artifacts/
```

The manifest must declare:

- `skillID`, `version`, `displayName`, `summary`
- installation scope: `system`, `workspace`, `mission`
- activation policy: `explicit`, `suggested`, `auto_eligible`
- projection surfaces: `root_prompt`, `tool_registry`, `shell_env`, `codergen`, `acp`, `attractor`
- required capabilities: filesystem, network, domains, MCP tools, secrets
- budget hints: preferred model tier, timeout class, cost class
- asset references for prompt snippets, shell content, Codergen overlays, and Attractor templates

OmniSkills is a compilation target, not just a file loader. The same installation must be able to produce:

- root-session prompt overlays
- provider-specific skill exposure for Anthropic/Gemini parity tools
- `ShellToolLocalSkill` and `ShellToolContainerSkill` payloads
- Codergen pipeline overlays in `PipelineContext`
- worker MCP tool registrations
- Attractor graph/node skill context

### Compatibility Rule

Sprint 008 must converge these existing seams:

- `AnthropicProfile` `.claude/commands` loading
- Gemini `activate_skill`
- `claudeSkillTool()`
- `ShellToolLocalSkill` / `ShellToolContainerSkill`
- `CodergenBackend` and `PipelineContext`
- worker MCP tool registry

The compatibility rule is:

- existing skill formats become import sources or projections into OmniSkills
- new skill behavior is added only in OmniSkills
- root and workers consume projected outputs from OmniSkills rather than each owning their own skill registry

### Mission Preparation Pipeline

Borrow the useful DeerFlow harness idea, but keep it narrow and repo-aligned. Add a fixed mission-preparation sequence before non-trivial mission execution:

1. normalize ingress
2. bind workspace/channel/actor
3. stage attachments and referenced artifacts
4. apply channel policy and onboarding gates
5. resolve skill suggestions and required activations
6. resolve budget and model route
7. choose execution mode: direct, worker task, or Attractor workflow

This is not a generic plugin pipeline. It is a deterministic set of preparation stages owned by the control plane.

### Telegram Policy and Channel Operations

Borrow OpenClaw’s operational defaults:

- DM default: `pairing`
- group default: allowlisted group binding + `requireMention = true`
- shared-chat sensitive approvals/questions default to DM reroute
- if DM reroute is needed but no DM exists, persist the request and issue a safe bootstrap prompt in the shared chat
- doctor flows include repair hints for pairing, webhook/polling, group policy, and callback delivery

Telegram-specific identifiers remain in channel bindings, pairing records, delivery receipts, and policy stores. Mission logic stays transport-neutral.

### Runtime Discipline

Borrow the timeout/watchdog rigor from `ai-agent-brain` and apply the Elixir-style supervision lesson to Swift actors and durable state:

- wall-clock timeout, idle timeout, and heartbeat absence are separate signals
- root, worker, ACP, Attractor, and tool executions emit lifecycle events
- heartbeats occur on model-start, first-token, tool-start, tool-end, progress, and completion
- retry policy is explicit on mission stages and tasks
- replay-safe idempotency keys prevent duplicate child work or approval side effects
- escalation always lands in the root inbox

This sprint should also add a small `TheAgentSupervisor` executable or service layer so restart policy is not purely an in-process assumption.

### Reflection and Routing

Borrow `ai-assistant-core` and PicoClaw selectively:

- root-owned post-mission reflection loop
- worker-produced artifacts and mission history as the only reflection inputs; the root alone synthesizes memory candidates and commits memory
- proactive notifications through the existing delivery layer
- deterministic model routing tiers such as `chat_light`, `chat_deep`, `planner`, `implementer`, `reviewer`, `vision`, and `codergen`

Routing is policy, not prompt folklore.

## Implementation

### Phase 1: OmniSkills Core and Installation Model

**Goals**
- create the canonical OmniSkills module
- define manifest, installation, versioning, activation, and projection models
- preserve compatibility with existing skill seams

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
- `Sources/OmniAgentMesh/Models/SkillRecord.swift`
- `Sources/OmniAgentMesh/Stores/SkillStore.swift`
- `Tests/OmniSkillsTests/OmniSkillManifestTests.swift`
- `Tests/OmniSkillsTests/OmniSkillInstallerTests.swift`
- `Tests/OmniSkillsTests/OmniSkillProjectionTests.swift`

**Tasks**
- Define the canonical `omniskill.json` schema.
- Support installation from local directory, local archive, and git checkout path for v1.
- Add durable system/workspace skill records with version pinning.
- Add activation records that tie mission, workspace, actor, and approval context to each activation.
- Import legacy `.claude/commands` and Gemini skill files into OmniSkills-compatible records.
- Add skill capability and budget metadata so later routing/policy stages can reason over them.

### Phase 2: Root Runtime, Provider Bridges, and Shell Skill Compatibility

**Goals**
- make OmniSkills work in the root loop and provider parity layer
- unify skill activation tooling
- compile skills into `OmniAgentsSDK` shell environments

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
- Replace provider-specific skill file scanning with OmniSkills projections.
- Make `claudeSkillTool()` and `activate_skill` resolve from the same registry.
- Add root tools: `list_skills`, `install_skill`, `activate_skill`, `deactivate_skill`, `skill_status`.
- Compile skills into `ShellToolLocalSkill` and `ShellToolContainerSkill` representations.
- Add skill suggestion logic that can recommend but not silently activate high-privilege skills.
- Route installation and approval requests through the root interaction broker.

### Phase 3: OmniSkills in Codergen, ACP, Attractor, and Worker Paths

**Goals**
- make OmniSkills first-class in worker execution
- unify skill propagation through Codergen and ACP-backed paths
- preserve Attractor as the structured worker mode for compound work

**Files**
- `Sources/OmniAIAttractor/Handlers/CodergenHandler.swift`
- `Sources/OmniAIAttractor/Handlers/CodingAgentBackend.swift`
- `Sources/OmniAIAttractor/Handlers/ACPAgentBackend.swift`
- `Sources/OmniAIAttractor/Engine/PipelineEngine.swift`
- `Sources/TheAgentWorker/Attractor/AttractorTaskExecutor.swift`
- `Sources/TheAgentWorker/Attractor/AttractorWorkflowTemplate.swift`
- `Sources/TheAgentWorker/ACP/ACPWorkerSession.swift`
- `Sources/TheAgentWorker/MCP/ToolRegistry.swift`
- `Sources/TheAgentWorker/WorkerExecutorFactory.swift`
- `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift`
- `Tests/TheAgentWorkerTests/OmniSkillCodergenBridgeTests.swift`
- `Tests/TheAgentWorkerTests/OmniSkillACPBridgeTests.swift`
- `Tests/TheAgentWorkerTests/OmniSkillNestedDelegationTests.swift`

**Tasks**
- Extend `PipelineContext` with active OmniSkill bundle metadata.
- Let Attractor graph/node config declare required skills by ID and version.
- Inject skill prompt overlays, artifacts, and capability hints into Codergen runs.
- Allow skill-provided worker tools to appear through the MCP registry.
- Propagate active skills, workspace scope, lineage, and budget metadata to child tasks and child workflows.
- Keep root approval over new high-privilege skill activation even when requested by a worker.

### Phase 4: Channel Policy, Pairing, Onboarding, Upload Staging, and Doctor

**Goals**
- make Telegram a real product surface instead of just a transport
- add policy, onboarding, and diagnostics
- add attachment staging inspired by DeerFlow without changing the root runtime contract

**Files**
- `Sources/TheAgentControlPlane/Policy/ChannelPolicyManager.swift`
- `Sources/TheAgentControlPlane/Policy/PairingStore.swift`
- `Sources/TheAgentControlPlane/Policy/WorkspaceAllowlist.swift`
- `Sources/TheAgentControlPlane/Onboarding/OnboardingWizard.swift`
- `Sources/TheAgentControlPlane/Diagnostics/DoctorService.swift`
- `Sources/TheAgentControlPlane/Diagnostics/DoctorReport.swift`
- `Sources/TheAgentIngress/AttachmentStager.swift`
- `Sources/TheAgentIngress/IngressGateway.swift`
- `Sources/TheAgentIngress/HTTPIngressServer.swift`
- `Sources/TheAgentTelegram/TelegramBotClient.swift`
- `Sources/TheAgentTelegram/TelegramWebhookHandler.swift`
- `Sources/TheAgentTelegram/TelegramPollingRunner.swift`
- `Sources/TheAgentTelegram/TelegramDeliveryFormatter.swift`
- `Sources/TheAgentControlPlane/main.swift`
- `Tests/TheAgentIngressTests/TelegramPairingTests.swift`
- `Tests/TheAgentIngressTests/TelegramPolicyTests.swift`
- `Tests/TheAgentIngressTests/AttachmentStagerTests.swift`
- `Tests/TheAgentControlPlaneTests/DoctorServiceTests.swift`

**Tasks**
- Add DM policy: `pairing`, `allowlist`, `open`, `disabled`.
- Add group policy with per-group membership rules, mention gating, and optional ambient handling.
- Implement pairing codes and onboarding flow for first-contact DMs.
- Add upload/artifact staging so attachments are normalized before mission execution.
- Add doctor reporting that covers channels, pairing, workers, skills, routing, and stalled missions.
- Preserve workspace and channel isolation across all onboarding and doctor flows.

### Phase 5: Watchdogs, Heartbeats, Restart Policy, and External Supervision

**Goals**
- harden the runtime against stalls and partial failures
- make recovery semantics explicit
- keep replay idempotent

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
- `Sources/TheAgentSupervisor/main.swift`
- `Tests/TheAgentControlPlaneTests/TimeoutWatchdogTests.swift`
- `Tests/TheAgentControlPlaneTests/MissionRecoveryTests.swift`
- `Tests/TheAgentWorkerTests/WorkerHeartbeatTests.swift`

**Tasks**
- Add lifecycle heartbeats for root, workers, ACP sessions, Attractor stages, and tools.
- Distinguish wall-clock timeout, idle timeout, and escalation-after-retries.
- Add dead-letter or escalation behavior after retry exhaustion.
- Add process-level supervisor behavior for recovery across crashes.
- Ensure approval and child-task side effects are idempotent during replay.

### Phase 6: Reflection, Proactive Notifications, and Model Routing

**Goals**
- make the root smarter and cheaper over time
- keep memory and notifications tenant-safe
- route models by policy instead of habit

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
- Add post-mission reflection that extracts structured workspace-scoped memory candidates.
- Use mission artifacts and transcripts as reflection inputs; workers do not write memory candidates directly.
- Add deterministic routing tiers keyed by mission stage, active skills, and budget class.
- Add proactive follow-up notifications for background mission completion and monitors.
- Keep all memory and notification data isolated by workspace.

### Phase 7: Live Proof, Docs, and Migration Closure

**Goals**
- prove the product contract live
- document OmniSkills and operator flows
- close the migration story from pre-OmniSkills behavior

**Files**
- `docs/agent-fabric-architecture.md`
- `docs/the-agent-runtime-runbook.md`
- `docs/omniskills.md`
- `Tests/TheAgentIngressTests/TelegramLiveParityTests.swift`
- `Tests/TheAgentWorkerTests/OmniSkillRemoteWorkerProofTests.swift`

**Tasks**
- Run a live Telegram proof with pairing or allowlist onboarding, root mission orchestration, approval routing, and final delivery.
- Run a remote worker proof where an activated OmniSkill affects ACP or Attractor execution.
- Prove workspace isolation for system-scope, workspace-scope, and mission-scope skills.
- Document migration from legacy `.claude/commands` and Gemini skill files into OmniSkills.

## Files Summary

| File | Action | Purpose |
|------|--------|---------|
| `Package.swift` | Modify | Add `OmniSkills`, supervisor, and new test targets |
| `Sources/OmniSkills/OmniSkillManifest.swift` | Create | Canonical skill schema |
| `Sources/OmniSkills/OmniSkillRegistry.swift` | Create | Installed skill discovery |
| `Sources/OmniSkills/OmniSkillInstaller.swift` | Create | Installation and versioning |
| `Sources/OmniSkills/OmniSkillProjection.swift` | Create | Prompt/tool/shell/Codergen/Attractor projections |
| `Sources/OmniAgentMesh/Stores/SkillStore.swift` | Create | Durable skill installation and activation storage |
| `Sources/OmniAIAgent/Providers/AnthropicProfile.swift` | Modify | Replace bespoke skill loading with OmniSkills |
| `Sources/OmniAIAgent/Tools/GeminiParityTools.swift` | Modify | Resolve Gemini skill activation through OmniSkills |
| `Sources/OmniAgentsSDK/Tool.swift` | Modify | Align shell skill environment models with OmniSkills projections |
| `Sources/OmniAIAttractor/Handlers/CodergenHandler.swift` | Modify | Pass active skills into Codergen pipelines |
| `Sources/TheAgentWorker/ACP/ACPWorkerSession.swift` | Modify | Apply OmniSkills in ACP-backed workers |
| `Sources/TheAgentWorker/MCP/ToolRegistry.swift` | Modify | Expose skill-provided worker tools |
| `Sources/TheAgentControlPlane/Policy/ChannelPolicyManager.swift` | Create | Pairing, allowlist, mention, and channel policy |
| `Sources/TheAgentControlPlane/Diagnostics/DoctorService.swift` | Create | Root-owned operator diagnostics |
| `Sources/TheAgentIngress/AttachmentStager.swift` | Create | Upload and attachment normalization |
| `Sources/TheAgentControlPlane/Supervision/TimeoutWatchdog.swift` | Create | Idle-aware stall detection |
| `Sources/TheAgentSupervisor/main.swift` | Create | Process-level supervision entry point |
| `Sources/TheAgentControlPlane/Memory/ReflectionLoop.swift` | Create | Post-mission reflection and memory extraction |
| `Sources/TheAgentControlPlane/Routing/ModelRouter.swift` | Create | Rule-based model routing |
| `docs/omniskills.md` | Create | Skill packaging and operational guide |

## Definition of Done

- [ ] OmniSkills packages can be installed from local path or archive, pinned to a version, and scoped to system, workspace, or mission.
- [ ] One OmniSkills activation path feeds the root session, Anthropic/Gemini parity tools, shell-tool environments, Codergen pipelines, ACP workers, and Attractor workflows.
- [ ] Existing `.claude/commands` and Gemini skill files can be imported or projected into OmniSkills without losing behavior.
- [ ] Root missions record active skills, approval state, and activation reason durably.
- [ ] Telegram pairing, allowlists, mention-gated groups, DM reroute, and onboarding flows work with the existing multi-user workspace model.
- [ ] The root can deliver one doctor report covering ingress, pairing, workers, skills, routing, and stalled missions.
- [ ] Root, worker, ACP, Attractor, and tool executions emit activity heartbeats that support idle-aware timeout enforcement.
- [ ] Crash or restart recovery does not duplicate child tasks, approvals, or other mission side effects.
- [ ] Reflection writes only workspace-scoped memory and can produce proactive follow-up notifications through the root.
- [ ] Model routing chooses different tiers for chat, planning, implementation, review, and vision based on explicit policy.
- [ ] A live Telegram proof demonstrates onboarding plus real mission execution.
- [ ] A remote worker proof demonstrates an activated OmniSkill affecting ACP or Attractor execution on another host.
- [ ] Tests cover OmniSkills manifests, projections, provider bridges, Codergen/ACP/Attractor propagation, Telegram policy, watchdogs, routing, and reflection isolation.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| OmniSkills becomes a second plugin system instead of the unifying one | Medium | High | Make every legacy skill surface an importer or projection into OmniSkills; forbid new parallel registries |
| Skill propagation diverges between root and workers | Medium | High | Use one activation record plus one projection compiler and cover each runtime with integration tests |
| Telegram policy work leaks transport concerns into mission logic | Medium | High | Keep all pairing, allowlist, mention, and doctor logic in ingress/control-plane policy modules |
| Watchdogs create false positives on long-running tasks | Medium | High | Distinguish idle timeout from wall-clock timeout and require lifecycle heartbeat coverage before aggressive retries |
| Reflection leaks tenant data | Low | High | Root-only memory commit, mandatory workspace IDs, and explicit cross-tenant isolation tests |
| Sprint scope is too broad | Medium | High | Land the sprint in this order: OmniSkills core, runtime bridges, channel operations, supervision, reflection/routing, live proof |

## Security Considerations

- OmniSkills must declare required capabilities and default to least privilege.
- Skill-provided shell environments and worker tools must never silently bypass workspace or mission policy.
- Channel access must fail closed by default until pairing or allowlist conditions are satisfied.
- Worker-initiated approvals and questions remain root-owned even when triggered by skills.
- Secrets for Telegram, ACP, skills, or model routing stay external to the repo and out of skill packages.
- Reflection, doctor, and notification outputs must redact tokens, secrets, and private workspace details.

## Dependencies

- Sprint 006 mesh/control-plane durability
- Sprint 007 multi-user runtime, ingress, artifacts, and Attractor worker execution
- Existing `CodergenBackend`, ACP worker path, and `OmniAgentsSDK` shell skill environment models
- User-provided Telegram credentials and bootstrap policy for live proof
- Provider credentials for the routing tiers enabled in the deployment

## Open Questions

1. Should signed remote skill registries be deferred until after local path and archive installs are stable?
2. Which approval classes should remain eligible for in-channel handling in shared Telegram workspaces once pairing and DM reroute exist?
3. Should `TheAgentSupervisor` ship as a separate binary immediately, or first as a library/service layer meant for `launchd` or `systemd` hosting?
4. Should proactive reflection-based notifications be opt-in for all workspaces, or enabled by default only for owner-only personal workspaces?
