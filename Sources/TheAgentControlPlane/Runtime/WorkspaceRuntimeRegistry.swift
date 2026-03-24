import Foundation
import OmniAICore
import OmniAIAgent
import OmniAgentMesh

public actor WorkspaceRuntimeRegistry {
    public typealias RuntimeFactory = @Sendable (
        RootAgentServer,
        AgentFabricStateRoot,
        RootAgentRuntimeOptions,
        Client?,
        (any ProviderProfile)?
    ) async throws -> RootAgentRuntime

    private let serverRegistry: WorkspaceSessionRegistry
    private let stateRoot: AgentFabricStateRoot
    private let runtimeOptions: RootAgentRuntimeOptions
    private let client: Client?
    private let baseProfile: (any ProviderProfile)?
    private let runtimeFactory: RuntimeFactory
    private var runtimes: [String: RootAgentRuntime] = [:]

    public init(
        serverRegistry: WorkspaceSessionRegistry,
        stateRoot: AgentFabricStateRoot,
        runtimeOptions: RootAgentRuntimeOptions = RootAgentRuntimeOptions(),
        client: Client? = nil,
        baseProfile: (any ProviderProfile)? = nil,
        runtimeFactory: RuntimeFactory? = nil
    ) {
        self.serverRegistry = serverRegistry
        self.stateRoot = stateRoot
        self.runtimeOptions = runtimeOptions
        self.client = client
        self.baseProfile = baseProfile
        self.runtimeFactory = runtimeFactory ?? { server, stateRoot, options, client, baseProfile in
            try await RootAgentRuntime.make(
                server: server,
                stateRoot: stateRoot,
                options: options,
                client: client,
                baseProfile: baseProfile
            )
        }
    }

    public func runtime(for scope: SessionScope) async throws -> RootAgentRuntime {
        let server = await serverRegistry.server(for: scope)
        return try await runtime(for: server)
    }

    public func runtime(sessionID: String) async throws -> RootAgentRuntime {
        let server = await serverRegistry.server(sessionID: sessionID)
        return try await runtime(for: server)
    }

    public func cachedSessionIDs() -> [String] {
        runtimes.keys.sorted()
    }

    public func close(sessionID: String) async {
        guard let runtime = runtimes.removeValue(forKey: sessionID) else {
            return
        }
        await runtime.close()
    }

    public func closeAll() async {
        let allRuntimes = runtimes.values
        runtimes.removeAll()
        for runtime in allRuntimes {
            await runtime.close()
        }
    }

    private func runtime(for server: RootAgentServer) async throws -> RootAgentRuntime {
        if let existing = runtimes[server.sessionID] {
            return existing
        }

        var options = runtimeOptions
        options.sessionID = server.sessionID
        let runtime = try await runtimeFactory(server, stateRoot, options, client, baseProfile)
        runtimes[server.sessionID] = runtime
        return runtime
    }
}
