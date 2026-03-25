import Foundation

public struct DoctorReport: Sendable, Equatable {
    public var workspaceID: String
    public var channelBindings: Int
    public var pendingPairings: Int
    public var registeredWorkers: Int
    public var staleWorkers: Int
    public var stalledTasks: Int
    public var installedSkills: Int
    public var activeSkillActivations: Int
    public var activeMissions: Int
    public var deferredDeliveries: Int
    public var routeTiers: [String]
    public var warnings: [String]

    public init(
        workspaceID: String,
        channelBindings: Int,
        pendingPairings: Int,
        registeredWorkers: Int,
        staleWorkers: Int,
        stalledTasks: Int,
        installedSkills: Int,
        activeSkillActivations: Int,
        activeMissions: Int,
        deferredDeliveries: Int,
        routeTiers: [String],
        warnings: [String]
    ) {
        self.workspaceID = workspaceID
        self.channelBindings = channelBindings
        self.pendingPairings = pendingPairings
        self.registeredWorkers = registeredWorkers
        self.staleWorkers = staleWorkers
        self.stalledTasks = stalledTasks
        self.installedSkills = installedSkills
        self.activeSkillActivations = activeSkillActivations
        self.activeMissions = activeMissions
        self.deferredDeliveries = deferredDeliveries
        self.routeTiers = routeTiers
        self.warnings = warnings
    }

    public var summaryText: String {
        [
            "Workspace: \(workspaceID)",
            "Channel bindings: \(channelBindings)",
            "Pending pairings: \(pendingPairings)",
            "Workers: \(registeredWorkers) (\(staleWorkers) stale)",
            "Stalled tasks: \(stalledTasks)",
            "Skills: \(installedSkills) installed, \(activeSkillActivations) active",
            "Active missions: \(activeMissions)",
            "Deferred deliveries: \(deferredDeliveries)",
            routeTiers.isEmpty ? nil : "Route tiers: \(routeTiers.joined(separator: ", "))",
            warnings.isEmpty ? nil : "Warnings:\n- " + warnings.joined(separator: "\n- "),
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}
