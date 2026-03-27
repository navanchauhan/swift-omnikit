# Sprint 007: The Agent Product Runtime

## Overview

Sprint 007 productizes the Sprint 006 root/worker fabric into a mission-oriented runtime where `TheAgent` is the only user-facing persona. The control plane stops exposing raw orchestration primitives as the primary interaction model and instead hosts a chief-of-staff root agent that accepts user work from transport adapters, plans execution, delegates recursively to workers and subagents, asks questions or approval requests only when necessary, and reports results back through the originating channel.

This sprint assumes Sprint 006 infrastructure is already shipped and stable: durable stores, HTTP mesh transport, remote worker registration, ACP-backed worker execution, and the live root `Session` hosted by the control plane. Sprint 007 builds on that substrate rather than replacing it. The primary product additions are mission orchestration, ingress normalization, identity and isolation, durable interaction brokering, remote artifact transport, and a disciplined worker execution model that uses `OmniAIAttractor` for structured workflows such as `plan -> implement -> validate` without forcing all work through Attractor.

The design is transport-agnostic at the mission core. Telegram is the first shipping ingress, but the root mission runtime, identity model, interaction broker, and supervision loop are not Telegram-specific. Multi-user, shared-workspace, and multi-channel isolation are foundational concerns in the persistence model, message routing, artifact access, and approval handling.

## Use Cases

1. A user sends a Telegram DM to `TheAgent` with a mission request. The ingress adapter normalizes the message into a canonical conversation event, the root agent creates or resumes a mission in the user’s default workspace, delegates work to one or more workers, asks follow-up questions only if required, and returns the final result in the same Telegram thread.

2. Multiple users share a workspace and interact with `TheAgent` from the same Telegram group or topic. The system maps each inbound event to a concrete `workspace + channel + participant` context, preserves mission isolation, routes root-owned questions and approvals to the correct participants, and prevents cross-mission or cross-workspace leakage.

3. The root agent receives a large implementation request and decomposes it into a structured worker workflow. A worker uses `OmniAIAttractor` to run `plan -> implement -> validate`, checkpointing progress, retrying failed stages, waiting for human input when explicitly requested by the root, and returning a structured result bundle.

4. A worker performing evaluation or review needs artifacts produced on a remote machine. The system uses shared artifact metadata plus transport-backed retrieval so the root, judges, or remote validators can inspect outputs durably instead of relying on worker-local files.

5. A worker delegates to a child worker or subagent for bounded sub-work. The system records lineage, depth, budgets, and supervision ownership so recursive delegation remains possible without becoming unbounded or opaque.

6. The control plane or worker process restarts during an active mission. The system reloads mission state, pending interactions, child task lineage, outstanding approvals, and remote artifact references, then resumes supervision and delivery without losing the user-facing mission thread.

7. A user request needs a root-owned approval, such as permission to modify a deployment or spend budget. Workers cannot directly ask the human. They raise an approval request to the root, which decides whether to ask the user, whom to ask inside the workspace, how to present the request in-channel, and how to continue after the decision.

## Architecture

Sprint 007 introduces a mission runtime layer above the Sprint 006 task fabric. The main architectural units are:

