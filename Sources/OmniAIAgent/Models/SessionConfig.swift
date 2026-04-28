import Foundation

public struct SessionConfig: Sendable, Codable {
    public var maxTurns: Int
    public var maxToolRoundsPerInput: Int
    public var interactiveMode: Bool
    public var defaultCommandTimeoutMs: Int
    public var maxCommandTimeoutMs: Int
    public var reasoningEffort: String?
    public var toolOutputLimits: [String: Int]
    public var toolLineLimits: [String: Int]
    public var enableLoopDetection: Bool
    public var loopDetectionWindow: Int
    public var maxSubagentDepth: Int
    public var userInstructions: String?
    public var llmInactivityTimeoutSeconds: Double?
    public var parallelToolCalls: Bool?
    public var terminalToolNames: [String]
    public var compactOldToolResults: Bool
    public var toolResultCompactionRecentUserTurns: Int
    public var toolResultCompactionMaxChars: Int
    public var toolResultCompactionPreviewChars: Int
    public var mcp: MCPSessionConfig

    public func applyingRuntimeFallbacks(from runtimeConfig: SessionConfig) -> SessionConfig {
        var merged = self
        if merged.llmInactivityTimeoutSeconds == nil {
            merged.llmInactivityTimeoutSeconds = runtimeConfig.llmInactivityTimeoutSeconds
        }
        if merged.parallelToolCalls == nil {
            merged.parallelToolCalls = runtimeConfig.parallelToolCalls
        }
        if merged.terminalToolNames.isEmpty {
            merged.terminalToolNames = runtimeConfig.terminalToolNames
        }
        if !merged.compactOldToolResults {
            merged.compactOldToolResults = runtimeConfig.compactOldToolResults
        }
        if merged.toolResultCompactionRecentUserTurns <= 0 {
            merged.toolResultCompactionRecentUserTurns = runtimeConfig.toolResultCompactionRecentUserTurns
        }
        if merged.toolResultCompactionMaxChars <= 0 {
            merged.toolResultCompactionMaxChars = runtimeConfig.toolResultCompactionMaxChars
        }
        if merged.toolResultCompactionPreviewChars < 0 {
            merged.toolResultCompactionPreviewChars = runtimeConfig.toolResultCompactionPreviewChars
        }
        return merged
    }

    public init(
        maxTurns: Int = 0,
        maxToolRoundsPerInput: Int = 0,
        interactiveMode: Bool = false,
        defaultCommandTimeoutMs: Int = 10_000,
        maxCommandTimeoutMs: Int = 600_000,
        reasoningEffort: String? = nil,
        toolOutputLimits: [String: Int] = [:],
        toolLineLimits: [String: Int] = [:],
        enableLoopDetection: Bool = true,
        loopDetectionWindow: Int = 10,
        maxSubagentDepth: Int = 1,
        userInstructions: String? = nil,
        llmInactivityTimeoutSeconds: Double? = nil,
        parallelToolCalls: Bool? = nil,
        terminalToolNames: [String] = [],
        compactOldToolResults: Bool = false,
        toolResultCompactionRecentUserTurns: Int = 2,
        toolResultCompactionMaxChars: Int = 4_000,
        toolResultCompactionPreviewChars: Int = 700,
        mcp: MCPSessionConfig = MCPSessionConfig()
    ) {
        self.maxTurns = maxTurns
        self.maxToolRoundsPerInput = maxToolRoundsPerInput
        self.interactiveMode = interactiveMode
        self.defaultCommandTimeoutMs = defaultCommandTimeoutMs
        self.maxCommandTimeoutMs = maxCommandTimeoutMs
        self.reasoningEffort = reasoningEffort
        self.toolOutputLimits = toolOutputLimits
        self.toolLineLimits = toolLineLimits
        self.enableLoopDetection = enableLoopDetection
        self.loopDetectionWindow = loopDetectionWindow
        self.maxSubagentDepth = maxSubagentDepth
        self.userInstructions = userInstructions
        self.llmInactivityTimeoutSeconds = llmInactivityTimeoutSeconds
        self.parallelToolCalls = parallelToolCalls
        self.terminalToolNames = terminalToolNames
        self.compactOldToolResults = compactOldToolResults
        self.toolResultCompactionRecentUserTurns = toolResultCompactionRecentUserTurns
        self.toolResultCompactionMaxChars = toolResultCompactionMaxChars
        self.toolResultCompactionPreviewChars = toolResultCompactionPreviewChars
        self.mcp = mcp
    }

