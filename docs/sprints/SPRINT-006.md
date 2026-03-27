# SPRINT-006: The Agent Fabric — Root/Worker Mega Sprint

## Overview

Sprint 006 is the **single canonical mega sprint** for the root/worker agent fabric. It merges the Claude, Codex, and Gemini planning work into one phased execution document instead of splitting the program across multiple future sprint specs. The goal is to add a durable root/worker system on top of the existing Swift stack, not replace it: `OmniAIAgent.Session` remains the local agent loop, `OmniAgentsSDK` remains the handoff and compaction substrate, `OmniACP` remains the ACP edge, `OmniMCP` remains the custom-tool surface, `OmniAIAttractor` remains the workflow/evaluation engine, and Sprint 005’s `OmniExecution` / `OmniContainer` work becomes a worker capability rather than a separate orchestration architecture.

The system shape is simple at the top and disciplined underneath. A single **root agent** is the only user-facing interface across text, chat, and audio. It can handle simple work directly, but it can also delegate durable background jobs to **worker agents** that may run on the same machine, other machines, or different compute classes. Workers may spawn child work, but child lineage, state, and context transfer must remain explicit and durable. ACP is used only at the **worker edge** for Codex, Claude, and Gemini sessions; it is not the root/worker mesh protocol.

This mega sprint is still intentionally phased. The first shipping slice is narrow: a durable root, a local worker daemon, a SQLite-backed task/event store, worker-local ACP/MCP integration, and a deploy fence that prevents release swaps from dropping unrelated jobs. Remote workers, nested delegation, and self-modifying delivery build on the same task/event model rather than forcing a second architecture later. The phases below are execution milestones inside Sprint 006, not separate canonical sprint documents.

## Use Cases

1. **Single root interface**: The user talks only to the root agent while summaries, notifications, and delegated work happen behind the scenes.
2. **Background delegation without interruption**: The root accepts a long-running coding or research task, keeps the user interaction responsive, and reports back when the result is important.
3. **Capability-based placement**: Tasks route to workers that advertise macOS, Linux, Blink/container, simulator, GPU, or other required capabilities.
4. **Nested delegation**: A worker handling a larger task can create child tasks for review, testing, or parallel subtasks while preserving parent/child lineage.
5. **Provider portability**: Workers use Codex ACP, Claude ACP, Gemini ACP, or local agent sessions without changing the mesh protocol or the task model.
6. **Custom tools once, everywhere**: Tools are exposed through MCP so provider edges and worker-native flows share the same tool surface.
7. **Self-modifying delivery**: The system can plan, implement, review, scenario-test, deploy, verify, and roll back safe Swift code changes.
8. **Rollback-safe continuity**: A failed deploy restores the previous release without erasing unrelated queued or running background tasks.

## Architecture

### Topology

```text
                          User
                    text / chat / audio
                             |
                             v
                 +------------------------+
                 | Root Agent Server      |
                 | context + scheduler +  |
                 | notification inbox     |
                 +-----------+------------+
                             |
                    OmniAgentMesh protocol
                             |
        +--------------------+--------------------+
        |                    |                    |
        v                    v                    v
 +--------------+    +--------------+    +--------------+
 | Worker Agent |    | Worker Agent |    | Worker Agent |
 | macOS / CPU  |    | Linux / CPU  |    | GPU / Linux  |
 +------+-------+    +------+-------+    +------+-------+
        |                   |                   |
        v                   v                   v
   local child work    local child work    local child work
        |                   |                   |
        +--------- ACP / MCP edge adapters -----+
                    |     |       |
                    v     v       v
                 Codex  Claude  Gemini

                 +------------------------+
                 | Supervisor             |
                 | deploy / rollback /    |
                 | health / drain         |
                 +------------------------+
```

### Core Rules

- The **root agent** is the only user-facing persona.
- **Workers** are durable execution nodes, not separate user-facing chats.
- **ACP is edge-only**. It is never the root/worker coordination protocol.
- **MCP is the custom tool strategy**. Do not add bespoke provider-specific tool glue if MCP can carry it.
- **Jobs may not live only in memory**. Durable ownership lives in the fabric stores, not in one process.
- **Deployment lifecycle is separate from job lifecycle**. A release swap cannot erase task state.
- **Child workers get a filtered history projection**, not the full parent transcript.
- **Current local subagent semantics remain as compatibility shims** until durable mesh-backed delegation fully replaces them.

### Persistence Boundaries

The fabric needs four separate persistence domains:

1. **Conversation Store**
   - root interaction items
   - summaries
   - notification history
   - modality metadata

2. **Job Store**
   - task records
   - attempts
   - assignments
   - leases
   - parent/child lineage
   - append-only task events

3. **Artifact Store**
   - patches
   - logs
   - screenshots
   - review output
   - test results
   - scenario evaluation artifacts

