Execution errort is written at `docs/sprints/drafts/SPRINT-008-CLAUDE-DRAFT.md` (551 lines). Here's a summary of the key design decisions I took concrete positions on instead of leaving as open questions:

### Positions Taken

1. **OmniSkills package format**: Plain directory + `omniskill.json` manifest. Archive and git-source are explicitly deferred. No registry references in Sprint 008—skills must be locally resolvable.

2. **Skill activation policy**: Explicit-first with auto-suggestion. The root explicitly activates skills, but may auto-suggest based on capability matching. Auto-activation requires workspace policy opt-in for trusted skills.

3. **Skill propagation into workers**: Layered combination—prompt augmentation, tool registration, and shell environment mounts all apply, with the `SkillActivationAdapter` as the single injection point that adapts to execution mode (plain/ACP/Attractor/Codergen).

4. **Channel policy default**: Pairing-first for all external ingress. Open mode is an explicit workspace admin override, not the default. Local-dev/CLI bypasses `IngressGateway` entirely and is unaffected.

5. **Reflection memory**: Root-driven only. Workers produce artifacts; only the root synthesizes memory. Uses economy-tier model, one call per completed mission, keyword/tag retrieval (not vector search).

6. **Model routing**: Deterministic routing table, not AI-driven. Skills declare capabilities and cost tier; the router resolves provider/model pairs. Workspace-configurable with sensible defaults.

7. **Scope management**: Phases 1–2 (OmniSkills) are the hard priority. Phase 5 (routing + reflection) is explicitly callable as deferrable if the sprint runs long.
ession continuity.

The chief-of-staff contract is preserved: one user-facing agent, everything else internal. OmniSkills extend what the agent and its workers can do; they do not create a second user-facing surface or a competing plugin model.

## Use Cases

1. **Skill-augmented mission**: An operator asks "research competitor pricing and produce a summary deck." The root selects an `OmniSkill` (e.g., `web-research`) that injects prompt guidance, tool registrations, and shell environment configuration into the delegated worker task—whether that worker runs locally, via ACP, or as an Attractor workflow—without the operator manually configuring anything.

2. **Write-once skill portability**: A skill author writes a single `omniskill.json` manifest with prompt fragments, tool schemas, and optional shell environment mounts. The same skill works in root direct-execution sessions, in CodergenBackend pipeline nodes, in ACP agent sessions, and in container-backed shell-tool environments. No per-backend skill reimplementation.

3. **Secure channel onboarding**: A stranger discovers the Telegram bot and sends a message. Instead of reaching the root runtime, they hit a pairing gate that requires an invitation code or admin approval. Once paired, they enter a lightweight onboarding flow that provisions their workspace and sets initial channel policy.

4. **Operator diagnostics**: The operator sends `/doctor`. The root inspects mesh connectivity, loaded skills, active workers, channel bindings, pending approvals, and workspace policy, then returns a structured health report without exposing internal state to non-admin actors.

5. **Heartbeat-aware stall detection**: A remote ACP worker executing a Codergen task stops emitting heartbeats for 90 seconds. The `MissionSupervisor` detects the stall, marks the task as `stalled`, attempts one supervised restart, and—if the restart also stalls—escalates to the operator's inbox with a diagnostic summary.

6. **Cost-aware model routing**: A skill declares `capability: "code-generation"` and `cost_tier: "standard"`. The `ModelRouter` selects Claude Sonnet for this task instead of Opus, honoring the workspace's cost policy. A different skill requiring deep reasoning routes to Opus. The operator never manually picks models per task.

7. **Proactive memory recall**: After completing a multi-day mission about API design, the reflection loop distills key decisions, constraints, and outcomes into workspace-scoped structured memory. Three weeks later, when the operator asks about API versioning, the root proactively surfaces the relevant prior decisions without being asked to search.

8. **Skill-enabled Attractor workflow**: A worker running a `plan → implement → validate` Attractor pipeline activates the `swift-codergen` skill for the `implement` stage. The skill injects Swift-specific prompt guidance, registers `swift build` and `swift test` as tool actions, and mounts a configured shell environment—all driven by the manifest, not hardcoded backend logic.

## Architecture

### Extended Topology

```text
                      Telegram / HTTP API
                               |
                               v
                 +-----------------------------+
                 | IngressGateway              |
                 | + ChannelPolicyMiddleware   |
                 | pairing / allowlist / onboard|
                 +-------------+---------------+
                               |
                    identity / workspace bind
                               |
                               v
                 +-----------------------------+
                 | WorkspaceRuntimeRegistry    |
                 | one root runtime per scope  |
                 +-------------+---------------+
                               |
                               v
                 +--------------------------------------+
                 | RootAgentRuntime                     |
                 | + OmniSkillRegistry (workspace)     |
                 | + ModelRouter                        |
                 | + ReflectionLoop                     |
                 | chief-of-staff per workspace/channel |
                 +------+------+-----------------------+
                        |      |
                        |      +-------------------------------+
                        |                                      |
                        v                                      v
              +--------------------+             +------------------------+
              | InteractionBroker  |             | MissionCoordinator     |
              | approvals/questions|             | + skill-aware dispatch  |
              +--------+-----------+             +----------+-------------+
                       |                                    |
                       |                              skill injection
                       |                                    |
                       v                                    v
            +---------------------+          +-------------------------------+
            | Telegram/API replies|          | Worker Daemons                |
            | + DM-routed approvals|         | local / ACP / Attractor mode  |
            +---------------------+          | + OmniSkillActivation        |
                                             +---------------+---------------+
                                                             |
                                                             v
                                             +-------------------------------+
                                             | ChildWorkerManager            |
                                             | + skill propagation           |
                                             | + heartbeat + timeout guards  |
                                             +-------------------------------+
```

### OmniSkills Architecture

