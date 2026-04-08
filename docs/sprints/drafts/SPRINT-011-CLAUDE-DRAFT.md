# SPRINT-011: The Agent Autonomous Delivery Runtime — Telegram-Driven Implementation, Canary Rollout, and Automatic Rollback

## Overview

Sprint 006 built the durable root/worker mesh. Sprint 007 made `TheAgent` a multi-user chief-of-staff runtime with Telegram ingress and mission orchestration. Sprint 008 added OmniSkills, channel policy, supervision, and reflection. Sprint 010 hardened concurrency and isolation. Sprint 011 closes the loop between "the root can implement things" and "the root can ship things safely."

The repo already contains the mechanical seams for deployment: `ChangeCoordinator` manages implementation/review/scenario task lifecycle, `ChangePipeline` orchestrates the full change flow, `ReleaseController` handles canary deployment with retry and rollback, `Supervisor` manages local release installation and health checks, and `DeploymentStore` persists immutable release records. What is missing is the opinionated wiring that makes this the default path for every repo-changing mission requested through Telegram, and the operational discipline that makes the result trustworthy: versioned release bundles, health-gated canary promotion, generation-aware worker drain, automatic rollback on failure, and clear deploy-outcome reporting back through the root inbox.

This sprint must not invent a parallel deployment system. It must make the existing `MissionCoordinator -> ChangeCoordinator -> ChangePipeline -> ReleaseController -> Supervisor` path the default endgame for code-change missions, and harden every stage so the user can trust it as the primary way TheAgent ships changes.

The product contract does not change:

- the user interacts only with the root agent
- the root owns approvals, questions, and final replies
- workers and subagents may recurse internally but never become user-facing
- all deployment state must be durable and inspectable

## Use Cases

1. **Feature request to deployed release**: A user asks for a feature over Telegram. The root plans, delegates implementation to a worker, collects review and scenario results, produces a versioned release bundle, deploys it through a canary slot, verifies health, promotes or rolls back, and reports the final outcome — all without the user managing any of the intermediate steps.

2. **Automatic rollback on health failure**: A canary deployment fails its health gate. The system automatically rolls back to the previous active release, preserves all unrelated running tasks and missions, and reports the rollback reason and release ID to the user through Telegram.

3. **Canary-only hold for uncertain health**: Health checks return inconclusive results. The canary remains deployed but is not promoted. The root reports the canary-only state and asks the user whether to promote, extend observation, or roll back.

4. **Approval-gated production promotion**: Workspace policy requires explicit user approval before canary promotion to production. The root sends an approval request through Telegram with the release summary, health status, and diff stats. The user approves or rejects through an inline button.

5. **Multi-service workspace deployments**: A workspace manages multiple deployable services. The root resolves which service a change targets using mission metadata and workspace inventory, then deploys to the correct release slot without affecting other services.

6. **Worker generation drain and rejoin**: A new release is being deployed. Workers running tasks from the old generation are drained gracefully — existing tasks complete, but no new tasks are claimed from the old generation. Once drain completes, the old generation's workers rejoin the pool under the new release.

7. **Stale generation cleanup**: A worker from a previous generation fails to drain within the timeout. The supervisor marks it as stale, reschedules its incomplete tasks on healthy workers, and reports the stale worker to the root inbox.

8. **Deploy outcome inspection**: The user asks the root for deployment status. The root returns a structured report from the durable deployment store: release ID, version, deploy state, health check results, canary duration, promotion or rollback timestamp, and any associated mission artifacts.

## Architecture

### Delivery Lifecycle

The delivery lifecycle extends the existing mission flow with explicit release and deployment stages:

