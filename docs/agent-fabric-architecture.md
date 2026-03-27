# The Agent Fabric Architecture

Date: 2026-03-24

Status: implemented through Sprint 007, with live Telegram proof still dependent on external bot credentials.

## Product Contract

`TheAgent` is the only user-facing persona.

- Users talk to the root agent over Telegram or authenticated HTTP/API.
- The root agent owns conversation memory, mission planning, approvals, questions, and final replies.
- Workers and subagents are internal execution lanes. They may recurse, but they never talk to the user directly.
- Multi-user support is first-class: every durable record is scoped to a workspace and channel boundary.

## Implemented Topology

```text
Telegram / HTTP API
        |
        v
+---------------------------+
| IngressGateway            |
| dedupe + scope + routing  |
+-------------+-------------+
              |
              v
+---------------------------+
| WorkspaceRuntimeRegistry  |
| one root runtime per      |
| workspace/channel scope   |
+-------------+-------------+
              |
              v
+---------------------------+
| RootAgentRuntime          |
| OmniAIAgent.Session       |
| + mission toolbox         |
+------+------+-------------+
       |      |
       |      v
       |  +------------------------+
       |  | InteractionBroker      |
       |  | approvals + questions  |
       |  +-----------+------------+
       |              |
       v              v
+---------------------------+     HTTP mesh
| MissionCoordinator        | <----------------------+
| direct / worker /         |                        |
| attractor-workflow        |                        |
+-------------+-------------+                        |
              |                                      |
              v                                      |
+---------------------------+                        |
| RootScheduler             |                        |
| durable task placement    |                        |
+-------------+-------------+                        |
              |                                      |
              v                                      |
+---------------------------+                        |
| WorkerDaemon              |------------------------+
| local / ACP / attractor   |
+-------------+-------------+
              |
              v
+---------------------------+
| ChildWorkerManager        |
| child tasks / workflows   |
+---------------------------+
```

## Durable State

The runtime uses the Sprint 006 state root and extends it for multi-user operation:

```text
.ai/the-agent/
  identity.sqlite
  conversation.sqlite
  missions.sqlite
  jobs.sqlite
  deploy.sqlite
  artifacts/
  checkpoints/
```

Primary durable domains:

- `IdentityStore`
  - actors
  - workspaces
  - memberships
  - channel bindings
- `ConversationStore`
  - scoped interactions
  - hot context
  - summaries
  - notifications
- `MissionStore`
  - missions
  - stages
  - approval requests
  - question requests
- `DeliveryStore`
  - inbound dedupe
  - outbound receipts
- `JobStore`
  - worker records
  - tasks
  - task events
  - attempt and escalation metadata
- `ArtifactStore`
  - mission and task artifacts
  - remote fetch via HTTP mesh

Sprint 006 compatibility is preserved through scoped session bootstrap and legacy session-key fallback, so old `root` state can still be discovered during migration.

## Workspace and Channel Isolation

The security and memory boundary is the workspace.

- Telegram DMs auto-provision a personal workspace.
- Shared Telegram groups and topics bind to a shared workspace/channel.
- Authenticated HTTP/API requests route through the same ingress normalization path.
- `WorkspaceSessionRegistry` and `WorkspaceRuntimeRegistry` prevent concurrent scopes from sharing one in-memory root runtime.
- Shared chats preserve per-message actor identity while reusing one scoped root session.

## Ingress and Delivery

All inbound traffic is normalized into `IngressEnvelope`.

Implemented ingress behavior:

- durable inbound dedupe by idempotency key
- mention/reply gating in shared Telegram chats
- ambient shared-chat handling only when workspace policy enables it
- callback query acknowledgement before longer mission work continues
- long assistant replies chunked into multiple Telegram messages
- unsupported Telegram media rejected explicitly instead of silently dropped
- shared-chat sensitive approvals/questions rerouted to DM by default
- DM bootstrap fallback when the user has not started a private chat with the bot yet

Ingress surfaces:

- `TelegramWebhookHandler`
- `TelegramPollingRunner`
- `HTTPIngressServer`

All three surfaces feed the same `IngressGateway`.

## Root Runtime

The root runtime is a real `OmniAIAgent.Session`, not a thin task dispatcher.

`RootAgentRuntime` wraps:

- scoped `RootAgentServer`
- scoped `RootConversation`
- `RootOrchestratorProfile`
- `RootAgentToolbox`

The root toolbox is mission-oriented. The model can:

- start missions
- inspect mission and task status
- list workers
- wait for task completion
- inspect and resolve inbox items

Raw task tools remain available as a fallback/debug path, but non-trivial work defaults to missions.

## Missions and Interaction Brokerage

`MissionCoordinator` is the default control-plane abstraction for non-trivial work.

Execution modes:

- `direct`
- `worker_task`
- `attractor_workflow`

Implemented mission behavior:

- mission contract artifact creation
- progress and verification artifact creation
- approval-gated mission startup
- workspace budget and recursion limits
- retry decisions through `MissionSupervisor`
- `ChangeCoordinator` reuse for code-change missions
- root-owned inbox isolation per workspace/session

`InteractionBroker` owns user-blocking questions and approvals. Worker-originated human gates are promoted into durable root-owned records before they are exposed to Telegram/API delivery.

## Worker Plane

`WorkerDaemon` supports three execution paths:

- plain local executor
- ACP-backed executor
- Attractor-backed executor

`WorkerExecutorFactory` selects the lane from CLI options and augments worker capabilities accordingly.

Recursive delegation is handled through `ChildWorkerManager`, which now carries:

- parent lineage
- bounded history projection
- recursion depth constraints
- budget constraints

## Attractor Integration

Attractor is the structured worker-side workflow engine, not the mesh protocol.

The default worker workflow template is:

- `plan`
- `implement`
- `review`
- `scenario`
- `judge`

Implemented control rules:

- validator stages are goal gates
- workflow retries are bounded by the template instead of inheriting Attractor’s permissive graph defaults
- `wait_human` prompts are bridged to the root interaction broker through `RootBrokerInterviewer`
- failure and retry outcomes surface back to the mission layer instead of disappearing into long retry loops

This keeps the worker workflow useful for compound tasks while leaving atomic tasks on the simpler plain-task path.

## Mesh Transport

`HTTPMeshServer` and `HTTPMeshClient` now cover more than task scheduling.

Implemented remote transport surfaces:

- worker registration and heartbeat
- task claim/start/progress/complete/fail/cancel
- task event replay
- artifact `put`
- artifact `get`
- artifact `list`
- worker interaction bridge requests for approvals/questions

This closes the Sprint 006 gap where remote workers could execute tasks but the root could not inspect remote artifacts durably.

## Telegram and API Operational Notes

Telegram-specific behavior is intentionally isolated at the edge.

- Bot API payloads map into `IngressEnvelope`.
- Reply chunking and inline callback markup live in `TelegramDeliveryFormatter`.
- Callback query payloads are encoded by `TelegramCallbackCodec`.
- Webhook and polling are transport choices only; mission logic stays transport-blind.

For startup and operator details, use [the-agent-runtime-runbook.md](/Users/navan.chauhan/Developer/navanchauhan/swift-omnikit/docs/the-agent-runtime-runbook.md).

## Current Gaps

The core runtime is implemented and validated by tests, but one external item remains outside the repo:

- real Telegram live proof still needs a bot token and either a reachable webhook endpoint or a polling session against that bot

The code path is present. The missing piece is environment-specific credentialed execution, not a remaining architecture hole.
