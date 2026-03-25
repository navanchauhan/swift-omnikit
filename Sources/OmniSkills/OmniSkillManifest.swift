import Foundation

public enum OmniSkillScope: String, Codable, Sendable, CaseIterable {
    case system
    case workspace
    case mission
}

public enum OmniSkillActivationPolicy: String, Codable, Sendable {
    case explicit
    case suggested
    case autoEligible = "auto_eligible"
}

public enum OmniSkillProjectionSurface: String, Codable, Sendable, CaseIterable {
    case rootPrompt = "root_prompt"
    case toolRegistry = "tool_registry"
    case shellEnv = "shell_env"
    case codergen
    case acp
    case attractor
}

public struct OmniSkillBudgetHints: Codable, Sendable, Equatable {
    public var preferredModelTier: String?
    public var timeoutClass: String?
    public var costClass: String?

    public init(
        preferredModelTier: String? = nil,
        timeoutClass: String? = nil,
        costClass: String? = nil
    ) {
        self.preferredModelTier = preferredModelTier
        self.timeoutClass = timeoutClass
        self.costClass = costClass
    }
}

public struct OmniSkillToolDefinition: Codable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var instructionFile: String?
    public var inlineInstruction: String?

    public init(
        name: String,
        description: String,
        instructionFile: String? = nil,
        inlineInstruction: String? = nil
    ) {
        self.name = name
        self.description = description
        self.instructionFile = instructionFile
        self.inlineInstruction = inlineInstruction
    }
}

public struct OmniSkillManifest: Codable, Sendable, Equatable {
    public var skillID: String
    public var version: String
    public var displayName: String
    public var summary: String
    public var supportedScopes: [OmniSkillScope]
    public var activationPolicy: OmniSkillActivationPolicy
    public var projectionSurfaces: [OmniSkillProjectionSurface]
    public var requiredCapabilities: [String]
    public var allowedDomains: [String]
    public var budgetHints: OmniSkillBudgetHints
    public var promptFile: String?
    public var codergenPromptFile: String?
    public var attractorPromptFile: String?
    public var shellPaths: [String]
    public var workerTools: [OmniSkillToolDefinition]

    public init(
        skillID: String,
        version: String,
        displayName: String,
        summary: String,
        supportedScopes: [OmniSkillScope] = OmniSkillScope.allCases,
        activationPolicy: OmniSkillActivationPolicy = .explicit,
        projectionSurfaces: [OmniSkillProjectionSurface] = [.rootPrompt],
        requiredCapabilities: [String] = [],
        allowedDomains: [String] = [],
        budgetHints: OmniSkillBudgetHints = OmniSkillBudgetHints(),
        promptFile: String? = "prompt.md",
        codergenPromptFile: String? = nil,
        attractorPromptFile: String? = nil,
        shellPaths: [String] = [],
        workerTools: [OmniSkillToolDefinition] = []
    ) {
        self.skillID = skillID
        self.version = version
        self.displayName = displayName
        self.summary = summary
        self.supportedScopes = supportedScopes.isEmpty ? OmniSkillScope.allCases : supportedScopes
        self.activationPolicy = activationPolicy
        self.projectionSurfaces = projectionSurfaces.isEmpty ? [.rootPrompt] : projectionSurfaces
        self.requiredCapabilities = Array(Set(requiredCapabilities)).sorted()
        self.allowedDomains = Array(Set(allowedDomains)).sorted()
        self.budgetHints = budgetHints
        self.promptFile = promptFile
        self.codergenPromptFile = codergenPromptFile
        self.attractorPromptFile = attractorPromptFile
        self.shellPaths = Array(Set(shellPaths)).sorted()
        self.workerTools = workerTools
    }

    public static func load(from url: URL) throws -> OmniSkillManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(OmniSkillManifest.self, from: data)
    }
}
