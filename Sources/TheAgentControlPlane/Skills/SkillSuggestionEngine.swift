import Foundation
import OmniSkills

public struct SkillSuggestionEngine: Sendable {
    public init() {}

    public func suggest(
        for text: String,
        available packages: [OmniSkillPackage]
    ) -> [String] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return []
        }
        return packages.compactMap { package in
            let manifest = package.manifest
            if normalized.localizedStandardContains("/\(manifest.skillID)") {
                return manifest.skillID
            }
            if normalized.localizedStandardContains(manifest.skillID) {
                return manifest.skillID
            }
            if normalized.localizedStandardContains(manifest.displayName) {
                return manifest.skillID
            }
            return nil
        }
    }
}
