import Foundation
import OmniAgentDeliveryCore
import OmniAgentMesh
import OmniSkills

public actor WorkspaceSessionRegistry {
    private let stateRoot: AgentFabricStateRoot
    private let identityStore: (any IdentityStore)?
    private let conversationStore: any ConversationStore
    private let jobStore: any JobStore
    private let missionStore: (any MissionStore)?
    private let skillStore: (any SkillStore)?
    private let artifactStore: (any ArtifactStore)?
    private let deliveryStore: (any DeliveryStore)?
    private let pairingStore: PairingStore?
    private let releaseBundleStore: (any ReleaseBundleStore)?
    private let releaseController: ReleaseController?
    private let hotWindowLimit: Int
    private let notificationPolicy: NotificationPolicy
    private let workspacePolicy: WorkspacePolicy
    private var servers: [String: RootAgentServer] = [:]

    public init(
        stateRoot: AgentFabricStateRoot = .workingDirectoryDefault(),
        identityStore: (any IdentityStore)? = nil,
        conversationStore: any ConversationStore,
        jobStore: any JobStore,
        missionStore: (any MissionStore)? = nil,
        skillStore: (any SkillStore)? = nil,
        artifactStore: (any ArtifactStore)? = nil,
        deliveryStore: (any DeliveryStore)? = nil,
        pairingStore: PairingStore? = nil,
        releaseBundleStore: (any ReleaseBundleStore)? = nil,
        releaseController: ReleaseController? = nil,
        hotWindowLimit: Int = 12,
        notificationPolicy: NotificationPolicy = NotificationPolicy(),
        workspacePolicy: WorkspacePolicy = WorkspacePolicy()
    ) {
        self.stateRoot = stateRoot
        self.identityStore = identityStore
        self.conversationStore = conversationStore
        self.jobStore = jobStore
        self.missionStore = missionStore
        self.skillStore = skillStore
        self.artifactStore = artifactStore
        self.deliveryStore = deliveryStore
        self.pairingStore = pairingStore
        self.releaseBundleStore = releaseBundleStore
        self.releaseController = releaseController
        self.hotWindowLimit = hotWindowLimit
        self.notificationPolicy = notificationPolicy
        self.workspacePolicy = workspacePolicy
    }

    public func server(for scope: SessionScope) -> RootAgentServer {
        if let existing = servers[scope.sessionID] {
            return existing
        }
        let server = RootAgentServer(
            scope: scope,
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            skillStore: skillStore,
            identityStore: identityStore,
            pairingStore: pairingStore,
            skillsRootDirectory: stateRoot.skillsDirectoryURL,
            runtimeRootDirectory: stateRoot.runtimeDirectoryURL,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore,
            releaseBundleStore: releaseBundleStore,
            releaseController: releaseController,
            hotWindowLimit: hotWindowLimit,
            notificationPolicy: notificationPolicy,
            workspacePolicy: workspacePolicy,
            scheduler: RootScheduler(jobStore: jobStore),
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        servers[scope.sessionID] = server
        return server
    }

    public func server(sessionID: String) -> RootAgentServer {
        if let existing = servers[sessionID] {
            return existing
        }
        let server = RootAgentServer(
            sessionID: sessionID,
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            skillStore: skillStore,
            identityStore: identityStore,
            pairingStore: pairingStore,
            skillsRootDirectory: stateRoot.skillsDirectoryURL,
            runtimeRootDirectory: stateRoot.runtimeDirectoryURL,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore,
            releaseBundleStore: releaseBundleStore,
            releaseController: releaseController,
            hotWindowLimit: hotWindowLimit,
            notificationPolicy: notificationPolicy,
            workspacePolicy: workspacePolicy,
            scheduler: RootScheduler(jobStore: jobStore),
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        servers[sessionID] = server
        return server
    }

    public func cachedScopes() -> [SessionScope] {
        servers.keys
            .map(SessionScope.bestEffort(sessionID:))
            .sorted { lhs, rhs in
                if lhs.workspaceID != rhs.workspaceID {
                    return lhs.workspaceID < rhs.workspaceID
                }
                if lhs.channelID != rhs.channelID {
                    return lhs.channelID < rhs.channelID
                }
                return lhs.actorID < rhs.actorID
            }
    }
}
