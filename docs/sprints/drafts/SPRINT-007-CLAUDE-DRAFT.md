Now I have a thorough understanding of the codebase. Let me produce the Sprint 007 draft.

# Sprint 007: The Agent Product Runtime — Ingress, Identity, and Mission Orchestration

## Overview

Sprint 007 turns the Sprint 006 root/worker fabric into a user-facing product runtime. Sprint 006 delivered the durable control plane, SQLite-backed job/conversation/deployment stores, HTTP mesh transport, ACP-backed worker execution, remote worker registration, recursive child delegation via `ChildWorkerManager`, and a root session with `delegate_task`/`wait_for_task`/`list_notifications` tooling. What it did not deliver is: an external ingress anyone can message, a multi-user or workspace identity model, a mission-level chief-of-staff orchestration loop (the current root is still task-oriented), root-owned interaction brokering for approvals and human questions, remote artifact visibility, or restart/recovery of active mission state.

This sprint adds five connected subsystems on top of the Sprint 006 baseline:

1. **Identity and workspace isolation** — multi-user, workspace, and channel scoping across every store and every control-plane operation.
2. **Mission orchestration** — a chief-of-staff mission loop that turns high-level user intents into coordinated multi-step plans, replacing the current raw-tool-call delegation style with structured intent → plan → delegate → supervise → report semantics.
3. **Interaction brokering** — a root-owned approval and question pipeline that workers and Attractor pipelines can call into, with delivery routed back through the user's active ingress.
4. **Telegram ingress** — the first real user-facing transport, built as a thin adapter that normalises Telegram messages into the control plane's transport-agnostic `InteractionItem` model.
5. **Remote artifact transport and supervision** — mesh-level `artifact.put`/`artifact.get` endpoints, mission checkpoint/recovery, and bounded recursive delegation with durable lineage.

The sprint is phased into five implementation milestones. Each phase produces a testable, shippable increment.

## Use Cases

1. **Telegram DM as primary interface**: A user sends a Telegram DM to the root agent's bot. The root agent responds as a chief-of-staff, deciding whether to answer directly or delegate work. All replies arrive in the same Telegram DM.
2. **Multi-user isolation**: Two users DM the same Telegram bot. Each user has an isolated workspace, session, and task namespace. Neither user can see the other's tasks, artifacts, or conversation history.
3. **Shared workspace with channel isolation**: Two users share a workspace (e.g., a team project). Tasks submitted in a shared Telegram group/topic are workspace-visible but channel-scoped. Approvals for shared work route to the originating user's DM by default.
4. **Mission-level delegation**: The user says "refactor the mesh transport to support WebSocket streaming." The root creates a `Mission`, generates a phased plan using its model, delegates implementation to a coding worker, routes review to a review worker, runs scenario evaluation, and reports the aggregate result — without the user needing to call `delegate_task` or `wait_for_task` manually.
5. **Attractor-backed structured execution**: A worker executing a complex implementation task uses `OmniAIAttractor.PipelineEngine` to run a `plan → implement → test → validate` DOT graph. The Attractor pipeline's `WaitHumanHandler` gates route through the interaction broker back to the root, which delivers the question to the user's Telegram DM and returns the answer.
6. **Root-owned approvals**: A worker needs human confirmation before merging a PR. The worker emits a `task.waiting` event with an `InteractionRequest`. The root's interaction broker picks it up, delivers it to the originating user via Telegram, collects the response, and routes it back to the worker's pending gate.
7. **Remote artifact visibility**: A review worker on a different machine needs to read implementation artifacts produced by a coding worker. The review worker fetches artifacts through the mesh `artifact.get` endpoint rather than assuming local filesystem access.
8. **Restart recovery**: The root process restarts. It loads durable mission state, reconnects active worker sessions, replays pending interaction requests, and resumes in-flight missions from their last checkpoint.

## Architecture

### Updated Topology

```text
                        Telegram / HTTP API / future transports
                                      |
                                      v
                         +------------------------+
                         | Ingress Gateway        |
                         | normalises messages    |
                         | into InteractionItems  |
                         +------------+-----------+
                                      |
                                      v
                         +----------------------------+
                         | Root Agent Server           |
                         | identity · missions ·       |
                         | interaction broker ·        |
                         | scheduler · notifications   |
                         +-------------+--------------+
                                       |
                              OmniAgentMesh protocol
                                       |
              +------------------------+------------------------+
              |                        |                        |
              v                        v                        v
       +--------------+         +--------------+         +--------------+
       | Worker Agent |         | Worker Agent |         | Worker Agent |
       | macOS / CPU  |         | Linux / CPU  |         | GPU / Linux  |
       +------+-------+         +------+-------+         +------+-------+
              |                        |                        |
              v                        v                        v
         Attractor PIV            local child work         ACP edge
         pipelines                     |                   adapters
              |                        |                        |
              +---------- Interaction Broker (via mesh) --------+
                                       |
                                       v
                              root-owned delivery
                              back to user ingress
```

