# SPRINT-007: The Agent Product Runtime — Multi-User Chief-of-Staff Missions, Telegram Ingress, and Attractor Worker Workflows

## Overview

Sprint 006 proved the durable root/worker fabric, remote worker registration, ACP-backed worker execution, and a live root loop. Sprint 007 turns that infrastructure into the actual product contract: the user talks only to `TheAgent`, while planning, delegation, validation, approvals, and subagent fan-out happen behind the scenes. The root agent becomes a tenant-scoped chief-of-staff runtime, not a thin wrapper over `delegate_task`.

This sprint adds multi-user and multi-workspace support from the start. There is no single global `root` conversation anymore. Every inbound message, mission, task, artifact, notification, approval, and delivery must be scoped to a workspace and a channel. Telegram is the first shipping ingress, but the architecture must remain transport-agnostic so HTTP/API and future chat surfaces reuse the same normalized interaction pipeline. The ingress and delivery path must explicitly handle transport realities such as durable update dedupe, callback-query acknowledgement, long-response chunking, and graceful treatment of unsupported media so Telegram quirks do not leak into mission logic.

`OmniAIAttractor` is explicitly part of the design, but as a worker-side mission engine rather than the universal runtime for every task. Simple work can still execute as plain local or ACP-backed worker tasks. Compound work that benefits from a structured `plan -> implement -> validate` flow should run as an Attractor-backed workflow inside the worker fabric, with all human questions and permission requests routed back through the root agent. The sprint also needs an explicit migration story from Sprint 006 local state so a developer with an existing `.ai/the-agent/` folder can move forward without losing root history or active task context.

## Execution Status

- Core Sprint 007 runtime work is implemented in source and covered by the new workspace, ingress, mission, artifact-transport, and Attractor execution tests.
- Remaining live-proof work is environment-specific: a real Telegram bot token plus polling or webhook deployment is still required to satisfy the final credentialed Telegram proof item in the Definition of Done.

## Use Cases

1. **Personal Telegram chief-of-staff**: A user opens a DM with the bot, asks for work, and receives only meaningful progress, blocking questions, approval requests, and final results.
2. **Shared team workspace**: Multiple users in a Telegram group or topic share one workspace-scoped root agent, with role-aware approvals, audit trails, and workspace memory.
3. **Transport parity**: The same root mission runtime can be used over Telegram today and authenticated HTTP/API tomorrow without duplicating orchestration logic.
4. **Recursive delegation**: A worker can decompose work into child tasks or child workflows without becoming user-facing and without bypassing the root agent’s policy and audit layer.
5. **Attractor-backed implementation**: A worker runs a `plan -> implement -> validate` flow, including code generation, review, scenario evaluation, and judge/fail-or-retry decisions.
6. **Root-owned approvals and questions**: Tool approvals, Attractor `wait_human` gates, scope questions, and deployment confirmations all funnel through one root inbox and one user-visible reply path.
7. **Multi-user isolation**: A private workspace’s conversation, tasks, artifacts, and approvals never leak into another workspace, even when workers are shared.
8. **Crash-safe recovery**: The control plane, ingress, and workers can restart and resume missions, Telegram deliveries, and approval states without losing ownership or duplicating work.

## Architecture

### Product Topology

```text
                          Telegram / API / CLI
                                   |
                                   v
                     +-----------------------------+
                     | Ingress Gateway             |
                     | normalize + dedupe + route |
                     +-------------+---------------+
                                   |
                        identity / workspace bind
                                   |
                                   v
                     +-----------------------------+
                     | Root Mission Runtime        |
                     | chief of staff per         |
                     | workspace + channel        |
                     +------+------+--------------+
                            |      |
                            |      +------------------------------+
                            |                                     |
                            v                                     v
                  +--------------------+              +---------------------+
                  | Interaction Broker |              | Mission Coordinator |
                  | approvals/questions|              | direct/task/workflow|
                  +---------+----------+              +----------+----------+
                            |                                    |
                            |                                    v
                            |                         +----------------------+
                            |                         | Root Scheduler       |
                            |                         | durable placement    |
                            |                         +----------+-----------+
                            |                                    |
                            |                          OmniAgentMesh + artifacts
                            |                                    |
                            v                                    v
                 +----------------------+          +-------------------------------+
                 | Telegram/API replies |          | Worker Daemons               |
                 | final answer only    |          | local / ACP / Attractor mode |
                 +----------------------+          +---------------+---------------+
                                                                   |
                                                                   v
                                                   +-------------------------------+
                                                   | Child tasks / child workflows |
                                                   | review / scenario / judge     |
                                                   +-------------------------------+
```

