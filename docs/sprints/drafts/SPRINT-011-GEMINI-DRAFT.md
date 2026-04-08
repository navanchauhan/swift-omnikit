# Sprint 011: The Agent Autonomous Delivery Runtime

## Overview

This sprint upgrades `TheAgent` from merely implementing code to safely delivering, deploying, and verifying software changes through Telegram. It transforms the root agent into a true chief of staff for software delivery. Instead of just mutating code in place, the system will orchestrate workers to produce durable release artifacts, deploy via controlled canary rollouts, verify health gates, and automatically roll back on failure. All status updates and rollout outcomes are reported back to the user via Telegram without exposing internal chaos or requiring manual supervision of routine failures.

## Use Cases

1. **Feature Request to Release Bundle:** A user requests a feature over Telegram; the root agent plans the work, delegates to workers for implementation, and produces a versioned, immutable release bundle.
2. **Canary Deployment:** The system automatically deploys the resulting release bundle to a designated canary slot or host, preserving the currently running production generation.
3. **Health Verification:** Explicit health checks and gates are executed against the newly deployed canary environment.
4. **Automatic Rollback on Failure:** If canary health checks fail (or are conclusively unhealthy), the system automatically rolls back the deployment, drains the canary workers, and reports the detailed failure and rollback reason to the user via Telegram.
5. **Promotion on Success:** If health checks pass, the canary is promoted to an active release, the previous generation is safely drained, and the user is notified of the successful deployment.
6. **Background Work Preservation:** Unrelated background work executing on the worker mesh is preserved and unaffected during deployment, promotion, or rollback.

## Architecture

- **Root Mission & Runtime Orchestration:** Integrates release and rollout semantics into `MissionCoordinator` and `RootAgentRuntime`. Code-change requests are treated as structured change missions by default.
- **Change & Deploy Pipeline:** Expands `OmniAgentDeploy/ChangePipeline` and `ReleaseController` to produce immutable release records (artifacts) and manage slot-based or canary deployments rather than mutating active state.
- **Health & Verification:** Adds explicit health-gating logic into `SupervisorService` and `DoctorService` to actively verify the operational state of a deployment before promotion is permitted.
- **Worker Plane:** Updates `WorkerDaemon` and `WorkerExecutorFactory` to support generation awareness. This ensures that old and new worker processes can coexist during a canary and that stale processes are gracefully drained or cleaned up.
- **Storage & Artifacts:** Enhances `ArtifactStore` and `DeploymentStore` to persistently track immutable release bundles, host generations, and rollout states.
- **Telegram Ingress/Egress:** Extends `TelegramDeliveryFormatter` and `InteractionBroker` to report clear, actionable deployment outcomes (e.g., `deployed`, `canary-only`, `rolled back`, `blocked`) directly to the user's inbox without leaking internal operational noise.

## Implementation Phases

### Phase 1: Release Bundles & Mission Integration
- Update `MissionCoordinator` to ensure repo-changing requests default to structured change missions.
- Implement logic in `ChangeCoordinator` and `ChangePipeline` to produce a durable, versioned release artifact (e.g., git SHA + bundle + health plan) upon successful implementation.
- Update `DeploymentStore` and `ArtifactStore` to track and persist these immutable release records.

### Phase 2: Canary Deployment & Slot Management
- Enhance `ReleaseController` to support deploying to canary/slot-based targets instead of mutating production environments in place.
- Update `SupervisorService` and `Supervisor` to manage the deployment of the release bundle to the selected canary slot.
- Introduce generation awareness into `WorkerDaemon` to properly track drain/rejoin states and ensure worker isolation between generations.

### Phase 3: Health Verification & Automatic Rollback
- Introduce explicit, policy-driven health gates in `DoctorService`.
- Implement automatic rollback logic within `ReleaseController` that is triggered seamlessly by health check failures.
- Ensure stale or failed worker generations are aggressively drained or ignored upon a rollback event.

### Phase 4: Telegram Reporting & User Experience
- Update `TelegramDeliveryFormatter` and `InteractionBroker` to distill deployment logs into clear, high-level status messages (`deployed`, `canary-only`, `rolled back`, `blocked`).
- Integrate workspace approval policies, prompting the user via Telegram only when explicit approval is required to proceed with a rollout or promotion.

## Files Summary

