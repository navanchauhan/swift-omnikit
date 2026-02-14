import Foundation

public struct ModelInfo: Sendable {
    public let id: String
    public let provider: String
    public let displayName: String
    public let contextWindow: Int
    public let maxOutput: Int?
    public let supportsTools: Bool
    public let supportsVision: Bool
    public let supportsReasoning: Bool
    public let inputCostPerMillion: Double?
    public let outputCostPerMillion: Double?
    public let aliases: [String]

    public init(
        id: String,
        provider: String,
        displayName: String,
        contextWindow: Int,
        maxOutput: Int? = nil,
        supportsTools: Bool = true,
        supportsVision: Bool = true,
        supportsReasoning: Bool = false,
        inputCostPerMillion: Double? = nil,
        outputCostPerMillion: Double? = nil,
        aliases: [String] = []
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.contextWindow = contextWindow
        self.maxOutput = maxOutput
        self.supportsTools = supportsTools
        self.supportsVision = supportsVision
        self.supportsReasoning = supportsReasoning
        self.inputCostPerMillion = inputCostPerMillion
        self.outputCostPerMillion = outputCostPerMillion
        self.aliases = aliases
    }
}

public struct ModelCatalog: Sendable {
    public static let models: [ModelInfo] = [
        // Anthropic
        ModelInfo(
            id: "claude-opus-4-6",
            provider: "anthropic",
            displayName: "Claude Opus 4.6",
            contextWindow: 200_000,
            maxOutput: 32_000,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: 15.0,
            outputCostPerMillion: 75.0,
            aliases: ["opus", "claude-opus"]
        ),
        ModelInfo(
            id: "claude-sonnet-4-5-20250929",
            provider: "anthropic",
            displayName: "Claude Sonnet 4.5",
            contextWindow: 200_000,
            maxOutput: 16_000,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: 3.0,
            outputCostPerMillion: 15.0,
            aliases: ["sonnet", "claude-sonnet", "claude-sonnet-4-5"]
        ),
        ModelInfo(
            id: "claude-haiku-4-5-20251001",
            provider: "anthropic",
            displayName: "Claude Haiku 4.5",
            contextWindow: 200_000,
            maxOutput: 8_192,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: false,
            inputCostPerMillion: 0.80,
            outputCostPerMillion: 4.0,
            aliases: ["haiku", "claude-haiku"]
        ),

        // OpenAI
        ModelInfo(
            id: "gpt-4.1",
            provider: "openai",
            displayName: "GPT-4.1",
            contextWindow: 1_047_576,
            maxOutput: 32_768,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: false,
            inputCostPerMillion: 2.0,
            outputCostPerMillion: 8.0,
            aliases: ["gpt-4.1"]
        ),
        ModelInfo(
            id: "gpt-4.1-mini",
            provider: "openai",
            displayName: "GPT-4.1 Mini",
            contextWindow: 1_047_576,
            maxOutput: 32_768,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: false,
            inputCostPerMillion: 0.40,
            outputCostPerMillion: 1.60,
            aliases: ["gpt-4.1-mini"]
        ),
        ModelInfo(
            id: "o4-mini",
            provider: "openai",
            displayName: "o4 mini",
            contextWindow: 200_000,
            maxOutput: 100_000,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: 1.10,
            outputCostPerMillion: 4.40,
            aliases: ["o4-mini"]
        ),
        ModelInfo(
            id: "o3",
            provider: "openai",
            displayName: "o3",
            contextWindow: 200_000,
            maxOutput: 100_000,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: 2.0,
            outputCostPerMillion: 8.0,
            aliases: ["o3"]
        ),

        // Gemini
        ModelInfo(
            id: "gemini-2.5-pro",
            provider: "gemini",
            displayName: "Gemini 2.5 Pro Preview",
            contextWindow: 1_048_576,
            maxOutput: 65_536,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: 1.25,
            outputCostPerMillion: 10.0,
            aliases: ["gemini-2.5-pro", "gemini-pro"]
        ),
        ModelInfo(
            id: "gemini-2.5-flash",
            provider: "gemini",
            displayName: "Gemini 2.5 Flash Preview",
            contextWindow: 1_048_576,
            maxOutput: 65_536,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: 0.15,
            outputCostPerMillion: 0.60,
            aliases: ["gemini-2.5-flash", "gemini-flash"]
        ),
    ]

    public static func getModelInfo(_ modelId: String) -> ModelInfo? {
        models.first { $0.id == modelId } ??
        models.first { $0.aliases.contains(modelId) }
    }

    public static func listModels(provider: String? = nil) -> [ModelInfo] {
        guard let provider = provider else { return models }
        return models.filter { $0.provider == provider }
    }

    public static func getLatestModel(provider: String, capability: String? = nil) -> ModelInfo? {
        let providerModels = models.filter { $0.provider == provider }
        if let capability = capability {
            switch capability {
            case "reasoning":
                return providerModels.first { $0.supportsReasoning }
            case "vision":
                return providerModels.first { $0.supportsVision }
            case "tools":
                return providerModels.first { $0.supportsTools }
            default:
                return providerModels.first
            }
        }
        return providerModels.first
    }
}
