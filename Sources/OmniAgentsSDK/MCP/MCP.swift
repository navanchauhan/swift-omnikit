import Foundation

public protocol MCPServer: Sendable {
    var name: String { get }
    func connect() async throws
    func cleanup() async
    func listTools() async throws -> [Tool]
}

public final class MCPServerManager: @unchecked Sendable {
    private let lock = NSLock()
    private var servers: [any MCPServer]

    public init(servers: [any MCPServer] = []) {
        self.servers = servers
    }

    public func addServer(_ server: any MCPServer) {
        lock.lock(); servers.append(server); lock.unlock()
    }

    public func connectAll() async throws {
        let current = lock.withLock { servers }
        for server in current {
            try await server.connect()
        }
    }

    public func cleanupAll() async {
        let current = lock.withLock { servers }
        for server in current {
            await server.cleanup()
        }
    }
}

public enum MCPUtil {
    public static func getAllFunctionTools(
        servers: [any MCPServer],
        convertSchemasToStrict: Bool,
        runContext: RunContextWrapper<Any>,
        agent: Any,
        failureErrorFunction: ToolErrorFunction? = defaultToolErrorFunction
    ) async throws -> [Tool] {
        var tools: [Tool] = []
        for server in servers {
            let serverTools = try await server.listTools()
            if convertSchemasToStrict {
                tools.append(contentsOf: serverTools.map { tool in
                    guard case .function(let functionTool) = tool else { return tool }
                    return .function(FunctionTool(
                        name: functionTool.name,
                        description: functionTool.description,
                        paramsJSONSchema: ensureStrictJSONSchema(functionTool.paramsJSONSchema),
                        onInvokeTool: functionTool.onInvokeTool,
                        strictJSONSchema: true,
                        isEnabled: functionTool.isEnabled,
                        toolInputGuardrails: functionTool.toolInputGuardrails,
                        toolOutputGuardrails: functionTool.toolOutputGuardrails,
                        needsApproval: functionTool.needsApproval,
                        timeoutSeconds: functionTool.timeoutSeconds,
                        timeoutBehavior: functionTool.timeoutBehavior,
                        timeoutErrorFunction: functionTool.timeoutErrorFunction,
                        isAgentTool: functionTool.isAgentTool,
                        isCodexTool: functionTool.isCodexTool,
                        agentInstance: functionTool.agentInstance
                    ))
                })
            } else {
                tools.append(contentsOf: serverTools)
            }
        }
        return tools
    }
}

public typealias MCPManager = MCPServerManager

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

