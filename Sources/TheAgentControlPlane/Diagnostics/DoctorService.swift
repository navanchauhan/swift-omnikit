import Foundation
import OmniAgentMesh

public actor DoctorService {
    private let scope: SessionScope
    private let identityStore: any IdentityStore
    private let jobStore: any JobStore
    private let missionStore: (any MissionStore)?
    private let deliveryStore: (any DeliveryStore)?
    private let skillStore: (any SkillStore)?
    private let pairingStore: PairingStore?
    private let watchdog: TimeoutWatchdog?
    private let modelRouter: ModelRouter?

    public init(
        scope: SessionScope,
        identityStore: any IdentityStore,
        jobStore: any JobStore,
        missionStore: (any MissionStore)? = nil,
        deliveryStore: (any DeliveryStore)? = nil,
        skillStore: (any SkillStore)? = nil,
        pairingStore: PairingStore? = nil,
        watchdog: TimeoutWatchdog? = nil,
        modelRouter: ModelRouter? = nil
    ) {
        self.scope = scope
        self.identityStore = identityStore
        self.jobStore = jobStore
        self.missionStore = missionStore
        self.deliveryStore = deliveryStore
        self.skillStore = skillStore
        self.pairingStore = pairingStore
        self.watchdog = watchdog
        self.modelRouter = modelRouter
    }

    public func report(now: Date = Date()) async throws -> DoctorReport {
        let bindings = try await identityStore.channelBindings(workspaceID: scope.workspaceID)
        let workers = try await jobStore.workers()
        let staleWorkers = workers.filter { now.timeIntervalSince($0.lastHeartbeatAt) > 120 }
        let installedSkills = try await skillStore?.installations(
            scope: nil,
            workspaceID: scope.workspaceID,
            skillID: nil
        ) ?? []
        let activeSkillActivations = try await skillStore?.activations(
            rootSessionID: scope.sessionID,
            workspaceID: scope.workspaceID,
            missionID: nil,
            statuses: [.active]
        ) ?? []
        let activeMissions = try await missionStore?.missions(
            sessionID: scope.sessionID,
            workspaceID: scope.workspaceID,
            statuses: MissionRecord.Status.allCases.filter { !$0.isTerminal }
        ) ?? []
        let deferredDeliveries = try await deliveryStore?.deliveries(
            direction: .outbound,
            sessionID: scope.sessionID,
            status: .deferred
        ) ?? []
        let stalledTasks = try await watchdog?.stalledTasks(now: now) ?? []
        let routeTiers = await modelRouter?.supportedTiers() ?? []
        let pendingPairings = await pairingStore?.pendingRecords(now: now).filter {
            $0.workspaceID == nil || $0.workspaceID == scope.workspaceID
        } ?? []

        var warnings: [String] = []
        if !staleWorkers.isEmpty {
            warnings.append("Stale workers detected: \(staleWorkers.map(\.displayName).joined(separator: ", "))")
        }
        if activeMissions.isEmpty {
            warnings.append("No active missions.")
        }
        if bindings.isEmpty {
            warnings.append("No channel bindings are configured for this workspace.")
        }
        if !stalledTasks.isEmpty {
            warnings.append("Stalled tasks detected: \(stalledTasks.map { $0.task.taskID }.joined(separator: ", "))")
        }

        return DoctorReport(
            workspaceID: scope.workspaceID.rawValue,
            channelBindings: bindings.count,
            pendingPairings: pendingPairings.count,
            registeredWorkers: workers.count,
            staleWorkers: staleWorkers.count,
            stalledTasks: stalledTasks.count,
            installedSkills: installedSkills.count,
            activeSkillActivations: activeSkillActivations.count,
            activeMissions: activeMissions.count,
            deferredDeliveries: deferredDeliveries.count,
            routeTiers: routeTiers,
            warnings: warnings
        )
    }
}
