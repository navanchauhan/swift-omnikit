import Foundation

public struct OmniTermStatePaths: Sendable, Equatable {
    public let baseDirectory: URL
    public let imageDirectory: URL
    public let rootDirectory: URL
    public let metadataFile: URL

    public init(
        baseDirectory: URL,
        imageDirectory: URL,
        rootDirectory: URL,
        metadataFile: URL
    ) {
        self.baseDirectory = baseDirectory
        self.imageDirectory = imageDirectory
        self.rootDirectory = rootDirectory
        self.metadataFile = metadataFile
    }
}

private struct OmniTermStateMetadata: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let imageRef: String
}

public enum OmniTermStateStore {
    public static let schemaVersion = 1
    public static let stateDirectoryEnvironmentKey = "OMNITERM_STATE_DIR"

    public static func defaultBaseDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment[stateDirectoryEnvironmentKey], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }

        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        if let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first {
            return cachesDirectory.appending(path: "OmniTerm", directoryHint: .isDirectory)
        }
        #endif

        if let xdgCacheHome = environment["XDG_CACHE_HOME"], !xdgCacheHome.isEmpty {
            return URL(filePath: xdgCacheHome, directoryHint: .isDirectory)
                .appending(path: "OmniTerm", directoryHint: .isDirectory)
        }

        let homePath = environment["HOME"] ?? NSHomeDirectory()
        return URL(filePath: homePath, directoryHint: .isDirectory)
            .appending(path: ".cache", directoryHint: .isDirectory)
            .appending(path: "OmniTerm", directoryHint: .isDirectory)
    }

    public static func paths(
        for imageRef: String,
        baseDirectoryOverride: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> OmniTermStatePaths {
        let baseDirectory =
            baseDirectoryOverride.map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? defaultBaseDirectory(environment: environment)
        let imageDirectory = baseDirectory
            .appending(path: "images", directoryHint: .isDirectory)
            .appending(path: imageKey(for: imageRef), directoryHint: .isDirectory)

        return OmniTermStatePaths(
            baseDirectory: baseDirectory,
            imageDirectory: imageDirectory,
            rootDirectory: imageDirectory.appending(path: "rootfs", directoryHint: .isDirectory),
            metadataFile: imageDirectory.appending(path: "state.json")
        )
    }

    public static func preparePaths(
        for imageRef: String,
        baseDirectoryOverride: String? = nil,
        reset: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> OmniTermStatePaths {
        let statePaths = paths(
            for: imageRef,
            baseDirectoryOverride: baseDirectoryOverride,
            environment: environment
        )

        try fileManager.createDirectory(
            at: statePaths.baseDirectory,
            withIntermediateDirectories: true
        )

        if reset || shouldResetExistingState(at: statePaths, imageRef: imageRef, fileManager: fileManager) {
            if fileManager.fileExists(atPath: statePaths.imageDirectory.path) {
                try fileManager.removeItem(at: statePaths.imageDirectory)
            }
        }

        try fileManager.createDirectory(
            at: statePaths.imageDirectory,
            withIntermediateDirectories: true
        )

        return statePaths
    }

    public static func isInitialized(
        at statePaths: OmniTermStatePaths,
        imageRef: String,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: statePaths.rootDirectory.path) else {
            return false
        }

        guard let data = try? Data(contentsOf: statePaths.metadataFile),
            let metadata = try? JSONDecoder().decode(OmniTermStateMetadata.self, from: data)
        else {
            return false
        }

        return metadata == OmniTermStateMetadata(
            schemaVersion: schemaVersion,
            imageRef: imageRef
        )
    }

    public static func markInitialized(
        at statePaths: OmniTermStatePaths,
        imageRef: String,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: statePaths.imageDirectory,
            withIntermediateDirectories: true
        )

        let metadata = OmniTermStateMetadata(
            schemaVersion: schemaVersion,
            imageRef: imageRef
        )
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: statePaths.metadataFile, options: .atomic)
    }

    public static func clearEphemeralDirectories(
        in statePaths: OmniTermStatePaths,
        relativePaths: [String] = ["tmp", "var/tmp"],
        fileManager: FileManager = .default
    ) throws {
        for relativePath in relativePaths {
            let directoryURL = statePaths.rootDirectory.appending(
                path: relativePath,
                directoryHint: .isDirectory
            )
            if fileManager.fileExists(atPath: directoryURL.path) {
                let contents = try fileManager.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: nil
                )
                for itemURL in contents {
                    try fileManager.removeItem(at: itemURL)
                }
            } else {
                try fileManager.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
            }
        }
    }

    public static func writeFile(
        relativePath: String,
        contents: String,
        in statePaths: OmniTermStatePaths,
        fileManager: FileManager = .default
    ) throws {
        let fileURL = statePaths.rootDirectory.appending(path: relativePath)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: fileURL, options: .atomic)
    }

    private static func shouldResetExistingState(
        at statePaths: OmniTermStatePaths,
        imageRef: String,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: statePaths.imageDirectory.path) else {
            return false
        }

        return !isInitialized(at: statePaths, imageRef: imageRef, fileManager: fileManager)
    }

    private static func imageKey(for imageRef: String) -> String {
        let slug = String(
            imageRef.lowercased()
                .map { character in
                    if character.isLetter || character.isNumber {
                        return character
                    }
                    return "-"
                }
        )
        let normalizedSlug = slug
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let prefix = normalizedSlug.isEmpty ? "image" : String(normalizedSlug.prefix(48))
        let hash = String(fnv1a64(imageRef), radix: 16)
        return "\(prefix)-\(hash)"
    }

    private static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}