### Core Product Rules

- The root agent is the only user-facing persona.
- Every interaction is scoped to a `workspaceID` and `channelID`.
- Workers and subagents may recurse, but they never talk to the user directly.
- The default orchestration unit is a **mission**, not a raw task.
- `delegate_task`, `wait_for_task`, and similar primitives remain internal tools.
- Attractor is a **worker execution mode** for structured workflows, not the root/worker mesh protocol.
- Human questions and permission requests are durable records owned by the root control plane.
- Shared state must be durable first and in-memory second.

### Domain Model

The sprint introduces six new durable domains on top of the Sprint 006 stores:

1. **Identity**
   - `ActorRecord`
   - `WorkspaceRecord`
   - `WorkspaceMembership`
   - `ChannelBinding`
   - `IngressCredential`

2. **Conversation**
   - `InteractionItem` with `workspaceID`, `channelID`, `actorID`, `transport`, and modality metadata
   - structured summaries per workspace/channel
   - visible delivery receipts

3. **Missions**
   - `MissionRecord`
   - `MissionStageRecord`
   - `MissionExecutionMode`
   - mission contracts, progress logs, and verification reports

4. **Interaction**
   - `ApprovalRequestRecord`
   - `QuestionRequestRecord`
   - `NotificationRecord`
   - `DeliveryRecord`

5. **Jobs**
   - existing task/event model extended with `workspaceID`, `missionID`, `requesterActorID`, restart policy, attempt budget, deadline, and escalation policy

6. **Artifacts**
   - task artifacts
   - mission artifacts
   - ingress attachments
   - validation reports

Recommended state root after this sprint:

```text
.ai/the-agent/
  identity.sqlite
  conversation.sqlite
  missions.sqlite
  jobs.sqlite
  deploy.sqlite
  artifacts/
  ingress/
  checkpoints/
  releases/
```

### Workspace and Channel Semantics

- A **workspace** is the security and memory boundary.
- A **channel** is one conversation surface inside a workspace.
- A **DM** auto-provisions a personal workspace by default.
- A **Telegram group/topic** binds to a shared workspace and uses membership/role checks.
- An **API client** binds to an existing workspace and one or more channels.

The root session key stops being a hardcoded `"root"` and becomes a composite runtime identity derived from workspace plus channel. The root can still maintain a coherent long-lived narrative, but it does so within a scoped workspace/channel lane.

That storage identity is not enough by itself for runtime isolation. Sprint 007 also needs an explicit per-scope runtime/session ownership layer so concurrent DMs, groups, and topics do not all multiplex through one in-memory `RootAgentRuntime`, `RootConversation`, or notification inbox instance.

### Mission Runtime

The root agent should reason in mission tools and mission states:

- `start_mission`
- `mission_status`
- `list_inbox`
- `approve_request`
- `answer_question`
- `cancel_mission`
- `retry_mission_stage`
- `pause_mission`
- `resume_mission`

Internal execution policies:

- `direct`: the root handles the work directly in its own `Session`
- `worker_task`: the root submits a bounded task to the worker fabric
- `attractor_workflow`: the root assigns a worker-side Attractor mission

The control plane owns the decision. Workers may recurse beneath it, but only within mission budgets, depth limits, and policy.

### Attractor Fit

Attractor is the structured workflow engine for compound execution inside the worker plane.

Default worker workflow template:

1. `plan`
   - produce a mission contract
   - identify acceptance checks
   - negotiate with evaluator/judge rules
2. `implement`
   - run ACP-backed coding or tool-driven execution
   - emit progress artifacts
3. `validate`
   - review
   - scenario evaluation
   - judge pass / retry / replan

The root does not become an Attractor node graph. Instead, the root chooses when a mission stage should be handed to an Attractor-backed worker executor. This preserves a simple chief-of-staff interface while reusing Attractor’s checkpointing, retries, and manager-loop capabilities where they are valuable.

### Human Interaction and Approvals

