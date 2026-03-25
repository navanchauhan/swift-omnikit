import Foundation
import OmniAgentMesh

public struct OmniSkillRegistry {
    public let skillsRootDirectory: URL?

    public init(skillsRootDirectory: URL? = nil) {
        self.skillsRootDirectory = skillsRootDirectory
    }

    public func loadInstalledPackages(
        from installations: [SkillInstallationRecord]
    ) throws -> [OmniSkillPackage] {
        try installations.compactMap { record in
            let root = URL(fileURLWithPath: record.installedPath, isDirectory: true)
            let manifestURL = root.appending(path: "omniskill.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path()) else {
                return nil
            }
            let manifest = try OmniSkillManifest.load(from: manifestURL)
            return OmniSkillPackage(
                manifest: manifest,
                rootDirectory: root,
                sourceDescription: record.sourcePath
            )
        }
    }

    public func resolveSkill(
        named name: String,
        workingDirectory: URL
    ) throws -> OmniSkillPackage? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }
        let candidates = try availablePackages(in: workingDirectory)
        return candidates.first(where: {
            $0.manifest.skillID == normalized ||
            $0.manifest.displayName.localizedStandardContains(normalized)
        })
    }

    public func availablePackages(in workingDirectory: URL) throws -> [OmniSkillPackage] {
        var packages: [OmniSkillPackage] = []

        let canonicalRoot = workingDirectory.appending(path: "skills", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: canonicalRoot.path()) {
            let manifestPaths = try FileManager.default.contentsOfDirectory(
                at: canonicalRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for entry in manifestPaths {
                let manifestURL = entry.appending(path: "omniskill.json")
                guard FileManager.default.fileExists(atPath: manifestURL.path()) else {
                    continue
                }
                let manifest = try OmniSkillManifest.load(from: manifestURL)
                packages.append(
                    OmniSkillPackage(
                        manifest: manifest,
                        rootDirectory: entry,
                        sourceDescription: entry.path()
                    )
                )
            }
        }

        packages.append(contentsOf: try ClaudeCommandImporter.importSkills(from: workingDirectory))
        packages.append(contentsOf: try GeminiSkillImporter.importSkills(from: workingDirectory))
        return deduplicated(packages)
    }

    private func deduplicated(_ packages: [OmniSkillPackage]) -> [OmniSkillPackage] {
        var seen: Set<String> = []
        var result: [OmniSkillPackage] = []
        for package in packages.sorted(by: { $0.manifest.skillID < $1.manifest.skillID }) {
            let key = "\(package.manifest.skillID)@\(package.manifest.version)"
            guard seen.insert(key).inserted else {
                continue
            }
            result.append(package)
        }
        return result
    }
}