```text
Telegram feature request
         |
         v
   IngressGateway
   (normalize + route)
         |
         v
   MissionCoordinator
   (detect repo-changing intent)
         |
         v
   ChangeCoordinator.startChange()
   (create root change task)
         |
         v
   ChangePipeline.run()
   ├─→ enqueueImplementation()
   │   └─→ WorkerDaemon executes via ACP/Attractor
   ├─→ enqueueReview() + enqueueScenarioEvaluation()
   │   └─→ parallel worker tasks
   ├─→ ReleaseController.prepareRelease()
   │   └─→ immutable DeploymentRecord (state: .prepared)
   ├─→ [optional] approval gate
   │   └─→ InteractionBroker → Telegram inline button
   ├─→ ReleaseController.deployCanary()
   │   ├─→ Supervisor.drain(previousGeneration)
   │   ├─→ Supervisor.install(candidate)
   │   ├─→ Supervisor.activate()
   │   ├─→ HealthGate.evaluate()
   │   │   ├─→ healthy: promote to .live
   │   │   ├─→ unhealthy: rollback to previous
   │   │   └─→ inconclusive: hold at .canary, ask user
   │   └─→ [on failure] Supervisor.rollback()
   └─→ ChangeCoordinator.completeChange() or failChange()
         |
         v
   Root inbox notification
   (deployed / canary-only / rolled back / blocked)
         |
         v
   Telegram delivery
```

### Release Bundle

A release bundle is an immutable, versioned artifact that captures everything needed to deploy and verify a change:

- **releaseID**: UUID, globally unique
- **version**: monotonically increasing per workspace/service
- **gitSHA**: commit hash of the change
- **buildArtifactRefs**: references to compiled outputs in the artifact store
- **healthPlan**: structured health check specification (endpoints, thresholds, timeout, retry count)
- **missionID**: originating mission for traceability
- **changeID**: originating change task ID
- **metadata**: diff stats, affected files, test results summary
- **previousReleaseID**: pointer to the release this replaces (for rollback)

The bundle is persisted as a `DeploymentRecord` in the deployment store and its binary artifacts are stored in the artifact store under the release directory.

### Deployment State Machine

```text
.prepared ──→ .approved ──→ .draining ──→ .installing ──→ .canary
                                                            │
                                          ┌────────────────┤
                                          │                 │
                                          v                 v
                                       .live           .rollingBack ──→ .rolledBack
                                                            │
                                                            v
                                                         .failed
```

New states beyond the current implementation:

- `.approved`: explicit approval received (when policy requires it)
- `.installing`: release is being written to the target but not yet activated
- `.canary`: release is active on the canary slot, health observation in progress
- `.rollingBack`: previous release is being restored
- `.rolledBack`: rollback completed successfully

### Health Gate

The health gate replaces the current boolean `checkHealth()` with a structured evaluation:

```swift
public struct HealthGateResult: Codable, Sendable {
    public enum Verdict: String, Codable, Sendable {
        case healthy
        case unhealthy
        case inconclusive
    }
    public let verdict: Verdict
    public let checks: [HealthCheckResult]
    public let observationDuration: TimeInterval
    public let timestamp: Date
}
```

Health checks are pluggable and composable:

- **ProcessHealthCheck**: target process is running and responsive
- **EndpointHealthCheck**: HTTP endpoint returns expected status code within latency threshold
- **LogHealthCheck**: error rate in recent logs does not exceed threshold
- **CustomHealthCheck**: user-provided shell command exits 0

The health gate runs checks on a schedule during the canary observation window. It requires a minimum observation duration before declaring healthy, and a configurable failure threshold before declaring unhealthy.

### Worker Generation Model

Each deployment creates a new **generation**. Workers are tagged with the generation they belong to. The generation model enables safe rollout without dropping unrelated work:

- **Active generation**: the generation currently accepting new work
- **Draining generation**: the previous generation; existing tasks run to completion, no new claims
- **Stale generation**: a draining generation that exceeded its drain timeout

The `WorkerRegistry` tracks generation assignments. The `RootScheduler` uses generation when placing tasks: only workers in the active generation receive new task claims. The `SupervisorService` sweeps for stale generations and reschedules orphaned tasks.

### Deploy Policy

Deploy policy is workspace-scoped and determines:

- whether repo-changing missions automatically produce release bundles
- whether canary promotion requires explicit approval
- minimum canary observation duration
- maximum rollout attempts before escalation
- which health checks are required
- drain timeout for old generations
- whether inconclusive health results hold or fail

Default policy: auto-bundle, approval-required for promotion, 60-second minimum observation, 3 max attempts, process health check required, 120-second drain timeout, inconclusive holds.

## Implementation

### Phase 1: Release Bundle Model and Deployment State Machine