OmniSkills is a **layered injection system**, not a plugin framework. A skill is a static manifest that declares what it contributes, and the runtime decides where and how to inject those contributions based on execution context.

**Manifest format**: A skill is a directory containing an `omniskill.json` manifest. The canonical format is a plain directory; archive (`.omniskill.zip`) and git-source installation are Phase 2 conveniences that this sprint does not implement. Registry references are not supported in Sprint 008—skills must be resolvable locally at activation time.

```text
my-skill/
  omniskill.json        # manifest (required)
  prompts/              # prompt fragments (optional)
    system.md
    guidance.md
  tools/                # tool schemas + implementations (optional)
    run-tests.json
  environment/          # shell environment config (optional)
    setup.sh
    requirements.txt
```

**Manifest schema** (`omniskill.json`):

```json
{
  "name": "swift-codergen",
  "version": "1.0.0",
  "description": "Swift code generation and validation skill",
  "capabilities": ["code-generation", "swift", "testing"],
  "cost_tier": "standard",

  "prompts": {
    "system_augmentation": "prompts/system.md",
    "guidance": "prompts/guidance.md"
  },

  "tools": [
    {
      "name": "swift_build",
      "description": "Build the Swift package",
      "schema_path": "tools/swift-build.json",
      "shell_command": "swift build",
      "requires_shell": true
    }
  ],

  "environment": {
    "type": "local",
    "setup_script": "environment/setup.sh",
    "working_directory_relative": true
  },

  "activation": {
    "mode": "explicit",
    "auto_match_capabilities": ["code-generation", "swift"]
  },

  "constraints": {
    "max_concurrent": 3,
    "timeout_seconds": 600,
    "requires_approval": false
  }
}
```

**Injection layers**: When a skill is activated for an execution context, the runtime applies its contributions as layers:

| Layer | Root Session | Worker Task | Attractor Stage | ACP Session | CodergenBackend |
|-------|-------------|-------------|-----------------|-------------|-----------------|
| Prompt augmentation | System prompt append | Task prompt append | Stage prompt append | Session prompt prepend | Context key injection |
| Tool registration | `FunctionTool` addition | Task tool addition | Stage tool addition | ACP tool declaration | Handler tool injection |
| Shell environment | `ShellToolLocalEnvironment` | Worker shell mount | Stage shell mount | Terminal delegation config | Codergen working dir setup |
| Constraints | Budget/timeout overlay | Task timeout overlay | Stage budget overlay | Session timeout | Pipeline timeout |

**Activation policy**: Activation is **explicit-first with auto-suggestion**. The root or a worker explicitly activates a skill for a mission/task. The root may also auto-suggest skills when a mission's description matches a skill's `auto_match_capabilities`, but the suggestion requires operator confirmation unless the workspace policy enables auto-activation for trusted skills.

**Skill propagation into workers**: When the `MissionCoordinator` dispatches a task to a worker, it serializes the active skill activation set into the task record. The worker-side `SkillActivationAdapter` reads the activation set and applies the appropriate injection layers for its execution mode (plain, ACP, or Attractor). Skills do not need to know which execution mode they are running in.

### Channel Policy Architecture (from OpenClaw)

Channel policy is a **middleware layer** inside `IngressGateway`, not a separate service. It intercepts every `IngressEnvelope` before workspace routing and enforces:

- **Pairing gate**: New Telegram users must present an invitation code or be approved by a workspace admin before their messages reach the root runtime. The default for all channels is pairing-first.
- **Workspace allowlist**: Each workspace maintains an explicit actor allowlist. Actors not on the list hit the pairing gate even if they have interacted before (prevents stale access).
- **Group policy**: Shared Telegram groups default to mention/reply-only triggering (carried forward from Sprint 007). The channel policy layer adds admin-configurable ambient mode and per-group skill restrictions.
- **Onboarding flow**: Paired actors who have not completed onboarding enter a lightweight guided flow that sets workspace preferences, default skill activations, and notification policies. This is a finite state machine, not a conversational AI interaction—it uses inline Telegram buttons where possible.

### Supervision Architecture (from ai-agent-brain)

Supervision is added to three layers:

1. **Mesh heartbeat**: Workers emit periodic heartbeats to the control plane via `HTTPMeshClient`. The `WorkerLivenessMonitor` (new) tracks last-seen timestamps and marks workers as `stale` after a configurable threshold (default: 60s). Stale workers' in-flight tasks are flagged for supervisor review.

2. **Mission idle timeout**: `MissionSupervisor` (existing, extended) tracks elapsed wall-clock time since last progress event per mission stage. If a stage exceeds its idle timeout (default: 120s, overridable by skill or workspace policy), the supervisor attempts one restart. If the restart also stalls, it escalates to the operator inbox.

3. **Dead-letter escalation**: After retry exhaustion (bounded by mission policy, default: 3 attempts), failed stages emit a structured diagnostic summary and enter a `dead_letter` state. The operator can inspect, retry with different parameters, or cancel.

### Model Routing Architecture (from PicoClaw)

`ModelRouter` is a lightweight, deterministic routing table—not an AI-driven selector. It maps `(capability_tags, cost_tier, workspace_policy)` to `(provider, model)` tuples.

```swift
struct ModelRoute: Sendable, Codable {
    var capabilities: Set<String>
    var costTier: CostTier          // .economy, .standard, .premium
    var provider: String            // "anthropic", "google", "openai"
    var model: String               // "claude-sonnet-4-20250514", etc.
    var priority: Int               // lower wins within a capability match
}
```

The router is configured per workspace with a default routing table. Skills declare their preferred `capabilities` and `cost_tier`; the router resolves the concrete provider/model at dispatch time. If no route matches, the workspace's default model is used. The router does not make API calls or use AI to decide routing.

### Reflection and Proactive Memory Architecture (from ai-assistant-core)

Reflection is **root-driven only**. Workers do not contribute memory candidates directly—they produce artifacts, and the reflection loop processes those artifacts at the root level. This avoids cross-tenant memory contamination and keeps the memory authority centralized.

