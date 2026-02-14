import Foundation

public struct GenerateResult: Sendable {
    public var text: String
    public var reasoning: String?
    public var toolCalls: [ToolCall]
    public var toolResults: [ToolResult]
    public var finishReason: FinishReason
    public var usage: Usage
    public var totalUsage: Usage
    public var steps: [StepResult]
    public var response: Response
    public var output: AnyCodable?

    public init(
        text: String,
        reasoning: String? = nil,
        toolCalls: [ToolCall] = [],
        toolResults: [ToolResult] = [],
        finishReason: FinishReason,
        usage: Usage,
        totalUsage: Usage,
        steps: [StepResult],
        response: Response,
        output: AnyCodable? = nil
    ) {
        self.text = text
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.finishReason = finishReason
        self.usage = usage
        self.totalUsage = totalUsage
        self.steps = steps
        self.response = response
        self.output = output
    }
}

public struct StepResult: Sendable {
    public var text: String
    public var reasoning: String?
    public var toolCalls: [ToolCall]
    public var toolResults: [ToolResult]
    public var finishReason: FinishReason
    public var usage: Usage
    public var response: Response
    public var warnings: [Warning]

    public init(
        text: String,
        reasoning: String? = nil,
        toolCalls: [ToolCall] = [],
        toolResults: [ToolResult] = [],
        finishReason: FinishReason,
        usage: Usage,
        response: Response,
        warnings: [Warning] = []
    ) {
        self.text = text
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.finishReason = finishReason
        self.usage = usage
        self.response = response
        self.warnings = warnings
    }
}
