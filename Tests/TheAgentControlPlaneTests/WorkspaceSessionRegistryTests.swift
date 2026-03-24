import Foundation
import Testing
import OmniAgentMesh
@testable import TheAgentControlPlaneKit

@Suite
struct WorkspaceSessionRegistryTests {
    @Test
    func registryKeepsScopedConversationsAndTasksIsolated() async throws {
        let stateRoot = try makeStateRoot(prefix: "registry")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let registry = WorkspaceSessionRegistry(
            conversationStore: conversationStore,
            jobStore: jobStore,
            hotWindowLimit: 5
        )

        let dmScope = SessionScope(actorID: "alice", workspaceID: "workspace-alice", channelID: "telegram-dm")
        let groupScope = SessionScope(actorID: "bob", workspaceID: "workspace-team", channelID: "telegram-topic-42")

        let dmServer = await registry.server(for: dmScope)
        let groupServer = await registry.server(for: groupScope)

        _ = try await dmServer.handleUserText("Personal work")
        _ = try await groupServer.handleUserText("Shared work")

        let dmTask = try await dmServer.delegateTask(brief: "Personal task")
        let groupTask = try await groupServer.delegateTask(brief: "Shared task")

        let dmSnapshot = try await dmServer.restoreState()
        let groupSnapshot = try await groupServer.restoreState()
        let dmTasks = try await dmServer.listTasks(currentRootOnly: true)
        let groupTasks = try await groupServer.listTasks(currentRootOnly: true)
        let scopes = await registry.cachedScopes()

        #expect(dmSnapshot.hotContext.count == 1)
        #expect(groupSnapshot.hotContext.count == 1)
        #expect(dmSnapshot.hotContext.first?.content == "Personal work")
        #expect(groupSnapshot.hotContext.first?.content == "Shared work")
        #expect(dmTasks.map(\.taskID) == [dmTask.taskID])
        #expect(groupTasks.map(\.taskID) == [groupTask.taskID])
        #expect(dmTasks.first?.workspaceID == dmScope.workspaceID)
        #expect(groupTasks.first?.workspaceID == groupScope.workspaceID)
        #expect(scopes == [dmScope, groupScope].sorted {
            if $0.workspaceID != $1.workspaceID {
                return $0.workspaceID < $1.workspaceID
            }
            if $0.channelID != $1.channelID {
                return $0.channelID < $1.channelID
            }
            return $0.actorID < $1.actorID
        })
    }

    @Test
    func registryPreservesLegacyStorageSessionIDsDuringMigrationWindow() async throws {
        let stateRoot = try makeStateRoot(prefix: "legacy-registry")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let identityStore = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let registry = WorkspaceSessionRegistry(
            conversationStore: conversationStore,
            jobStore: jobStore,
            hotWindowLimit: 5
        )

        _ = try await conversationStore.appendInteraction(
            InteractionItem(
                sessionID: "root",
                role: .user,
                modality: .text,
                content: "Legacy root conversation"
            )
        )
        _ = try await jobStore.createTask(
            TaskRecord(
                taskID: "legacy-root-task",
                rootSessionID: "root",
                historyProjection: HistoryProjection(taskBrief: "Continue legacy task")
            ),
            idempotencyKey: "legacy-root-task"
        )
        _ = try await SessionScopeBootstrapper(
            identityStore: identityStore,
            conversationStore: conversationStore,
            jobStore: jobStore
        ).bootstrap()

        let legacyServer = await registry.server(sessionID: "root")
        let snapshot = try await legacyServer.restoreState()
        let tasks = try await legacyServer.listTasks(currentRootOnly: true)

        #expect(legacyServer.sessionID == "root")
        #expect(legacyServer.scope == SessionScope.bestEffort(sessionID: "root"))
        #expect(snapshot.hotContext.map(\.content) == ["Legacy root conversation"])
        #expect(tasks.map(\.taskID) == ["legacy-root-task"])
        #expect(tasks.first?.workspaceID == "root")
        #expect(tasks.first?.channelID == "root")
    }

    private func makeStateRoot(prefix: String) throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
