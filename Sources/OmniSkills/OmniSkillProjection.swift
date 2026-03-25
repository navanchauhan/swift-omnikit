import Foundation

public struct OmniSkillShellProjection: Codable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var path: String

    public init(name: String, description: String, path: String) {
        self.name = name
        self.description = description
        self.path = path
    }
}

public struct OmniSkillWorkerToolProjection: Codable, Sendable, Equatable {
    public var skillID: String
    public var name: String
    public var description: String
    public var instruction: String

    public init(skillID: String, name: String, description: String, instruction: String) {
        self.skillID = skillID
        self.name = name
        self.description = description
        self.instruction = instruction
    }
}

public struct OmniSkillProjectionBundle: Sendable, Equatable {
    public struct SkillRef: Sendable, Equatable {
        public var skillID: String
        public var version: String
        public var displayName: String
        public var summary: String

        public init(skillID: String, version: String, displayName: String, summary: String) {
            self.skillID = skillID
            self.version = version
            self.displayName = displayName
            self.summary = summary
        }
    }

    public var activeSkills: [SkillRef]
    public var promptOverlay: String
    public var codergenOverlay: String
    public var attractorOverlay: String
    public var shellSkills: [OmniSkillShellProjection]
    public var workerTools: [OmniSkillWorkerToolProjection]
    public var requiredCapabilities: [String]
    public var allowedDomains: [String]
    public var preferredModelTier: String?

    public init(
        activeSkills: [SkillRef] = [],
        promptOverlay: String = "",
        codergenOverlay: String = "",
        attractorOverlay: String = "",
        shellSkills: [OmniSkillShellProjection] = [],
        workerTools: [OmniSkillWorkerToolProjection] = [],
        requiredCapabilities: [String] = [],
        allowedDomains: [String] = [],
        preferredModelTier: String? = nil
    ) {
        self.activeSkills = activeSkills
        self.promptOverlay = promptOverlay
        self.codergenOverlay = codergenOverlay
        self.attractorOverlay = attractorOverlay
        self.shellSkills = shellSkills
        self.workerTools = workerTools
        self.requiredCapabilities = Array(Set(requiredCapabilities)).sorted()
        self.allowedDomains = Array(Set(allowedDomains)).sorted()
        self.preferredModelTier = preferredModelTier
    }

    public var activeSkillIDs: [String] {
        activeSkills.map(\.skillID)
    }
}

public enum OmniSkillProjectionCompiler {
    public static func compile(
        packages: [OmniSkillPackage]
    ) throws -> OmniSkillProjectionBundle {
        var refs: [OmniSkillProjectionBundle.SkillRef] = []
        var promptSections: [String] = []
        var codergenSections: [String] = []
        var attractorSections: [String] = []
        var shellSkills: [OmniSkillShellProjection] = []
        var workerTools: [OmniSkillWorkerToolProjection] = []
        var requiredCapabilities: [String] = []
        var allowedDomains: [String] = []
        var preferredModelTier: String?

        for package in packages.sorted(by: { $0.manifest.skillID < $1.manifest.skillID }) {
            let manifest = package.manifest
            refs.append(
                OmniSkillProjectionBundle.SkillRef(
                    skillID: manifest.skillID,
                    version: manifest.version,
                    displayName: manifest.displayName,
                    summary: manifest.summary
                )
            )
            if manifest.projectionSurfaces.contains(.rootPrompt),
               let overlay = try package.textAsset(at: manifest.promptFile),
               !overlay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                promptSections.append("# \(manifest.displayName)\n\(overlay)")
            }
            let codergenPath = manifest.codergenPromptFile ?? manifest.promptFile
            if manifest.projectionSurfaces.contains(.codergen),
               let overlay = try package.textAsset(at: codergenPath),
               !overlay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                codergenSections.append("# \(manifest.displayName)\n\(overlay)")
            }
            let attractorPath = manifest.attractorPromptFile ?? manifest.codergenPromptFile ?? manifest.promptFile
            if manifest.projectionSurfaces.contains(.attractor),
               let overlay = try package.textAsset(at: attractorPath),
               !overlay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                attractorSections.append("# \(manifest.displayName)\n\(overlay)")
            }
            if manifest.projectionSurfaces.contains(.shellEnv) {
                for url in package.shellURLs() {
                    shellSkills.append(
                        OmniSkillShellProjection(
                            name: manifest.skillID,
                            description: manifest.summary,
                            path: url.path()
                        )
                    )
                }
            }
            if manifest.projectionSurfaces.contains(.toolRegistry) {
                for tool in manifest.workerTools {
                    let instruction = try resolveInstruction(for: tool, in: package)
                    workerTools.append(
                        OmniSkillWorkerToolProjection(
                            skillID: manifest.skillID,
                            name: tool.name,
                            description: tool.description,
                            instruction: instruction
                        )
                    )
                }
            }
            requiredCapabilities.append(contentsOf: manifest.requiredCapabilities)
            allowedDomains.append(contentsOf: manifest.allowedDomains)
            preferredModelTier = preferredModelTier ?? manifest.budgetHints.preferredModelTier
        }

        return OmniSkillProjectionBundle(
            activeSkills: refs,
            promptOverlay: promptSections.joined(separator: "\n\n"),
            codergenOverlay: codergenSections.joined(separator: "\n\n"),
            attractorOverlay: attractorSections.joined(separator: "\n\n"),
            shellSkills: shellSkills,
            workerTools: workerTools,
            requiredCapabilities: requiredCapabilities,
            allowedDomains: allowedDomains,
            preferredModelTier: preferredModelTier
        )
    }

    private static func resolveInstruction(
        for definition: OmniSkillToolDefinition,
        in package: OmniSkillPackage
    ) throws -> String {
        if let inlineInstruction = definition.inlineInstruction,
           !inlineInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return inlineInstruction
        }
        if let fileInstruction = try package.textAsset(at: definition.instructionFile),
           !fileInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fileInstruction
        }
        return "Use \(definition.name) from skill \(package.manifest.skillID)."
    }
}
