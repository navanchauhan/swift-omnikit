import Foundation

public struct OmniSkillPackage: Sendable, Equatable {
    public var manifest: OmniSkillManifest
    public var rootDirectory: URL?
    public var inlineAssets: [String: String]
    public var sourceDescription: String

    public init(
        manifest: OmniSkillManifest,
        rootDirectory: URL? = nil,
        inlineAssets: [String: String] = [:],
        sourceDescription: String
    ) {
        self.manifest = manifest
        self.rootDirectory = rootDirectory
        self.inlineAssets = inlineAssets
        self.sourceDescription = sourceDescription
    }

    public func textAsset(at relativePath: String?) throws -> String? {
        guard let relativePath, !relativePath.isEmpty else {
            return nil
        }
        if let inline = inlineAssets[relativePath] {
            return inline
        }
        guard let rootDirectory else {
            return nil
        }
        let url = rootDirectory.appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: url.path()) else {
            return nil
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func shellURLs() -> [URL] {
        guard let rootDirectory else {
            return []
        }
        return manifest.shellPaths.map { rootDirectory.appending(path: $0) }
    }
}
