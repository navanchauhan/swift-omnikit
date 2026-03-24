import Foundation
import OmniAICore
import OmniAgentMesh

public struct HandoffLineage: Sendable, Equatable {
    public var taskID: String?
    public var parentTaskID: String?
    public var summary: String?

    public init(taskID: String? = nil, parentTaskID: String? = nil, summary: String? = nil) {
        self.taskID = taskID
        self.parentTaskID = parentTaskID
        self.summary = summary
    }
}

public struct HandoffInputData: Sendable {
    public var inputHistory: StringOrInputList
    public var preHandoffItems: [any RunItem]
    public var newItems: [any RunItem]
    public var runContext: RunContextWrapper<Any>?
    public var inputItems: [any RunItem]?
    public var historyProjection: HistoryProjection?
    public var lineage: HandoffLineage?

    public init(
        inputHistory: StringOrInputList,
        preHandoffItems: [any RunItem] = [],
        newItems: [any RunItem] = [],
        runContext: RunContextWrapper<Any>? = nil,
        inputItems: [any RunItem]? = nil,
        historyProjection: HistoryProjection? = nil,
        lineage: HandoffLineage? = nil
    ) {
        self.inputHistory = inputHistory
        self.preHandoffItems = preHandoffItems
        self.newItems = newItems
        self.runContext = runContext
        self.inputItems = inputItems
        self.historyProjection = historyProjection
        self.lineage = lineage
    }

    public func clone() -> HandoffInputData {
        HandoffInputData(
            inputHistory: inputHistory,
            preHandoffItems: preHandoffItems,
            newItems: newItems,
            runContext: runContext,
            inputItems: inputItems,
            historyProjection: historyProjection,
            lineage: lineage
        )
    }
}

public typealias HandoffInputFilter = @Sendable (HandoffInputData) async throws -> HandoffInputData
public typealias HandoffHistoryMapper = @Sendable (HandoffInputData) async throws -> [TResponseInputItem]

public struct Handoff<TContext>: @unchecked Sendable {
    public var toolName: String
    public var toolDescription: String
    public var inputJSONSchema: [String: JSONValue]
    public var onInvokeHandoff: @Sendable (RunContextWrapper<TContext>, String) async throws -> Agent<TContext>
    public var agentName: String
    public var inputFilter: HandoffInputFilter?
    public var nestHandoffHistory: Bool?
    public var strictJSONSchema: Bool
    public var isEnabled: ToolEnabledPredicate

    public init(
        toolName: String,
        toolDescription: String,
        inputJSONSchema: [String: JSONValue] = ensureStrictJSONSchema([
            "type": .string("object"),
            "properties": .object(["input": .object(["type": .string("string")])]),
            "required": .array([.string("input")]),
            "additionalProperties": .bool(false),
        ]),
        onInvokeHandoff: @escaping @Sendable (RunContextWrapper<TContext>, String) async throws -> Agent<TContext>,
        agentName: String,
        inputFilter: HandoffInputFilter? = nil,
        nestHandoffHistory: Bool? = nil,
        strictJSONSchema: Bool = true,
        isEnabled: ToolEnabledPredicate = .always(true)
    ) {
        self.toolName = toolName
        self.toolDescription = toolDescription
        self.inputJSONSchema = strictJSONSchema ? ensureStrictJSONSchema(inputJSONSchema) : inputJSONSchema
        self.onInvokeHandoff = onInvokeHandoff
        self.agentName = agentName
        self.inputFilter = inputFilter
        self.nestHandoffHistory = nestHandoffHistory
        self.strictJSONSchema = strictJSONSchema
        self.isEnabled = isEnabled
    }

    public func getTransferMessage() -> String {
        "Transferred to \(agentName)"
    }

    public static func defaultToolName(agent: Agent<TContext>) -> String {
        transformStringFunctionStyle("transfer_to_\(agent.name)")
    }

    public static func defaultToolDescription(agent: Agent<TContext>) -> String {
        let description = agent.handoffDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let description, !description.isEmpty {
            return description
        }
        return "Handoff to \(agent.name)"
    }
}

private final class ConversationHistoryWrapperStore: @unchecked Sendable {
    static let shared = ConversationHistoryWrapperStore()

    private let lock = NSLock()
    private var mapper: HandoffHistoryMapper?

    func set(_ mapper: HandoffHistoryMapper?) {
        lock.lock()
        self.mapper = mapper
        lock.unlock()
    }

    func get() -> HandoffHistoryMapper? {
        lock.lock()
        defer { lock.unlock() }
        return mapper
    }
}

