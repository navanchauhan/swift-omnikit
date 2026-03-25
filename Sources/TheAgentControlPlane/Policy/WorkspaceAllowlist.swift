import Foundation
import OmniAgentMesh

public enum WorkspaceAllowlist {
    public static func actorIDs(from workspace: WorkspaceRecord) -> Set<ActorID> {
        actorIDs(from: workspace.metadata)
    }

    public static func externalActorIDs(from workspace: WorkspaceRecord) -> Set<String> {
        externalActorIDs(from: workspace.metadata)
    }

    public static func actorIDs(from metadata: [String: String]) -> Set<ActorID> {
        Set(csv(metadata["allowlist_actor_ids"]).map { ActorID(rawValue: $0) })
    }

    public static func externalActorIDs(from metadata: [String: String]) -> Set<String> {
        Set(csv(metadata["allowlist_external_actor_ids"]))
    }

    public static func globalActorIDs(
        from metadata: [String: String],
        transport: ChannelBinding.Transport
    ) -> Set<ActorID> {
        let global = Set(csv(metadata["global_allowlist_actor_ids"]).map { ActorID(rawValue: $0) })
        let transportScoped = Set(csv(metadata["\(transport.rawValue)_allowlist_actor_ids"]).map { ActorID(rawValue: $0) })
        return global.union(transportScoped)
    }

    public static func globalExternalActorIDs(
        from metadata: [String: String],
        transport: ChannelBinding.Transport
    ) -> Set<String> {
        let global = Set(csv(metadata["global_allowlist_external_actor_ids"]))
        let transportScoped = Set(csv(metadata["\(transport.rawValue)_allowlist_external_actor_ids"]))
        return global.union(transportScoped)
    }

    private static func csv(_ rawValue: String?) -> [String] {
        rawValue?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }
}