All human interaction flows through a root-owned `InteractionBroker`:

- worker permission requests
- Attractor `wait_human` questions
- deployment approvals
- clarifying questions
- mission completion notifications

Workers and subagents emit durable approval/question records upward. The broker batches or serializes them into one user-visible reply path for Telegram/API. No worker-side console interaction is allowed in production mission flows.

### Telegram as First Ingress

Telegram is the first ingress, but not the only one the design supports.

Ingress design rules:

- Use a normalized `IngressEnvelope` for inbound text, callback actions, attachments, and transport metadata.
- Use Telegram webhook delivery for production and `getUpdates` polling for local/dev.
- Dedupe inbound updates durably.
- Keep Telegram-specific identifiers in `ChannelBinding`, not in mission logic.
- Use inline buttons and callback actions for approvals/questions where possible.
- Keep `allowed_updates` narrow to the message types the product actually handles.
- Acknowledge webhook/callback traffic immediately and decouple transport acknowledgement from mission-state transitions.
- Chunk or otherwise repackage long root responses so delivery survives Telegram message-size limits.

### Supervision and Recovery

Introduce explicit supervision semantics inspired by mission runtimes rather than ad hoc retries:

- one mission supervisor per active mission
- bounded stage retries with backoff
- one-for-one restart for failed workers/stages where safe
- escalation to the root inbox after retry exhaustion
- process restart rebuild from SQLite-backed mission/job state

## Implementation

### Phase 1: Multi-User Identity, Workspace, and Session Partitioning

**Goals**
- Add first-class actor/workspace/channel identity models
- Partition all root conversation and mission state by workspace/channel
- Remove single-session assumptions from the control plane

**Files**
- `Package.swift`
- `Sources/OmniAgentMesh/Models/ActorRecord.swift`
- `Sources/OmniAgentMesh/Models/WorkspaceRecord.swift`
- `Sources/OmniAgentMesh/Models/WorkspaceMembership.swift`
- `Sources/OmniAgentMesh/Models/ChannelBinding.swift`
- `Sources/OmniAgentMesh/Stores/IdentityStore.swift`
- `Sources/OmniAgentMesh/Stores/ConversationStore.swift`
- `Sources/OmniAgentMesh/Models/TaskRecord.swift`
- `Sources/TheAgentControlPlane/Runtime/WorkspaceSessionRegistry.swift`
- `Sources/TheAgentControlPlane/RootAgentServer.swift`
- `Sources/TheAgentControlPlane/RootConversation.swift`

**Tasks**
- [ ] Add durable actor/workspace/membership/channel binding models and SQLite-backed stores.
- [ ] Extend conversation items, snapshots, notifications, tasks, and artifacts with `workspaceID` and `channelID`.
- [ ] Replace hardcoded root-session assumptions with scoped runtime/session identities.
- [ ] Introduce a backward-compatible scoped session key serialization so Sprint 006 state can migrate without losing existing conversation and task lookups during the transition window.
- [ ] Add a per-scope runtime/session registry so each active workspace/channel gets isolated `RootAgentRuntime`, `RootConversation`, and inbox ownership instead of sharing one global in-memory root session.
- [ ] Add role-aware workspace authorization helpers for owner/admin/member/viewer actions.
- [ ] Add migration/bootstrap logic for existing single-user local state.
- [ ] Prove migration from an existing Sprint 006 `.ai/the-agent/` state root into the new multi-user schema without losing conversation or task continuity.
- [ ] Add tenant isolation tests that prove conversations, tasks, and notifications cannot cross workspace boundaries.

### Phase 2: Unified Ingress Gateway with Telegram-First Delivery

**Goals**
- Introduce a transport-agnostic ingress layer
- Ship Telegram DM/group/topic ingress first
- Keep a minimal authenticated HTTP/API path aligned with the same runtime contract

**Files**
- `Package.swift`
- `Sources/TheAgentIngress/IngressEnvelope.swift`
- `Sources/TheAgentIngress/IngressGateway.swift`
- `Sources/TheAgentIngress/IngressDelivery.swift`
- `Sources/TheAgentIngress/HTTPIngressServer.swift`
- `Sources/TheAgentTelegram/TelegramBotClient.swift`
- `Sources/TheAgentTelegram/TelegramWebhookHandler.swift`
- `Sources/TheAgentTelegram/TelegramPollingRunner.swift`
- `Sources/TheAgentTelegram/TelegramCallbackCodec.swift`
- `Sources/TheAgentControlPlane/main.swift`

