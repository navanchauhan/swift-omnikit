public enum KnownModels {
    // Ordered by preference within provider (newest/best first).
    public static let all: [ModelInfo] = [
        // Anthropic
        ModelInfo(
            id: "claude-opus-4-6",
            provider: "anthropic",
            displayName: "Claude Opus 4.6",
            contextWindow: 200_000,
            maxOutput: nil,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            aliases: ["opus", "claude-opus"]
        ),
        ModelInfo(
            id: "claude-sonnet-4-5",
            provider: "anthropic",
            displayName: "Claude Sonnet 4.5",
            contextWindow: 200_000,
            maxOutput: nil,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            aliases: ["sonnet", "claude-sonnet"]
        ),

        // OpenAI
        ModelInfo(
            id: "gpt-5.2",
            provider: "openai",
            displayName: "GPT-5.2",
            contextWindow: 1_047_576,
            maxOutput: nil,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            aliases: ["gpt5", "gpt-5", "latest-openai"]
        ),
        ModelInfo(
            id: "gpt-5.2-mini",
            provider: "openai",
            displayName: "GPT-5.2 Mini",
            contextWindow: 1_047_576,
            maxOutput: nil,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            aliases: ["gpt-5-mini"]
        ),
        ModelInfo(
            id: "gpt-5.2-codex",
            provider: "openai",
            displayName: "GPT-5.2 Codex",
            contextWindow: 1_047_576,
            maxOutput: nil,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            aliases: ["codex", "gpt-5-codex"]
        ),

        // Gemini
        ModelInfo(
            id: "gemini-3-pro-preview",
            provider: "gemini",
            displayName: "Gemini 3 Pro (Preview)",
            contextWindow: 1_048_576,
            maxOutput: nil,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            aliases: ["gemini-3-pro", "latest-gemini-pro"]
        ),
        ModelInfo(
            id: "gemini-3-flash-preview",
            provider: "gemini",
            displayName: "Gemini 3 Flash (Preview)",
            contextWindow: 1_048_576,
            maxOutput: nil,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            aliases: ["gemini-3-flash", "latest-gemini"]
        ),
    ]
}