The `ReflectionLoop` runs as a background task attached to `RootAgentRuntime`:

1. After a mission completes, the loop collects the mission contract, progress artifacts, verification reports, and conversation transcript.
2. It synthesizes structured memory entries: decisions made, constraints discovered, outcomes achieved, and lessons learned.
3. Entries are stored in `MemoryStore` (new SQLite-backed store) scoped to `workspaceID`.
4. During future root sessions, the `RootOrchestratorProfile` queries `MemoryStore` for relevant prior context and injects it as system prompt augmentation.

Memory retrieval is keyword/tag-based in Sprint 008, not vector-search. Vector retrieval is a follow-on optimization.

## Implementation

### Phase 1: OmniSkills Core — Manifest, Registry, and Activation

**Goals**
- Define the canonical skill manifest schema
- Build a workspace-scoped skill registry with discovery, validation, and activation
- Implement the skill activation adapter that maps manifest declarations to runtime injection layers

**Files**
- `Sources/OmniAgentsSDK/Skills/OmniSkillManifest.swift` — Create
- `Sources/OmniAgentsSDK/Skills/OmniSkillRegistry.swift` — Create
- `Sources/OmniAgentsSDK/Skills/OmniSkillActivation.swift` — Create
- `Sources/OmniAgentsSDK/Skills/OmniSkillError.swift` — Create
- `Sources/OmniAgentsSDK/Skills/SkillPromptLoader.swift` — Create
- `Sources/OmniAgentsSDK/Skills/SkillToolBuilder.swift` — Create
- `Sources/OmniAgentsSDK/Skills/SkillEnvironmentBuilder.swift` — Create
- `Sources/OmniAgentsSDK/Tool.swift` — Modify (add skill-sourced tool factory)
- `Tests/OmniAgentsSDKTests/Skills/OmniSkillManifestTests.swift` — Create
- `Tests/OmniAgentsSDKTests/Skills/OmniSkillRegistryTests.swift` — Create
- `Tests/OmniAgentsSDKTests/Skills/OmniSkillActivationTests.swift` — Create

**Tasks**
- [ ] Define `OmniSkillManifest` as a `Codable`, `Sendable` struct matching the manifest schema above. Include prompt references, tool declarations, environment config, activation policy, and constraints.
- [ ] Build `OmniSkillRegistry` as a workspace-scoped actor that discovers skills from a configurable search path (default: `.ai/the-agent/skills/`), validates manifests, and tracks installed/activated state.
- [ ] Implement `OmniSkillActivation` as the serializable activation record carried through mission/task dispatch. It captures which skills are active and their resolved configuration for the target execution context.
- [ ] Implement `SkillPromptLoader` that reads prompt fragment files and produces system-prompt augmentation strings.
- [ ] Implement `SkillToolBuilder` that reads tool declarations from manifests and produces `FunctionTool` instances with shell-command backing where `requires_shell` is true.
- [ ] Implement `SkillEnvironmentBuilder` that maps manifest environment config to `ShellToolLocalEnvironment` or `ShellToolContainerAutoEnvironment` depending on the target context.
- [ ] Add a `skillSourcedTools()` method or factory that converts skill tool declarations into the existing `Tool` enum cases.
- [ ] Validate that malformed manifests, missing prompt files, and invalid tool schemas produce clear errors rather than silent failures.
- [ ] Test manifest round-trip encoding/decoding, registry discovery from filesystem, activation serialization, and prompt/tool/environment building.

### Phase 2: OmniSkills Integration — Root, Worker, Attractor, ACP, and Codergen

**Goals**
- Wire skill activation into every execution path
- Ensure skills propagate through mission dispatch without backend-specific skill code
- Converge existing fragmented skill patterns (`.claude/commands`, Gemini `activate_skill`) into OmniSkills

**Files**
- `Sources/TheAgentControlPlane/RootAgentToolbox.swift` — Modify (add `activate_skill`, `list_skills`, `deactivate_skill` tools)
- `Sources/TheAgentControlPlane/RootOrchestratorProfile.swift` — Modify (inject active skill prompts)
- `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift` — Modify (carry skill activations in task dispatch)
- `Sources/TheAgentWorker/Skills/SkillActivationAdapter.swift` — Create
- `Sources/TheAgentWorker/WorkerExecutorFactory.swift` — Modify (apply skill layers per execution mode)
- `Sources/TheAgentWorker/Attractor/AttractorTaskExecutor.swift` — Modify (inject skill prompts/tools into pipeline stages)
- `Sources/OmniAIAttractor/Handlers/CodergenHandler.swift` — Modify (accept skill context keys)
- `Sources/OmniAIAttractor/Handlers/CodingAgentBackend.swift` — Modify (apply skill environment to ACP/Codergen sessions)
- `Sources/OmniAIAgent/Providers/AnthropicProfile.swift` — Modify (replace `.claude/commands` loading with OmniSkills query)
- `Sources/OmniAIAgent/Tools/GeminiParityTools.swift` — Modify (replace `activate_skill` with OmniSkills delegation)
- `Sources/OmniAIAgent/Tools/ToolRegistry.swift` — Modify (accept skill-sourced tools alongside static tools)
- `Tests/TheAgentWorkerTests/SkillActivationAdapterTests.swift` — Create
- `Tests/TheAgentControlPlaneTests/SkillIntegrationTests.swift` — Create

