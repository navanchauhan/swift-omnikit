import Foundation
import Testing
@testable import OmniAgentMesh

@Suite
struct IdentityStoreTests {
    @Test
    func sessionScopeRoundTripsAndFallsBackFromLegacySessionID() throws {
        let original = SessionScope(
            actorID: "telegram-user-42",
            workspaceID: "workspace-team",
            channelID: "topic-7"
        )

        let roundTrip = try #require(SessionScope(sessionID: original.sessionID))
        let legacy = SessionScope.bestEffort(sessionID: "root")

        #expect(roundTrip == original)
        #expect(legacy.actorID == "root")
        #expect(legacy.workspaceID == "root")
        #expect(legacy.channelID == "root")
    }

    @Test
    func identityStorePersistsActorsWorkspacesMembershipsAndBindings() async throws {
        let stateRoot = try makeStateRoot()
        let store = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)

        let actor = ActorRecord(actorID: "alice", displayName: "Alice Example")
        let workspace = WorkspaceRecord(workspaceID: "workspace-alpha", displayName: "Alpha", kind: .shared)
        let membership = WorkspaceMembership(workspaceID: workspace.workspaceID, actorID: actor.actorID, role: .owner)
        let binding = ChannelBinding(
            transport: .telegram,
            externalID: "chat:100/thread:9",
            workspaceID: workspace.workspaceID,
            channelID: "telegram-topic-9",
            actorID: actor.actorID,
            metadata: ["kind": "topic"]
        )

        try await store.saveActor(actor)
        try await store.saveWorkspace(workspace)
        try await store.saveMembership(membership)
        try await store.saveChannelBinding(binding)

        let reopened = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        let restoredActor = try await reopened.actor(actorID: actor.actorID)
        let restoredWorkspace = try await reopened.workspace(workspaceID: workspace.workspaceID)
        let restoredMembership = try await reopened.membership(workspaceID: workspace.workspaceID, actorID: actor.actorID)
        let restoredBinding = try await reopened.channelBinding(transport: .telegram, externalID: binding.externalID)
        let workspaceBindings = try await reopened.channelBindings(workspaceID: workspace.workspaceID)

        #expect(restoredActor == actor)
        #expect(restoredWorkspace == workspace)
        #expect(restoredMembership == membership)
        #expect(restoredBinding == binding)
        #expect(workspaceBindings == [binding])
    }

    @Test
    func scopedRecordsInferWorkspaceAndChannelFromSessionScope() {
        let scope = SessionScope(actorID: "alice", workspaceID: "workspace-alpha", channelID: "telegram-dm")

        let interaction = InteractionItem(
            sessionID: scope.sessionID,
            role: .user,
            modality: .text,
            content: "hello"
        )
        let notification = NotificationRecord(
            sessionID: scope.sessionID,
            title: "Heads up",
            body: "A worker needs approval."
        )
        let task = TaskRecord(
            rootSessionID: scope.sessionID,
            historyProjection: HistoryProjection(taskBrief: "Run the task")
        )

        #expect(interaction.actorID == scope.actorID)
        #expect(interaction.workspaceID == scope.workspaceID)
        #expect(interaction.channelID == scope.channelID)
        #expect(notification.workspaceID == scope.workspaceID)
        #expect(notification.channelID == scope.channelID)
        #expect(task.requesterActorID == scope.actorID)
        #expect(task.workspaceID == scope.workspaceID)
        #expect(task.channelID == scope.channelID)
    }

    @Test
    func workspacePermissionsRequireExpectedMembershipRole() async throws {
        let stateRoot = try makeStateRoot()
        let store = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        let workspaceID: WorkspaceID = "workspace-team"

        try await store.saveMembership(.init(workspaceID: workspaceID, actorID: "viewer", role: .viewer))
        try await store.saveMembership(.init(workspaceID: workspaceID, actorID: "member", role: .member))
        try await store.saveMembership(.init(workspaceID: workspaceID, actorID: "admin", role: .admin))
        try await store.saveMembership(.init(workspaceID: workspaceID, actorID: "owner", role: .owner))

        #expect(try await store.isAuthorized(workspaceID: workspaceID, actorID: "viewer", for: .viewWorkspace))
        #expect(!(try await store.isAuthorized(workspaceID: workspaceID, actorID: "viewer", for: .startMission)))
        #expect(try await store.isAuthorized(workspaceID: workspaceID, actorID: "member", for: .startMission))
        #expect(!(try await store.isAuthorized(workspaceID: workspaceID, actorID: "member", for: .approveStandardInteraction)))
        #expect(try await store.isAuthorized(workspaceID: workspaceID, actorID: "admin", for: .approveStandardInteraction))
        #expect(!(try await store.isAuthorized(workspaceID: workspaceID, actorID: "admin", for: .approveSensitiveInteraction)))
        #expect(try await store.isAuthorized(workspaceID: workspaceID, actorID: "owner", for: .approveSensitiveInteraction))
        #expect(try await store.isAuthorized(workspaceID: workspaceID, actorID: "owner", for: .manageMembers))
    }

    @Test
    func bootstrapperCreatesIdentityRecordsForLegacySprint006Sessions() async throws {
        let stateRoot = try makeStateRoot()
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let identityStore = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)

        _ = try await conversationStore.appendInteraction(
            InteractionItem(
                sessionID: "root",
                role: .user,
                modality: .text,
                content: "Legacy root history"
            )
        )
        _ = try await conversationStore.saveNotification(
            NotificationRecord(
                sessionID: "root",
                title: "Legacy notice",
                body: "Needs attention."
            )
        )
        _ = try await jobStore.createTask(
            TaskRecord(
                taskID: "legacy-root-task",
                rootSessionID: "root",
                historyProjection: HistoryProjection(taskBrief: "Keep root continuity")
            ),
            idempotencyKey: "legacy-root-task"
        )

        let summary = try await SessionScopeBootstrapper(
            identityStore: identityStore,
            conversationStore: conversationStore,
            jobStore: jobStore
        ).bootstrap()

        let rootScope = SessionScope.bestEffort(sessionID: "root")
        let actor = try await identityStore.actor(actorID: rootScope.actorID)
        let workspace = try await identityStore.workspace(workspaceID: rootScope.workspaceID)
        let membership = try await identityStore.membership(workspaceID: rootScope.workspaceID, actorID: rootScope.actorID)
        let legacyBinding = try await identityStore.channelBinding(transport: .local, externalID: "root")
        let canonicalBinding = try await identityStore.channelBinding(transport: .local, externalID: rootScope.sessionID)
        let restoredLegacyTask = try await jobStore.task(taskID: "legacy-root-task")
        let restoredLegacyHistory = try await conversationStore.interactions(sessionID: "root", limit: nil)

        #expect(summary.sessionIDs.contains("root"))
        #expect(summary.createdActors >= 1)
        #expect(actor?.kind == .system)
        #expect(workspace?.kind == .service)
        #expect(membership?.role == .owner)
        #expect(legacyBinding?.workspaceID == rootScope.workspaceID)
        #expect(canonicalBinding?.workspaceID == rootScope.workspaceID)
        #expect(restoredLegacyTask?.workspaceID == rootScope.workspaceID)
        #expect(restoredLegacyTask?.channelID == rootScope.channelID)
        #expect(restoredLegacyHistory.first?.workspaceID == rootScope.workspaceID)
        #expect(restoredLegacyHistory.first?.channelID == rootScope.channelID)
    }

    private func makeStateRoot() throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-identity-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
