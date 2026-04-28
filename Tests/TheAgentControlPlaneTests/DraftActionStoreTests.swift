import Foundation
import OmniAICore
import Testing
@testable import TheAgentControlPlaneKit

@Suite
struct DraftActionStoreTests {
    @Test
    func storesPendingDraftActionsDurably() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("draft-action-store-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("draft-actions.json")
        let store = DraftActionStore(fileURL: fileURL)

        let created = try await store.create(
            sourceSessionID: "root.test",
            title: "reply to meghan",
            draftBody: "sounds good, let's chat next week",
            actionKind: "email",
            actionType: "email_reply",
            targetDescription: "meghan@v3talent.ai",
            payload: .object([
                "account_id": .string("icloud"),
                "mailbox": .string("INBOX"),
                "uid": .string("123"),
                "body": .string("sounds good, let's chat next week"),
            ]),
            channelTransport: "imessage",
            channelTargetExternalID: "+14155550100",
            actorExternalID: "+14155550100"
        )

        let reloaded = DraftActionStore(fileURL: fileURL)
        let pending = try await reloaded.list(status: .pendingConfirmation)
        #expect(pending.count == 1)
        #expect(pending.first?.draftID == created.draftID)
        #expect(try await reloaded.promptContext()?.contains(created.draftID) == true)

        let cancelled = try await reloaded.cancel(created.draftID)
        #expect(cancelled?.status == .cancelled)
        #expect(try await reloaded.promptContext() == nil)
    }
}
