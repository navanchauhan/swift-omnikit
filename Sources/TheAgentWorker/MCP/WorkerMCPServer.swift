import Foundation
import OmniACPModel
import OmniAICore
import OmniMCP

public actor WorkerMCPServer: OmniMCP.MCPServer {
    public nonisolated let name: String

    private let registry: ToolRegistry
    private var connected = false

    public init(name: String = "worker-tools", registry: ToolRegistry) {
        self.name = name
        self.registry = registry
    }

    public func connect() async throws {
        connected = true
    }

    public func cleanup() async {
        connected = false
    }

    public func listTools() async throws -> [MCPToolDefinition] {
        if !connected {
            try await connect()
        }
        return await registry.listTools()
    }

    public func callTool(name: String, arguments: JSONValue) async throws -> MCPToolCallResult {
        if !connected {
            try await connect()
        }
        return try await registry.callTool(name: name, arguments: arguments)
    }

    public func acpServerDescriptors(
        command: String = "worker-mcp-server",
        arguments: [String] = []
    ) async -> [OmniACPModel.MCPServer] {
        await registry.makeACPServers(serverName: name, command: command, arguments: arguments)
    }
}