- `Ingress Gateway`: Accepts external events from Telegram first, later HTTP/API or other transports. It verifies transport authenticity, converts transport-specific payloads into canonical ingress events, and forwards them into the control plane.
- `Identity and Isolation Layer`: Defines durable concepts for `User`, `Workspace`, `Channel`, `Membership`, `Mission`, `Interaction`, and `Approval`. Every inbound or outbound event is scoped through these identities before it reaches mission logic.
- `Root Mission Runtime`: Replaces raw tool-first root behavior with a mission contract. It owns mission lifecycle, conversation continuity, delegation policy, supervision, question routing, approval routing, and final response delivery.
- `Interaction Broker`: Centralizes all human-facing asks. Workers cannot directly talk to humans. They emit structured `question`, `approval`, or `status` requests to the root, and the broker decides how they are surfaced and correlated to replies.
- `Delegation and Supervision Layer`: Extends Sprint 006 task routing with durable lineage, recursion limits, execution budgets, parent-child relationships, recovery markers, and escalation behavior.
- `Artifact Transport Layer`: Promotes artifacts from worker-local outputs into remotely retrievable objects with metadata, ownership, access scope, and transport-backed download or proxy semantics.
- `Worker Execution Modes`: Supports both lightweight task execution and structured Attractor-backed workflows. Atomic tasks stay on the direct execution path; complex implementation missions use `OmniAIAttractor`.
- `Delivery Layer`: Sends user-visible responses, questions, approvals, and mission updates back through the originating channel adapter while preserving the single root persona.

Core model additions:

- `User`: durable identity for a human participant.
- `Workspace`: collaboration boundary and policy container.
- `Channel`: external conversation surface, such as Telegram DM, group, or topic.
- `ChannelBinding`: mapping between transport-native identifiers and internal channel/workspace records.
- `Membership`: user access and role within a workspace.
- `Mission`: durable root-owned unit of user work, above task/job level.
- `MissionStep`: root-visible progression and supervision checkpoints.
- `InteractionRequest`: pending question/approval/status event awaiting delivery or response.
- `ApprovalDecision`: durable user decision correlated to a root-owned approval request.
- `ArtifactReference`: remotely retrievable artifact handle with storage and access metadata.
- `DelegationLineage`: parent/child linkage across root tasks, worker tasks, and subagent workflows.

Root runtime contract:

- The root receives canonical ingress events.
- The root resolves identity and workspace context.
- The root creates or resumes a mission.
- The root decides whether the mission can be handled directly, delegated simply, or delegated through an Attractor-backed workflow.
- The root remains the only user-facing persona for replies, questions, and approvals.
- The root owns completion, failure explanation, retry escalation, and recovery on restart.

Attractor placement:

- `OmniAIAttractor` is a worker-side structured workflow engine, not the universal transport or mission core.
- The root selects Attractor when the task benefits from explicit staged execution, retries, checkpoints, evaluation, or human gates.
- Direct worker execution remains available for simple, bounded, or low-latency operations.
- Attractor workflows report progress and human-gate requests back to the root through structured control-plane events, never directly to the end user.

Isolation model:

- Every mission is bound to one workspace and one originating channel context.
- Every inbound message is resolved as `transport -> channel -> workspace -> actor`.
- Shared chats are supported through channel membership and topic/thread binding, not through ad hoc heuristics.
- Artifact access, approval visibility, and mission state queries are filtered by workspace membership and mission/channel scope.
- The foundation layer stores enough identity metadata to prevent leakage before higher-level policy is applied.

## Implementation

1. Mission Runtime Refactor
- Introduce a mission-oriented root coordinator above the existing Sprint 006 session/task runtime.
- Replace raw tool-first interaction with mission methods such as `startMission`, `resumeMission`, `requestClarification`, `requestApproval`, `delegateMissionStep`, `recordArtifact`, and `completeMission`.
- Preserve Sprint 006 stores and transport where possible; add mission state rather than reworking the mesh fabric.
- Keep the root agent as the only user-facing persona in all prompts, responses, and state transitions.

2. Identity, Workspace, and Channel Foundation
- Add durable models and store support for users, workspaces, memberships, channels, and channel bindings.
- Define canonical routing keys that include workspace and channel scope for every conversation, mission, interaction, and artifact.
- Support shared workspaces from the start, including role-aware approval routing.
- Add policy hooks for workspace defaults, permitted transports, delegation budgets, and artifact visibility.