### Identity Model

Every entity in the system is scoped by three orthogonal dimensions:

- **UserID** — a unique, transport-agnostic identity for a human user. Telegram user IDs, HTTP API keys, and future transports all resolve to a canonical `UserID`.
- **WorkspaceID** — a collaboration boundary. A user belongs to one or more workspaces. Tasks, artifacts, conversation history, and missions are workspace-scoped.
- **ChannelID** — a conversation channel within a workspace. A Telegram DM is a channel. A Telegram group topic is a channel. An HTTP API session is a channel. Channels provide conversation isolation within a workspace.

The existing `sessionID` on `RootAgentServer`, `TaskRecord.rootSessionID`, `InteractionItem.sessionID`, `ConversationSummary.sessionID`, and `NotificationRecord.sessionID` all currently carry a flat string. Sprint 007 replaces the flat `sessionID` with a structured `SessionScope` that encodes `(userID, workspaceID, channelID)` while keeping the serialized string compatible with existing SQLite schemas.

### Mission Model

A mission is a root-owned multi-step plan that sits above individual tasks. The current root toolbox exposes raw primitives (`delegate_task`, `wait_for_task`). Sprint 007 adds a `Mission` record and a `MissionCoordinator` that:

1. Accepts a user intent (a natural-language goal).
2. Uses the root model to produce a structured `MissionPlan` (a list of ordered/parallel steps with capability requirements, expected outputs, and success criteria).
3. Delegates each step as a durable `TaskRecord` through the existing scheduler.
4. Monitors step completion, re-plans on failure, and asks for human input when stuck.
5. Produces a mission-level summary and delivers it back to the user.

The root's toolbox is extended with mission-level tools (`start_mission`, `get_mission_status`, `approve_mission_step`) alongside the existing task-level tools, which remain available for direct delegation when the user or root prefers them.

### Interaction Broker

The interaction broker is a root-side subsystem that owns all human-facing questions and approvals:

- Workers emit `InteractionRequest` records (stored in the job store as a new task event kind: `task.interaction_request`).
- The root's interaction broker polls for pending requests, matches them to the originating user/workspace/channel, and delivers them through the active ingress (Telegram, HTTP API, etc.).
- Responses flow back through the broker to the worker, either as a resolved `InteractionResponse` in the job store or as a direct mesh callback.
- Attractor's `WaitHumanHandler` is bridged to the broker through a new `MeshBridgedInterviewer` that implements the `Interviewer` protocol by emitting an `InteractionRequest` and awaiting the broker's response.

### Ingress Gateway

The ingress gateway is a protocol-level abstraction (`IngressTransport`) with Telegram as the first concrete adapter. Each adapter:

1. Receives raw transport messages (Telegram `Update` objects, HTTP request bodies, etc.).
2. Normalises them into `InteractionItem` values with a resolved `SessionScope`.
3. Forwards them to the root agent server.
4. Receives outbound messages from the root (assistant replies, notifications, interaction requests) and delivers them back through the transport.

The gateway does not contain business logic. It is a bidirectional message pump.

### Remote Artifact Transport

Sprint 006's `FileArtifactStore` is worker-local. Sprint 007 adds:

- `artifact.put` and `artifact.get` endpoints to `HTTPMeshServer` and `HTTPMeshClient`.
- An `artifact.list` endpoint for task-scoped artifact enumeration.
- A `RemoteArtifactStore` that implements the `ArtifactStore` protocol by proxying to the control plane's mesh endpoint.
- Workers producing artifacts write to their local store AND push metadata + content to the control plane.
- Workers consuming artifacts (e.g., review workers reading implementation output) fetch through the `RemoteArtifactStore`.

### Supervision and Restart Recovery

- **Mission checkpointing**: `MissionCoordinator` persists mission state (plan, current step index, step outcomes) to the job store as structured task events. On restart, the coordinator replays the event log to reconstruct mission state.
- **Interaction recovery**: Pending `InteractionRequest` records survive restart. The broker re-delivers them on the next ingress poll cycle.
- **Worker reconnect**: The existing lease/heartbeat/orphan-recovery mechanism (`recoverOrphanedTasks`) handles worker restarts. Sprint 007 adds a `MissionReconciler` that detects orphaned missions (missions whose child tasks are all terminal but the mission itself was never completed) and either completes or re-plans them.
- **Recursive delegation bounds**: `ChildWorkerManager` gains a configurable `maxDepth` (default: 5) and `maxFanOut` (default: 10) policy. Exceeding either limit fails the child task request with a clear error rather than silently creating unbounded trees.

### OmniAIAttractor Integration

Attractor is used as a worker-side structured execution engine, not as a universal runtime. The integration points are:

