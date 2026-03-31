import Foundation

public protocol ReleaseBundleStore: Sendable {
    func saveBundle(_ bundle: ReleaseBundle) async throws
    func bundle(bundleID: String) async throws -> ReleaseBundle?
    func listBundles() async throws -> [ReleaseBundle]
}

public actor FileReleaseBundleStore: ReleaseBundleStore {
    private let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    public func saveBundle(_ bundle: ReleaseBundle) async throws {
        let fileURL = rootDirectory.appending(path: "\(bundle.bundleID).json")
        try encoder.encode(bundle).write(to: fileURL, options: .atomic)
    }

    public func bundle(bundleID: String) async throws -> ReleaseBundle? {
        let fileURL = rootDirectory.appending(path: "\(bundleID).json")
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(ReleaseBundle.self, from: data)
    }

    public func listBundles() async throws -> [ReleaseBundle] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var bundles: [(Date, ReleaseBundle)] = []
        for url in urls where url.pathExtension == "json" {
            let data = try Data(contentsOf: url)
            let bundle = try decoder.decode(ReleaseBundle.self, from: data)
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            bundles.append((values.contentModificationDate ?? .distantPast, bundle))
        }
        return bundles
            .sorted { lhs, rhs in lhs.0 > rhs.0 }
            .map(\.1)
    }
}