**Tasks**
- [ ] Add `activate_skill`, `list_skills`, and `deactivate_skill` as root mission tools in `RootAgentToolbox`. `activate_skill` takes a skill name and optional mission scope; `list_skills` returns installed skills with activation status.
- [ ] Modify `RootOrchestratorProfile` to query the workspace's `OmniSkillRegistry` for currently active skills and append their prompt augmentations to the root system prompt.
- [ ] Modify `MissionCoordinator` to serialize `OmniSkillActivation` records into `TaskRecord` when dispatching worker tasks. Workers receive skill activation as task metadata, not as a separate RPC.
- [ ] Create `SkillActivationAdapter` in `TheAgentWorker` that reads activation records from task metadata and applies prompt/tool/environment layers appropriate to the worker's execution mode.
- [ ] For plain local workers: inject prompt augmentation into the worker's `Session` system prompt, register skill tools into the worker's tool set, and configure `ShellToolLocalEnvironment` with skill-declared setup.
- [ ] For ACP-backed workers: inject prompt augmentation as session prompt, declare skill tools as ACP tool schemas, and configure terminal delegation with skill environment settings.
- [ ] For Attractor-backed workers: inject prompt augmentation as stage-level context keys, register skill tools into the relevant pipeline stage handlers, and mount skill shell environments into Codergen working directories.
- [ ] Migrate `AnthropicProfile` `.claude/commands` loading to read from `OmniSkillRegistry` instead. Existing `.claude/commands` directories should auto-discover as legacy skills with a compatibility adapter.
- [ ] Migrate `GeminiParityTools.activate_skill` to delegate to `OmniSkillRegistry.activate` instead of maintaining a parallel activation model.
- [ ] Test that the same skill manifest produces correct injection across all four execution modes (root, plain worker, ACP worker, Attractor worker).
- [ ] Test skill propagation through recursive child delegation (child tasks inherit parent skill activations unless explicitly overridden).

### Phase 3: Channel Policy, Onboarding, and Diagnostics

**Goals**
- Add pairing-first channel security to all ingress surfaces
- Implement lightweight onboarding for newly paired actors
- Add `/doctor` runtime diagnostics

**Files**
- `Sources/TheAgentControlPlane/Policy/ChannelPolicyManager.swift` — Create
- `Sources/TheAgentControlPlane/Policy/PairingGate.swift` — Create
- `Sources/TheAgentControlPlane/Policy/OnboardingStateMachine.swift` — Create
- `Sources/TheAgentControlPlane/Diagnostics/DoctorCommand.swift` — Create
- `Sources/TheAgentIngress/IngressGateway.swift` — Modify (insert policy middleware)
- `Sources/OmniAgentMesh/Models/ChannelBinding.swift` — Modify (add pairing state and policy fields)
- `Sources/OmniAgentMesh/Stores/IdentityStore.swift` — Modify (add pairing/allowlist persistence)
- `Sources/TheAgentControlPlane/RootAgentToolbox.swift` — Modify (add `/doctor` tool)
- `Tests/TheAgentIngressTests/ChannelPolicyTests.swift` — Create
- `Tests/TheAgentIngressTests/OnboardingTests.swift` — Create
- `Tests/TheAgentControlPlaneTests/DoctorTests.swift` — Create

**Tasks**
- [ ] Implement `ChannelPolicyManager` as middleware inside `IngressGateway` that intercepts every `IngressEnvelope` and enforces pairing, allowlist, and group-policy rules before workspace routing.
- [ ] Implement `PairingGate` that requires new actors to present an invitation code (operator-generated, single-use or multi-use with a cap) before their messages reach the root runtime. Unpaired actors receive a fixed pairing prompt, not silence.
- [ ] Add pairing state (`unpaired`, `pending_approval`, `paired`, `blocked`) and policy fields (`ambient_mode`, `skill_restrictions`, `admin_only`) to `ChannelBinding`.
- [ ] Implement `OnboardingStateMachine` as a finite-state flow (not a conversational agent) that guides newly paired actors through workspace setup. States: `welcome` → `preferences` → `skill_defaults` → `complete`. Use Telegram inline buttons for choices where possible.
- [ ] Default all channels to pairing-first. Workspace admins can switch specific channels to open mode via a policy override (this is intentionally not the default).
- [ ] Implement `DoctorCommand` that inspects: mesh worker connectivity, loaded/activated skills, channel bindings and policy, pending approval/question count, workspace budget usage, and recent mission failure summary.
- [ ] Register `/doctor` as a root tool. Non-admin actors in shared workspaces receive a redacted health summary (e.g., "system healthy" / "issues detected") instead of full diagnostics.
- [ ] Persist invitation codes in `IdentityStore` with creation time, use count, max uses, and expiration.
- [ ] Test: unpaired actor messages are blocked; valid pairing code grants access; expired/exhausted codes are rejected; onboarding state machine completes correctly; doctor output reflects actual system state.

### Phase 4: Supervision, Heartbeat, and Idle-Timeout Hardening

**Goals**
- Add heartbeat-based worker liveness monitoring
- Implement idle-aware mission timeout and stall escalation
- Add dead-letter behavior after retry exhaustion

**Files**
- `Sources/OmniAgentMesh/Transport/HTTPMeshProtocol.swift` — Modify (add heartbeat message type)
- `Sources/OmniAgentMesh/Transport/HTTPMeshServer.swift` — Modify (accept heartbeat, expose liveness API)
- `Sources/OmniAgentMesh/Transport/HTTPMeshClient.swift` — Modify (emit periodic heartbeats)
- `Sources/TheAgentControlPlane/Supervision/WorkerLivenessMonitor.swift` — Create
- `Sources/TheAgentControlPlane/Missions/MissionSupervisor.swift` — Modify (add idle timeout and dead-letter logic)
- `Sources/TheAgentControlPlane/Supervision/DeadLetterStore.swift` — Create
- `Sources/TheAgentWorker/WorkerDaemon.swift` — Modify (emit heartbeats from worker main loop)
- `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift` — Modify (propagate heartbeat from child tasks)
- `Tests/TheAgentControlPlaneTests/WorkerLivenessTests.swift` — Create
- `Tests/TheAgentControlPlaneTests/MissionTimeoutTests.swift` — Create
- `Tests/TheAgentControlPlaneTests/DeadLetterTests.swift` — Create