1. **Worker-local Attractor execution**: When a worker receives a task whose `capabilityRequirements` include `attractor-pipeline` or whose brief references a DOT graph, the `LocalTaskExecutor` routes execution through `PipelineEngine` instead of the default ACP session.
2. **Bridged human gates**: `WaitHumanHandler` uses a `MeshBridgedInterviewer` that emits `InteractionRequest` records via the mesh, waits for the root broker to deliver and collect the human response, and returns the answer to the pipeline.
3. **Attractor artifact mirroring**: Pipeline artifacts (logs, test results, evaluation reports) are mirrored to the mesh `ArtifactStore` so the root and other workers can access them.
4. **Manager loop as mission step**: `ManagerLoopHandler` cycles can be mapped to mission steps, allowing the root to track Attractor pipeline progress as first-class mission state rather than opaque worker internals.

## Implementation

### Phase 1: Identity, Workspace, and Channel Isolation

**Goals**
- Introduce `UserID`, `WorkspaceID`, `ChannelID`, and `SessionScope` types.
- Add workspace/user/channel columns to SQLite schemas (conversation, jobs, notifications, artifacts).
- Update `ConversationStore`, `JobStore`, `ArtifactStore` protocols and their SQLite implementations to accept and enforce scope parameters.
- Update `RootAgentServer` to accept a `SessionScope` instead of a flat `sessionID`.
- Add workspace CRUD to the control plane.

**Files**

| File | Action | Purpose |
|------|--------|---------|
| `Sources/OmniAgentMesh/Models/IdentityModels.swift` | Create | `UserID`, `WorkspaceID`, `ChannelID`, `SessionScope` types |
| `Sources/OmniAgentMesh/Models/WorkspaceRecord.swift` | Create | Durable workspace model with membership |
| `Sources/OmniAgentMesh/Stores/ConversationStore.swift` | Modify | Add scope-aware queries; migrate schema |
| `Sources/OmniAgentMesh/Stores/JobStore.swift` | Modify | Add workspace-scoped task queries; `workspaceID` on `TaskRecord` |
| `Sources/OmniAgentMesh/Stores/ArtifactStore.swift` | Modify | Add workspace-scoped artifact listing |
| `Sources/OmniAgentMesh/Models/TaskRecord.swift` | Modify | Add `workspaceID` field |
| `Sources/OmniAgentMesh/Models/ConversationModels.swift` | Modify | Replace flat `sessionID` with `SessionScope` or add scope fields |
| `Sources/TheAgentControlPlane/RootAgentServer.swift` | Modify | Accept `SessionScope`; enforce isolation on every query |
| `Sources/TheAgentControlPlane/Identity/WorkspaceManager.swift` | Create | Workspace CRUD, membership, and resolution |
| `Sources/TheAgentControlPlane/Identity/UserResolver.swift` | Create | Transport-agnostic user resolution from ingress credentials |
| `Tests/OmniAgentMeshTests/IdentityIsolationTests.swift` | Create | Cross-user, cross-workspace, cross-channel isolation tests |

**Tasks**
- [ ] Define `SessionScope` as `"\(userID):\(workspaceID):\(channelID)"` serialized string for backward-compatible SQLite storage.
- [ ] Migrate existing `sessionID`-based queries to use `SessionScope` without breaking existing unit tests.
- [ ] Write isolation tests proving User A cannot read User B's tasks, conversations, or artifacts.
- [ ] Write workspace membership tests proving shared-workspace users can see shared tasks but not each other's private channels.

### Phase 2: Ingress Gateway and Telegram Adapter

**Goals**
- Define the `IngressTransport` protocol.
- Build the Telegram Bot API adapter using long polling (webhook support deferred).
- Route inbound Telegram messages through identity resolution to `RootAgentServer.submitUserText`.
- Route outbound root replies and notifications back through Telegram.

**Files**

| File | Action | Purpose |
|------|--------|---------|
| `Sources/TheAgentControlPlane/Ingress/IngressTransport.swift` | Create | Protocol: `start()`, `stop()`, `send(to:message:)`, inbound message stream |
| `Sources/TheAgentControlPlane/Ingress/IngressMessage.swift` | Create | Transport-agnostic inbound/outbound message envelope |
| `Sources/TheAgentControlPlane/Ingress/IngressRouter.swift` | Create | Routes inbound messages to root server, outbound replies to transport |
| `Sources/TheAgentControlPlane/Ingress/Telegram/TelegramTransport.swift` | Create | Telegram Bot API long-polling adapter |
| `Sources/TheAgentControlPlane/Ingress/Telegram/TelegramTypes.swift` | Create | Minimal Telegram Bot API types (`Update`, `Message`, `Chat`, `User`) |
| `Sources/TheAgentControlPlane/Ingress/Telegram/TelegramClient.swift` | Create | HTTP client for `sendMessage`, `getUpdates`, `getMe` |
| `Sources/TheAgentControlPlane/Ingress/Telegram/TelegramUserResolver.swift` | Create | Maps Telegram `User.id` + `Chat.id` to `SessionScope` |
| `Sources/TheAgentControlPlane/Identity/UserResolver.swift` | Modify | Add Telegram-specific resolution path |
| `Sources/TheAgentControlPlane/RootAgentRuntime.swift` | Modify | Add ingress lifecycle management |
| `Sources/TheAgentControlPlane/main.swift` | Modify | Wire Telegram transport on startup when `TELEGRAM_BOT_TOKEN` is set |
| `Tests/TheAgentControlPlaneTests/IngressRouterTests.swift` | Create | Inbound/outbound routing with mock transport |
| `Tests/TheAgentControlPlaneTests/TelegramTransportTests.swift` | Create | Telegram message normalisation and scope resolution |

