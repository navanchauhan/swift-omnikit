# SPRINT-011: The Agent Autonomous Delivery Runtime — Telegram-Driven Change Missions, Release Bundles, Canary Rollout, and Automatic Rollback

## Overview

Sprint 007 made `TheAgent` a real root/worker runtime with Telegram ingress, mission orchestration, multi-user scope, and remote worker execution. Sprint 008 productized that runtime with skills, channel policy, supervision, and diagnostics. The current gap is delivery.

Today, the system can plan and implement work, and it already contains early deploy seams in `ChangeCoordinator`, `ChangePipeline`, `ReleaseController`, `Supervisor`, and `SupervisorService`. But those seams are still too optimistic and too local. The system can build and mutate code, but it does not yet treat deployment identity, canary rollout, health gating, automatic rollback, and deploy-result reporting as first-class mission outcomes.

Sprint 011 turns the root Telegram agent into a real software-delivery chief of staff:

- a Telegram feature request becomes a structured change mission by default
- successful implementation produces a durable release bundle
- rollout happens through a canary or slot-based path, not in-place mutation
- health gates decide promotion or rollback
- rollback is automatic for routine failures
- the root reports one clear outcome back to the user

The product contract does not change:

- the user talks only to the root agent
- workers and subagents stay internal
- approvals and questions remain root-owned
- unrelated background work must survive rollout and rollback

## Implementation Status

**Status:** repo-side implementation complete, live rollout proof still pending

Implemented in this sprint execution:

- repo-changing code missions now reconcile through a deploy-aware delivery path in `MissionCoordinator`
- immutable release bundles, slot/canary rollout state, release controller, supervisor, and deploy health logic now live in a shared `OmniAgentDeliveryCore` target
- deployable change missions now produce durable release/deployment metadata and expose that state through root mission serialization
- generation-aware worker selection and draining behavior are covered by focused scheduler/registry tests
- concise delivery metadata is available to the root/Telegram-facing layer

Validated in this execution:

- `swift build --product TheAgentControlPlane --product OmniAgentDeployCLI --product TheAgentSupervisor`
- `swift test --filter 'MissionCoordinatorTests|ChangePipelineTests|RollbackScenarioTests|AgentFabricScenarioTests|RootOrchestratorTests|DeployHealthServiceTests|SlotControllerTests|ReleaseBundleTests|WorkerGenerationTests'`

Still outstanding:

- a true operator-driven live canary/promotion proof and a live failed-canary/rollback proof outside the test harness
- runbook/architecture doc pass for the new delivery-core split and rollout flow

## Why This Sprint Exists

The repo already has the right foundation, but not the right guarantees:

- `ChangePipeline` already chains implementation, review, scenario evaluation, release preparation, and canary deployment
- `ReleaseController` can prepare a release, attempt a canary, and roll back to the previous active release
- `Supervisor` can install, activate, and roll back releases
- `SupervisorService` already reconciles stalled runtime state

What is missing is the system around those seams:

- immutable release identity and artifact lineage
- a real slot/canary deployment model
- health verification richer than a single optimistic boolean
- generation-aware worker draining and rejoin behavior
- deploy results that become first-class mission state and user-facing outcomes
- default routing of repo-changing asks into the delivery path instead of ad hoc code-change execution

## Use Cases

1. A user asks over Telegram: “add X to the service and ship it”
   The root starts a change mission, obtains approval if policy requires it, delegates implementation, and drives the release path to a final outcome.

2. A worker-backed implementation succeeds, but the canary health check fails
   The system rolls back automatically, records the rollback target and reason, and sends a concise Telegram result instead of waiting for a human to notice.

3. A canary passes
   The release is promoted, the previous generation is drained gracefully, and the user receives a final deployed result with release and mission identifiers.

4. A rollout stalls because a host or worker generation is stale
   The control plane detects that the target generation is wrong, suppresses false success, drains the stale generation, and retries or fails honestly.

5. A non-deployable code-change request lands in the same Telegram root
   The mission remains a change mission, but exits at `artifact_only` or `blocked_for_targeting` instead of pretending every repo change is a production rollout.

