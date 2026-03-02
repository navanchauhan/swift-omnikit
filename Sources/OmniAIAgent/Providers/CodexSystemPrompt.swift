import Foundation

/// Contains the exact Codex CLI system prompts.
///
/// Prompt files are vendored from `openai/codex` and loaded from package resources
/// to keep byte-for-byte parity with upstream text.
public enum CodexSystemPrompt {
    public static let basePrompt = loadPrompt(named: "prompt.md")
    public static let codexModelPrompt = loadPrompt(named: "gpt_5_codex_prompt.md")
    public static let gpt52Prompt = loadPrompt(named: "gpt_5_2_prompt.md")
    public static let gpt51Prompt = loadPrompt(named: "gpt_5_1_prompt.md")
    public static let gpt51CodexMaxPrompt = loadPrompt(named: "gpt-5.1-codex-max_prompt.md")
    public static let applyPatchInstructions = loadPrompt(named: "apply_patch_tool_instructions.md")

    /// The full prompt with apply_patch instructions.
    public static var fullPrompt: String {
        basePrompt + applyPatchInstructions
    }

    /// Returns the appropriate system prompt for a given model ID.
    public static func prompt(for modelId: String) -> String {
        let id = modelId.lowercased()

        if id.contains("gpt-5.1-codex-max") || id.contains("gpt5.1-codex-max") {
            return gpt51CodexMaxPrompt + applyPatchInstructions
        }

        if id.contains("codex") {
            return codexModelPrompt + applyPatchInstructions
        }

        if id.contains("gpt-5.2") || id.contains("gpt5.2") {
            return gpt52Prompt + applyPatchInstructions
        }

        if id.contains("gpt-5.1") || id.contains("gpt5.1") {
            return gpt51Prompt + applyPatchInstructions
        }

        return fullPrompt
    }

    private static func loadPrompt(named filename: String) -> String {
        guard let url = Bundle.module.url(
            forResource: filename,
            withExtension: nil,
            subdirectory: "CodexPrompts"
        ) else {
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
