# Sprint 007 Intent: The Agent Product Runtime

## Seed

Build one comprehensive sprint that turns `TheAgent` into the only thing the user interacts with: a chief-of-staff root agent that can accept work over text/chat/API, recursively delegate to worker agents and subagents, ask for permissions/questions only when needed, and report results when done. The first user-facing transport should be Telegram. The design must support multiple users and shared workspaces from the start. It should also fit `OmniAIAttractor` into the architecture, especially for structured `plan -> implement -> validate` execution, without making Attractor the universal runtime for every task.

The sprint must reflect the repo’s actual current state and build on Sprint 006 rather than pretending the required substrate does not exist.

## Context

- Sprint 006 already added the root/worker fabric: durable job/conversation/deployment stores, HTTP mesh transport, remote worker registration, ACP-backed worker execution, and a live root `Session` hosted by the control plane.
- The current root runtime is still task-oriented, not mission-oriented. The root exposes raw tools like `delegate_task`, `list_workers`, `wait_for_task`, and notification helpers instead of a higher-level chief-of-staff mission contract.
- `OmniAIAttractor` is already a serious workflow engine in this repo: it has a `PipelineEngine`, retry/checkpointing, manager loops, evaluator-style handlers, human gates, and a CLI/server path.
- There is currently no Telegram ingress, no general ingress gateway, and no multi-user or workspace-scoped identity model in the control plane or durable stores.
- Artifact transport is still incomplete for a real remote mission system: task and worker transport exist over HTTP mesh, but remote artifact access is still worker-local and limits remote review/scenario/judge credibility.

## Recent Sprint Context

- `docs/sprints/SPRINT-006.md` established the canonical mega-sprint for the root/worker fabric and positioned `OmniAIAttractor` as the workflow/evaluation engine rather than the mesh protocol.
- Commit `6c1bf58` (`Implement Sprint 006 control plane and worker fabric`) shipped the current control plane, remote worker path, ACP worker execution wiring, and root orchestrator loop.
- The repo now has working proof points for same-host and cross-machine worker assignment, plus a root session that can manage delegated tasks, but the product still lacks ingress, multi-user partitioning, and mission-level orchestration.

## Relevant Codebase Areas

- `Sources/TheAgentControlPlane/RootAgentRuntime.swift`
- `Sources/TheAgentControlPlane/RootAgentServer.swift`
- `Sources/TheAgentControlPlane/RootAgentToolbox.swift`
- `Sources/TheAgentControlPlane/RootOrchestratorProfile.swift`
- `Sources/TheAgentControlPlane/Changes/ChangeCoordinator.swift`
- `Sources/TheAgentControlPlane/Scheduler/RootScheduler.swift`
- `Sources/TheAgentWorker/WorkerDaemon.swift`
- `Sources/TheAgentWorker/WorkerExecutorFactory.swift`
- `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift`
- `Sources/OmniAgentMesh/Models/TaskRecord.swift`
- `Sources/OmniAgentMesh/Stores/ConversationStore.swift`
- `Sources/OmniAgentMesh/Stores/JobStore.swift`
- `Sources/OmniAgentMesh/Stores/ArtifactStore.swift`
- `Sources/OmniAgentMesh/Transport/HTTPMeshServer.swift`
- `Sources/OmniAgentMesh/Transport/HTTPMeshClient.swift`
- `Sources/OmniAIAttractor/Engine/PipelineEngine.swift`
- `Sources/OmniAIAttractor/Handlers/ManagerLoopHandler.swift`
- `Sources/OmniAIAttractor/Handlers/WaitHumanHandler.swift`
- `Sources/OmniAIAttractor/Server/HTTPServer.swift`
- `docs/agent-fabric-architecture.md`

## Constraints

- Must follow project conventions from `AGENTS.md`, including Swift 6 strict concurrency, reuse of existing repo HTTP/WebSocket stack, SQLite-first persistence, and repo-owned integrations instead of new third-party frameworks.
- Must preserve the root agent as the only user-facing persona.
- Must support multiple users and shared workspaces from the foundation layer, not as an afterthought.
- Must integrate Telegram as the first ingress without baking Telegram-specific logic into the mission/control-plane core.
- Must fit `OmniAIAttractor` into the system, but should not turn every tiny worker task into an Attractor workflow if a simpler task path is better.
- Must preserve recursive delegation while adding bounded supervision, depth limits, and durable lineage.
- Must address root-owned approvals/questions and remote artifact access as first-class design problems.

## Success Criteria

The sprint is successful if it defines a coherent, buildable architecture and phased implementation plan that:

- turns the root agent into a mission-level chief-of-staff runtime;
- introduces multi-user/workspace/channel identity and isolation;
- ships Telegram as the first real user-facing ingress;
- routes all human questions and approval requests through the root;
- uses Attractor as a worker-side structured mission engine for `plan -> implement -> validate`;
- supports recursive worker/subagent delegation with policy and supervision;
- closes the remote artifact visibility gap required for remote validation and judging;
- defines concrete files, phases, tests, risks, and definition-of-done criteria that match this repo.

## Verification Strategy

- Reference implementation: validate against the existing Sprint 006 control-plane/worker design and current source layout rather than inventing a second architecture.
- Spec/documentation: align the sprint with `docs/agent-fabric-architecture.md`, the current `SPRINT-006.md`, and official Telegram Bot API expectations for transport shape.
- Edge cases identified:
  - multi-user/workspace leakage
  - shared Telegram group/topic routing
  - root-owned approvals in shared chats
  - recursive delegation loops
  - remote artifact visibility for evaluator/judge flows
  - restart/recovery of active missions and deliveries
- Testing approach:
  - store/unit tests for identity, workspace isolation, mission state, approvals, and artifact transport
  - integration tests for Telegram ingress normalization and routing
  - root control-plane tests for mission orchestration and interaction brokering
  - worker tests for Attractor-backed execution and child workflow lineage
  - end-to-end proof across local and remote workers with Telegram ingress

## Uncertainty Assessment

- Correctness uncertainty: Medium — the repo has the main substrate already, but Telegram ingress, workspace isolation, and artifact transport still need architectural judgment.
- Scope uncertainty: High — this is a productization sprint spanning ingress, identity, missions, worker execution, and observability.
- Architecture uncertainty: Medium — the likely structure is clear, but the exact boundary between mission coordinator, interaction broker, and Attractor execution still benefits from independent drafts and critique.

## Open Questions

1. Should Telegram shared-chat approvals stay in-channel, or reroute to a private admin DM by default?
2. Should the first shipping cut support Telegram DMs only, or DMs plus shared groups/topics immediately?
3. What should be the default recursion depth and budget for worker-managed child workflows?
4. How much of the root mission state should be model-visible versus hidden control-plane state?
5. Should the minimal authenticated HTTP/API ingress live in the control-plane binary or in a separate ingress target/process?
6. What is the cleanest way to fit Attractor into worker execution without overusing it for atomic tasks?