**Tasks**
- [ ] Normalize inbound messages, callback queries, attachments, and metadata into one ingress envelope.
- [ ] Implement Telegram Bot API client and delivery adapter without third-party frameworks.
- [ ] Support webhook mode for production and polling mode for local/dev.
- [ ] Dedupe Telegram updates durably and record delivery receipts.
- [ ] Require explicit `@botname` mention or reply-context triggering in shared Telegram groups unless a workspace opts into ambient channel handling.
- [ ] Acknowledge callback queries and inbound webhook work immediately, then continue mission transitions asynchronously.
- [ ] Add long-response chunking and attachment/document fallback so root replies survive Telegram delivery limits.
- [ ] Normalize or explicitly reject unsupported Telegram media types instead of silently dropping them.
- [ ] Auto-provision DM workspaces and shared-group bindings with explicit membership policies.
- [ ] Default sensitive approvals and blocking questions that originate in shared chats to private DM delivery, with a per-workspace override for fully in-channel flows.
- [ ] If private-DM delivery is required but no DM thread exists with the bot yet, persist the request, emit a safe shared-chat prompt directing the user to start a DM, and avoid silently dropping or auto-failing the approval.
- [ ] Add a minimal authenticated HTTP/API ingress for text submission, inbox polling, and approval responses.
- [ ] Add tests for duplicate Telegram updates, callback approval routing, webhook secret validation, polling resume, and shared-chat routing.

### Phase 3: Root Chief-of-Staff Mission Runtime and Interaction Broker

**Goals**
- Make missions the default orchestration abstraction
- Funnel every blocking question/approval through one root-owned inbox
- Upgrade the root prompt and tool surface from task management to mission management

**Files**
- `Sources/OmniAgentMesh/Models/MissionRecord.swift`
- `Sources/OmniAgentMesh/Models/MissionStageRecord.swift`
- `Sources/OmniAgentMesh/Models/ApprovalRequestRecord.swift`
- `Sources/OmniAgentMesh/Models/QuestionRequestRecord.swift`
- `Sources/OmniAgentMesh/Stores/MissionStore.swift`
- `Sources/OmniAgentMesh/Stores/DeliveryStore.swift`
- `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift`
- `Sources/TheAgentControlPlane/Missions/MissionSupervisor.swift`
- `Sources/TheAgentControlPlane/Interaction/InteractionBroker.swift`
- `Sources/TheAgentControlPlane/Interaction/ApprovalBroker.swift`
- `Sources/TheAgentControlPlane/Changes/ChangeCoordinator.swift`
- `Sources/TheAgentControlPlane/RootAgentRuntime.swift`
- `Sources/TheAgentControlPlane/RootAgentToolbox.swift`
- `Sources/TheAgentControlPlane/RootOrchestratorProfile.swift`

**Tasks**
- [ ] Add durable mission and interaction stores.
- [ ] Teach the root to use mission-level tools instead of raw task-level operations for non-trivial work.
- [ ] Add mission execution policies: `direct`, `worker_task`, and `attractor_workflow`.
- [ ] Create contract/progress/verification artifacts for every mission.
- [ ] Add a root-owned inbox for approvals, questions, and completion notifications.
- [ ] Add per-workspace budget, rate-limit, and escalation-policy hooks so shared workspaces cannot exhaust the system accidentally.
- [ ] Make `ChangeCoordinator` the default implementation engine for code-change mission stages, with `MissionCoordinator` delegating to it instead of building a second parallel implement/review/scenario pipeline.
- [ ] Route worker and Attractor human gates through the interaction broker.
- [ ] Keep raw task-level tools available as an explicit fallback path even after mission-level orchestration becomes the default.
- [ ] Add tests for root-only user interaction, mission resume, per-workspace inbox isolation, and approval batching.

### Phase 4: Attractor-Backed Worker Missions and Recursive Delegation

**Goals**
- Add a worker execution mode that runs structured Attractor workflows
- Standardize `plan -> implement -> validate` mission templates
- Allow controlled child-task and child-workflow recursion