public func setConversationHistoryWrappers(_ mapper: HandoffHistoryMapper?) {
    ConversationHistoryWrapperStore.shared.set(mapper)
}

public func getConversationHistoryWrappers() -> HandoffHistoryMapper? {
    ConversationHistoryWrapperStore.shared.get()
}

public func resetConversationHistoryWrappers() {
    ConversationHistoryWrapperStore.shared.set(nil)
}

public func defaultHandoffHistoryMapper(_ data: HandoffInputData) async throws -> [TResponseInputItem] {
    if let projection = data.historyProjection {
        return [historyProjectionInputItem(projection: projection, lineage: data.lineage)]
    }

    var lines: [String] = []
    switch data.inputHistory {
    case .string(let text):
        lines.append(text)
    case .inputList(let items):
        lines.append(items.map { ItemHelpers.stringifyJSON(.object($0)) }.joined(separator: "\n"))
    }
    let transcript = lines.filter { !$0.isEmpty }.joined(separator: "\n")
    return [[
        "role": .string("assistant"),
        "content": .string(transcript),
    ]]
}

public func nestHandoffHistory(_ data: HandoffInputData) async throws -> [TResponseInputItem] {
    if let mapper = getConversationHistoryWrappers() {
        return try await mapper(data)
    }
    return try await defaultHandoffHistoryMapper(data)
}

public func historyProjectionHandoffHistory(_ data: HandoffInputData) async throws -> [TResponseInputItem] {
    guard let projection = data.historyProjection else {
        return try await defaultHandoffHistoryMapper(data)
    }
    return [historyProjectionInputItem(projection: projection, lineage: data.lineage)]
}

public func handoff<TContext>(
    _ agent: Agent<TContext>,
    toolName: String? = nil,
    toolDescription: String? = nil,
    inputJSONSchema: [String: JSONValue]? = nil,
    inputFilter: HandoffInputFilter? = nil,
    nestHandoffHistory: Bool? = nil,
    strictJSONSchema: Bool = true,
    isEnabled: ToolEnabledPredicate = .always(true)
) -> Handoff<TContext> {
    Handoff(
        toolName: toolName ?? Handoff.defaultToolName(agent: agent),
        toolDescription: toolDescription ?? Handoff.defaultToolDescription(agent: agent),
        inputJSONSchema: inputJSONSchema ?? [
            "type": .string("object"),
            "properties": .object(["input": .object(["type": .string("string")])]),
            "required": .array([.string("input")]),
            "additionalProperties": .bool(false),
        ],
        onInvokeHandoff: { _, _ in agent },
        agentName: agent.name,
        inputFilter: inputFilter,
        nestHandoffHistory: nestHandoffHistory,
        strictJSONSchema: strictJSONSchema,
        isEnabled: isEnabled
    )
}

private func historyProjectionInputItem(
    projection: HistoryProjection,
    lineage: HandoffLineage?
) -> TResponseInputItem {
    var lines: [String] = ["Delegated child context."]
    if let lineage {
        if let taskID = lineage.taskID, !taskID.isEmpty {
            lines.append("Task ID: \(taskID)")
        }
        if let parentTaskID = lineage.parentTaskID, !parentTaskID.isEmpty {
            lines.append("Parent task ID: \(parentTaskID)")
        }
        if let summary = lineage.summary, !summary.isEmpty {
            lines.append("Lineage summary: \(summary)")
        }
    }
    lines.append("Task brief: \(projection.taskBrief)")
    if !projection.summaries.isEmpty {
        lines.append("Relevant summaries:\n" + projection.summaries.map { "- \($0)" }.joined(separator: "\n"))
    }
    if !projection.parentExcerpts.isEmpty {
        lines.append("Parent excerpts:\n" + projection.parentExcerpts.map { "- \($0)" }.joined(separator: "\n"))
    }
    if !projection.artifactRefs.isEmpty {
        lines.append("Artifact references:\n" + projection.artifactRefs.map { "- \($0)" }.joined(separator: "\n"))
    }
    if !projection.constraints.isEmpty {
        lines.append("Constraints:\n" + projection.constraints.map { "- \($0)" }.joined(separator: "\n"))
    }
    if !projection.expectedOutputs.isEmpty {
        lines.append("Expected outputs:\n" + projection.expectedOutputs.map { "- \($0)" }.joined(separator: "\n"))
    }
    return [
        "role": .string("assistant"),
        "content": .string(lines.joined(separator: "\n\n")),
    ]
}