**Tasks**
- [ ] Add a `heartbeat` message type to `HTTPMeshProtocol`. Workers emit heartbeats every 30 seconds (configurable). Each heartbeat includes worker ID, current task ID (if any), memory/load hints, and timestamp.
- [ ] Implement `WorkerLivenessMonitor` as an actor that tracks per-worker last-seen timestamps. Workers not seen for 60s are marked `stale`. Workers not seen for 180s are marked `presumed_dead` and their in-flight tasks are flagged for supervisor review.
- [ ] Extend `MissionSupervisor` with idle-timeout detection: if a mission stage has not received a progress event or heartbeat correlation within its idle timeout window, the supervisor triggers a restart attempt.
- [ ] Implement bounded restart: first stall triggers one supervised restart (re-dispatch task to same or different worker). Second consecutive stall on the same stage escalates to operator inbox.
- [ ] Implement `DeadLetterStore` for stages that exhaust their retry budget. Dead-lettered stages include: original task context, error/timeout summary, attempt history, and suggested operator actions (retry, cancel, reassign).
- [ ] Surface dead-letter items in the operator's `list_inbox` results alongside approvals and questions.
- [ ] Emit structured telemetry events for: heartbeat received, worker marked stale, worker marked dead, stage idle timeout, stage restart, stage dead-lettered.
- [ ] Test: simulated worker disappearance triggers stale → dead marking; idle stage triggers restart then escalation; dead-letter entries appear in operator inbox; heartbeat resume clears stale status.

### Phase 5: Model Routing and Reflection Memory

**Goals**
- Add deterministic model routing based on skill capabilities and workspace policy
- Implement root-driven reflection loop and structured memory store
- Wire proactive memory into root session prompt augmentation

**Files**
- `Sources/TheAgentControlPlane/Routing/ModelRouter.swift` — Create
- `Sources/TheAgentControlPlane/Routing/ModelRoute.swift` — Create
- `Sources/TheAgentControlPlane/Routing/DefaultRoutingTable.swift` — Create
- `Sources/TheAgentControlPlane/Memory/ReflectionLoop.swift` — Create
- `Sources/TheAgentControlPlane/Memory/MemoryEntry.swift` — Create
- `Sources/OmniAgentMesh/Stores/MemoryStore.swift` — Create
- `Sources/TheAgentControlPlane/RootAgentRuntime.swift` — Modify (attach reflection loop and model router)
- `Sources/TheAgentControlPlane/RootOrchestratorProfile.swift` — Modify (inject relevant memory into system prompt)
- `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift` — Modify (use model router for task dispatch)
- `Tests/TheAgentControlPlaneTests/ModelRouterTests.swift` — Create
- `Tests/TheAgentControlPlaneTests/ReflectionLoopTests.swift` — Create
- `Tests/OmniAgentMeshTests/MemoryStoreTests.swift` — Create

**Tasks**
- [ ] Define `ModelRoute` as a `Sendable`, `Codable` struct with capability tags, cost tier, provider/model pair, and priority.
- [ ] Implement `ModelRouter` as a deterministic lookup: given a set of capability tags and a cost tier, return the highest-priority matching route. Fall back to workspace default model if no route matches.
- [ ] Provide `DefaultRoutingTable` with sensible defaults (e.g., `code-generation` + `standard` → Claude Sonnet, `deep-reasoning` + `premium` → Claude Opus, `fast-lookup` + `economy` → Gemini Flash). Workspaces can override.
- [ ] Modify `MissionCoordinator` to consult `ModelRouter` when dispatching tasks. The resolved model is carried in the task record so workers use the routed model, not their default.
- [ ] Implement `MemoryEntry` as a `Codable` struct: workspace ID, tags, summary text, source mission ID, created timestamp, relevance score (static, not ML-derived).
- [ ] Implement `MemoryStore` as a SQLite-backed store with workspace-scoped CRUD and tag-based retrieval.
- [ ] Implement `ReflectionLoop` as a background task on `RootAgentRuntime`. After mission completion, it collects mission artifacts, feeds them through a single model call to extract structured memory entries, and persists them. The reflection call uses the workspace's economy-tier model, not the primary model.
- [ ] Modify `RootOrchestratorProfile` to query `MemoryStore` for entries matching the current conversation's recent keywords/tags and inject up to 5 relevant entries as "prior context" in the system prompt.
- [ ] Reflection is opt-in per workspace (default: enabled). Operators can disable it or clear memory.
- [ ] Test: routing table resolves correctly for various capability/tier combinations; reflection loop produces memory entries from mock mission artifacts; memory entries are retrievable by tag; memory is workspace-isolated.

### Phase 6: End-to-End Integration, Migration, and Live Proof

**Goals**
- Wire all new systems together and verify cross-cutting behavior
- Migrate existing fragmented skill patterns
- Prove the full stack live

**Files**
- `Package.swift` — Modify (add new targets and test targets)
- `Sources/TheAgentControlPlane/main.swift` — Modify (wire new subsystems)
- `Sources/TheAgentWorker/main.swift` — Modify (wire skill adapter and heartbeat)
- `Tests/TheAgentControlPlaneTests/EndToEndSkillMissionTests.swift` — Create
- `Tests/TheAgentControlPlaneTests/ChannelPolicyEndToEndTests.swift` — Create
- `Tests/TheAgentWorkerTests/HeartbeatSupervisionTests.swift` — Create
- `docs/agent-fabric-architecture.md` — Modify (document OmniSkills, channel policy, supervision, routing, and reflection)
- `docs/the-agent-runtime-runbook.md` — Modify (add skill installation, channel policy config, and doctor usage)
- `docs/sprints/SPRINT-008.md` — Create (final merged sprint document)