6. Other missions are running at the same time
   A rollout should not erase unrelated background work, task history, or worker ownership.

## Architecture

### Product Shape

Sprint 011 keeps the current topology:

- Telegram / HTTP ingress
- root `OmniAIAgent.Session`
- `MissionCoordinator`
- worker fabric and mesh
- root-owned approvals/questions

It adds a proper delivery layer on top:

1. **Change Mission Policy**
   Root repo-changing asks default to a structured delivery mission instead of a raw worker task.

2. **Release Bundle Layer**
   Every deployable mission produces an immutable release bundle and release record before rollout begins.

3. **Deployment Driver Layer**
   Rollout is driven through slot/canary semantics instead of mutating the active runtime in place.

4. **Health Gate Layer**
   Promotion depends on explicit health evaluation, not just “build finished”.

5. **Generation Control Layer**
   Worker and host generations become durable rollout state so stale workers do not silently keep serving or claiming tasks after promotion.

6. **Outcome Reporting Layer**
   Deploy results become root-owned mission artifacts and Telegram-facing summaries such as:
   - `deployed`
   - `canary_only`
   - `rolled_back`
   - `blocked`
   - `artifact_only`

### Release Bundle Model

Add an immutable release bundle model that is produced by the change pipeline before any rollout step:

- `release_id`
- source repo / target service
- git commit or worktree snapshot identifier
- artifact refs and hashes
- version string
- migration/checkpoint info
- health plan
- rollback target eligibility
- creation metadata

This is not a mutable “current release” blob. It is the durable record of what the mission is trying to ship.

### Slot / Canary Deployment Model

Replace optimistic activate-in-place semantics with explicit deployment slots:

- `prepared`
- `canary`
- `live`
- `failed`
- `rolled_back`

V1 should support a simple slot model:

- `active`
- `next`
- optional `canary`

Promotion is a slot transition. Rollback is a slot transition. This is what makes fallback and rollover operationally cheap.

### Health Gates

Health verification should be a policy-driven service, not an ad hoc closure.

Health inputs should include:

- process/service liveness
- worker heartbeats
- task backlog sanity
- service-specific smoke checks
- optional doctor probes
- timeout windows for warmup vs steady state

Health outputs should be explicit:

- `healthy`
- `unhealthy`
- `inconclusive`

`inconclusive` must not promote automatically.

### Generation Awareness

Deploys need generation-aware runtime coordination:

- worker registration includes a rollout generation
- target workers for the new release join the new generation
- previous-generation workers are drained after promotion
- stale generations are ignored or evicted during rollback/recovery

This lets the system roll forward or back without confusing the scheduler or leaving zombie workers in the registry.

### Telegram Reporting

Telegram should remain boring and clean:

- one approval prompt when needed
- one “canary failed, rolled back” message if relevant
- one final deployed / blocked / rolled-back summary

The root should report exact ids when useful:

- `mission_id`
- `release_id`
- `rollback_release_id`
- `canary_target`

But it should not dump deploy internals into chat unless the user asks.

## Implementation Phases

### Phase 1: Route Repo Changes Into the Delivery Path

**Goals**

- make structured change missions the default path for deployable repo changes
- preserve non-deployable and artifact-only change behavior

**Files**

- `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift`
- `Sources/TheAgentControlPlane/RootAgentRuntime.swift`
- `Sources/TheAgentControlPlane/RootAgentToolbox.swift`
- `Sources/TheAgentControlPlane/Changes/ChangeCoordinator.swift`
- `Sources/TheAgentControlPlane/Policy/WorkspacePolicy.swift`
- `Tests/TheAgentControlPlaneTests/MissionCoordinatorTests.swift`
- `Tests/TheAgentControlPlaneTests/RootOrchestratorTests.swift`

**Tasks**

- Add explicit delivery mission selection rules for repo-changing requests.
- Distinguish:
  - `artifact_only`
  - `deployable`
  - `blocked_for_targeting`
- Add mission-level policy for:
  - deploy approval requirements
  - target environment selection
  - auto-rollout eligibility
- Make root tooling expose deploy-aware mission results instead of only raw task completion.

**Acceptance Criteria**