4. **Deployment Store**
   - release versions
   - health state
   - canary status
   - rollback checkpoints

Recommended development state root:

```text
.ai/the-agent/
  conversation.sqlite
  jobs.sqlite
  deploy.sqlite
  artifacts/
  releases/
  checkpoints/
```

### Task and Context Model

Delegation is durable and task-based. Each task record should include:

- `taskID`
- `rootSessionID`
- `parentTaskID`
- `assignedAgentID`
- `capabilityRequirements`
- `historyProjection`
- `artifactRefs`
- `priority`
- `lease`
- `status`

Minimum task events:

- `task.submitted`
- `task.assigned`
- `task.started`
- `task.progress`
- `task.waiting`
- `task.tool_call`
- `task.artifact`
- `task.completed`
- `task.failed`
- `task.cancelled`
- `task.resumed`

Every child task must be built from an explicit **history projection**:

- task brief
- relevant summaries
- selected parent excerpts
- artifact references
- constraints and expected outputs

Children should never receive a full parent session by default.

### Transport Strategy

Use a staged mesh transport, not a single universal transport from day one.

- **Phase 1 / same-host**: in-process or loopback mesh transport for local worker execution
- **Phase 2 / remote**: split transport
  - HTTP for registration, admin calls, artifact metadata, and health checks
  - WebSocket for long-lived worker sessions, heartbeats, progress streaming, cancellation, and resume

Every task event must carry a monotonic sequence number and idempotency key so reconnect/replay does not duplicate side effects.

### Reuse-First Module Plan

**New targets**

- `Sources/OmniAgentMesh`
- `Sources/TheAgentControlPlane`
- `Sources/TheAgentWorker`
- `Sources/OmniAgentDeploy`

**Existing modules to extend**

- `Sources/OmniAIAgent`
- `Sources/OmniAIAttractor`
- `Sources/OmniACP`
- `Sources/OmniMCP`
- `Sources/OmniAgentsSDK`
- `Sources/OmniContainer`

**Important constraints**

- Reuse the repo’s current HTTP/WebSocket stack before considering new dependencies.
- Use SQLite and repo-owned store layers before adding any new database package.
- Keep Swift 6 strict concurrency intact.

## Implementation

### Phase 1: Mesh Foundation and Durable Stores

**Goals**
- Add `OmniAgentMesh`
- Define durable task, event, lease, artifact, and deployment models
- Introduce SQLite-backed conversation/job/deployment stores and file-backed artifacts

**Files**
- `Package.swift`
- `Sources/OmniAgentMesh/Models/TaskRecord.swift`
- `Sources/OmniAgentMesh/Models/TaskEvent.swift`
- `Sources/OmniAgentMesh/Models/WorkerRecord.swift`
- `Sources/OmniAgentMesh/Models/HistoryProjection.swift`
- `Sources/OmniAgentMesh/Stores/ConversationStore.swift`
- `Sources/OmniAgentMesh/Stores/JobStore.swift`
- `Sources/OmniAgentMesh/Stores/ArtifactStore.swift`
- `Sources/OmniAgentMesh/Stores/DeploymentStore.swift`

**Tasks**
- [ ] Define the append-only task event envelope, sequence numbers, and idempotency keys.
- [ ] Implement store protocols plus SQLite/file-backed bootstrap implementations.
- [ ] Add restart replay and orphan recovery tests.

### Phase 2: Root Control Plane and Universal Context

**Goals**
- Add `TheAgentControlPlane`
- Build the root-facing daemon and root session spine
- Normalize text/chat/audio transcript inputs into one interaction model

**Files**
- `Sources/TheAgentControlPlane/main.swift`
- `Sources/TheAgentControlPlane/RootAgentServer.swift`
- `Sources/TheAgentControlPlane/RootConversation.swift`
- `Sources/TheAgentControlPlane/NotificationInbox.swift`
- `Sources/TheAgentControlPlane/Policy/NotificationPolicy.swift`
- `Sources/TheAgentControlPlane/Scheduler/RootScheduler.swift`
- `Sources/OmniAIAgent/Models/SessionPersistence.swift`
- `Sources/OmniAgentsSDK/Memory/CompactionSession.swift`
- `Sources/OmniAgentsSDK/Memory/SQLiteSession.swift`

**Tasks**
- [ ] Restore root context, summaries, and unresolved notifications after restart.
- [ ] Maintain a hot context window plus rolling structured summary.
- [ ] Add a notification inbox so the root decides when to interrupt the user.
- [ ] Keep audio readiness at the data-model layer even if live capture lands later.

### Phase 3: Local Worker Daemon and Durable Task Lifecycle

**Goals**
- Add `TheAgentWorker`
- Build a local worker daemon with registration, heartbeat, lease renewal, progress streaming, and cancellation
- Reuse current local execution and container capabilities