**Tasks**
- [ ] Wire `OmniSkillRegistry`, `ChannelPolicyManager`, `WorkerLivenessMonitor`, `ModelRouter`, and `ReflectionLoop` into the control plane startup path.
- [ ] Wire `SkillActivationAdapter` and heartbeat emission into the worker startup path.
- [ ] Add migration logic that discovers existing `.claude/commands` directories and registers them as legacy OmniSkills with a compatibility manifest.
- [ ] End-to-end test: create a skill, activate it for a mission, dispatch to a worker, verify skill prompt/tool/environment injection, complete mission, verify reflection memory creation.
- [ ] End-to-end test: unpaired actor attempts interaction → pairing gate → pairing code → onboarding → successful mission.
- [ ] End-to-end test: worker stalls → heartbeat timeout → supervisor restart → second stall → dead-letter escalation to operator inbox.
- [ ] End-to-end test: skill with `cost_tier: "economy"` routes to economy model; same mission with `premium` skill routes to premium model.
- [ ] Live proof: Telegram ingress → pairing → skill-augmented mission → remote worker with heartbeat → completion → reflection memory → proactive recall in next session.
- [ ] Update `agent-fabric-architecture.md` with OmniSkills topology, channel policy flow, supervision model, routing table, and reflection loop.
- [ ] Update `the-agent-runtime-runbook.md` with skill installation instructions, channel policy configuration, invitation code generation, and `/doctor` usage.

## Files Summary

| File | Action | Purpose |
|------|--------|---------|
| `Package.swift` | Modify | Add Skills test targets and new module dependencies |
| **OmniSkills Core** | | |
| `Sources/OmniAgentsSDK/Skills/OmniSkillManifest.swift` | Create | Skill manifest schema and Codable model |
| `Sources/OmniAgentsSDK/Skills/OmniSkillRegistry.swift` | Create | Workspace-scoped skill discovery, validation, and lifecycle |
| `Sources/OmniAgentsSDK/Skills/OmniSkillActivation.swift` | Create | Serializable activation record for task dispatch |
| `Sources/OmniAgentsSDK/Skills/OmniSkillError.swift` | Create | Structured skill error types |
| `Sources/OmniAgentsSDK/Skills/SkillPromptLoader.swift` | Create | Prompt fragment file reading and composition |
| `Sources/OmniAgentsSDK/Skills/SkillToolBuilder.swift` | Create | Manifest tool declarations → FunctionTool instances |
| `Sources/OmniAgentsSDK/Skills/SkillEnvironmentBuilder.swift` | Create | Manifest environment config → ShellToolEnvironment |
| `Sources/OmniAgentsSDK/Tool.swift` | Modify | Add skill-sourced tool factory method |
| **OmniSkills Integration** | | |
| `Sources/TheAgentWorker/Skills/SkillActivationAdapter.swift` | Create | Worker-side skill injection across execution modes |
| `Sources/TheAgentControlPlane/RootAgentToolbox.swift` | Modify | Add skill and doctor tools |
| `Sources/TheAgentControlPlane/RootOrchestratorProfile.swift` | Modify | Inject skill prompts and memory context |
| `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift` | Modify | Skill-aware and route-aware task dispatch |
| `Sources/TheAgentWorker/WorkerExecutorFactory.swift` | Modify | Apply skill layers per execution mode |
| `Sources/TheAgentWorker/Attractor/AttractorTaskExecutor.swift` | Modify | Inject skill context into Attractor stages |
| `Sources/OmniAIAttractor/Handlers/CodergenHandler.swift` | Modify | Accept skill context keys |
| `Sources/OmniAIAttractor/Handlers/CodingAgentBackend.swift` | Modify | Apply skill environment to ACP/Codergen |
| `Sources/OmniAIAgent/Providers/AnthropicProfile.swift` | Modify | Replace .claude/commands with OmniSkills |
| `Sources/OmniAIAgent/Tools/GeminiParityTools.swift` | Modify | Replace activate_skill with OmniSkills |
| `Sources/OmniAIAgent/Tools/ToolRegistry.swift` | Modify | Accept skill-sourced tools |
| **Channel Policy** | | |
| `Sources/TheAgentControlPlane/Policy/ChannelPolicyManager.swift` | Create | Ingress policy middleware |
| `Sources/TheAgentControlPlane/Policy/PairingGate.swift` | Create | Invitation-code pairing enforcement |
| `Sources/TheAgentControlPlane/Policy/OnboardingStateMachine.swift` | Create | Post-pairing guided workspace setup |
| `Sources/TheAgentIngress/IngressGateway.swift` | Modify | Insert channel policy middleware |
| `Sources/OmniAgentMesh/Models/ChannelBinding.swift` | Modify | Add pairing state and policy fields |
| `Sources/OmniAgentMesh/Stores/IdentityStore.swift` | Modify | Persist pairing/allowlist/invitation data |
| **Diagnostics** | | |
| `Sources/TheAgentControlPlane/Diagnostics/DoctorCommand.swift` | Create | Runtime health inspection |
| **Supervision** | | |
| `Sources/TheAgentControlPlane/Supervision/WorkerLivenessMonitor.swift` | Create | Heartbeat-based worker liveness tracking |
| `Sources/TheAgentControlPlane/Supervision/DeadLetterStore.swift` | Create | Dead-lettered stage persistence |
| `Sources/TheAgentControlPlane/Missions/MissionSupervisor.swift` | Modify | Add idle timeout and dead-letter logic |
| `Sources/OmniAgentMesh/Transport/HTTPMeshProtocol.swift` | Modify | Add heartbeat message type |
| `Sources/OmniAgentMesh/Transport/HTTPMeshServer.swift` | Modify | Accept heartbeats and expose liveness |
| `Sources/OmniAgentMesh/Transport/HTTPMeshClient.swift` | Modify | Emit periodic heartbeats |
| `Sources/TheAgentWorker/WorkerDaemon.swift` | Modify | Emit heartbeats and wire skill adapter |
| `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift` | Modify | Propagate heartbeat from child tasks |
| **Model Routing** | | |
| `Sources/TheAgentControlPlane/Routing/ModelRouter.swift` | Create | Deterministic capability/tier → model resolution |
| `Sources/TheAgentControlPlane/Routing/ModelRoute.swift` | Create | Route definition model |
| `Sources/TheAgentControlPlane/Routing/DefaultRoutingTable.swift` | Create | Sensible default route table |
| **Reflection Memory** | | |
| `Sources/TheAgentControlPlane/Memory/ReflectionLoop.swift` | Create | Background mission-completion memory synthesis |
| `Sources/TheAgentControlPlane/Memory/MemoryEntry.swift` | Create | Structured memory record model |
| `Sources/OmniAgentMesh/Stores/MemoryStore.swift` | Create | SQLite-backed workspace-scoped memory |
| `Sources/TheAgentControlPlane/RootAgentRuntime.swift` | Modify | Attach reflection, router, and liveness monitor |
| **Tests** | | |
| `Tests/OmniAgentsSDKTests/Skills/OmniSkillManifestTests.swift` | Create | Manifest encoding/decoding |
| `Tests/OmniAgentsSDKTests/Skills/OmniSkillRegistryTests.swift` | Create | Registry discovery and lifecycle |
| `Tests/OmniAgentsSDKTests/Skills/OmniSkillActivationTests.swift` | Create | Activation serialization and layer application |
| `Tests/TheAgentWorkerTests/SkillActivationAdapterTests.swift` | Create | Worker-side skill injection |
| `Tests/TheAgentControlPlaneTests/SkillIntegrationTests.swift` | Create | Root → worker → Attractor skill propagation |
| `Tests/TheAgentIngressTests/ChannelPolicyTests.swift` | Create | Pairing, allowlist, group policy |
| `Tests/TheAgentIngressTests/OnboardingTests.swift` | Create | Onboarding state machine |
| `Tests/TheAgentControlPlaneTests/DoctorTests.swift` | Create | Diagnostics output |
| `Tests/TheAgentControlPlaneTests/WorkerLivenessTests.swift` | Create | Heartbeat and stale-worker detection |
| `Tests/TheAgentControlPlaneTests/MissionTimeoutTests.swift` | Create | Idle timeout and restart escalation |
| `Tests/TheAgentControlPlaneTests/DeadLetterTests.swift` | Create | Retry exhaustion and dead-letter behavior |
| `Tests/TheAgentControlPlaneTests/ModelRouterTests.swift` | Create | Route resolution |
| `Tests/TheAgentControlPlaneTests/ReflectionLoopTests.swift` | Create | Memory synthesis and retrieval |
| `Tests/OmniAgentMeshTests/MemoryStoreTests.swift` | Create | Memory store persistence and isolation |
| `Tests/TheAgentControlPlaneTests/EndToEndSkillMissionTests.swift` | Create | Full skill → mission → worker → reflection |
| `Tests/TheAgentControlPlaneTests/ChannelPolicyEndToEndTests.swift` | Create | Pairing → onboarding → mission flow |
| `Tests/TheAgentWorkerTests/HeartbeatSupervisionTests.swift` | Create | Worker liveness + supervisor restart |
| **Docs** | | |
| `docs/agent-fabric-architecture.md` | Modify | Add OmniSkills, policy, supervision, routing, reflection |
| `docs/the-agent-runtime-runbook.md` | Modify | Add skill install, policy config, doctor usage |