3. Ingress Gateway and Telegram Adapter
- Add a transport-agnostic ingress boundary in the control plane.
- Implement Telegram as the first adapter: webhook polling or webhook delivery shape, message normalization, chat/thread mapping, reply correlation, and outbound delivery.
- Normalize Telegram DMs, groups, and topics into canonical ingress events without leaking Telegram-specific types into mission logic.
- Create a delivery abstraction so later HTTP/API ingress can reuse the same mission runtime.

4. Root-Owned Interaction Broker
- Add a durable interaction queue for questions, approvals, and delivery retries.
- Require workers and Attractor workflows to raise human interaction needs to the root rather than contacting users directly.
- Support correlation of inbound human replies to pending mission interactions.
- Add shared-chat-safe interaction modes, including explicit routing metadata and configurable approval visibility.

5. Recursive Delegation, Lineage, and Supervision
- Extend task/job records with mission lineage, depth, parent step, recursion budget, and supervising root mission identifiers.
- Enforce bounded delegation with depth limits and budget exhaustion policies.
- Add supervision loops for stalled child work, repeated retries, orphaned subtasks, and restart recovery.
- Record child workflow lineage consistently across direct worker tasks, ACP executions, and subagent-managed child workers.

6. Attractor Integration for Structured Worker Workflows
- Add a worker execution mode that launches `OmniAIAttractor` pipelines for tasks that need `plan -> implement -> validate`.
- Map root mission steps onto Attractor pipeline requests with clear inputs, outputs, checkpoints, and evaluation criteria.
- Translate Attractor wait/human-gate events into root interaction requests rather than direct user prompts.
- Keep atomic worker actions on the simpler execution path to avoid unnecessary workflow overhead.

7. Remote Artifact Transport
- Extend artifact storage and transport so artifacts can be listed, fetched, and validated across machines.
- Separate artifact metadata from artifact bytes so mission state can reference durable artifact handles even before retrieval.
- Add root-readable and evaluator-readable artifact resolution for remote review, scenario checks, and judge flows.
- Ensure artifact ownership, workspace scope, and retention metadata are enforced consistently.

8. Recovery and Durability
- Persist mission state transitions, pending interactions, approval waits, delivery attempts, delegation lineage, and artifact handles.
- On control-plane restart, reload active missions and re-register any supervision watches.
- On worker restart, reconcile in-flight Attractor workflows or direct tasks against durable lineage state.
- Add retry and dead-letter handling for ingress events, outbound deliveries, and artifact transfers.

9. Observability and Testing
- Add mission-level logs and identifiers that tie together root events, worker executions, child delegations, approvals, and artifact flows.
- Add unit tests for identity and workspace isolation, mission state transitions, approval brokering, and delegation policy.
- Add integration tests for Telegram normalization, routing, outbound delivery, and shared-channel correlation.
- Add worker tests for Attractor-backed execution and child lineage persistence.
- Add end-to-end tests spanning local and remote workers with Telegram as the user-facing ingress.

## Files Summary

- `Sources/TheAgentControlPlane/RootAgentRuntime.swift`
  - Refactor from task-oriented orchestration into mission lifecycle ownership, interaction brokering, and supervision entrypoints.

- `Sources/TheAgentControlPlane/RootAgentServer.swift`
  - Add ingress-facing mission endpoints, transport adapter registration, and recovery bootstrapping.

- `Sources/TheAgentControlPlane/RootAgentToolbox.swift`
  - Narrow raw operator tools behind mission-level capabilities and root-only interaction methods.

- `Sources/TheAgentControlPlane/RootOrchestratorProfile.swift`
  - Update root persona and contract so the root behaves as the sole user-facing chief-of-staff agent.

- `Sources/TheAgentControlPlane/Changes/ChangeCoordinator.swift`
  - Connect mission approvals and change gating to root-owned approval flow.

- `Sources/TheAgentControlPlane/Scheduler/RootScheduler.swift`
  - Add supervision scheduling, stalled mission rechecks, delivery retries, and orphan recovery.

- `Sources/TheAgentWorker/WorkerDaemon.swift`
  - Support mission-scoped execution context, artifact publication, and Attractor-backed worker workflows.