**Files**
- `Sources/TheAgentWorker/Attractor/AttractorTaskExecutor.swift`
- `Sources/TheAgentWorker/Attractor/AttractorWorkflowTemplate.swift`
- `Sources/TheAgentWorker/Attractor/RootBrokerInterviewer.swift`
- `Sources/TheAgentWorker/WorkerExecutorFactory.swift`
- `Sources/TheAgentWorker/WorkerDaemon.swift`
- `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift`
- `Sources/OmniAIAttractor/Handlers/ManagerLoopHandler.swift`
- `Sources/OmniAIAttractor/Handlers/WaitHumanHandler.swift`
- `Sources/OmniAIAttractor/Engine/PipelineEngine.swift`

**Tasks**
- [ ] Add `.attractor` as a worker execution path beside local and ACP execution.
- [ ] Build a default Attractor mission template with `plan`, `implement`, `review`, `scenario`, and `judge` stages.
- [ ] Bridge `wait_human` and approval events to the root interaction broker.
- [ ] Carry workspace/mission/task lineage through child tasks and child pipelines.
- [ ] Add recursion depth, budget, and timeout guards so nested orchestration cannot spiral.
- [ ] Define and test the policy that chooses direct worker execution versus Attractor-backed workflow execution.
- [ ] Keep atomic tasks on the simpler plain-task path; do not force every task through Attractor.
- [ ] Add tests for contract creation, evaluator rejection, child workflow lineage, and root-mediated questions.

### Phase 5: Artifact Mesh, Supervision Policies, and Cross-Node Delivery Guarantees

**Goals**
- Make remote artifacts and mission state observable across machines
- Add bounded retry/restart policies and escalation semantics
- Close the gap between local and remote validator visibility

**Files**
- `Sources/OmniAgentMesh/Transport/HTTPMeshProtocol.swift`
- `Sources/OmniAgentMesh/Transport/HTTPMeshServer.swift`
- `Sources/OmniAgentMesh/Transport/HTTPMeshClient.swift`
- `Sources/OmniAgentMesh/Stores/ArtifactStore.swift`
- `Sources/OmniAgentMesh/Models/TaskRecord.swift`
- `Sources/OmniAgentMesh/Models/TaskEvent.swift`
- `Sources/TheAgentControlPlane/Scheduler/RootScheduler.swift`
- `Sources/TheAgentControlPlane/Policy/WorkspacePolicy.swift`

**Tasks**
- [ ] Add artifact `put/get/list` APIs to the mesh so remote evaluators and the root can inspect worker outputs.
- [ ] Extend task/misson records with attempt counts, restart policy, deadline, escalation policy, and mission linkage.
- [ ] Add durable delivery receipts for outbound Telegram/API replies and approval prompts.
- [ ] Add artifact size limits, retention rules, and chunked or streamed retrieval for large remote outputs.
- [ ] Implement dead-letter/escalation behavior after retry exhaustion.
- [ ] Add tests for remote artifact fetch, duplicate delivery suppression, bounded retries, and restart recovery.

### Phase 6: Security, Observability, Admin Surfaces, and End-to-End Proof

**Goals**
- Harden the system for real multi-user operation
- Add visibility and admin controls needed to run it
- Prove the full stack live over Telegram and remote workers

**Files**
- `Sources/TheAgentControlPlane/Policy/PermissionPolicy.swift`
- `Sources/TheAgentControlPlane/Policy/TransportPolicy.swift`
- `Sources/TheAgentControlPlane/main.swift`
- `Sources/TheAgentWorker/main.swift`
- `Tests/TheAgentControlPlaneTests/MissionCoordinatorTests.swift`
- `Tests/TheAgentWorkerTests/AttractorTaskExecutorTests.swift`
- `Tests/OmniAgentMeshTests/IdentityStoreTests.swift`
- `Tests/OmniAgentMeshTests/ArtifactTransportTests.swift`
- `Tests/TheAgentIngressTests/TelegramIngressTests.swift`
- `Tests/TheAgentIngressTests/MultiUserRoutingTests.swift`
- `docs/agent-fabric-architecture.md`

