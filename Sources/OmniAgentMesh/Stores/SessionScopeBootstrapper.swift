import Foundation

public struct SessionScopeBootstrapSummary: Sendable, Equatable {
    public var sessionIDs: [String]
    public var createdActors: Int
    public var createdWorkspaces: Int
    public var createdMemberships: Int
    public var createdBindings: Int

    public init(
        sessionIDs: [String] = [],
        createdActors: Int = 0,
        createdWorkspaces: Int = 0,
        createdMemberships: Int = 0,
        createdBindings: Int = 0
    ) {
        self.sessionIDs = sessionIDs
        self.createdActors = createdActors
        self.createdWorkspaces = createdWorkspaces
        self.createdMemberships = createdMemberships
        self.createdBindings = createdBindings
    }
}

public actor SessionScopeBootstrapper {
    private let identityStore: any IdentityStore
    private let conversationStore: any ConversationStore
    private let jobStore: any JobStore

    public init(
        identityStore: any IdentityStore,
        conversationStore: any ConversationStore,
        jobStore: any JobStore
    ) {
        self.identityStore = identityStore
        self.conversationStore = conversationStore
        self.jobStore = jobStore
    }

    public func bootstrap(
        transport: ChannelBinding.Transport = .local,
        includeSystemRootScope: Bool = true
    ) async throws -> SessionScopeBootstrapSummary {
        var knownSessionIDs = Set(try await conversationStore.sessionIDs())
        let existingTasks = try await jobStore.tasks(statuses: nil)
        for task in existingTasks {
            knownSessionIDs.insert(task.rootSessionID)
        }
        if includeSystemRootScope {
            knownSessionIDs.insert("root")
        }

        let orderedSessionIDs = knownSessionIDs.sorted()
        var summary = SessionScopeBootstrapSummary(sessionIDs: orderedSessionIDs)
        for sessionID in orderedSessionIDs {
            let counts = try await bootstrapScope(sessionID: sessionID, transport: transport)
            summary.createdActors += counts.createdActors
            summary.createdWorkspaces += counts.createdWorkspaces
            summary.createdMemberships += counts.createdMemberships
            summary.createdBindings += counts.createdBindings
        }
        return summary
    }

    public func bootstrapScope(
        sessionID: String,
        transport: ChannelBinding.Transport = .local
    ) async throws -> SessionScopeBootstrapSummary {
        let scope = SessionScope.bestEffort(sessionID: sessionID)
        var summary = SessionScopeBootstrapSummary(sessionIDs: [sessionID])

        if try await identityStore.actor(actorID: scope.actorID) == nil {
            try await identityStore.saveActor(defaultActorRecord(for: scope, sessionID: sessionID))
            summary.createdActors += 1
        }

        if try await identityStore.workspace(workspaceID: scope.workspaceID) == nil {
            try await identityStore.saveWorkspace(defaultWorkspaceRecord(for: scope, sessionID: sessionID))
            summary.createdWorkspaces += 1
        }

        if try await identityStore.membership(workspaceID: scope.workspaceID, actorID: scope.actorID) == nil {
            try await identityStore.saveMembership(
                WorkspaceMembership(
                    workspaceID: scope.workspaceID,
                    actorID: scope.actorID,
                    role: .owner
                )
            )
            summary.createdMemberships += 1
        }

        for externalID in bindingExternalIDs(for: scope, storageSessionID: sessionID) {
            if try await identityStore.channelBinding(transport: transport, externalID: externalID) != nil {
                continue
            }
            try await identityStore.saveChannelBinding(
                ChannelBinding(
                    transport: transport,
                    externalID: externalID,
                    workspaceID: scope.workspaceID,
                    channelID: scope.channelID,
                    actorID: scope.actorID,
                    metadata: bindingMetadata(
                        storageSessionID: sessionID,
                        externalID: externalID,
                        scope: scope
                    )
                )
            )
            summary.createdBindings += 1
        }

        return summary
    }

    private func defaultActorRecord(for scope: SessionScope, sessionID: String) -> ActorRecord {
        if sessionID == "root" || scope.actorID.rawValue == "root" {
            return ActorRecord(
                actorID: scope.actorID,
                displayName: "TheAgent Root",
                kind: .system,
                metadata: [
                    "bootstrap_source": "session_scope",
                    "storage_session_id": sessionID,
                ]
            )
        }

        return ActorRecord(
            actorID: scope.actorID,
            displayName: scope.actorID.rawValue,
            kind: .human,
            metadata: [
                "bootstrap_source": "session_scope",
                "storage_session_id": sessionID,
            ]
        )
    }

    private func defaultWorkspaceRecord(for scope: SessionScope, sessionID: String) -> WorkspaceRecord {
        let kind: WorkspaceRecord.Kind
        let displayName: String
        if sessionID == "root" || scope.workspaceID.rawValue == "root" {
            kind = .service
            displayName = "TheAgent Root Workspace"
        } else if scope.workspaceID.rawValue == scope.actorID.rawValue {
            kind = .personal
            displayName = "\(scope.actorID.rawValue) Workspace"
        } else {
            kind = .shared
            displayName = scope.workspaceID.rawValue
        }

        return WorkspaceRecord(
            workspaceID: scope.workspaceID,
            displayName: displayName,
            kind: kind,
            metadata: [
                "bootstrap_source": "session_scope",
                "storage_session_id": sessionID,
            ]
        )
    }

    private func bindingExternalIDs(for scope: SessionScope, storageSessionID: String) -> [String] {
        let candidates = [storageSessionID, scope.sessionID]
        return Array(Set(candidates)).sorted()
    }

    private func bindingMetadata(
        storageSessionID: String,
        externalID: String,
        scope: SessionScope
    ) -> [String: String] {
        var metadata = [
            "bootstrap_source": "session_scope",
            "storage_session_id": storageSessionID,
            "scope_session_id": scope.sessionID,
        ]
        if externalID != scope.sessionID {
            metadata["binding_alias"] = "legacy-session-id"
        } else if externalID == storageSessionID {
            metadata["binding_alias"] = "storage-session-id"
        } else {
            metadata["binding_alias"] = "scope-session-id"
        }
        return metadata
    }
}