- `Sources/TheAgentWorker/WorkerExecutorFactory.swift`
  - Add execution mode selection between direct execution and Attractor pipelines.

- `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift`
  - Persist child lineage, recursion depth, budgets, and parent mission supervision metadata.

- `Sources/OmniAgentMesh/Models/TaskRecord.swift`
  - Extend with mission identifiers, parent-child lineage, recursion metadata, and artifact references.

- `Sources/OmniAgentMesh/Stores/ConversationStore.swift`
  - Add workspace/channel/user scoping and interaction correlation support.

- `Sources/OmniAgentMesh/Stores/JobStore.swift`
  - Persist mission linkage, supervision status, retries, and recovery markers.

- `Sources/OmniAgentMesh/Stores/ArtifactStore.swift`
  - Add remote artifact handles, access metadata, transport-backed retrieval state, and retention tracking.

- `Sources/OmniAgentMesh/Transport/HTTPMeshServer.swift`
  - Support artifact retrieval endpoints and mission-aware authenticated transport contracts.

- `Sources/OmniAgentMesh/Transport/HTTPMeshClient.swift`
  - Add remote artifact fetch/publish flows and mission-aware lineage propagation.

- `Sources/OmniAIAttractor/Engine/PipelineEngine.swift`
  - Ensure worker-launched pipelines expose checkpoints, result bundles, and resumable status suitable for mission supervision.

- `Sources/OmniAIAttractor/Handlers/ManagerLoopHandler.swift`
  - Fit structured `plan -> implement -> validate` manager loops into worker execution contracts.

- `Sources/OmniAIAttractor/Handlers/WaitHumanHandler.swift`
  - Route human waits through root-owned interaction requests instead of direct user contact.

- `Sources/OmniAIAttractor/Server/HTTPServer.swift`
  - Reuse or adapt for worker-local structured workflow execution only where needed, not as the global ingress.

- `Sources/TheAgentControlPlane/Ingress/`
  - New module area for canonical ingress event types, adapter interfaces, Telegram adapter, and outbound delivery abstractions.

- `Sources/TheAgentControlPlane/Identity/`
  - New module area for user, workspace, membership, channel, and routing models plus store/service logic.

- `Sources/TheAgentControlPlane/Missions/`
  - New module area for mission records, interaction requests, approval records, and mission coordinator logic.

- `Tests/TheAgentControlPlaneTests/`
  - Add mission runtime, identity isolation, Telegram routing, and recovery coverage.

- `Tests/TheAgentWorkerTests/`
  - Add Attractor integration, child delegation lineage, and artifact publishing coverage.

- `Tests/OmniAgentMeshTests/`
  - Add store and transport coverage for workspace-scoped artifacts and mission-linked records.

- `docs/sprints/SPRINT-007.md`
  - New sprint document capturing this plan.

## Definition of Done

- The root agent operates as the only user-facing persona for all inbound and outbound mission interactions.
- The control plane supports durable `User`, `Workspace`, `Channel`, and `Membership` identities and enforces workspace/channel isolation in stores and routing.
- Telegram is shipped as the first working ingress and delivery transport through a transport-agnostic gateway.
- The root runtime supports mission lifecycle management, not just raw delegated tasks.
- Questions and approval requests are root-owned, durable, correlated to missions, and resumable after restart.
- Recursive delegation remains functional with lineage, depth limits, supervision, and budget enforcement.
- Workers support both direct execution and Attractor-backed structured workflows, with clear selection policy.
- `OmniAIAttractor` is integrated for `plan -> implement -> validate` style missions without becoming mandatory for every task.
- Remote artifacts can be published, discovered, and retrieved across machines for validation and judging flows.
- Restarting the control plane or a worker does not lose active mission state, pending approvals, or lineage required for recovery.
- Unit, integration, and end-to-end tests cover identity isolation, Telegram ingress, mission orchestration, Attractor execution, artifact transport, and restart recovery.
- The sprint lands as an additive evolution of Sprint 006 rather than a competing architecture.