**Tasks**
- [ ] Add secure configuration handling for Telegram bot tokens, webhook secrets, API credentials, and workspace admin bindings.
- [ ] Add structured telemetry for ingress, mission, stage, approval, delivery, and worker events.
- [ ] Add admin inspection flows for workspace membership, mission status, and delivery failures.
- [ ] Verify local and deployed runtime configuration for Telegram webhook ports, callback handling, and mounted `.ai/the-agent/` state persistence.
- [ ] Run local and cross-machine end-to-end proofs with Telegram ingress, remote worker assignment, Attractor mission execution, and root-mediated approvals.
- [ ] Update architecture docs and operational runbooks.

## Files Summary

| File | Action | Purpose |
|------|--------|---------|
| `Package.swift` | Modify | Add ingress/Telegram targets and new test targets |
| `Sources/OmniAgentMesh/Models/ActorRecord.swift` | Create | Durable actor identity |
| `Sources/OmniAgentMesh/Models/WorkspaceRecord.swift` | Create | Workspace/tenant boundary |
| `Sources/OmniAgentMesh/Models/WorkspaceMembership.swift` | Create | Role-aware membership model |
| `Sources/OmniAgentMesh/Models/ChannelBinding.swift` | Create | Transport-specific binding to a workspace/channel |
| `Sources/OmniAgentMesh/Models/MissionRecord.swift` | Create | Durable mission model |
| `Sources/OmniAgentMesh/Models/MissionStageRecord.swift` | Create | Stage-level mission tracking |
| `Sources/OmniAgentMesh/Models/ApprovalRequestRecord.swift` | Create | Root-owned approval requests |
| `Sources/OmniAgentMesh/Models/QuestionRequestRecord.swift` | Create | Root-owned blocking questions |
| `Sources/OmniAgentMesh/Stores/IdentityStore.swift` | Create | Identity/workspace persistence |
| `Sources/OmniAgentMesh/Stores/MissionStore.swift` | Create | Mission/stage persistence |
| `Sources/OmniAgentMesh/Stores/DeliveryStore.swift` | Create | Outbound delivery receipts and dedupe |
| `Sources/OmniAgentMesh/Models/TaskRecord.swift` | Modify | Add workspace/mission/restart metadata |
| `Sources/OmniAgentMesh/Stores/ArtifactStore.swift` | Modify | Support mission-scoped and remote artifact access |
| `Sources/OmniAgentMesh/Transport/HTTPMeshProtocol.swift` | Modify | Artifact and mission-aware mesh messages |
| `Sources/OmniAgentMesh/Transport/HTTPMeshServer.swift` | Modify | Artifact transport and delivery endpoints |
| `Sources/OmniAgentMesh/Transport/HTTPMeshClient.swift` | Modify | Remote artifact and delivery client support |
| `Sources/TheAgentControlPlane/Runtime/WorkspaceSessionRegistry.swift` | Create | Per-workspace/channel runtime ownership and isolation |
| `Sources/TheAgentIngress/IngressEnvelope.swift` | Create | Transport-neutral inbound message model |
| `Sources/TheAgentIngress/IngressGateway.swift` | Create | Routing from ingress to workspace root runtime |
| `Sources/TheAgentIngress/HTTPIngressServer.swift` | Create | Minimal authenticated API ingress |
| `Sources/TheAgentTelegram/TelegramBotClient.swift` | Create | Direct Telegram Bot API client |
| `Sources/TheAgentTelegram/TelegramDeliveryFormatter.swift` | Create | Response chunking, callback acknowledgement, and delivery fallback rules |
| `Sources/TheAgentTelegram/TelegramWebhookHandler.swift` | Create | Production Telegram webhook receiver |
| `Sources/TheAgentTelegram/TelegramPollingRunner.swift` | Create | Local/dev polling adapter |
| `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift` | Create | Root mission orchestration |
| `Sources/TheAgentControlPlane/Missions/MissionSupervisor.swift` | Create | Retry/restart/escalation policy |
| `Sources/TheAgentControlPlane/Interaction/InteractionBroker.swift` | Create | Root-owned question/approval funnel |
| `Sources/TheAgentControlPlane/Policy/BudgetPolicy.swift` | Create | Workspace budgets, rate limits, and escalation thresholds |
| `Sources/TheAgentControlPlane/Changes/ChangeCoordinator.swift` | Modify | Explicit handoff target for code-change mission stages |
| `Sources/TheAgentControlPlane/RootAgentRuntime.swift` | Modify | Workspace/channel-scoped root runtime |
| `Sources/TheAgentControlPlane/RootAgentServer.swift` | Modify | Mission-aware control plane |
| `Sources/TheAgentControlPlane/RootAgentToolbox.swift` | Modify | Mission-level tool surface |
| `Sources/TheAgentControlPlane/RootOrchestratorProfile.swift` | Modify | Chief-of-staff prompt contract |
| `Sources/TheAgentWorker/Attractor/AttractorTaskExecutor.swift` | Create | Attractor-backed worker execution mode |
| `Sources/TheAgentWorker/Attractor/RootBrokerInterviewer.swift` | Create | Route Attractor human gates to root |
| `Sources/TheAgentWorker/WorkerExecutorFactory.swift` | Modify | Choose local/ACP/Attractor execution |
| `Sources/TheAgentWorker/WorkerDaemon.swift` | Modify | Mission-aware execution, lineage, and telemetry |
| `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift` | Modify | Scoped recursive child delegation |
| `Sources/OmniAIAttractor/Handlers/ManagerLoopHandler.swift` | Modify | Mission lineage, budgets, and child loops |
| `Sources/OmniAIAttractor/Handlers/WaitHumanHandler.swift` | Modify | Root-brokered human interaction |
| `Tests/OmniAgentMeshTests/IdentityStoreTests.swift` | Create | Tenant/workspace persistence coverage |
| `Tests/OmniAgentMeshTests/ArtifactTransportTests.swift` | Create | Remote artifact transport coverage |
| `Tests/TheAgentControlPlaneTests/MissionCoordinatorTests.swift` | Create | Root mission orchestration coverage |
| `Tests/TheAgentWorkerTests/AttractorTaskExecutorTests.swift` | Create | Worker Attractor execution coverage |
| `Tests/TheAgentIngressTests/TelegramIngressTests.swift` | Create | Telegram webhook/polling coverage |
| `Tests/TheAgentIngressTests/MultiUserRoutingTests.swift` | Create | Shared/private workspace routing coverage |
| `docs/agent-fabric-architecture.md` | Modify | Align architecture document to sprint result |

