import Foundation
import OmniAgentMesh

public actor ApprovalBroker {
    private let interactionBroker: InteractionBroker
    private let scope: SessionScope
    private let policy: WorkspacePolicy

    public init(
        interactionBroker: InteractionBroker,
        scope: SessionScope,
        policy: WorkspacePolicy = WorkspacePolicy()
    ) {
        self.interactionBroker = interactionBroker
        self.scope = scope
        self.policy = policy
    }

    public func requestPermission(
        title: String,
        prompt: String,
        missionID: String? = nil,
        taskID: String? = nil,
        requesterActorID: ActorID? = nil,
        sensitive: Bool = true,
        metadata: [String: String] = [:]
    ) async throws -> ApprovalRequestRecord {
        try await interactionBroker.requestApproval(
            scope: scope,
            title: title,
            prompt: prompt,
            missionID: missionID,
            taskID: taskID,
            requesterActorID: requesterActorID,
            sensitive: sensitive,
            policy: policy,
            metadata: metadata
        )
    }
}