**Files**
- `Sources/TheAgentWorker/main.swift`
- `Sources/TheAgentWorker/WorkerDaemon.swift`
- `Sources/TheAgentWorker/WorkerCapabilities.swift`
- `Sources/TheAgentWorker/LocalTaskExecutor.swift`
- `Sources/TheAgentWorker/TaskStreams/WorkerEventStream.swift`
- `Sources/OmniAIAgent/Subagents/SubAgent.swift`
- `Sources/OmniAIAgent/Subagents/WorktreeIsolation.swift`

**Tasks**
- [ ] Delegate from root to same-host worker asynchronously.
- [ ] Preserve task state across root restart or worker restart.
- [ ] Keep current `spawn_agent` semantics as compatibility shims while durable ownership moves into the mesh.

### Phase 4: ACP Adapter Registry, MCP Tool Bundles, and Remote Transport Base

**Goals**
- Make Codex, Claude, and Gemini first-class worker-local ACP adapters
- Expose custom tools through MCP only
- Add the first remote transport implementation

**Files**
- `Sources/TheAgentWorker/ACP/ACPExecutor.swift`
- `Sources/TheAgentWorker/ACP/ACPWorkerSession.swift`
- `Sources/TheAgentWorker/MCP/WorkerMCPServer.swift`
- `Sources/TheAgentWorker/MCP/ToolRegistry.swift`
- `Sources/OmniAIAttractor/Handlers/ACPAgentBackend.swift`
- `Sources/OmniAIAttractor/Handlers/ACPBackendPreset.swift`
- `Sources/OmniAgentMesh/Transport/MeshServer.swift`
- `Sources/OmniAgentMesh/Transport/MeshClient.swift`

**Tasks**
- [ ] Run the same delegated task through Codex ACP, Claude ACP, and Gemini ACP.
- [ ] Mount the same MCP registry across provider edges and worker-native sessions.
- [ ] Add remote registration, heartbeats, and streamed progress over the mesh transport.

### Phase 5: Remote Scheduling, Reconnect, Resume, and Nested Delegation

**Goals**
- Add capability-based remote placement
- Add reconnect/resume semantics and event replay
- Convert child work into durable mesh-backed lineage

**Files**
- `Sources/TheAgentControlPlane/Registry/WorkerRegistry.swift`
- `Sources/TheAgentControlPlane/Scheduler/CapabilityMatcher.swift`
- `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift`
- `Sources/TheAgentWorker/Subagents/HistoryProjectionBuilder.swift`
- `Sources/OmniAgentsSDK/Handoffs.swift`

**Tasks**
- [ ] Dispatch to a remote worker and survive disconnect/reconnect.
- [ ] Build bounded `HistoryProjection` objects for child work.
- [ ] Keep parent notifications coherent across child task fan-out.

### Phase 6: Safe Self-Modification, Supervisor, Deploy, and Rollback

**Goals**
- Add `OmniAgentDeploy`
- Add an external supervisor for root/worker binaries
- Implement safe self-modifying delivery with review, scenario evaluation, deploy, verify, rollback, and retry

**Files**
- `Sources/OmniAgentDeploy/main.swift`
- `Sources/OmniAgentDeploy/Supervisor.swift`
- `Sources/OmniAgentDeploy/ReleaseController.swift`
- `Sources/OmniAgentDeploy/ChangePipeline.swift`
- `Sources/TheAgentControlPlane/Changes/ChangeCoordinator.swift`
- `Sources/TheAgentWorker/Review/ReviewWorker.swift`
- `Sources/TheAgentWorker/Scenarios/ScenarioEvalWorker.swift`
- `Sources/OmniAIAttractor/Handlers/ParallelHandler.swift`
- `Sources/OmniAIAttractor/Handlers/ManagerLoopHandler.swift`
- `Sources/OmniAIAttractor/Models/ArtifactStore.swift`
- `Sources/OmniAIAttractor/Models/PipelineEvent.swift`

**Tasks**
- [ ] Route implementation, review, and evaluation to separate workers or isolated lanes.
- [ ] Make PR-only integration the default initial policy.
- [ ] Add canary deploy, health verification, rollback, and recovery of unrelated background tasks.

## Files Summary

