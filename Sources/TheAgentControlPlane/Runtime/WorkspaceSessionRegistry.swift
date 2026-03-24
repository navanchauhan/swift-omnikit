import Foundation
import OmniAgentMesh

public actor WorkspaceSessionRegistry {
    private let conversationStore: any ConversationStore
    private let jobStore: any JobStore
    private let missionStore: (any MissionStore)?
    private let artifactStore: (any ArtifactStore)?
    private let deliveryStore: (any DeliveryStore)?
    private let hotWindowLimit: Int
    private let notificationPolicy: NotificationPolicy
    private let workspacePolicy: WorkspacePolicy
    private var servers: [String: RootAgentServer] = [:]

    public init(
        conversationStore: any ConversationStore,
        jobStore: any JobStore,
        missionStore: (any MissionStore)? = nil,
        artifactStore: (any ArtifactStore)? = nil,
        deliveryStore: (any DeliveryStore)? = nil,
        hotWindowLimit: Int = 12,
        notificationPolicy: NotificationPolicy = NotificationPolicy(),
        workspacePolicy: WorkspacePolicy = WorkspacePolicy()
    ) {
        self.conversationStore = conversationStore
        self.jobStore = jobStore
        self.missionStore = missionStore
        self.artifactStore = artifactStore
        self.deliveryStore = deliveryStore
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
            artifactStore: artifactStore,
            deliveryStore: deliveryStore,
            hotWindowLimit: hotWindowLimit,
            notificationPolicy: notificationPolicy,
            workspacePolicy: workspacePolicy,
            scheduler: RootScheduler(jobStore: jobStore)
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
            artifactStore: artifactStore,
            deliveryStore: deliveryStore,
            hotWindowLimit: hotWindowLimit,
            notificationPolicy: notificationPolicy,
            workspacePolicy: workspacePolicy,
            scheduler: RootScheduler(jobStore: jobStore)
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