## Risks & Mitigations

- Mission orchestration may sprawl into a second runtime beside the Sprint 006 task fabric.
  - Mitigation: treat Sprint 006 task execution as substrate and add a mission layer above it rather than replacing stores, transport, or worker wiring.

- Multi-user and shared-channel leakage could compromise trust and correctness.
  - Mitigation: enforce workspace and channel scope in storage keys, routing resolution, artifact access, and approval correlation from the foundation layer.

- Telegram-specific assumptions could contaminate the core architecture.
  - Mitigation: isolate Telegram in adapter and delivery layers and require canonical ingress event types at the mission boundary.

- Recursive delegation could create loops, runaway cost, or opaque failure trees.
  - Mitigation: persist lineage, enforce depth and budget caps, add supervisor escalation, and surface recursion state in root mission logs.

- Attractor could be overused, adding latency and complexity to simple tasks.
  - Mitigation: define explicit execution-mode selection rules and keep direct worker execution as the default for atomic work.

- Remote artifact transport may add consistency and lifecycle complexity.
  - Mitigation: separate artifact metadata from bytes, use durable references, and introduce retention and access controls before broadening artifact types.

- Recovery behavior may be incomplete across mixed root, worker, and Attractor states.
  - Mitigation: add explicit restart state machines, resumable checkpoints, dead-letter paths, and recovery-focused tests.

## Security Considerations

- Authenticate Telegram ingress and verify request provenance before accepting events.
- Treat transport-native identifiers as untrusted until resolved against internal workspace and channel bindings.
- Enforce workspace membership checks on every mission resume, approval action, artifact fetch, and outbound delivery.
- Prevent cross-workspace or cross-channel artifact disclosure through scoped `ArtifactReference` access rules.
- Ensure approval actions are attributable to a specific user identity and durable interaction record.
- Keep workers non-user-facing; only the root may communicate with humans.
- Apply least-privilege remote artifact retrieval so evaluators and validators only access artifacts referenced by their mission scope.
- Log security-relevant routing and approval events with stable identifiers for audit and recovery.
- Avoid embedding secrets in sprinted integrations; Telegram tokens and related credentials must remain externalized through deployment configuration.
- Protect against replay or duplicated ingress events with idempotency keys and durable delivery state.

## Dependencies

- Sprint 006 control-plane and worker fabric is assumed shipped and stable.
- Existing durable stores for jobs, conversations, deployments, and mesh transport remain the substrate.
- Existing HTTP/WebSocket stack is reused for ingress, artifact transport, and control-plane communication.
- `OmniAIAttractor` existing engine, handlers, checkpointing, and server path are reused for structured worker workflows.
- ACP-backed worker execution remains the underlying execution path for worker tasks.
- SQLite-first persistence remains the default storage strategy for new identity, mission, interaction, and artifact metadata.

## Open Questions

1. Should the first Telegram shipping cut support only DMs for user actions, or DMs plus shared groups/topics immediately?
2. When approvals are initiated from shared chats, should the default behavior stay in-channel or reroute to a private admin DM?
3. What should the default recursion depth, child budget, and timeout policy be for worker-managed subwork?
4. Which parts of mission state should be model-visible to the root prompt versus hidden control-plane state?
5. Should authenticated HTTP/API ingress live inside the control-plane binary first, or as a separate ingress process sharing the same canonical event contract?
6. What are the exact rules for selecting direct worker execution versus an Attractor-backed `plan -> implement -> validate` workflow?
7. How should remote artifact bytes be stored and retained for the first shipping cut: database-backed blobs, filesystem-backed handles, or pluggable storage behind the same `ArtifactReference` contract?
8. What is the minimum viable shared-workspace role model for approvals and mission visibility in Sprint 007?