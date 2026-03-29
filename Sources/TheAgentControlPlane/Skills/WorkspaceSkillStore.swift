import Foundation
import OmniAgentMesh
import OmniSkills

public struct SkillStatusSnapshot: Sendable, Equatable {
    public var installed: [SkillInstallationRecord]
    public var activations: [SkillActivationRecord]
    public var projection: OmniSkillProjectionBundle

    public init(
        installed: [SkillInstallationRecord],
        activations: [SkillActivationRecord],
        projection: OmniSkillProjectionBundle
    ) {
        self.installed = installed
        self.activations = activations
        self.projection = projection
    }
}

public struct SkillOperationResult: Sendable, Equatable {
    public var installation: SkillInstallationRecord?
    public var activation: SkillActivationRecord?
    public var approvalRequest: ApprovalRequestRecord?
    public var projection: OmniSkillProjectionBundle

    public init(
        installation: SkillInstallationRecord? = nil,
        activation: SkillActivationRecord? = nil,
        approvalRequest: ApprovalRequestRecord? = nil,
        projection: OmniSkillProjectionBundle
    ) {
        self.installation = installation
        self.activation = activation
        self.approvalRequest = approvalRequest
        self.projection = projection
    }
}

public enum WorkspaceSkillStoreError: Error, CustomStringConvertible {
    case skillNotFound(String)

    public var description: String {
        switch self {
        case .skillNotFound(let skillID):
            return "Skill \(skillID) was not found."
        }
    }
}