**Tasks**
- [ ] Implement `TelegramTransport` with `getUpdates` long polling and configurable timeout.
- [ ] Map Telegram DM chats to `SessionScope(userID: "\(telegramUserID)", workspaceID: "personal-\(telegramUserID)", channelID: "dm-\(chatID)")`.
- [ ] Map Telegram group/topic messages to `SessionScope(userID: "\(telegramUserID)", workspaceID: "group-\(chatID)", channelID: "topic-\(threadID ?? chatID)")`.
- [ ] Deliver outbound assistant text and notifications via `sendMessage` with Markdown formatting.
- [ ] Add `IngressRouter` that maintains a map of active transports and routes outbound messages to the correct one.
- [ ] Keep `TELEGRAM_BOT_TOKEN` as the only required secret; fail gracefully if unset.
- [ ] Use the repo's existing NIO HTTP stack for outbound Telegram API calls (no new HTTP client dependency).

### Phase 3: Mission Orchestration and Interaction Broker

**Goals**
- Add the `Mission` record and `MissionCoordinator`.
- Add the `InteractionBroker` for root-owned approvals and questions.
- Extend the root toolbox with mission-level tools.
- Bridge Attractor's `Interviewer` protocol to the interaction broker.

**Files**

| File | Action | Purpose |
|------|--------|---------|
| `Sources/OmniAgentMesh/Models/MissionRecord.swift` | Create | `MissionRecord`, `MissionPlan`, `MissionStep` types |
| `Sources/OmniAgentMesh/Models/InteractionRequest.swift` | Create | `InteractionRequest`, `InteractionResponse` types |
| `Sources/OmniAgentMesh/Stores/JobStore.swift` | Modify | Add `task.interaction_request` and `task.interaction_response` event kinds; mission CRUD |
| `Sources/OmniAgentMesh/Models/TaskEvent.swift` | Modify | Add `.interactionRequest` and `.interactionResponse` event kinds |
| `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift` | Create | Plan generation, step delegation, monitoring, re-planning, completion |
| `Sources/TheAgentControlPlane/Missions/MissionReconciler.swift` | Create | Restart recovery and orphan mission detection |
| `Sources/TheAgentControlPlane/Interactions/InteractionBroker.swift` | Create | Polls for pending requests, routes to ingress, collects responses |
| `Sources/TheAgentControlPlane/Interactions/InteractionDelivery.swift` | Create | Formats interaction requests for Telegram/HTTP delivery |
| `Sources/TheAgentControlPlane/RootAgentToolbox.swift` | Modify | Add `start_mission`, `get_mission_status`, `approve_interaction` tools |
| `Sources/TheAgentControlPlane/RootOrchestratorProfile.swift` | Modify | Add mission-aware system prompt instructions |
| `Sources/TheAgentControlPlane/RootAgentServer.swift` | Modify | Wire mission coordinator and interaction broker |
| `Sources/TheAgentControlPlane/Ingress/IngressRouter.swift` | Modify | Handle interaction response routing |
| `Sources/OmniAIAttractor/Handlers/MeshBridgedInterviewer.swift` | Create | `Interviewer` implementation that emits `InteractionRequest` via mesh |
| `Sources/TheAgentWorker/WorkerDaemon.swift` | Modify | Emit `InteractionRequest` events for worker-side human gates |
| `Tests/TheAgentControlPlaneTests/MissionCoordinatorTests.swift` | Create | Plan → delegate → complete lifecycle tests |
| `Tests/TheAgentControlPlaneTests/InteractionBrokerTests.swift` | Create | Request → deliver → respond round-trip tests |
| `Tests/OmniAIAttractorTests/MeshBridgedInterviewerTests.swift` | Create | Attractor human gate → broker → response bridge tests |