- Root repo-changing asks default to a structured delivery mission.
- Non-deployable code changes do not pretend to be deployable.
- Mission snapshots expose delivery state cleanly.

### Phase 2: Immutable Release Bundles and Durable Deployment Records

**Goals**

- introduce a first-class release bundle model
- make deployment identity durable and inspectable

**Files**

- `Sources/OmniAgentDeliveryCore/ReleaseBundle.swift` (new)
- `Sources/OmniAgentDeliveryCore/ReleaseBundleStore.swift` (new)
- `Sources/OmniAgentDeliveryCore/ReleaseController.swift`
- `Sources/OmniAgentDeploy/ChangePipeline.swift`
- `Sources/OmniAgentMesh/Models/DeploymentRecord.swift`
- `Sources/OmniAgentMesh/Stores/DeploymentStore.swift`
- `Tests/OmniAgentDeployTests/ReleaseBundleTests.swift` (new)
- `Tests/OmniAgentDeployTests/ReleaseControllerTests.swift`

**Tasks**

- Define immutable release-bundle metadata.
- Persist bundle refs and hashes alongside deployment records.
- Update `ChangePipeline` so successful implementation/review/scenario stages produce a release bundle before rollout.
- Record rollout intent, canary target, and rollback target in durable deployment state.

**Acceptance Criteria**

- Every deployable mission produces a release bundle before canary rollout.
- Deployment state can answer “what exactly was deployed” after restart.
- Rollback targets are durable, not inferred from memory.

### Phase 3: Slot / Canary Deployment Driver

**Goals**

- replace optimistic release activation with a real slot/canary rollout path

**Files**

- `Sources/OmniAgentDeliveryCore/DeploymentDriver.swift` (new)
- `Sources/OmniAgentDeliveryCore/SlotController.swift` (new)
- `Sources/OmniAgentDeliveryCore/ReleaseController.swift`
- `Sources/OmniAgentDeliveryCore/Supervisor.swift`
- `Sources/TheAgentSupervisor/main.swift`
- `Tests/OmniAgentDeployTests/SlotControllerTests.swift` (new)
- `Tests/OmniAgentDeployTests/ChangePipelineTests.swift`

**Tasks**

- Define a deployment-driver abstraction for filesystem/service-slot rollout.
- Introduce explicit slot states:
  - `prepared`
  - `canary`
  - `live`
  - `failed`
  - `rolled_back`
- Implement canary-first activation.
- Make promotion and rollback explicit transitions, not “just activate another release”.

**Acceptance Criteria**

- Release activation happens through a slot/canary driver.
- Rollback is a first-class operation with durable state transitions.
- The deploy path can promote or roll back without erasing unrelated background tasks.

### Phase 4: Health Verification and Automatic Rollback

**Goals**

- make health checks authoritative for promotion
- automate rollback on routine rollout failure

**Files**

- `Sources/OmniAgentDeliveryCore/DeployHealthService.swift` (new)
- `Sources/TheAgentControlPlane/Diagnostics/DoctorService.swift`
- `Sources/TheAgentControlPlane/Supervision/SupervisorService.swift`
- `Sources/OmniAgentDeliveryCore/ReleaseController.swift`
- `Tests/TheAgentControlPlaneTests/DeployHealthServiceTests.swift` (new)
- `Tests/OmniAgentDeployTests/RollbackScenarioTests.swift` (new)

**Tasks**

- Add structured health outcomes: `healthy`, `unhealthy`, `inconclusive`.
- Separate warmup timeout from steady-state timeout.
- Trigger automatic rollback on `unhealthy`.
- Treat `inconclusive` as no-promotion and explicit failure unless policy says otherwise.
- Emit durable deploy and rollback events for root reporting.

**Acceptance Criteria**

- Failed canary health checks roll back automatically.
- Inconclusive health does not silently promote.
- Rollback outcomes are visible through mission and deployment records.

### Phase 5: Worker Generation, Drain, and Host Inventory

**Goals**

- make rollout-aware worker lifecycle management real

**Files**