**Goals**
- extend `DeploymentRecord` with full release bundle metadata
- add the complete deployment state machine
- add deploy policy as a workspace-scoped configuration
- make release records fully immutable after creation

**Files**
- `Sources/OmniAgentMesh/Models/DeploymentRecord.swift`
- `Sources/OmniAgentMesh/Models/DeploymentState.swift`
- `Sources/OmniAgentMesh/Models/ReleaseBundleManifest.swift`
- `Sources/OmniAgentMesh/Stores/DeploymentStore.swift`
- `Sources/TheAgentControlPlane/Policy/DeployPolicy.swift`
- `Sources/TheAgentControlPlane/Policy/WorkspacePolicy.swift`
- `Tests/OmniAgentMeshTests/DeploymentRecordTests.swift`
- `Tests/OmniAgentMeshTests/DeploymentStoreTests.swift`

**Tasks**
- [ ] Extend `DeploymentRecord` with gitSHA, buildArtifactRefs, healthPlan, missionID, changeID, previousReleaseID, diffStats, and version metadata.
- [ ] Add `DeploymentState` enum with the full state machine: `.prepared`, `.approved`, `.draining`, `.installing`, `.canary`, `.live`, `.rollingBack`, `.rolledBack`, `.failed`.
- [ ] Add `ReleaseBundleManifest` as the structured, Codable specification for a release bundle that is written to the artifact store alongside binary outputs.
- [ ] Add `DeployPolicy` with workspace-scoped configuration: auto-bundle, approval-required, observation duration, max attempts, required health checks, drain timeout, inconclusive behavior.
- [ ] Extend `DeploymentStore` to support state transition logging with timestamps and reason codes, and to enforce immutability of release metadata after initial write.
- [ ] Add version monotonicity enforcement per workspace/service in the deployment store.
- [ ] Add migration for existing `DeploymentStore` schema to support new columns without losing existing release records.
- [ ] Add unit tests for state machine transitions, invalid transition rejection, version ordering, and policy defaults.

### Phase 2: Health Gate and Pluggable Health Checks

**Goals**
- replace the boolean health check with a structured health gate
- add pluggable health check types
- support observation windows and failure thresholds

**Files**
- `Sources/OmniAgentDeploy/Health/HealthGate.swift`
- `Sources/OmniAgentDeploy/Health/HealthGateResult.swift`
- `Sources/OmniAgentDeploy/Health/HealthCheckProtocol.swift`
- `Sources/OmniAgentDeploy/Health/ProcessHealthCheck.swift`
- `Sources/OmniAgentDeploy/Health/EndpointHealthCheck.swift`
- `Sources/OmniAgentDeploy/Health/LogHealthCheck.swift`
- `Sources/OmniAgentDeploy/Health/CustomHealthCheck.swift`
- `Sources/OmniAgentDeploy/Supervisor.swift`
- `Sources/OmniAgentDeploy/ReleaseController.swift`
- `Tests/OmniAgentDeployTests/HealthGateTests.swift`
- `Tests/OmniAgentDeployTests/HealthCheckTests.swift`

**Tasks**
- [ ] Define `HealthCheckProtocol` with an async `evaluate(release:) -> HealthCheckResult` method.
- [ ] Implement `ProcessHealthCheck`: verifies a named process is running and optionally responds on a port.
- [ ] Implement `EndpointHealthCheck`: HTTP GET to a URL, checks status code and latency against thresholds.
- [ ] Implement `LogHealthCheck`: scans recent log output for error patterns, compares error rate to threshold.
- [ ] Implement `CustomHealthCheck`: runs a shell command, interprets exit code 0 as healthy, non-zero as unhealthy, timeout as inconclusive.
- [ ] Implement `HealthGate` actor that runs a set of health checks on a configurable interval during the observation window.
- [ ] Add `HealthGateResult` with `.healthy`, `.unhealthy`, `.inconclusive` verdicts and per-check detail.
- [ ] Update `Supervisor.checkHealth()` to delegate to the health gate instead of a bare closure.
- [ ] Update `ReleaseController.deployCanary()` to use the three-way verdict: promote on healthy, rollback on unhealthy, hold and notify on inconclusive.
- [ ] Add unit tests for each health check type, gate timing, verdict aggregation, and inconclusive handling.