| File | Action | Purpose |
|------|--------|---------|
| `Package.swift` | Modify | Add mesh, control-plane, worker, and deploy targets plus tests |
| `Sources/OmniAgentMesh/` | Create | Durable models, stores, and mesh transport |
| `Sources/TheAgentControlPlane/` | Create | Root daemon, context spine, notifications, scheduler |
| `Sources/TheAgentWorker/` | Create | Worker daemon, execution backends, nested delegation |
| `Sources/OmniAgentDeploy/` | Create | Supervisor, release control, change pipeline |
| `Sources/OmniAIAgent/Models/SessionPersistence.swift` | Modify | Extend snapshot/recovery for root continuity |
| `Sources/OmniAIAgent/Subagents/SubAgent.swift` | Modify | Preserve compatibility while introducing durable lineage |
| `Sources/OmniAgentsSDK/Memory/CompactionSession.swift` | Modify | Shared summary and history projection support |
| `Sources/OmniAIAttractor/Handlers/ACPBackendPreset.swift` | Modify | Worker-local Codex/Claude/Gemini ACP registration |
| `Sources/OmniMCP/MCPServer.swift` | Modify | Shared MCP tool surfacing |
| `Sources/OmniContainer/` | Reuse | Worker execution capabilities, not control-plane ownership |
| `Tests/OmniAgentMeshTests/` | Create | Stores, transport, reconnect, and event replay tests |
| `Tests/TheAgentControlPlaneTests/` | Create | Root persistence and notification tests |
| `Tests/TheAgentWorkerTests/` | Create | Worker lifecycle, ACP, MCP, and child task tests |
| `Tests/OmniAgentScenarioTests/` | Create | Restart, reconnect, deploy, rollback, and continuity scenarios |

## Definition of Done

- [ ] The root control plane owns user-facing context, summaries, task notifications, worker registry, and scheduling without depending on in-memory task ownership.
- [ ] Task, event, lease, artifact, and deployment state are durable across root restarts and release swaps.
- [ ] A worker daemon can run in local or remote mode, advertise capabilities, accept tasks, stream progress, reconnect, and resume.
- [ ] Nested delegation preserves lineage and bounded context through explicit history projections.
- [ ] Codex, Claude, and Gemini ACP adapters run as worker-local edges, and custom tools are exposed through MCP instead of bespoke provider glue.
- [ ] The self-modifying path can implement, review, scenario-test, deploy, verify, rollback, and retry without erasing unrelated background work.
- [ ] New tests cover restart, reconnect, cancellation, duplicate delivery, nested delegation depth, ACP adapter isolation, and deploy rollback continuity.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Current `Session` / `spawn_agent` behavior is process-local | High | High | Keep compatibility shims and move durable ownership into `OmniAgentMesh` first |
| Current Attractor artifacts/events are not durable enough | High | High | Mirror authoritative task events and artifacts into the new stores immediately |
| Sprint 005 runtime surfaces may still move | Medium | High | Treat `OmniContainer` and `OmniExecution` as worker capabilities and avoid invasive refactors |
| Context explodes under nested delegation | High | High | Make `HistoryProjection` mandatory and summarize aggressively at the root |
| Remote reconnect duplicates work | Medium | High | Use leases, sequence numbers, idempotency keys, and explicit reclaim rules |
| Self-modifying deploys can brick the system | Medium | High | Use external supervisor, PR-only default, independent review/eval lanes, and automatic rollback |

## Security Considerations

- Authenticate worker registration, task streaming, and lease reclaim.
- Keep control-plane credentials separate from provider/model credentials.
- Run implementation, review, and scenario evaluation in isolated worktrees or containers when possible.
- Keep direct protected-`main` integration disabled by default; PR-only should be the initial policy.
- Persist an audit trail for task events, tool calls, approvals, artifact hashes, releases, and rollbacks.
- Redact secrets from logs, summaries, and persisted artifacts before model exposure.

## Dependencies

- `OmniAIAgent` for the local loop, session persistence, and current subagent surfaces
- `OmniAgentsSDK` for handoff and compaction primitives
- `OmniACP` plus `ACPAgentBackend` / `ACPBackendPreset` for worker-local Codex, Claude, and Gemini ACP integration
- `OmniMCP` for the custom-tool surface
- `OmniAIAttractor` for review, scenario, and deployment workflow orchestration
- Sprint 005’s `OmniExecution`, `OmniVFS`, and `OmniContainer` as worker capabilities
- SQLite via a repo-owned store layer and system library binding, not a new third-party package
- A stable state directory outside the active release directory

## Open Questions

1. Should the new targets follow `TheAgent*` naming from the architecture note, or be renamed to `OmniAgent*` for package consistency?
2. Is the first remote mesh transport split HTTP control + WebSocket stream, or pure WebSocket end-to-end?
3. Does Sprint 008 ship only text/chat plus transcript ingestion, or is live audio capture part of the same delivery cut?
4. Should the supervisor be a repo-owned Swift executable, or should the repo provide libraries while `launchd`, `systemd`, or container orchestration owns process supervision?
5. When, if ever, should direct protected-`main` self-modification be allowed instead of PR-only integration?
6. For nested delegation, should same-host child work default to local worker spawning, or should children return to the root unless the parent explicitly requests local placement?
