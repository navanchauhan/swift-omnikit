# Sprint 011 Intent: The Agent Autonomous Delivery Runtime — Telegram-Driven Implementation, Canary Rollout, and Automatic Rollback

## Seed

Create a sprint that upgrades `TheAgent` from “can implement things through Telegram” to “can safely ship things through Telegram.” The user should be able to ask for a feature over Telegram, have the root agent plan and implement it through workers, produce a release artifact, deploy it through a controlled rollout, verify health, fall back or roll back automatically when needed, and report the result back through the root agent only.

## Context

- Sprint 006 and Sprint 007 already built the durable control plane, mission runtime, Telegram/API ingress, worker mesh, and Attractor-backed worker execution.
- The repo already contains deploy-oriented seams, but they are not yet the default mission endgame for code-change requests:
  - `ChangeCoordinator`
  - `OmniAgentDeploy/ChangePipeline`
  - `ReleaseController`
  - `Supervisor`
  - `SupervisorService`
- The current system is strong at orchestration and worker delegation, but weak at release discipline. It can build and modify code, yet deployment identity, canary progression, health gates, automatic rollback, and operator-safe rollout semantics are not yet first-class in the Telegram-facing product contract.
- The user wants the root Telegram agent to act like a real chief of staff for software delivery:
  - accept feature requests
  - route work to workers/subagents
  - ask for approval only when needed
  - ship changes safely
  - fall back or roll back automatically
  - tell the user what happened without exposing internal chaos
- Existing live operational experience in this repo shows the same general lesson:
  - workers need better generation awareness
  - stale rows/processes need better lifecycle cleanup
  - deploy/rollout outcomes need to be durable and operator-visible
  - fake success is worse than honest failure

## Recent Sprint Context

- Sprint 007 made `TheAgent` a real multi-user chief-of-staff runtime with Telegram ingress, mission coordination, and worker-side Attractor workflows.
- Sprint 008 productized the runtime with OmniSkills, channel policy, routing, supervision, and reflection.
- Sprint 010 cleaned up concurrency and reliability issues in the core runtime, transport, and worker paths.
- The current repo state proves the mesh/runtime works, but the deploy path is still not opinionated enough to be trusted as the primary way the Telegram root ships changes.

## Relevant Codebase Areas

- Root mission/runtime orchestration:
  - `Sources/TheAgentControlPlane/RootAgentRuntime.swift`
  - `Sources/TheAgentControlPlane/RootAgentToolbox.swift`
  - `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift`
  - `Sources/TheAgentControlPlane/Missions/MissionSupervisor.swift`
  - `Sources/TheAgentControlPlane/Interaction/InteractionBroker.swift`
  - `Sources/TheAgentControlPlane/NotificationInbox.swift`
- Change and deploy path:
  - `Sources/TheAgentControlPlane/Changes/ChangeCoordinator.swift`
  - `Sources/OmniAgentDeploy/ChangePipeline.swift`
  - `Sources/OmniAgentDeploy/ReleaseController.swift`
  - `Sources/OmniAgentDeploy/Supervisor.swift`
  - `Sources/TheAgentSupervisor/main.swift`
  - `Sources/TheAgentControlPlane/Supervision/SupervisorService.swift`
  - `Sources/TheAgentControlPlane/Diagnostics/DoctorService.swift`
- Worker plane and remote execution:
  - `Sources/TheAgentWorker/WorkerDaemon.swift`
  - `Sources/TheAgentWorker/WorkerExecutorFactory.swift`
  - `Sources/TheAgentWorker/Attractor/AttractorTaskExecutor.swift`
  - `Sources/TheAgentWorker/Subagents/ChildWorkerManager.swift`
  - `Sources/TheAgentControlPlane/Scheduler/RootScheduler.swift`
  - `Sources/TheAgentControlPlane/Registry/WorkerRegistry.swift`
- Telegram/API user-facing edge:
  - `Sources/TheAgentTelegram/TelegramPollingRunner.swift`
  - `Sources/TheAgentTelegram/TelegramWebhookHandler.swift`
  - `Sources/TheAgentTelegram/TelegramDeliveryFormatter.swift`
  - `Sources/TheAgentIngress/IngressGateway.swift`