### Phase 3: Worker Generation Awareness and Drain/Rejoin

**Goals**
- tag workers and tasks with deployment generations
- implement graceful drain of old-generation workers
- handle stale generation cleanup and task rescheduling

**Files**
- `Sources/OmniAgentMesh/Models/WorkerRecord.swift`
- `Sources/OmniAgentMesh/Models/TaskRecord.swift`
- `Sources/OmniAgentMesh/Stores/JobStore.swift`
- `Sources/TheAgentControlPlane/Registry/WorkerRegistry.swift`
- `Sources/TheAgentControlPlane/Scheduler/RootScheduler.swift`
- `Sources/TheAgentControlPlane/Supervision/SupervisorService.swift`
- `Sources/TheAgentWorker/WorkerDaemon.swift`
- `Sources/OmniAgentDeploy/Supervisor.swift`
- `Tests/TheAgentControlPlaneTests/WorkerGenerationTests.swift`
- `Tests/TheAgentControlPlaneTests/DrainRejoinTests.swift`

**Tasks**
- [ ] Add `generation` field to `WorkerRecord` and `TaskRecord` with a string identifier tied to the active release ID.
- [ ] Add `generationState` enum to `WorkerRecord`: `.active`, `.draining`, `.stale`, `.rejoined`.
- [ ] Extend `WorkerRegistry` to track generation assignments and provide generation-filtered dispatcher queries.
- [ ] Extend `RootScheduler` to only place new tasks on workers in the active generation.
- [ ] Add `drain(generation:)` to `Supervisor` that transitions all workers in the given generation to `.draining` state.
- [ ] Modify `WorkerDaemon` to respect drain state: finish in-flight tasks but stop claiming new ones when draining.
- [ ] Add drain timeout enforcement in `SupervisorService`: sweep for draining generations that exceeded the timeout, mark as stale, reschedule orphaned tasks to active-generation workers.
- [ ] Add rejoin logic: after a generation is fully drained, its workers are re-registered under the new active generation.
- [ ] Add tests for generation tagging, drain behavior, stale detection, task rescheduling, and rejoin.

### Phase 4: Mission-to-Deploy Integration and Approval Gates

**Goals**
- make `MissionCoordinator` detect repo-changing intent and delegate to `ChangeCoordinator`/`ChangePipeline` by default
- wire deploy approval through the existing `InteractionBroker`
- produce release bundles as mission artifacts

**Files**
- `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift`
- `Sources/TheAgentControlPlane/Changes/ChangeCoordinator.swift`
- `Sources/OmniAgentDeploy/ChangePipeline.swift`
- `Sources/OmniAgentDeploy/ReleaseController.swift`
- `Sources/TheAgentControlPlane/Interaction/InteractionBroker.swift`
- `Sources/TheAgentControlPlane/RootAgentToolbox.swift`
- `Sources/TheAgentControlPlane/RootOrchestratorProfile.swift`
- `Sources/TheAgentControlPlane/Policy/DeployPolicy.swift`
- `Tests/TheAgentControlPlaneTests/MissionDeployIntegrationTests.swift`
- `Tests/TheAgentControlPlaneTests/DeployApprovalTests.swift`

**Tasks**
- [ ] Add a `missionClassifier` step in `MissionCoordinator.startMission()` that detects repo-changing intent from mission metadata, title, or brief keywords and sets execution mode to route through `ChangeCoordinator`.
- [ ] Make `ChangeCoordinator` the default code-change execution engine when `MissionCoordinator` detects a deployable change, rather than requiring explicit tool invocation.
- [ ] Add `deploy_approval` as a new approval class in `InteractionBroker` with workspace-scoped policy for whether it requires explicit user confirmation.
- [ ] Wire the approval gate into `ChangePipeline`: after release preparation and before canary deployment, check `DeployPolicy.approvalRequired` and if true, create an approval request and block until resolved.
- [ ] Add `release_bundle` as a mission artifact type so the release manifest is stored alongside other mission outputs.
- [ ] Add root tools: `deploy_status`, `promote_canary`, `rollback_release`, `list_releases` to `RootAgentToolbox`.
- [ ] Update `RootOrchestratorProfile` system prompt to describe the deploy lifecycle and available deploy tools.
- [ ] Extend `ChangePipeline` to produce the full `ReleaseBundleManifest` from implementation task outputs, including git SHA extraction, artifact collection, and health plan resolution from deploy policy.
- [ ] Add integration tests for the full mission → change → pipeline → release → deploy → outcome path.
- [ ] Add approval gate tests: approval-required blocks deploy, approval grants proceeds, rejection fails the change.