## Definition of Done

- [ ] A user can interact with `TheAgent` over Telegram DM and receive real mission execution, not just a demo echo path.
- [ ] Shared Telegram workspaces support multiple users with role-aware approvals and no cross-workspace leakage.
- [ ] Concurrent ingress across multiple workspace/channel scopes does not cross-talk through one shared in-memory root session; this is proven with a runtime/session ownership test.
- [ ] The root agent is the only user-facing persona for questions, approvals, and final answers.
- [ ] Non-trivial work defaults to a mission flow instead of manual root `delegate_task` juggling.
- [ ] Raw task-level orchestration tools still function for fallback/debug flows after mission-level tools ship.
- [ ] Workers can execute structured Attractor workflows with `plan -> implement -> validate`.
- [ ] Workers can recursively delegate child tasks or child workflows within depth and budget limits.
- [ ] Remote artifacts are available to the root and remote validators through the mesh.
- [ ] Mission, approval, and delivery state survives process restarts and reconnects.
- [ ] An existing Sprint 006 state root migrates forward without losing conversation history or task continuity.
- [ ] A root reply that exceeds Telegram message limits is chunked or otherwise delivered successfully.
- [ ] In shared Telegram chats, the bot only triggers on explicit mention/reply-context unless a workspace policy enables ambient handling.
- [ ] Telegram callback approvals are acknowledged promptly while still driving durable mission-state transitions.
- [ ] If an approval must reroute to DM but the user has not opened a DM with the bot, the system persists the request and presents a recoverable fallback path instead of dropping the interaction.
- [ ] Bounded recursion failure is covered by tests and escalates cleanly to the root inbox.
- [ ] Telegram webhook mode, polling mode, and authenticated HTTP/API mode all route through the same normalized ingress path.
- [ ] Unit, integration, and end-to-end tests cover workspace isolation, Telegram ingress, mission orchestration, Attractor execution, and remote worker recovery.
- [ ] Live proof is completed locally and against at least one remote worker host using Telegram as the ingress.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Multi-user isolation leaks state across workspaces | Medium | High | Make `workspaceID` mandatory in every primary record and add cross-tenant invariants in stores and tests |
| Per-scope root runtime ownership is incomplete, causing cross-talk between concurrent chats | Medium | High | Add an explicit workspace/channel session registry and concurrency tests that run simultaneous ingress across scopes |
| Telegram ingress becomes too transport-specific and contaminates mission logic | Medium | High | Force all transport handling through `IngressEnvelope` and `ChannelBinding`; keep mission/runtime logic Telegram-blind |
| Telegram message-size or callback-ack constraints break delivery or approvals | Medium | High | Add delivery chunking, immediate webhook/callback acknowledgement, and durable correlation between transport events and mission actions |
| Sensitive approvals routed to DM fail because the user never opened a DM with the bot | Medium | Medium | Persist the approval, emit a safe shared-chat instruction to start a DM, and resume automatically when the DM channel binds |
| Root mission orchestration becomes an overcomplicated bureaucracy | Medium | High | Keep root tools mission-level, keep worker execution simple for atomic tasks, cap recursive orchestration depth |
| Attractor is overused for tiny tasks and adds latency | High | Medium | Default to plain task execution for atomic work; gate Attractor to compound or validator-heavy tasks |
| Worker-side human gates bypass the root persona | Low | High | Forbid direct worker interaction in production and require all questions/approvals through `InteractionBroker` |
| Remote validators cannot inspect worker output reliably | High | High | Add artifact transport before depending on remote review/scenario/judge flows |
| Telegram delivery duplication or callback replay creates duplicate side effects | Medium | Medium | Dedupe updates and outbound deliveries durably; use idempotency keys for mission/approval transitions |
| Mission replay or restart creates duplicate child tasks or repeated side effects | Medium | High | Add idempotent mission-step submission keys, child-task lineage checks, and recovery tests that assert no duplicate child dispatch |
| Shared-workspace abuse or runaway missions exhaust API budget | Medium | High | Add workspace budgets, rate limits, escalation thresholds, and explicit approval gates for expensive actions |
| Shared chat approval UX is confusing or unsafe | Medium | Medium | Start with explicit role rules and allow sensitive approvals to reroute to a private admin channel if needed |