    private enum CodingKeys: String, CodingKey {
        case maxTurns
        case maxToolRoundsPerInput
        case interactiveMode
        case defaultCommandTimeoutMs
        case maxCommandTimeoutMs
        case reasoningEffort
        case toolOutputLimits
        case toolLineLimits
        case enableLoopDetection
        case loopDetectionWindow
        case maxSubagentDepth
        case userInstructions
        case llmInactivityTimeoutSeconds
        case parallelToolCalls
        case terminalToolNames
        case compactOldToolResults
        case toolResultCompactionRecentUserTurns
        case toolResultCompactionMaxChars
        case toolResultCompactionPreviewChars
        case mcp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxTurns = try container.decodeIfPresent(Int.self, forKey: .maxTurns) ?? 0
        maxToolRoundsPerInput = try container.decodeIfPresent(Int.self, forKey: .maxToolRoundsPerInput) ?? 0
        interactiveMode = try container.decodeIfPresent(Bool.self, forKey: .interactiveMode) ?? false
        defaultCommandTimeoutMs = try container.decodeIfPresent(Int.self, forKey: .defaultCommandTimeoutMs) ?? 10_000
        maxCommandTimeoutMs = try container.decodeIfPresent(Int.self, forKey: .maxCommandTimeoutMs) ?? 600_000
        reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
        toolOutputLimits = try container.decodeIfPresent([String: Int].self, forKey: .toolOutputLimits) ?? [:]
        toolLineLimits = try container.decodeIfPresent([String: Int].self, forKey: .toolLineLimits) ?? [:]
        enableLoopDetection = try container.decodeIfPresent(Bool.self, forKey: .enableLoopDetection) ?? true
        loopDetectionWindow = try container.decodeIfPresent(Int.self, forKey: .loopDetectionWindow) ?? 10
        maxSubagentDepth = try container.decodeIfPresent(Int.self, forKey: .maxSubagentDepth) ?? 1
        userInstructions = try container.decodeIfPresent(String.self, forKey: .userInstructions)
        llmInactivityTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .llmInactivityTimeoutSeconds)
        parallelToolCalls = try container.decodeIfPresent(Bool.self, forKey: .parallelToolCalls)
        terminalToolNames = try container.decodeIfPresent([String].self, forKey: .terminalToolNames) ?? []
        compactOldToolResults = try container.decodeIfPresent(Bool.self, forKey: .compactOldToolResults) ?? false
        toolResultCompactionRecentUserTurns = try container.decodeIfPresent(Int.self, forKey: .toolResultCompactionRecentUserTurns) ?? 2
        toolResultCompactionMaxChars = try container.decodeIfPresent(Int.self, forKey: .toolResultCompactionMaxChars) ?? 4_000
        toolResultCompactionPreviewChars = try container.decodeIfPresent(Int.self, forKey: .toolResultCompactionPreviewChars) ?? 700
        mcp = try container.decodeIfPresent(MCPSessionConfig.self, forKey: .mcp) ?? MCPSessionConfig()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maxTurns, forKey: .maxTurns)
        try container.encode(maxToolRoundsPerInput, forKey: .maxToolRoundsPerInput)
        try container.encode(interactiveMode, forKey: .interactiveMode)
        try container.encode(defaultCommandTimeoutMs, forKey: .defaultCommandTimeoutMs)
        try container.encode(maxCommandTimeoutMs, forKey: .maxCommandTimeoutMs)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        try container.encode(toolOutputLimits, forKey: .toolOutputLimits)
        try container.encode(toolLineLimits, forKey: .toolLineLimits)
        try container.encode(enableLoopDetection, forKey: .enableLoopDetection)
        try container.encode(loopDetectionWindow, forKey: .loopDetectionWindow)
        try container.encode(maxSubagentDepth, forKey: .maxSubagentDepth)
        try container.encodeIfPresent(userInstructions, forKey: .userInstructions)
        try container.encodeIfPresent(llmInactivityTimeoutSeconds, forKey: .llmInactivityTimeoutSeconds)
        try container.encodeIfPresent(parallelToolCalls, forKey: .parallelToolCalls)
        try container.encode(terminalToolNames, forKey: .terminalToolNames)
        try container.encode(compactOldToolResults, forKey: .compactOldToolResults)
        try container.encode(toolResultCompactionRecentUserTurns, forKey: .toolResultCompactionRecentUserTurns)
        try container.encode(toolResultCompactionMaxChars, forKey: .toolResultCompactionMaxChars)
        try container.encode(toolResultCompactionPreviewChars, forKey: .toolResultCompactionPreviewChars)
        try container.encode(mcp, forKey: .mcp)
    }
}