### Phase 5: Telegram Deploy Reporting and Outcome Delivery

**Goals**
- report deployment outcomes clearly through the root inbox and Telegram
- format deploy status for Telegram inline display
- support deploy-specific callback actions (promote, rollback, inspect)

**Files**
- `Sources/TheAgentControlPlane/NotificationInbox.swift`
- `Sources/TheAgentControlPlane/Interaction/InteractionBroker.swift`
- `Sources/TheAgentTelegram/TelegramDeliveryFormatter.swift`
- `Sources/TheAgentTelegram/TelegramCallbackCodec.swift`
- `Sources/TheAgentControlPlane/Diagnostics/DoctorService.swift`
- `Sources/OmniAgentDeploy/DeployReporter.swift`
- `Tests/TheAgentTelegramTests/DeployDeliveryTests.swift`
- `Tests/OmniAgentDeployTests/DeployReporterTests.swift`

**Tasks**
- [ ] Create `DeployReporter` actor that translates deployment state transitions into structured notification records for the root inbox.
- [ ] Add notification templates for each deploy outcome: `deployed` (release ID, version, health summary), `canary-only` (release ID, health status, user action needed), `rolled back` (release ID, reason, previous release restored), `blocked` (reason, required action).
- [ ] Extend `TelegramDeliveryFormatter` with deploy-specific message formatting: release summary card, health check results, diff stats.
- [ ] Add Telegram inline button callbacks for deploy actions: `promote:{releaseID}`, `rollback:{releaseID}`, `extend_observation:{releaseID}`.
- [ ] Encode deploy callbacks in `TelegramCallbackCodec` and route them through `InteractionBroker` to `ReleaseController`.
- [ ] Add deploy status to `DoctorService` reporting: active release, pending canaries, recent rollbacks, drain state, stale workers.
- [ ] Add tests for notification content, Telegram formatting, callback routing, and doctor deploy diagnostics.

### Phase 6: End-to-End Proof, Recovery Tests, and Documentation

**Goals**
- prove the full delivery lifecycle works end-to-end
- validate crash recovery, partial failure, and stale state handling
- update architecture and operational documentation

**Files**
- `Tests/OmniAgentDeployTests/ChangePipelineIntegrationTests.swift`
- `Tests/OmniAgentDeployTests/RollbackRecoveryTests.swift`
- `Tests/TheAgentControlPlaneTests/DeployRecoveryTests.swift`
- `Tests/TheAgentWorkerTests/GenerationDrainTests.swift`
- `Tests/TheAgentIngressTests/TelegramDeployProofTests.swift`
- `docs/agent-fabric-architecture.md`
- `docs/the-agent-runtime-runbook.md`

**Tasks**
- [ ] Integration test: feature request → change mission → implementation → review → scenario → release bundle → canary → health pass → promotion → Telegram notification.
- [ ] Integration test: same flow but health check fails → automatic rollback → Telegram rollback notification.
- [ ] Integration test: inconclusive health → canary hold → user promote callback → promotion.
- [ ] Recovery test: supervisor restarts mid-canary → resumes from durable state → completes deploy or rollback.
- [ ] Recovery test: worker crashes during drain → stale generation detected → orphaned tasks rescheduled.
- [ ] Recovery test: partial rollout with some workers on new generation and some on old → drain completes → consistent state.
- [ ] Telegram proof test: deploy approval inline button → canary deploy → health check → promote/rollback → formatted result message.
- [ ] Add at least one remote-worker-backed change mission that produces a release artifact and canary result.
- [ ] Add one intentional failed health-check path that rolls back automatically and reports the rollback clearly.
- [ ] Update `docs/agent-fabric-architecture.md` with the delivery lifecycle topology and deploy state machine.
- [ ] Update `docs/the-agent-runtime-runbook.md` with deploy policy configuration, health check setup, and rollback procedures.