- **Root Orchestration:**
  - `Sources/TheAgentControlPlane/Missions/MissionCoordinator.swift`
  - `Sources/TheAgentControlPlane/Interaction/InteractionBroker.swift`
  - `Sources/TheAgentControlPlane/RootAgentRuntime.swift`
- **Deploy & Pipeline:**
  - `Sources/TheAgentControlPlane/Changes/ChangeCoordinator.swift`
  - `Sources/OmniAgentDeploy/ChangePipeline.swift`
  - `Sources/OmniAgentDeploy/ReleaseController.swift`
- **Supervision & Health:**
  - `Sources/OmniAgentDeploy/Supervisor.swift`
  - `Sources/TheAgentControlPlane/Supervision/SupervisorService.swift`
  - `Sources/TheAgentControlPlane/Diagnostics/DoctorService.swift`
- **Worker Management:**
  - `Sources/TheAgentWorker/WorkerDaemon.swift`
  - `Sources/TheAgentWorker/WorkerExecutorFactory.swift`
- **User Interface (Telegram):**
  - `Sources/TheAgentTelegram/TelegramDeliveryFormatter.swift`
- **State & Stores:**
  - `Sources/OmniAgentMesh/Stores/ArtifactStore.swift`
  - `Sources/OmniAgentMesh/Stores/DeploymentStore.swift`

## Definition of Done

- **Functional:**
  - Feature requests from Telegram successfully translate into structured change missions.
  - Change missions deterministically produce versioned, immutable release bundles.
  - Deployments execute on a designated canary slot/host rather than overriding live production state.
  - Explicit health checks run against the canary before any promotion occurs.
  - Health check failures trigger an automatic, successful rollback to the previous generation.
  - Successful canaries are automatically promoted to active releases, gracefully draining the old generation.
  - The root agent reports final deployment outcomes (e.g., `deployed`, `rolled back`) back to the user via Telegram.
- **Testing & Validation:**
  - Unit tests verify release bundle creation, slot selection, health policy evaluation, and rollback decisions.
  - Integration tests cover the full `mission -> change pipeline -> release controller -> supervisor` path.
  - A live-proof remote worker-backed change mission successfully produces a release artifact and canary result.
  - A live-proof intentional health-check failure rolls back automatically and reports the failure clearly to the user.

## Risks

- **Scope Creep:** This sprint touches missions, workers, durable state, deploy artifacts, host ops, health verification, and user messaging. Strict adherence to minimal v1 deploy semantics is required.
- **Architecture Friction:** Fitting rigorous rollout mechanics onto the existing control-plane and worker model without regressing the current, working Telegram runtime contract may require delicate refactoring in `MissionCoordinator`.
- **State Inconsistency:** If host generation, drain/rejoin state, or worker liveness are not tracked accurately, remote rollouts could lead to orphaned worker processes, fake success reports, or degraded system performance.

## Security

- **Isolation:** Multi-user workspace and channel isolation must remain fully intact during all deployment and rollout phases.
- **Operator Safety:** The system must not execute unauthorized deploy operations or skip required approvals defined by workspace policy.
- **Information Disclosure:** Release artifacts and deployment error logs must not leak sensitive internal operational chaos, stack traces, or credentials to the Telegram response path.

## Dependencies

- Existing control-plane and worker mesh architecture (established in Sprint 006 and Sprint 007).
- OmniSkills, channel policy, routing, supervision, and reflection (established in Sprint 008).
- Concurrency and reliability guarantees in the core runtime and transport (established in Sprint 010).

## Open Questions

1. Should every repo-changing mission always produce a release bundle, or only missions targeting explicitly declared deployable repos/services?
2. What constitutes the minimal v1 release artifact: git SHA + bundle + health plan, or a richer manifest with migration and traffic metadata?
3. Should canary/slot promotion operate on filesystem release directories, git worktrees, service units, container images, or support multiple drivers from the start?
4. How should the root agent choose deployment targets for a workspace/repo: via explicit mission config, skill policy, or dynamic host inventory rules?
5. What is the fallback behavior when canary health is inconclusive (e.g., timeouts, flapping) rather than clearly healthy or failed?
6. How aggressively should stale worker generations be drained, killed, or ignored once a newer rollout generation is active?
7. Which deploy operations always require explicit user approval via Telegram, and which can be auto-approved under workspace policy?
