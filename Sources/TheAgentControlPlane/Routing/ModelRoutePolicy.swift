import Foundation

public struct ModelRoutePolicy: Sendable, Equatable {
    public enum Tier: String, CaseIterable, Sendable {
        case chatLight = "chat_light"
        case chatDeep = "chat_deep"
        case planner
        case implementer
        case reviewer
        case vision
        case codergen
    }

    public struct Entry: Sendable, Equatable {
        public var provider: String
        public var model: String
        public var reasoningEffort: String

        public init(
            provider: String,
            model: String,
            reasoningEffort: String
        ) {
            self.provider = provider
            self.model = model
            self.reasoningEffort = reasoningEffort
        }
    }

    public var entries: [Tier: Entry]

    public init(entries: [Tier: Entry] = Self.defaultEntries) {
        self.entries = entries
    }

    public static let defaultEntries: [Tier: Entry] = [
        .chatLight: Entry(provider: "openai", model: "gpt-5.4", reasoningEffort: "medium"),
        .chatDeep: Entry(provider: "openai", model: "gpt-5.4", reasoningEffort: "high"),
        .planner: Entry(provider: "openai", model: "gpt-5.4", reasoningEffort: "high"),
        .implementer: Entry(provider: "openai", model: "gpt-5.4", reasoningEffort: "high"),
        .reviewer: Entry(provider: "openai", model: "gpt-5.4", reasoningEffort: "medium"),
        .vision: Entry(provider: "openai", model: "gpt-5.4", reasoningEffort: "high"),
        .codergen: Entry(provider: "openai", model: "gpt-5.3-codex", reasoningEffort: "high"),
    ]
}
