import Foundation

public struct SkillInstallationRecord: Codable, Sendable, Equatable {
    public enum Scope: String, Codable, Sendable, CaseIterable {
        case system
        case workspace
        case mission
    }

    public enum SourceType: String, Codable, Sendable {
        case localDirectory = "local_directory"
        case localArchive = "local_archive"
        case gitCheckoutPath = "git_checkout_path"
        case legacyClaudeCommand = "legacy_claude_command"
        case legacyGeminiSkill = "legacy_gemini_skill"
    }

    public var installationID: String
    public var skillID: String
    public var version: String
    public var scope: Scope
    public var workspaceID: WorkspaceID?
    public var sourceType: SourceType
    public var sourcePath: String
    public var installedPath: String
    public var digest: String
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        installationID: String = UUID().uuidString,
        skillID: String,
        version: String,
        scope: Scope,
        workspaceID: WorkspaceID? = nil,
        sourceType: SourceType,
        sourcePath: String,
        installedPath: String,
        digest: String,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.installationID = installationID
        self.skillID = skillID
        self.version = version
        self.scope = scope
        self.workspaceID = workspaceID
        self.sourceType = sourceType
        self.sourcePath = sourcePath
        self.installedPath = installedPath
        self.digest = digest
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct SkillActivationRecord: Codable, Sendable, Equatable {
    public enum Scope: String, Codable, Sendable, CaseIterable {
        case system
        case workspace
        case mission
    }

    public enum Status: String, Codable, Sendable {
        case active
        case pendingApproval = "pending_approval"
        case inactive
    }

    public var activationID: String
    public var installationID: String?
    public var skillID: String
    public var version: String?
    public var scope: Scope
    public var rootSessionID: String
    public var workspaceID: WorkspaceID?
    public var channelID: ChannelID?
    public var actorID: ActorID?
    public var missionID: String?
    public var approvalRequestID: String?
    public var status: Status
    public var reason: String
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date
    public var deactivatedAt: Date?

    public init(
        activationID: String = UUID().uuidString,
        installationID: String? = nil,
        skillID: String,
        version: String? = nil,
        scope: Scope,
        rootSessionID: String,
        workspaceID: WorkspaceID? = nil,
        channelID: ChannelID? = nil,
        actorID: ActorID? = nil,
        missionID: String? = nil,
        approvalRequestID: String? = nil,
        status: Status = .active,
        reason: String,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deactivatedAt: Date? = nil
    ) {
        let resolvedScope = SessionScope.bestEffort(sessionID: rootSessionID)
        self.activationID = activationID
        self.installationID = installationID
        self.skillID = skillID
        self.version = version
        self.scope = scope
        self.rootSessionID = rootSessionID
        self.workspaceID = workspaceID ?? resolvedScope.workspaceID
        self.channelID = channelID ?? resolvedScope.channelID
        self.actorID = actorID ?? resolvedScope.actorID
        self.missionID = missionID
        self.approvalRequestID = approvalRequestID
        self.status = status
        self.reason = reason
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deactivatedAt = deactivatedAt
    }
}
