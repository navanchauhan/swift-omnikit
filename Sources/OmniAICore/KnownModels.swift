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

        // Cerebras
        ModelInfo(
            id: "zai-glm-4.7",
            provider: "cerebras",
            displayName: "Z.AI GLM 4.7 (Preview)",
            contextWindow: 131_072,
            maxOutput: nil,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            aliases: ["glm-4.7", "latest-cerebras"]
        ),
        ModelInfo(
            id: "qwen-3-235b-a22b-instruct-2507",
            provider: "cerebras",
            displayName: "Qwen 3 235B A22B Instruct 2507",
            contextWindow: 131_072,
            maxOutput: nil,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            aliases: ["qwen-3-235b"]
        ),
        ModelInfo(
            id: "gpt-oss-120b",
            provider: "cerebras",
            displayName: "GPT-OSS 120B",
            contextWindow: 131_072,
            maxOutput: nil,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            aliases: ["gpt-oss", "oss-120b"]
        ),
        ModelInfo(
            id: "qwen-3-32b",
            provider: "cerebras",
            displayName: "Qwen 3 32B",
            contextWindow: 131_072,
            maxOutput: nil,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            aliases: ["qwen-3", "qwen-32b"]
        ),
        ModelInfo(
            id: "llama-3.3-70b",
            provider: "cerebras",
            displayName: "Llama 3.3 70B",
            contextWindow: 131_072,
            maxOutput: nil,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            aliases: ["llama-3.3", "llama-70b"]
        ),
        ModelInfo(
            id: "llama3.1-8b",
            provider: "cerebras",
            displayName: "Llama 3.1 8B",
            contextWindow: 131_072,
            maxOutput: nil,
            supportsTools: true,
            supportsVision: true,
            supportsReasoning: true,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            aliases: ["llama-3.1", "llama-8b"]
        ),
    ]
}