**Tasks**
- [ ] Define `MissionRecord` with: `missionID`, `workspaceID`, `userID`, `channelID`, `intent` (user's original text), `plan` (structured `MissionPlan`), `currentStepIndex`, `status`, `taskIDs` (ordered list of child task IDs), `createdAt`, `updatedAt`.
- [ ] Define `MissionPlan` as an ordered array of `MissionStep` (brief, capability requirements, depends-on indices, expected outputs, attractor DOT path if applicable).
- [ ] Implement `MissionCoordinator.startMission(intent:scope:)` which calls the root model to produce a `MissionPlan`, then delegates step 0.
- [ ] Implement `MissionCoordinator.advanceMission(missionID:)` which checks the latest step's task status and delegates the next step, re-plans if the step failed, or completes the mission.
- [ ] Implement `InteractionBroker` that scans for `task.interaction_request` events across all active missions/tasks, matches to `SessionScope`, and delivers via the ingress router.
- [ ] Add `start_mission` tool that takes `intent` and optional `steps_hint` and returns a mission ID.
- [ ] Add `get_mission_status` tool that returns the mission plan, current step, and latest events.
- [ ] Add `approve_interaction` tool that resolves a pending interaction request with a user-provided response.
- [ ] Ensure mission state survives root restart via event replay in `MissionReconciler`.

### Phase 4: Remote Artifact Transport and Attractor Integration

**Goals**
- Add mesh-level artifact endpoints.
- Implement `RemoteArtifactStore`.
- Bridge Attractor pipeline execution into the worker task executor.
- Mirror Attractor pipeline artifacts to the mesh.

**Files**

| File | Action | Purpose |
|------|--------|---------|
| `Sources/OmniAgentMesh/Transport/HTTPMeshServer.swift` | Modify | Add `/artifacts/put`, `/artifacts/get`, `/artifacts/list` endpoints |
| `Sources/OmniAgentMesh/Transport/HTTPMeshClient.swift` | Modify | Add artifact client methods |
| `Sources/OmniAgentMesh/Transport/HTTPMeshProtocol.swift` | Modify | Add artifact request/response types |
| `Sources/OmniAgentMesh/Stores/RemoteArtifactStore.swift` | Create | `ArtifactStore` implementation backed by mesh HTTP |
| `Sources/TheAgentWorker/LocalTaskExecutor.swift` | Modify | Route `attractor-pipeline` tasks to `PipelineEngine` |
| `Sources/TheAgentWorker/Attractor/AttractorTaskBridge.swift` | Create | Converts task brief + DOT path into `PipelineConfig`; mirrors artifacts |
| `Sources/OmniAIAttractor/Handlers/MeshBridgedInterviewer.swift` | Modify | Wire to `RemoteArtifactStore` for pipeline artifact visibility |
| `Tests/OmniAgentMeshTests/RemoteArtifactTransportTests.swift` | Create | Put/get/list round-trip over HTTP mesh |
| `Tests/TheAgentWorkerTests/AttractorTaskBridgeTests.swift` | Create | Task → Attractor pipeline → artifact mirroring tests |

**Tasks**
- [ ] Add artifact endpoints to `HTTPMeshServer` with chunked upload/download for large artifacts.
- [ ] Implement `RemoteArtifactStore` that calls `HTTPMeshClient.putArtifact` / `getArtifact` / `listArtifacts`.
- [ ] In `WorkerDaemon.executeClaimedTask`, after writing artifacts to the local `FileArtifactStore`, push them to the remote store via the mesh client.
- [ ] Implement `AttractorTaskBridge` that:
  - Reads the DOT graph path from the task's `historyProjection.constraints` (e.g., `attractor_dot=path/to/graph.dot`).
  - Constructs a `PipelineConfig` with a `MeshBridgedInterviewer` and the worker's ACP backend.
  - Runs the pipeline and maps `PipelineResult` back to `LocalTaskExecutor.TaskResult`.
  - Mirrors all pipeline log files and node artifacts to the `RemoteArtifactStore`.
- [ ] Write integration test: root submits a task requiring Attractor execution → worker runs DOT pipeline → human gate fires → interaction broker delivers to test harness → response returns → pipeline completes → artifacts visible from root.

### Phase 5: Supervision, Delegation Bounds, and End-to-End Proof

**Goals**
- Add recursive delegation depth and fan-out limits.
- Add mission checkpoint and recovery.
- End-to-end proof: Telegram DM → root → mission → worker (with Attractor) → interaction broker → Telegram reply → mission complete.

**Files**

| File | Action | Purpose |
|------|--------|---------|
| `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift` | Modify | Add `maxDepth` and `maxFanOut` policy enforcement |
| `Sources/TheAgentWorker/Subagents/DelegationPolicy.swift` | Create | Configurable depth/fan-out/budget limits |
| `Sources/TheAgentControlPlane/Missions/MissionReconciler.swift` | Modify | Full restart recovery: replay events, reconcile orphaned missions |
| `Sources/TheAgentControlPlane/Supervision/RootSupervisor.swift` | Create | Health check loop, graceful drain, restart signal |
| `Sources/TheAgentControlPlane/main.swift` | Modify | Wire supervisor, reconciler, and full lifecycle |
| `Tests/TheAgentControlPlaneTests/MissionRecoveryTests.swift` | Create | Simulate root restart mid-mission; verify recovery |
| `Tests/TheAgentWorkerTests/DelegationPolicyTests.swift` | Create | Depth and fan-out limit enforcement |
| `Tests/OmniAgentScenarioTests/EndToEndTelegramTests.swift` | Create | Full Telegram → mission → worker → Attractor → reply scenario |

**Tasks**
- [ ] Add `DelegationPolicy` struct with `maxDepth: Int` (default 5), `maxFanOut: Int` (default 10), `maxBudgetSeconds: TimeInterval` (default 3600).
- [ ] In `ChildWorkerManager.spawnChildTask`, compute current depth by walking `parentTaskID` chain; reject if exceeding `maxDepth`.
- [ ] In `ChildWorkerManager.spawnChildTask`, count existing children for the parent; reject if exceeding `maxFanOut`.
- [ ] Implement `MissionReconciler.reconcileAll()` which loads all non-terminal missions and advances or completes each based on its child task states.
- [ ] Implement `RootSupervisor` as a lightweight health-check loop that monitors the root process and worker connectivity; emit alerts through the notification inbox on degradation.
- [ ] Write end-to-end scenario test with a mock Telegram transport that exercises the full path: user message → scope resolution → mission creation → plan generation → task delegation → worker execution (with Attractor DOT pipeline) → human gate → interaction broker → mock Telegram reply → mission completion → final response delivered to mock Telegram.

## Files Summary

| File | Action | Purpose |
|------|--------|---------|
| `Package.swift` | Modify | Add new source files to existing targets |
| `Sources/OmniAgentMesh/Models/IdentityModels.swift` | Create | `UserID`, `WorkspaceID`, `ChannelID`, `SessionScope` |
| `Sources/OmniAgentMesh/Models/WorkspaceRecord.swift` | Create | Workspace model with membership |
| `Sources/OmniAgentMesh/Models/MissionRecord.swift` | Create | Mission, MissionPlan, MissionStep |
| `Sources/OmniAgentMesh/Models/InteractionRequest.swift` | Create | Interaction request/response types |
| `Sources/OmniAgentMesh/Models/TaskRecord.swift` | Modify | Add `workspaceID` |
| `Sources/OmniAgentMesh/Models/TaskEvent.swift` | Modify | Add interaction event kinds |
| `Sources/OmniAgentMesh/Models/ConversationModels.swift` | Modify | Scope-aware session fields |
| `Sources/OmniAgentMesh/Stores/ConversationStore.swift` | Modify | Scope-aware queries and schema migration |
| `Sources/OmniAgentMesh/Stores/JobStore.swift` | Modify | Workspace-scoped queries; mission CRUD; interaction events |
| `Sources/OmniAgentMesh/Stores/ArtifactStore.swift` | Modify | Workspace-scoped listing |
| `Sources/OmniAgentMesh/Stores/RemoteArtifactStore.swift` | Create | Mesh-backed remote artifact access |
| `Sources/OmniAgentMesh/Transport/HTTPMeshServer.swift` | Modify | Artifact endpoints |
| `Sources/OmniAgentMesh/Transport/HTTPMeshClient.swift` | Modify | Artifact client methods |
| `Sources/OmniAgentMesh/Transport/HTTPMeshProtocol.swift` | Modify | Artifact protocol types |
| `Sources/TheAgentControlPlane/Identity/WorkspaceManager.swift` | Create | Workspace CRUD and membership |
| `Sources/TheAgentControlPlane/Identity/UserResolver.swift` | Create | Transport-agnostic user identity resolution |
| `Sources/TheAgentControlPlane/Ingress/IngressTransport.swift` | Create | Ingress transport protocol |
| `Sources/TheAgentControlPlane/Ingress/IngressMessage.swift` | Create | Transport-agnostic message envelope |
| `Sources/TheAgentControlPlane/Ingress/IngressRouter.swift` | Create | Inbound/outbound message routing |
| `Sources/TheAgentControlPlane/Ingress/Telegram/TelegramTransport.swift` | Create | Telegram Bot API long-polling adapter |
| `Sources/TheAgentControlPlane/Ingress/Telegram/TelegramTypes.swift` | Create | Minimal Telegram API types |
| `Sources/TheAgentControlPlane/Ingress/Telegram/TelegramClient.swift` | Create | Telegram HTTP client |
| `Sources/TheAgentControlPlane/Ingress/Telegram/TelegramUserResolver.swift` | Create | Telegram → SessionScope mapping |
| `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift` | Create | Mission plan/delegate/monitor/complete lifecycle |
| `Sources/TheAgentControlPlane/Missions/MissionReconciler.swift` | Create | Restart recovery and orphan detection |
| `Sources/TheAgentControlPlane/Interactions/InteractionBroker.swift` | Create | Root-owned approval/question pipeline |
| `Sources/TheAgentControlPlane/Interactions/InteractionDelivery.swift` | Create | Format interaction requests for transport delivery |
| `Sources/TheAgentControlPlane/Supervision/RootSupervisor.swift` | Create | Health check, drain, restart signal |
| `Sources/TheAgentControlPlane/RootAgentServer.swift` | Modify | Wire scope, missions, interactions |
| `Sources/TheAgentControlPlane/RootAgentRuntime.swift` | Modify | Ingress lifecycle; mission/interaction wiring |
| `Sources/TheAgentControlPlane/RootAgentToolbox.swift` | Modify | Mission-level tools |
| `Sources/TheAgentControlPlane/RootOrchestratorProfile.swift` | Modify | Chief-of-staff system prompt |
| `Sources/TheAgentControlPlane/main.swift` | Modify | Full startup wiring |
| `Sources/TheAgentWorker/WorkerDaemon.swift` | Modify | Interaction request emission |
| `Sources/TheAgentWorker/LocalTaskExecutor.swift` | Modify | Attractor routing for pipeline tasks |
| `Sources/TheAgentWorker/Attractor/AttractorTaskBridge.swift` | Create | Task → Attractor pipeline bridge |
| `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift` | Modify | Delegation depth/fan-out enforcement |
| `Sources/TheAgentWorker/Subagents/DelegationPolicy.swift` | Create | Configurable delegation limits |
| `Sources/OmniAIAttractor/Handlers/MeshBridgedInterviewer.swift` | Create | Interviewer backed by mesh interaction broker |
| `Tests/OmniAgentMeshTests/IdentityIsolationTests.swift` | Create | Multi-user/workspace store isolation |
| `Tests/OmniAgentMeshTests/RemoteArtifactTransportTests.swift` | Create | Artifact put/get/list over HTTP |
| `Tests/TheAgentControlPlaneTests/IngressRouterTests.swift` | Create | Inbound/outbound routing |
| `Tests/TheAgentControlPlaneTests/TelegramTransportTests.swift` | Create | Telegram normalisation |
| `Tests/TheAgentControlPlaneTests/MissionCoordinatorTests.swift` | Create | Mission lifecycle |
| `Tests/TheAgentControlPlaneTests/InteractionBrokerTests.swift` | Create | Interaction round-trip |
| `Tests/TheAgentControlPlaneTests/MissionRecoveryTests.swift` | Create | Restart recovery |
| `Tests/TheAgentWorkerTests/DelegationPolicyTests.swift` | Create | Depth/fan-out limits |
| `Tests/TheAgentWorkerTests/AttractorTaskBridgeTests.swift` | Create | Attractor pipeline bridge |
| `Tests/OmniAIAttractorTests/MeshBridgedInterviewerTests.swift` | Create | Attractor interviewer bridge |
| `Tests/OmniAgentScenarioTests/EndToEndTelegramTests.swift` | Create | Full end-to-end scenario |

## Definition of Done

- [ ] Multi-user and workspace isolation is enforced at the store layer. A test proves User A cannot read User B's tasks, artifacts, or conversations in any store.
- [ ] Telegram DM ingress works end-to-end: a user sends a message to the bot, the root responds, and the reply appears in the same DM.
- [ ] Telegram group/topic ingress correctly resolves workspace and channel scope. Messages in different topics route to different channels within the same workspace.
- [ ] The root agent operates as a chief-of-staff: it can accept a natural-language intent, produce a multi-step mission plan, delegate steps, and report aggregate results — all without the user manually calling `delegate_task`.
- [ ] Raw task-level tools (`delegate_task`, `list_tasks`, etc.) remain functional alongside mission-level tools.
- [ ] Worker-emitted `InteractionRequest` records are delivered to the originating user through their active ingress transport and responses flow back to the worker.
- [ ] Attractor `WaitHumanHandler` gates route through the `MeshBridgedInterviewer` → interaction broker → Telegram → user → response → pipeline continuation.
- [ ] Remote artifact `put`/`get` works across machines. A review worker on a different host can read implementation artifacts produced by a coding worker.
- [ ] Recursive delegation is bounded by `maxDepth` (5) and `maxFanOut` (10). Exceeding either limit produces a clear error, not a silent failure.
- [ ] Mission state survives root restart. A test simulates a restart mid-mission and verifies the mission resumes from the correct step.
- [ ] Pending interaction requests survive root restart and are re-delivered on the next broker poll cycle.
- [ ] New tests cover: identity isolation, Telegram message normalisation, mission lifecycle, interaction broker round-trip, remote artifact transport, delegation policy limits, Attractor bridge, and end-to-end scenario.
- [ ] All new code compiles under Swift 6 strict concurrency with zero warnings.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Existing `sessionID`-based schemas break during identity migration | High | High | Use backward-compatible `SessionScope` serialization; add migration tests; keep flat `sessionID` as a computed alias during transition |
| Telegram Bot API rate limits under multi-user load | Medium | Medium | Implement per-chat rate limiting in `TelegramClient`; batch notifications; use `sendMessage` reply queuing |
| Mission planning produces low-quality plans from the root model | High | Medium | Keep raw `delegate_task` tools as a fallback; allow user to override or edit plans; start with simple 1-3 step missions |
| Interaction broker latency blocks worker execution | Medium | High | Use configurable timeout on `InteractionRequest` with sensible defaults; allow auto-approve policies for low-risk gates |
| Remote artifact transport adds unacceptable overhead for large files | Medium | Medium | Stream artifacts in chunks; defer full-content push for artifacts above a configurable size threshold (metadata-only until fetched) |
| Workspace isolation bugs leak data between users | Low | Critical | Enforce isolation at the SQL query level (WHERE clauses), not just application logic; add fuzz/property tests for isolation |
| Recursive delegation depth limits frustrate complex workflows | Medium | Low | Make limits configurable per-workspace; log warnings at depth 3+ rather than hard-failing |
| Root restart during active Telegram long poll causes duplicate message processing | Medium | Medium | Track last processed `update_id` in durable storage; use Telegram's offset mechanism to avoid reprocessing |

## Security Considerations

- **Bot token isolation**: `TELEGRAM_BOT_TOKEN` must not be logged, persisted in conversation stores, or included in artifact metadata. Load from environment only.
- **User identity verification**: Telegram user IDs are trusted as identity anchors for the Telegram transport. For HTTP API ingress (future), require API key or token-based authentication.
- **Workspace isolation enforcement**: Every store query must include a workspace scope predicate. Never return unscoped results from any public API.
- **Interaction request spoofing**: Workers cannot forge interaction requests for other users' sessions. The broker validates that the requesting task's `workspaceID` matches the target `SessionScope`.
- **Artifact access control**: `artifact.get` requests must prove the caller has access to the owning workspace (via worker registration metadata or authenticated mesh headers).
- **Secret redaction**: Before persisting any interaction, artifact, or event payload, strip known secret patterns (API keys, tokens, passwords) from content and metadata.
- **Recursive delegation abuse**: Delegation depth and fan-out limits prevent a compromised or buggy worker from creating exponential task trees.
- **Shared group privacy**: In Telegram groups, interaction requests for approvals route to the originating user's private DM by default, not to the shared group.

## Dependencies

- `OmniAgentMesh` (Sprint 006 baseline) — stores, models, transport, mesh protocol
- `TheAgentControlPlane` (Sprint 006 baseline) — root server, scheduler, notifications, conversation, changes
- `TheAgentWorker` (Sprint 006 baseline) — worker daemon, ACP executor, child worker manager
- `OmniAIAttractor` — `PipelineEngine`, `WaitHumanHandler`, `ManagerLoopHandler`, `Interviewer` protocol
- `OmniAIAgent` — `Session`, `ProviderProfile`, `ToolRegistry` for root model interaction
- `OmniACP` — ACP edge adapters on workers (unchanged from Sprint 006)
- `OmniMCP` — MCP tool surface (unchanged from Sprint 006)
- NIO (`NIOCore`, `NIOHTTP1`, `NIOPosix`) — already in use for `HTTPMeshServer`; reuse for Telegram HTTP client
- SQLite (system library via repo-owned binding) — already in use for all stores
- Telegram Bot API (external) — HTTPS endpoint; no new Swift dependency needed (use raw NIO HTTP client)

## Open Questions

1. **Telegram DMs only or groups+topics in Phase 2?** Starting with DM-only simplifies scope resolution and avoids shared-chat approval routing complexity. Groups/topics could ship in a fast-follow within the same sprint if DM ingress lands cleanly.
2. **Mission plan generation: model-driven or template-driven?** The first cut should use the root model to generate plans from the intent text, but having a small library of plan templates for common patterns (implement → review → merge, research → summarize) would reduce model variance.
3. **Interaction request timeout default**: Should the default timeout for a pending human gate be 5 minutes (fast feedback) or 24 hours (async workflow)? This likely needs to be per-mission-step configurable.
4. **Artifact push strategy: eager or lazy?** Eager push (worker pushes content to root on completion) is simpler but wasteful for large artifacts nobody reads. Lazy push (metadata only, content fetched on demand) requires the worker to remain reachable. The first cut should use eager push with a size threshold (e.g., 10 MB) above which only metadata is pushed.
5. **Should `SessionScope` migration be a one-time schema migration or a live dual-write?** A one-time migration is simpler but requires a clean break. A dual-write period allows rollback but adds complexity. Given the system is pre-production, a one-time migration with backup is recommended.
6. **Should the minimal authenticated HTTP API ingress ship in this sprint or be deferred?** Telegram is the primary deliverable. A minimal HTTP API ingress (for programmatic access and testing) would be low effort given the `IngressTransport` abstraction, but could be deferred to avoid scope creep.
7. **What is the cleanest boundary between `MissionCoordinator` and `ChangeCoordinator`?** The existing `ChangeCoordinator` handles implement → review → scenario flows. `MissionCoordinator` is more general. The recommended approach is to have `MissionCoordinator` delegate to `ChangeCoordinator` when the mission plan includes a code change step, rather than replacing it.