## Definition of Done

- [ ] An operator can install a skill by placing a directory with `omniskill.json` in `.ai/the-agent/skills/` and the registry discovers and validates it on startup.
- [ ] `activate_skill` and `list_skills` work as root mission tools; the root can activate, inspect, and deactivate skills within a workspace session.
- [ ] The same skill manifest produces correct prompt augmentation, tool registration, and environment configuration across root direct execution, plain worker tasks, ACP-backed tasks, and Attractor-backed workflows.
- [ ] Skill activations serialize into task records and propagate through worker dispatch without backend-specific skill plumbing.
- [ ] Existing `.claude/commands` directories are auto-discovered as legacy OmniSkills and work without manual migration.
- [ ] Existing Gemini `activate_skill` calls delegate to `OmniSkillRegistry` instead of maintaining a parallel model.
- [ ] Unpaired Telegram actors cannot reach the root runtime; they receive a pairing prompt.
- [ ] Valid invitation codes grant pairing; expired or exhausted codes are rejected.
- [ ] Newly paired actors complete the onboarding flow before entering the main workspace.
- [ ] `/doctor` returns accurate mesh, skill, policy, and health status; non-admin actors see a redacted summary.
- [ ] Remote workers emit heartbeats; the control plane detects stale and presumed-dead workers within configured thresholds.
- [ ] A stalled mission stage triggers one supervised restart, then escalates to the operator inbox on second stall.
- [ ] Dead-lettered stages appear in the operator's inbox with diagnostic context and actionable options.
- [ ] `ModelRouter` resolves capability/tier combinations to provider/model pairs according to workspace routing tables.
- [ ] Skill-declared `capabilities` and `cost_tier` influence model selection at dispatch time.
- [ ] `ReflectionLoop` synthesizes structured memory entries from completed mission artifacts and persists them workspace-scoped.
- [ ] Proactive memory entries appear in root session system prompts when relevant to the current conversation.
- [ ] Memory, skills, channel policy, and diagnostics are all workspace-isolated—no cross-tenant leakage.
- [ ] All new code uses modern Swift concurrency (`async`/`await`, `@Sendable`, actor isolation) and no third-party frameworks.
- [ ] Unit, integration, and end-to-end tests cover skill lifecycle, channel policy, supervision, routing, and reflection.
- [ ] Live proof is completed: Telegram ingress → pairing → skill-augmented mission → remote worker with heartbeat → completion → reflection memory.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| OmniSkills becomes a second competing plugin model alongside existing tool registration | High | High | OmniSkills deliberately produces `FunctionTool`/`ShellToolEnvironment` instances that feed into the existing `Tool` enum and `ToolRegistry`. It is a manifest-driven factory, not a parallel plugin runtime. Phase 2 explicitly migrates `.claude/commands` and `activate_skill` to prevent coexistence. |
| Skill injection differs subtly across execution modes, causing "works in root but not in worker" bugs | Medium | High | `SkillActivationAdapter` is the single injection point for all worker modes. Phase 2 tests explicitly verify the same manifest across all four execution paths. |
| Channel policy breaks existing local-dev workflows that don't use Telegram | Medium | Medium | Pairing is only enforced for external ingress (Telegram, HTTP API). Direct CLI/local-dev `RootAgentRuntime` usage bypasses `IngressGateway` entirely and is unaffected. |
| Heartbeat infrastructure adds latency or chattiness to the mesh | Low | Medium | Heartbeats are 30s intervals with tiny payloads. They use the existing HTTP mesh transport, not a new connection. The liveness monitor is pull-based (checks timestamps), not event-driven. |
| ReflectionLoop model calls add cost per completed mission | Medium | Medium | Reflection uses the economy-tier model by default. It is opt-in per workspace. The reflection call is bounded to one call per mission, not per stage. |
| Scope creep — too many subsystems in one sprint | High | High | Strict phase ordering. Phase 1–2 (OmniSkills) are the priority and must ship before Phase 3–5 can proceed. Phase 5 (routing + reflection) can be deferred to a follow-on if the sprint runs long. |
| Model routing table becomes stale as providers release new models | Low | Low | The routing table is workspace-configurable, not hardcoded. `DefaultRoutingTable` is a starting point, not a contract. |
| Onboarding flow is too rigid or annoying for operators | Medium | Medium | The onboarding state machine is minimal (3 steps) and uses inline buttons. Workspace admins can pre-pair actors and skip onboarding entirely by setting `onboarding_complete` directly. |
| Existing skills in `.claude/commands` break during migration | Medium | High | Legacy `.claude/commands` auto-discover as compatibility skills. The old loading path is not removed until the migration adapter is proven. Both paths coexist during the transition window. |

