import Foundation
import OmniAICore

public let DEFAULT_MAX_TURNS = 10

public func defaultTraceIncludeSensitiveData() -> Bool {
    let value = ProcessInfo.processInfo.environment["OPENAI_AGENTS_TRACE_INCLUDE_SENSITIVE_DATA"] ?? "true"
    return ["1", "true", "yes", "on"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
}

public struct ModelInputData: Sendable, Equatable {
    public var input: [TResponseInputItem]
    public var instructions: String?

    public init(input: [TResponseInputItem], instructions: String?) {
        self.input = input
        self.instructions = instructions
    }
}

public struct CallModelData<TContext>: @unchecked Sendable {
    public var modelData: ModelInputData
    public var agent: Agent<TContext>
    public var context: TContext?

    public init(modelData: ModelInputData, agent: Agent<TContext>, context: TContext?) {
        self.modelData = modelData
        self.agent = agent
        self.context = context
    }
}

public enum ReasoningItemIDPolicy: String, Sendable, Codable, Equatable {
    case preserve
    case omit
}

public struct ToolErrorFormatterArgs<TContext>: Sendable {
    public var kind: String
    public var toolType: String
    public var toolName: String
    public var callID: String
    public var defaultMessage: String
    public var runContext: RunContextWrapper<TContext>

    public init(
        kind: String,
        toolType: String,
        toolName: String,
        callID: String,
        defaultMessage: String,
        runContext: RunContextWrapper<TContext>
    ) {
        self.kind = kind
        self.toolType = toolType
        self.toolName = toolName
        self.callID = callID
        self.defaultMessage = defaultMessage
        self.runContext = runContext
    }
}

public typealias CallModelInputFilter<TContext> = @Sendable (CallModelData<TContext>) async throws -> ModelInputData
public typealias ToolErrorFormatter<TContext> = @Sendable (ToolErrorFormatterArgs<TContext>) async throws -> String?
public typealias SessionInputCallback = @Sendable ([TResponseInputItem], [TResponseInputItem]) async throws -> [TResponseInputItem]

public struct RunConfig: @unchecked Sendable {
    public var model: ModelReference?
    public var modelProvider: any ModelProvider
    public var modelSettings: ModelSettings?
    public var handoffInputFilter: HandoffInputFilter?
    public var nestHandoffHistory: Bool
    public var handoffHistoryMapper: HandoffHistoryMapper?
    public var inputGuardrails: [InputGuardrail<Any>]?
    public var outputGuardrails: [OutputGuardrail<Any>]?
    public var tracingDisabled: Bool
    public var tracing: TracingConfig?
    public var traceIncludeSensitiveData: Bool
    public var workflowName: String
    public var traceID: String?
    public var groupID: String?
    public var traceMetadata: [String: JSONValue]?
    public var sessionInputCallback: SessionInputCallback?
    public var callModelInputFilter: (@Sendable (CallModelData<Any>) async throws -> ModelInputData)?
    public var toolErrorFormatter: (@Sendable (ToolErrorFormatterArgs<Any>) async throws -> String?)?
    public var sessionSettings: SessionSettings?
    public var reasoningItemIDPolicy: ReasoningItemIDPolicy?

    public init(
        model: ModelReference? = nil,
        modelProvider: any ModelProvider = MultiProvider(),
        modelSettings: ModelSettings? = nil,
        handoffInputFilter: HandoffInputFilter? = nil,
        nestHandoffHistory: Bool = false,
        handoffHistoryMapper: HandoffHistoryMapper? = nil,
        inputGuardrails: [InputGuardrail<Any>]? = nil,
        outputGuardrails: [OutputGuardrail<Any>]? = nil,
        tracingDisabled: Bool = false,
        tracing: TracingConfig? = nil,
        traceIncludeSensitiveData: Bool = defaultTraceIncludeSensitiveData(),
        workflowName: String = "Agent workflow",
        traceID: String? = nil,
        groupID: String? = nil,
        traceMetadata: [String: JSONValue]? = nil,
        sessionInputCallback: SessionInputCallback? = nil,
        callModelInputFilter: (@Sendable (CallModelData<Any>) async throws -> ModelInputData)? = nil,
        toolErrorFormatter: (@Sendable (ToolErrorFormatterArgs<Any>) async throws -> String?)? = nil,
        sessionSettings: SessionSettings? = nil,
        reasoningItemIDPolicy: ReasoningItemIDPolicy? = nil
    ) {
        self.model = model
        self.modelProvider = modelProvider
        self.modelSettings = modelSettings
        self.handoffInputFilter = handoffInputFilter
        self.nestHandoffHistory = nestHandoffHistory
        self.handoffHistoryMapper = handoffHistoryMapper
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.tracingDisabled = tracingDisabled
        self.tracing = tracing
        self.traceIncludeSensitiveData = traceIncludeSensitiveData
        self.workflowName = workflowName
        self.traceID = traceID
        self.groupID = groupID
        self.traceMetadata = traceMetadata
        self.sessionInputCallback = sessionInputCallback
        self.callModelInputFilter = callModelInputFilter
        self.toolErrorFormatter = toolErrorFormatter
        self.sessionSettings = sessionSettings
        self.reasoningItemIDPolicy = reasoningItemIDPolicy
    }
}

public struct RunOptions<TContext>: @unchecked Sendable {
    public var context: TContext?
    public var maxTurns: Int
    public var hooks: RunHooks<TContext>?
    public var runConfig: RunConfig?
    public var previousResponseID: String?
    public var autoPreviousResponseID: Bool
    public var conversationID: String?
    public var session: Session?
    public var errorHandlers: RunErrorHandlers<TContext>?

    public init(
        context: TContext? = nil,
        maxTurns: Int = DEFAULT_MAX_TURNS,
        hooks: RunHooks<TContext>? = nil,
        runConfig: RunConfig? = nil,
        previousResponseID: String? = nil,
        autoPreviousResponseID: Bool = false,
        conversationID: String? = nil,
        session: Session? = nil,
        errorHandlers: RunErrorHandlers<TContext>? = nil
    ) {
        self.context = context
        self.maxTurns = maxTurns
        self.hooks = hooks
        self.runConfig = runConfig
        self.previousResponseID = previousResponseID
        self.autoPreviousResponseID = autoPreviousResponseID
        self.conversationID = conversationID
        self.session = session
        self.errorHandlers = errorHandlers
    }
}