- `Sources/TheAgentControlPlane/Registry/WorkerRegistry.swift`
- `Sources/TheAgentControlPlane/Scheduler/RootScheduler.swift`
- `Sources/TheAgentWorker/WorkerDaemon.swift`
- `Sources/TheAgentWorker/WorkerCapabilities.swift`
- `Sources/OmniAgentMesh/Models/WorkerRecord.swift`
- `Sources/TheAgentControlPlane/Supervision/ActivityHeartbeat.swift`
- `Tests/TheAgentControlPlaneTests/WorkerGenerationTests.swift` (new)
- `Tests/TheAgentWorkerTests/WorkerDaemonTests.swift`

**Tasks**

- Add rollout generation metadata to worker registration.
- Support drain / draining / drained lifecycle states.
- Prevent stale-generation workers from being preferred after promotion.
- Reconcile dead or abandoned generations during supervisor sweeps.

**Acceptance Criteria**

- Fresh rollout generations can join without confusing the scheduler.
- Old generations can be drained after promotion or rollback.
- Registry/scheduler state stays coherent across restart and reconnect.

### Phase 6: Telegram-Facing Delivery UX

**Goals**

- make deploy outcomes clean and useful in Telegram

**Files**

- `Sources/TheAgentControlPlane/Interaction/InteractionBroker.swift`
- `Sources/TheAgentControlPlane/Interaction/ApprovalBroker.swift`
- `Sources/TheAgentControlPlane/NotificationInbox.swift`
- `Sources/TheAgentTelegram/TelegramDeliveryFormatter.swift`
- `Sources/TheAgentControlPlane/RootAgentToolbox.swift`
- `Tests/TheAgentIngressTests/TelegramIngressTests.swift`
- `Tests/TheAgentControlPlaneTests/RootOrchestratorTests.swift`

**Tasks**

- Define root-facing delivery result summaries.
- Route deploy approvals through the existing approval broker.
- Add compact Telegram summaries for deploy outcomes.
- Keep deploy verbosity low by default while preserving exact ids.

**Acceptance Criteria**

- Telegram users get one concise deploy outcome instead of internal pipeline noise.
- Approval requests remain explicit and root-owned.
- Deploy result messages render cleanly with current Telegram formatting rules.

### Phase 7: Live Proof and Recovery Hardening

**Goals**

- prove the path on real remote workers
- close the fake-success / stale-generation class of rollout bugs

**Files**

- `Tests/TheAgentControlPlaneTests/ChangeMissionLiveParityTests.swift` (new)
- `Tests/OmniAgentDeployTests/CanaryRollbackE2ETests.swift` (new)
- `docs/the-agent-runtime-runbook.md`
- `docs/agent-fabric-architecture.md`

**Tasks**

- Run one live remote worker-backed deployable change mission that produces a release bundle.
- Run one intentional failed health-check path that rolls back automatically.
- Record operator runbook steps for rollout, rollback, and stale-generation cleanup.

**Acceptance Criteria**

- Live proof shows:
  - release bundle created
  - canary attempted
  - promotion or rollback recorded durably
  - root reports the final result cleanly
- No fake success receipts remain in the delivery path.

## Files Summary

### Modify

- `Package.swift`
- `Sources/OmniAgentDeliveryCore/DeployHealthService.swift`
- `Sources/OmniAgentDeliveryCore/DeploymentDriver.swift`
- `Sources/OmniAgentDeliveryCore/ReleaseBundle.swift`
- `Sources/OmniAgentDeliveryCore/ReleaseBundleStore.swift`
- `Sources/OmniAgentDeliveryCore/ReleaseController.swift`
- `Sources/OmniAgentDeliveryCore/SlotController.swift`
- `Sources/OmniAgentDeliveryCore/Supervisor.swift`
- `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift`
- `Sources/TheAgentControlPlane/RootAgentRuntime.swift`
- `Sources/TheAgentControlPlane/RootAgentToolbox.swift`
- `Sources/TheAgentControlPlane/Changes/ChangeCoordinator.swift`
- `Sources/TheAgentControlPlane/Interaction/InteractionBroker.swift`
- `Sources/TheAgentControlPlane/Interaction/ApprovalBroker.swift`
- `Sources/TheAgentControlPlane/NotificationInbox.swift`
- `Sources/TheAgentControlPlane/Diagnostics/DoctorService.swift`
- `Sources/TheAgentControlPlane/Supervision/SupervisorService.swift`
- `Sources/TheAgentControlPlane/Registry/WorkerRegistry.swift`
- `Sources/TheAgentControlPlane/Scheduler/RootScheduler.swift`
- `Sources/TheAgentTelegram/TelegramDeliveryFormatter.swift`
- `Sources/TheAgentWorker/WorkerDaemon.swift`
- `Sources/TheAgentWorker/WorkerCapabilities.swift`
- `Sources/OmniAgentDeploy/ChangePipeline.swift`
- `Sources/TheAgentSupervisor/main.swift`
- `Sources/OmniAgentMesh/Models/DeploymentRecord.swift`
- `Sources/OmniAgentMesh/Stores/DeploymentStore.swift`
- `docs/the-agent-runtime-runbook.md`
- `docs/agent-fabric-architecture.md`