public actor WorkspaceSkillStore {
    private let scope: SessionScope
    private let store: any SkillStore
    private let registry: OmniSkillRegistry
    private let installer: OmniSkillInstaller
    private let workingDirectory: URL

    public init(
        scope: SessionScope,
        store: any SkillStore,
        skillsRootDirectory: URL,
        workingDirectory: String
    ) {
        self.scope = scope
        self.store = store
        self.registry = OmniSkillRegistry(skillsRootDirectory: skillsRootDirectory)
        self.installer = OmniSkillInstaller(installsRootDirectory: skillsRootDirectory)
        self.workingDirectory = URL(fileURLWithPath: workingDirectory, isDirectory: true)
    }

    public func installSkill(
        from sourcePath: String,
        scope installationScope: SkillInstallationRecord.Scope
    ) async throws -> SkillInstallationRecord {
        let installation = try await installer.install(
            from: URL(fileURLWithPath: sourcePath),
            scope: installationScope,
            workspaceID: installationScope == .workspace ? scope.workspaceID : nil
        )
        return try await store.saveInstallation(installation)
    }

    public func installedSkills(skillID: String? = nil) async throws -> [SkillInstallationRecord] {
        let system = try await store.installations(scope: .system, workspaceID: nil, skillID: skillID)
        let workspace = try await store.installations(scope: .workspace, workspaceID: scope.workspaceID, skillID: skillID)
        return (system + workspace).sorted { lhs, rhs in
            if lhs.skillID != rhs.skillID {
                return lhs.skillID < rhs.skillID
            }
            if lhs.scope != rhs.scope {
                return lhs.scope.rawValue < rhs.scope.rawValue
            }
            return lhs.version.localizedStandardCompare(rhs.version) == .orderedDescending
        }
    }

    public func activations(
        missionID: String? = nil,
        statuses: [SkillActivationRecord.Status]? = nil
    ) async throws -> [SkillActivationRecord] {
        let allActivations = try await store.activations(
            rootSessionID: scope.sessionID,
            workspaceID: scope.workspaceID,
            missionID: nil,
            statuses: statuses
        )
        return allActivations.filter { activation in
            switch activation.scope {
            case .system, .workspace:
                true
            case .mission:
                activation.missionID == missionID
            }
        }
    }

    public func resolvePackage(skillID: String) async throws -> OmniSkillPackage? {
        if let installation = try await preferredInstallation(skillID: skillID) {
            return try registry.loadInstalledPackages(from: [installation]).first
        }
        return try registry.resolveSkill(named: skillID, workingDirectory: workingDirectory)
    }

    public func activateSkill(
        skillID: String,
        activationScope: SkillActivationRecord.Scope,
        missionID: String? = nil,
        reason: String,
        actorID: ActorID? = nil,
        status: SkillActivationRecord.Status = .active,
        approvalRequestID: String? = nil,
        metadata: [String: String] = [:]
    ) async throws -> SkillActivationRecord {
        guard let package = try await resolvePackage(skillID: skillID) else {
            throw WorkspaceSkillStoreError.skillNotFound(skillID)
        }
        let installation = try await preferredInstallation(skillID: skillID)
        let activation = SkillActivationRecord(
            installationID: installation?.installationID,
            skillID: package.manifest.skillID,
            version: installation?.version ?? package.manifest.version,
            scope: activationScope,
            rootSessionID: scope.sessionID,
            workspaceID: scope.workspaceID,
            channelID: scope.channelID,
            actorID: actorID ?? scope.actorID,
            missionID: missionID,
            approvalRequestID: approvalRequestID,
            status: status,
            reason: reason,
            metadata: metadata
        )
        return try await store.saveActivation(activation)
    }

    public func deactivateSkill(
        skillID: String,
        activationScope: SkillActivationRecord.Scope,
        missionID: String? = nil,
        reason: String
    ) async throws -> SkillActivationRecord? {
        let candidates = try await activations(missionID: missionID, statuses: [.active, .pendingApproval])
            .filter { $0.skillID == skillID && $0.scope == activationScope }
            .sorted { $0.createdAt > $1.createdAt }
        guard var latest = candidates.first else {
            return nil
        }
        latest.status = .inactive
        latest.reason = reason
        latest.deactivatedAt = Date()
        return try await store.saveActivation(latest)
    }

    public func markActivation(
        activationID: String,
        status: SkillActivationRecord.Status,
        approvalRequestID: String? = nil
    ) async throws -> SkillActivationRecord? {
        guard var activation = try await store.activation(activationID: activationID) else {
            return nil
        }
        activation.status = status
        if let approvalRequestID {
            activation.approvalRequestID = approvalRequestID
        }
        if status == .inactive {
            activation.deactivatedAt = Date()
        }
        return try await store.saveActivation(activation)
    }

    public func activeProjection(missionID: String? = nil) async throws -> OmniSkillProjectionBundle {
        let installations = try await installedSkills()
        let activations = try await activations(missionID: missionID, statuses: [.active])
        let activeInstalled = OmniSkillActivationResolver.activeInstallations(
            installations: installations,
            activations: activations,
            scope: scope,
            missionID: missionID
        )
        var packages = try registry.loadInstalledPackages(from: activeInstalled)
        var seenKeys = Set(packages.map { "\($0.manifest.skillID)@\($0.manifest.version)" })

        for activation in activations where activation.status == .active {
            guard let package = try registry.resolveSkill(named: activation.skillID, workingDirectory: workingDirectory) else {
                continue
            }
            let key = "\(package.manifest.skillID)@\(package.manifest.version)"
            if seenKeys.insert(key).inserted {
                packages.append(package)
            }
        }
        return try OmniSkillProjectionCompiler.compile(packages: packages)
    }

    public func status(skillID: String? = nil, missionID: String? = nil) async throws -> SkillStatusSnapshot {
        let installed = try await installedSkills(skillID: skillID)
        let activations = try await activations(missionID: missionID, statuses: nil)
            .filter { skillID == nil || $0.skillID == skillID }
        let projection = try await activeProjection(missionID: missionID)
        return SkillStatusSnapshot(installed: installed, activations: activations, projection: projection)
    }

    public func promptContext(missionID: String? = nil) async throws -> [String: String] {
        let projection = try await activeProjection(missionID: missionID)
        return Self.metadata(from: projection)
    }

    public static func metadata(from projection: OmniSkillProjectionBundle) -> [String: String] {
        let workerToolsData = try? JSONEncoder().encode(projection.workerTools)
        let workerToolsJSON = workerToolsData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return [
            "omni_skills.active_ids": projection.activeSkillIDs.joined(separator: ","),
            "omni_skills.prompt_overlay": projection.promptOverlay,
            "omni_skills.codergen_overlay": projection.codergenOverlay,
            "omni_skills.attractor_overlay": projection.attractorOverlay,
            "omni_skills.worker_tools_json": workerToolsJSON,
            "omni_skills.required_capabilities": projection.requiredCapabilities.joined(separator: ","),
            "omni_skills.allowed_domains": projection.allowedDomains.joined(separator: ","),
            "omni_skills.preferred_model_tier": projection.preferredModelTier ?? "",
        ]
    }

    private func preferredInstallation(skillID: String) async throws -> SkillInstallationRecord? {
        try await installedSkills(skillID: skillID).first
    }
}