## Security Considerations

- Treat Telegram bot tokens, webhook secret tokens, ACP endpoints, and API credentials as secrets loaded from environment or external secret stores only.
- Validate Telegram webhook authenticity and reject mismatched secret tokens.
- Enforce workspace/membership authorization before mission creation, approval, cancellation, or artifact access.
- Add audit logs for mission creation, approval decisions, deployment actions, and cross-host worker operations.
- Redact secrets and policy-sensitive values from model-visible artifacts, progress logs, and outbound notifications.
- Apply per-workspace rate limits and mission budgets to prevent abuse from shared chats or compromised API credentials.
- Protect callback/approval paths against replay by correlating transport events with durable interaction IDs and idempotency keys.

## Dependencies

- Sprint 006 root/worker fabric and current `OmniAgentMesh` durable stores
- `OmniAIAgent.Session` as the root local reasoning loop
- `OmniAIAttractor` as the workflow/evaluation engine
- `OmniACP` and existing ACP worker execution path
- Existing repo HTTP/WebSocket stack and SQLite store pattern
- User-provided Telegram bot token, webhook configuration details, and initial workspace/admin mapping
- Provider credentials for whichever root and worker model backends are enabled

## Open Questions

1. Which approval classes, if any, should be allowed to remain in a shared Telegram channel instead of following the default private-DM delivery rule?
2. Should the initial release support Telegram groups/topics on day one, or ship DM-first with shared workspaces immediately behind it?
3. What is the default recursion depth for worker-managed child workflows before the root must replan?
4. Should mission contracts be JSON-first only, or also mirrored into markdown for easier human inspection?
5. Do we want the minimal authenticated HTTP/API ingress in the same binary as the control plane, or as a separate ingress process using the same stores?
6. For long-running Telegram replies, do we want to use simple message edits first, or add draft/progressive streaming behavior later as an optimization?
7. For the first shipping cut, should Telegram voice notes and images be normalized into artifacts, or explicitly rejected as unsupported inputs?
8. What is the cleanest API surface for the `MissionCoordinator -> ChangeCoordinator` handoff now that code-change mission stages should reuse `ChangeCoordinator` by default?