## Files Summary

| File | Phase | Action | Purpose |
|------|-------|--------|---------|
| `Sources/OmniAgentMesh/Models/DeploymentRecord.swift` | 1 | Modify | Full release bundle metadata |
| `Sources/OmniAgentMesh/Models/DeploymentState.swift` | 1 | Create | Complete deployment state machine enum |
| `Sources/OmniAgentMesh/Models/ReleaseBundleManifest.swift` | 1 | Create | Structured release bundle specification |
| `Sources/OmniAgentMesh/Stores/DeploymentStore.swift` | 1 | Modify | State transition logging, immutability, version monotonicity |
| `Sources/TheAgentControlPlane/Policy/DeployPolicy.swift` | 1 | Create | Workspace-scoped deploy configuration |
| `Sources/TheAgentControlPlane/Policy/WorkspacePolicy.swift` | 1 | Modify | Add deploy policy integration |
| `Sources/OmniAgentDeploy/Health/HealthGate.swift` | 2 | Create | Observation-window health evaluation actor |
| `Sources/OmniAgentDeploy/Health/HealthGateResult.swift` | 2 | Create | Three-way verdict with per-check detail |
| `Sources/OmniAgentDeploy/Health/HealthCheckProtocol.swift` | 2 | Create | Pluggable health check interface |
| `Sources/OmniAgentDeploy/Health/ProcessHealthCheck.swift` | 2 | Create | Process liveness verification |
| `Sources/OmniAgentDeploy/Health/EndpointHealthCheck.swift` | 2 | Create | HTTP endpoint health verification |
| `Sources/OmniAgentDeploy/Health/LogHealthCheck.swift` | 2 | Create | Log error-rate health verification |
| `Sources/OmniAgentDeploy/Health/CustomHealthCheck.swift` | 2 | Create | Shell-command health verification |
| `Sources/OmniAgentDeploy/Supervisor.swift` | 2, 3 | Modify | Health gate integration, generation drain |
| `Sources/OmniAgentDeploy/ReleaseController.swift` | 2, 4 | Modify | Three-way verdict, approval gate, bundle creation |
| `Sources/OmniAgentMesh/Models/WorkerRecord.swift` | 3 | Modify | Generation field and generation state |
| `Sources/OmniAgentMesh/Models/TaskRecord.swift` | 3 | Modify | Generation tagging |
| `Sources/OmniAgentMesh/Stores/JobStore.swift` | 3 | Modify | Generation-filtered task claims |
| `Sources/TheAgentControlPlane/Registry/WorkerRegistry.swift` | 3 | Modify | Generation-aware dispatcher queries |
| `Sources/TheAgentControlPlane/Scheduler/RootScheduler.swift` | 3 | Modify | Generation-constrained task placement |
| `Sources/TheAgentControlPlane/Supervision/SupervisorService.swift` | 3 | Modify | Stale generation sweep and task rescheduling |
| `Sources/TheAgentWorker/WorkerDaemon.swift` | 3 | Modify | Drain-aware claim gating |
| `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift` | 4 | Modify | Repo-changing intent detection and ChangeCoordinator delegation |
| `Sources/TheAgentControlPlane/Changes/ChangeCoordinator.swift` | 4 | Modify | Default engine for code-change missions |
| `Sources/OmniAgentDeploy/ChangePipeline.swift` | 4 | Modify | Approval gate, bundle manifest creation |
| `Sources/TheAgentControlPlane/Interaction/InteractionBroker.swift` | 4, 5 | Modify | Deploy approval class, callback routing |
| `Sources/TheAgentControlPlane/RootAgentToolbox.swift` | 4 | Modify | Deploy tools: status, promote, rollback, list |
| `Sources/TheAgentControlPlane/RootOrchestratorProfile.swift` | 4 | Modify | Deploy lifecycle prompt context |
| `Sources/OmniAgentDeploy/DeployReporter.swift` | 5 | Create | Deployment outcome notification generation |
| `Sources/TheAgentTelegram/TelegramDeliveryFormatter.swift` | 5 | Modify | Deploy-specific message formatting |
| `Sources/TheAgentTelegram/TelegramCallbackCodec.swift` | 5 | Modify | Deploy action callback encoding |
| `Sources/TheAgentControlPlane/Diagnostics/DoctorService.swift` | 5 | Modify | Deploy status diagnostics |
| `Sources/TheAgentControlPlane/NotificationInbox.swift` | 5 | Modify | Deploy outcome notification templates |
| `docs/agent-fabric-architecture.md` | 6 | Modify | Delivery lifecycle and deploy state machine |
| `docs/the-agent-runtime-runbook.md` | 6 | Modify | Deploy policy, health checks, rollback procedures |

