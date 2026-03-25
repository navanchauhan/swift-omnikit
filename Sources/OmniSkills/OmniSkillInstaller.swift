import Foundation
import OmniAgentMesh

public enum OmniSkillInstallerError: Error, CustomStringConvertible {
    case manifestNotFound(URL)
    case unsupportedArchive(URL)
    case unzipFailed(URL)

    public var description: String {
        switch self {
        case .manifestNotFound(let url):
            return "No omniskill.json manifest was found at \(url.path())."
        case .unsupportedArchive(let url):
            return "Archive installs currently support only .zip inputs. Received \(url.lastPathComponent)."
        case .unzipFailed(let url):
            return "Failed to extract OmniSkill archive \(url.path())."
        }
    }
}

public struct OmniSkillInstaller {
    public let installsRootDirectory: URL

    public init(installsRootDirectory: URL) {
        self.installsRootDirectory = installsRootDirectory
    }

    public func install(
        from sourceURL: URL,
        scope: SkillInstallationRecord.Scope,
        workspaceID: WorkspaceID? = nil,
        now: Date = Date()
    ) throws -> SkillInstallationRecord {
        let prepared = try preparedSource(from: sourceURL)
        let manifestURL = prepared.directory.appending(path: "omniskill.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path()) else {
            throw OmniSkillInstallerError.manifestNotFound(prepared.directory)
        }

        let manifest = try OmniSkillManifest.load(from: manifestURL)
        let destination = installsRootDirectory
            .appending(path: scope.rawValue, directoryHint: .isDirectory)
            .appending(path: workspaceID?.rawValue ?? "_shared", directoryHint: .isDirectory)
            .appending(path: manifest.skillID, directoryHint: .isDirectory)
            .appending(path: manifest.version, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path()) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: prepared.directory, to: destination)

        let digest = try contentDigest(for: destination)
        return SkillInstallationRecord(
            skillID: manifest.skillID,
            version: manifest.version,
            scope: scope,
            workspaceID: workspaceID,
            sourceType: prepared.sourceType,
            sourcePath: sourceURL.path(),
            installedPath: destination.path(),
            digest: digest,
            metadata: [
                "display_name": manifest.displayName,
                "summary": manifest.summary,
            ],
            createdAt: now,
            updatedAt: now
        )
    }

    private func preparedSource(
        from sourceURL: URL
    ) throws -> (directory: URL, sourceType: SkillInstallationRecord.SourceType) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: sourceURL.path(), isDirectory: &isDirectory), isDirectory.boolValue {
            return (sourceURL, .localDirectory)
        }
        guard sourceURL.pathExtension.lowercased() == "zip" else {
            throw OmniSkillInstallerError.unsupportedArchive(sourceURL)
        }
        let extractionRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appending(path: "omniskill-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["unzip", "-q", sourceURL.path(), "-d", extractionRoot.path()]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw OmniSkillInstallerError.unzipFailed(sourceURL)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: extractionRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        if let directManifest = contents.first(where: { $0.lastPathComponent == "omniskill.json" }) {
            return (directManifest.deletingLastPathComponent(), .localArchive)
        }
        if let directory = contents.first(where: {
            FileManager.default.fileExists(atPath: $0.appending(path: "omniskill.json").path())
        }) {
            return (directory, .localArchive)
        }
        throw OmniSkillInstallerError.manifestNotFound(extractionRoot)
    }

    private func contentDigest(for directory: URL) throws -> String {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var digest: UInt64 = 14695981039346656037
        let prime: UInt64 = 1099511628211

        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            let relativePath = url.path().replacingOccurrences(of: directory.path() + "/", with: "")
            for byte in relativePath.utf8 {
                digest ^= UInt64(byte)
                digest = digest &* prime
            }
            let data = try Data(contentsOf: url)
            for byte in data {
                digest ^= UInt64(byte)
                digest = digest &* prime
            }
        }
        return String(digest, radix: 16)
    }
}
