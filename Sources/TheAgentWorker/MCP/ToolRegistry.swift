import Foundation
import OmniAICore
import OmniACPModel
import OmniMCP

public enum WorkerToolError: Error, Sendable, Equatable {
    case duplicateTool(String)
    case unknownTool(String)
}

public struct WorkerTool: Sendable {
    public typealias Handler = @Sendable (JSONValue) async throws -> JSONValue

    public var name: String
    public var description: String
    public var inputSchema: JSONValue
    public var handler: Handler

    public init(
        name: String,
        description: String,
        inputSchema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false),
        ]),
        handler: @escaping Handler
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.handler = handler
    }

    public var mcpDefinition: MCPToolDefinition {
        MCPToolDefinition(name: name, description: description, inputSchema: inputSchema)
    }
}

public actor ToolRegistry {
    private var tools: [String: WorkerTool] = [:]

    public init(tools: [WorkerTool] = []) throws {
        for tool in tools {
            guard self.tools[tool.name] == nil else {
                throw WorkerToolError.duplicateTool(tool.name)
            }
            self.tools[tool.name] = tool
        }
    }

    public func register(_ tool: WorkerTool) throws {
        guard tools[tool.name] == nil else {
            throw WorkerToolError.duplicateTool(tool.name)
        }
        tools[tool.name] = tool
    }

    public func tool(named name: String) -> WorkerTool? {
        tools[name]
    }

    public func listTools() -> [MCPToolDefinition] {
        tools.values
            .map(\.mcpDefinition)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func callTool(name: String, arguments: JSONValue) async throws -> MCPToolCallResult {
        guard let tool = tools[name] else {
            throw WorkerToolError.unknownTool(name)
        }
        let content = try await tool.handler(arguments)
        return MCPToolCallResult(content: content, isError: false)
    }

    public func makeACPServers(
        serverName: String = "worker-tools",
        command: String = "worker-mcp-server",
        arguments: [String] = []
    ) -> [OmniACPModel.MCPServer] {
        let names = tools.keys.sorted()
        let environment = [
            "OMNIKIT_WORKER_MCP_SERVER=\(serverName)",
            "OMNIKIT_WORKER_MCP_TOOLS=\(names.joined(separator: ","))",
        ]
        return [
            OmniACPModel.MCPServer(
                name: serverName,
                command: command,
                args: arguments,
                env: environment
            ),
        ]
    }
}