## Definition of Done

- [ ] Every repo-changing mission automatically produces a versioned, immutable release bundle with git SHA, build artifact refs, health plan, and traceability metadata.
- [ ] The deployment state machine enforces valid transitions and persists every state change with timestamp and reason code.
- [ ] Canary deployment uses a structured health gate with pluggable checks, observation windows, and three-way verdicts (healthy/unhealthy/inconclusive).
- [ ] Unhealthy canaries are rolled back automatically without user intervention; the previous active release is restored and the rollback is reported to the root inbox.
- [ ] Inconclusive health results hold the canary without promoting and surface a user-actionable notification through Telegram.
- [ ] Workspace deploy policy controls approval requirements, observation duration, max attempts, required health checks, and drain timeout.
- [ ] Workers are tagged with deployment generations; the scheduler only places new tasks on active-generation workers.
- [ ] Old-generation workers drain gracefully: existing tasks complete, no new claims, timeout triggers stale marking and task rescheduling.
- [ ] The root agent reports deployment outcomes through Telegram with structured messages: release ID, version, health summary, and action buttons.
- [ ] Telegram inline buttons support promote, rollback, and extend-observation actions for canary releases.
- [ ] `MissionCoordinator` detects repo-changing missions and delegates to `ChangeCoordinator`/`ChangePipeline` by default without requiring the user to invoke deploy-specific tools.
- [ ] Root tools `deploy_status`, `promote_canary`, `rollback_release`, and `list_releases` are available in the toolbox.
- [ ] Deploy status is included in `DoctorService` diagnostic reports.
- [ ] Unrelated background tasks and missions are preserved across release promotions and rollbacks.
- [ ] At least one integration test covers the full path: mission → implementation → review → release → canary → health → promote/rollback → notification.
- [ ] At least one integration test covers automatic rollback on health failure.
- [ ] At least one recovery test proves supervisor restart mid-canary resumes correctly from durable state.
- [ ] At least one remote-worker-backed change mission produces a release artifact and canary result.
- [ ] A live proof demonstrates one intentional health-check failure that rolls back automatically and reports clearly through Telegram.
- [ ] Architecture and operational docs are updated with the delivery lifecycle.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Deploy state machine complexity causes subtle transition bugs | Medium | High | Enforce transitions through a single validated method; reject invalid transitions explicitly; cover every edge with unit tests |
| Health gate false positives trigger unnecessary rollbacks | Medium | High | Require minimum observation duration before declaring unhealthy; distinguish transient startup failures from persistent ones; allow inconclusive hold state |
| Health gate false negatives promote unhealthy releases | Low | High | Require multiple consecutive healthy checks before promotion; make health plan configurable per workspace; include endpoint, process, and log checks by default |
| Worker generation drain drops in-flight tasks | Medium | High | Drain only gates new claims; existing tasks run to completion; timeout and stale-rescue path covers the edge case |
| Deploy approval blocks time-sensitive changes | Medium | Medium | Make approval policy configurable per workspace; allow auto-approve for low-risk changes based on diff size or test coverage |
| MissionCoordinator misclassifies non-deploy missions as deploy-eligible | Medium | Medium | Use explicit metadata flags and keyword detection; allow manual override through mission parameters; never auto-deploy without a release bundle |
| Canary observation window is too short for real health signals | Medium | High | Default to 60 seconds minimum; expose as policy configuration; allow user to extend observation through callback action |
| Rollback restores a release that is itself unhealthy | Low | High | Verify rollback target health before marking as active; if rollback target also fails health, escalate to operator instead of looping |
| Stale generation cleanup races with legitimate slow drain | Medium | Medium | Use conservative drain timeout (120s default); log drain progress; only reschedule tasks after timeout, not eagerly |
| Sprint scope expands into release pipeline features beyond the intent | Medium | High | Limit v1 to filesystem release directories; defer container images, traffic shifting, and multi-region to future sprints |