- Durable stores and artifacts:
  - `Sources/OmniAgentMesh/Stores/JobStore.swift`
  - `Sources/OmniAgentMesh/Stores/ArtifactStore.swift`
  - `Sources/OmniAgentMesh/Stores/DeploymentStore.swift`
  - `Sources/OmniAgentMesh/Models/*`
- Existing docs:
  - `docs/agent-fabric-architecture.md`
  - `docs/the-agent-runtime-runbook.md`
  - `docs/sprints/SPRINT-006.md`
  - `docs/sprints/SPRINT-007.md`
  - `docs/sprints/SPRINT-008.md`

## Constraints

- Must preserve the core product contract: the user interacts only with the root agent.
- Workers and subagents may recurse internally, but they cannot become user-facing.
- Multi-user workspace and channel isolation must remain intact.
- Must work with the current mission/control-plane architecture rather than replacing it.
- Must support Telegram-first operation without making deploy semantics Telegram-specific.
- Must bias toward safe, durable release semantics:
  - immutable release records
  - canary-first promotion
  - health-gated rollout
  - automatic rollback on failure
- Must not require the user to manually supervise routine rollout failures.
- Must reuse current worker fabric and mesh rather than creating an unrelated deployment system.
- Must avoid fake success receipts; deployment and verification outcomes must be durable and inspectable.

## Success Criteria

This sprint is successful if it defines one implementable delivery sprint that makes the Telegram root agent capable of:

- treating repo-changing requests as structured change missions by default
- producing a durable release bundle for every deployable change mission
- deploying through a canary or slot-based rollout path instead of mutating production in place
- verifying rollout health using explicit health gates, not just “build succeeded”
- automatically rolling back failed canaries or unhealthy releases
- reporting clear deployment outcomes back to the root inbox / Telegram response path
- tracking host generation, drain/rejoin state, and worker liveness well enough to support remote rollouts
- preserving unrelated background work when a release is promoted or rolled back

## Verification Strategy

- Source validation:
  - inspect `ChangeCoordinator`, `ChangePipeline`, `ReleaseController`, and supervisor code for current release semantics
  - inspect mission/runtime code to ensure the sprint fits the existing root/worker orchestration shape
- Runtime validation goals:
  - feature request from Telegram becomes a change mission
  - mission produces a versioned release bundle
  - canary deployment occurs on a designated slot/host
  - health check failure triggers rollback automatically
  - successful canary promotes to active release
  - root reports `deployed`, `canary-only`, `rolled back`, or `blocked`
- Required tests:
  - unit tests for release bundle creation, slot selection, health policy, and rollback decisions
  - integration tests for mission -> change pipeline -> release controller -> supervisor path
  - recovery tests for stale worker generations, partial rollout failure, and supervisor restart
  - Telegram-facing tests for approval and final deploy-result messaging
- Live-proof goals:
  - at least one remote worker-backed change mission that produces a release artifact and canary result
  - one intentional failed health-check path that rolls back automatically and reports the rollback clearly

## Uncertainty Assessment

- Correctness uncertainty: Medium
  - the rollout mechanics are well understood, but they must be fitted onto the existing control-plane/worker model without regressing the current Telegram runtime contract
- Scope uncertainty: High
  - this touches missions, workers, durable state, deploy artifacts, host operations, health verification, and user messaging
- Architecture uncertainty: Medium to High
  - the main question is how much of the deploy lifecycle should remain inside `MissionCoordinator` versus being pushed into a more explicit release/runtime subsystem

## Open Questions

1. Should every repo-changing mission always produce a release bundle, or only missions targeting declared deployable repos/services?
2. What is the minimal v1 release artifact: git SHA + bundle + health plan, or a richer manifest with migration/traffic metadata?
3. Should canary/slot promotion operate on filesystem release directories, git worktrees, service units, container images, or support multiple drivers from the start?
4. How should the root choose deployment targets for a workspace/repo: explicit mission config, skill policy, or host inventory rules?
5. What should happen when canary health is inconclusive rather than clearly healthy or clearly failed?
6. How aggressively should stale worker generations be drained or ignored once a newer rollout generation is active?
7. Which deploy operations always require approval, and which can be auto-approved under workspace policy?