### Create

- `Tests/OmniAgentDeployTests/ReleaseBundleTests.swift`
- `Tests/OmniAgentDeployTests/SlotControllerTests.swift`
- `Tests/OmniAgentDeployTests/RollbackScenarioTests.swift`
- `Tests/TheAgentControlPlaneTests/DeployHealthServiceTests.swift`
- `Tests/TheAgentControlPlaneTests/WorkerGenerationTests.swift`
- `Tests/TheAgentControlPlaneTests/ChangeMissionLiveParityTests.swift`
- `Tests/OmniAgentDeployTests/CanaryRollbackE2ETests.swift`

## Definition of Done

- [x] Repo-changing Telegram requests default to structured change missions with delivery semantics.
- [x] Deployable change missions produce immutable release bundles and durable deployment records.
- [x] Rollout uses a canary or slot-based deployment path instead of mutating active state in place.
- [x] Promotion depends on explicit health gates, not just build success.
- [x] Unhealthy canaries roll back automatically and durably record the rollback target and reason.
- [x] Worker/host generations are tracked well enough to drain stale rollout generations safely.
- [x] Telegram receives concise, root-owned deploy results with exact ids when useful.
- [ ] Live proof demonstrates one successful canary/promotion path and one failed canary/rollback path.
- [x] Unrelated background tasks remain intact across promotion and rollback.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Sprint scope balloons into a generic platform rewrite | High | High | Keep v1 focused on release bundles, canary slots, health gates, rollback, and reporting |
| Deploy driver abstraction becomes too generic too early | Medium | High | Start with one concrete filesystem/service-slot driver and only abstract what the repo uses |
| Scheduler and worker registry drift during rollout | Medium | High | Add generation metadata, drain states, and supervisor reconciliation before live rollout proof |
| Health checks are too weak or too noisy | High | High | Separate warmup vs steady-state checks and support `inconclusive` as a first-class outcome |
| Telegram UX becomes noisy and operationally unreadable | Medium | Medium | Keep deploy reporting summarized at the root and expose detail only on request |
| Rollback mutates unrelated mission/task state | Medium | High | Keep release state separate from general task ownership and treat rollback as a release transition only |

## Security

- Release and deploy operations must respect workspace policy and approval rules.
- Deployment artifacts and error logs must not leak secrets or raw internal traces into Telegram.
- Multi-user workspace isolation must remain intact across change missions, rollout state, and deploy notifications.
- Rollout drivers must use explicit target selection rather than ambient shell state.

## Dependencies

- Sprint 007 control-plane runtime and Telegram/API ingress
- Sprint 008 supervision, routing, skills, and product-runtime hardening
- Sprint 010 concurrency and transport cleanup
- existing `ChangeCoordinator`, `ChangePipeline`, `ReleaseController`, `Supervisor`, and `SupervisorService` seams

## Open Questions

1. Should every repo-changing mission always emit a release bundle, or only repos explicitly marked deployable?
2. What is the minimal v1 release artifact schema?
3. Should the first deployment driver target filesystem release directories, service units, or both?
4. How should deployment targets be resolved for a workspace or repo?
5. What exact policy should `inconclusive` health map to in v1?
6. Which deploy operations require explicit approval, and which can be auto-approved under workspace policy?