## Security Considerations

- Release bundles must be immutable after creation; no field in a persisted `DeploymentRecord` may be modified after initial write except deployment state and state-transition metadata.
- Health check endpoints and custom commands must be scoped to the workspace and validated against the deploy policy; arbitrary URLs or commands from mission metadata must be rejected unless they match the health plan template.
- Deploy approval actions through Telegram callback buttons must be verified against workspace membership and actor role; only workspace owners and admins may promote or rollback.
- Generation drain must not expose task state from one workspace to another; generation scoping respects workspace boundaries.
- Release directory paths must be sanitized to prevent path traversal; release IDs are UUIDs and version strings are validated before filesystem use.
- Deploy outcome notifications must redact secrets, internal error details, and worker hostnames from user-facing Telegram messages.
- Rollback must never leave the system in a state where no active release is set; if rollback fails, the system must escalate rather than null out the active release.
- Custom health check commands run in a sandboxed context with the same capability restrictions as worker shell tool execution.

## Dependencies

- Sprint 006 durable root/worker mesh and task/event stores
- Sprint 007 multi-user mission runtime, Telegram ingress, Attractor worker execution, and interaction broker
- Sprint 008 OmniSkills, channel policy, supervision, and workspace-scoped deploy policy foundations
- Sprint 010 concurrency hardening and isolation guarantees
- Existing `OmniAgentDeploy` module: `ChangePipeline`, `ReleaseController`, `Supervisor`
- Existing `OmniAgentMesh` stores: `DeploymentStore`, `ArtifactStore`, `JobStore`
- Existing `TheAgentControlPlane` modules: `MissionCoordinator`, `ChangeCoordinator`, `InteractionBroker`, `SupervisorService`, `WorkerRegistry`, `RootScheduler`
- Existing Telegram delivery infrastructure: `TelegramDeliveryFormatter`, `TelegramCallbackCodec`
- User-provided Telegram credentials and workspace configuration for live proof
- Provider credentials for worker execution backends

## Open Questions

1. Should every repo-changing mission always produce a release bundle, or only missions that target a workspace with an explicit `DeployPolicy` configured? The intent document leaves this open; a reasonable v1 default is to require an explicit deploy policy before auto-bundling.

2. What is the minimal v1 release artifact: git SHA + filesystem bundle + health plan, or a richer manifest with migration scripts and traffic metadata? This sprint proposes git SHA + filesystem bundle + health plan as the v1 floor, with manifest extensibility for future needs.

3. Should canary deployment operate on filesystem release directories, git worktrees, service units, or container images? This sprint targets filesystem release directories as the single v1 driver, with a `DeployDriver` protocol seam for future backends.

4. How should the root choose deployment targets when a workspace manages multiple services? This sprint proposes explicit service metadata on the mission or change request, with a fallback to the workspace's default service if only one is configured.

5. What should happen when canary health is inconclusive after the maximum observation window? This sprint proposes hold-and-ask: the canary stays active, the user receives a notification with promote/rollback/extend options, and no automatic action is taken.

6. How aggressively should stale worker generations be drained? This sprint proposes a conservative 120-second default with configurable override, reschedule-on-timeout, and explicit escalation to the root inbox rather than silent cleanup.

7. Which deploy operations always require approval? This sprint proposes canary-to-live promotion requires approval by default, rollback is auto-approved (safety bias), and initial canary deployment is auto-approved if the change passed review and scenario gates.

8. Should the `DeployReporter` produce notifications for every state transition, or only for terminal states and user-actionable holds? This sprint proposes terminal states (`.live`, `.rolledBack`, `.failed`) plus user-actionable holds (`.canary` with inconclusive health) as the default notification set, with verbose mode as a policy option.