## Security

- **Pairing-first default**: All external ingress channels default to requiring an invitation code before messages reach the root runtime. This is the security boundary for multi-user access.
- **Skill sandboxing**: Skills declare their environment needs in the manifest. Shell environments are constrained to the skill's declared working directory. Skills cannot escalate to root-level file access or arbitrary network access unless explicitly granted by workspace policy.
- **Skill validation**: `OmniSkillRegistry` validates manifests on discovery. Malformed manifests, missing required files, and schema violations are rejected with clear errors. Skills with `requires_approval: true` in their constraints require operator confirmation before first activation.
- **Workspace-scoped everything**: Skills, memory, channel policy, diagnostics, routing tables, and dead-letter records are all scoped to workspace ID. Cross-workspace access is structurally impossible at the store level (workspace ID is part of every primary key and query predicate).
- **Invitation code hygiene**: Codes have configurable max-use counts and expiration times. Expired and exhausted codes are purged on a schedule. Code generation requires workspace admin role.
- **Diagnostics redaction**: `/doctor` output for non-admin actors omits worker addresses, skill implementation details, and policy configuration. Admin-level output still redacts secrets and credentials.
- **Heartbeat authenticity**: Heartbeat messages include the worker's registration token (established during Sprint 006 worker registration). Heartbeats from unregistered workers are rejected.
- **Reflection privacy**: Memory entries never include raw conversation transcripts or artifacts. The reflection loop extracts structured summaries only. Memory entries inherit the workspace's data-retention policy.
- **Secret exclusion**: Skill manifests must not contain secrets. Environment variables needed by skill shell environments are resolved from the operator's environment at activation time, not stored in the manifest.

## Dependencies

- Sprint 006 root/worker fabric and `OmniAgentMesh` durable stores
- Sprint 007 multi-user identity, mission orchestration, ingress, and Attractor integration
- `OmniAIAgent.Session` as the root and worker local reasoning loop
- `OmniAIAttractor` pipeline engine and Codergen/ACP handlers
- `OmniACP` transport and session model for ACP-backed worker execution
- `OmniAgentsSDK` `Tool` enum, `FunctionTool`, `ShellTool`, and `ShellToolEnvironment` types
- Existing `ToolRegistry`, `AnthropicProfile`, and `GeminiParityTools` for migration targets
- Existing `HTTPMeshServer`/`HTTPMeshClient` for heartbeat transport
- Existing `MissionSupervisor` for timeout/restart extension
- SQLite store pattern established in prior sprints for `MemoryStore` and `DeadLetterStore`
- User-provided Telegram bot token and workspace admin configuration
- Provider credentials for root and worker model backends

## Open Questions

1. **Skill versioning**: Sprint 008 treats skills as unversioned local directories. Should we add a `skills-lock.json` (similar to the existing repo file) that pins installed skill versions, or is that a follow-on concern?
2. **Skill marketplace/sharing**: The current design is local-only skill installation. Cross-team skill sharing (git-based, registry-based) is explicitly deferred. Is there a minimal sharing mechanism worth including now, such as `git clone` into the skills directory?
3. **Reflection frequency**: The current design reflects once per completed mission. Should high-value missions (determined by cost, duration, or operator flag) get additional mid-mission reflection checkpoints?
4. **Routing table UI**: The default routing table is code-configured. Should workspace admins be able to edit routes via a root conversation command (e.g., `set_model_route`), or is config-file editing sufficient for Sprint 008?
5. **Onboarding skip**: Should workspace admins be able to pre-pair actors and skip onboarding entirely (e.g., bulk-import an allowlist), or must every actor complete the onboarding flow at least once?
