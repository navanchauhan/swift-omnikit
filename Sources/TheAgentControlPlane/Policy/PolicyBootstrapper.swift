import Foundation
import OmniAgentMesh

public enum PolicyBootstrapper {
    public static func applyEnvironmentOverrides(
        identityStore: any IdentityStore,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws {
        guard var rootWorkspace = try await identityStore.workspace(workspaceID: WorkspaceID(rawValue: "root")) else {
            return
        }

        var updated = false
        if let telegramAllowlist = mergedTelegramAllowlist(from: environment), !telegramAllowlist.isEmpty,
           rootWorkspace.metadata["telegram_allowlist_external_actor_ids"] != telegramAllowlist {
            rootWorkspace.metadata["telegram_allowlist_external_actor_ids"] = telegramAllowlist
            updated = true
        }

        let desiredTelegramDMPolicy = environment["THE_AGENT_TELEGRAM_DM_POLICY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            ?? (
                mergedTelegramAllowlist(from: environment).flatMap { $0.isEmpty ? nil : "allowlist" }
            )
        if let desiredTelegramDMPolicy,
           rootWorkspace.metadata["telegram_dm_policy"] != desiredTelegramDMPolicy {
            rootWorkspace.metadata["telegram_dm_policy"] = desiredTelegramDMPolicy
            updated = true
        }

        if updated {
            rootWorkspace.updatedAt = Date()
            try await identityStore.saveWorkspace(rootWorkspace)
        }
    }

    public static func mergedTelegramAllowlist(from environment: [String: String]) -> String? {
        let ownerID = environment["THE_AGENT_TELEGRAM_OWNER_ID"]
        let explicitAllowlist = environment["THE_AGENT_TELEGRAM_ALLOWED_USER_IDS"]
        let values = [ownerID, explicitAllowlist]
            .compactMap { $0 }
            .flatMap { rawValue in
                rawValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        guard !values.isEmpty else {
            return nil
        }
        return Array(Set(values)).sorted().joined(separator: ",")
    }
}
