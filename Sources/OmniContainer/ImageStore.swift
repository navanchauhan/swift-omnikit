import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OmniVFS

/// Actor that manages Alpine rootfs images, caching them as TarFS instances.
public actor ImageStore {
    public static let shared = ImageStore()

    private var cache: [String: any VFS] = [:]
    private let cacheDir: URL

    /// Alpine minirootfs manifest -- pinned version + SHA256.
    private struct ImageManifest: Sendable {
        let version: String
        let arch: String
        let sha256: String
        let url: String
    }

    private static let alpineManifest = ImageManifest(
        version: "3.21.3",
        arch: "x86_64",
        sha256: "4e9e728e25e64928a0e2ddfe7e68ead64e2e3e3db041ed448a30f7eea1a0ad93",
        url: "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-minirootfs-3.21.3-x86_64.tar.gz"
    )

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.cacheDir = home.appendingPathComponent(".omnikit/images")
    }

    /// Resolve an image reference to a VFS (TarFS backed by cached rootfs).
    public func resolve(_ ref: String) async throws -> any VFS {
        if let cached = cache[ref] { return cached }

        let tarData = try await fetchOrLoadFromDisk(ref)
        let decompressed = try decompressGzip(tarData)
        let tarFS = try TarFS(data: Array(decompressed))
        cache[ref] = tarFS
        return tarFS
    }

    private func fetchOrLoadFromDisk(_ ref: String) async throws -> Data {
        // Check disk cache
        let cacheFile = cacheDir.appendingPathComponent(sanitizeRef(ref) + ".tar.gz")
        if FileManager.default.fileExists(atPath: cacheFile.path) {
            return try Data(contentsOf: cacheFile)
        }

        // Download
        let manifest = Self.alpineManifest
        guard let url = URL(string: manifest.url) else {
            throw VFSError.notFound("Invalid URL for image: \(ref)")
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        // TODO: Verify SHA256 (use CryptoKit or CC_SHA256 in real impl)

        // Cache to disk
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try data.write(to: cacheFile)

        return data
    }

    private func sanitizeRef(_ ref: String) -> String {
        ref.replacingOccurrences(of: "/", with: "_")
           .replacingOccurrences(of: ":", with: "_")
    }

    private func decompressGzip(_ data: Data) throws -> Data {
        // Shell out to gunzip for reliable gzip decompression
        let tempIn = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tar.gz")
        try data.write(to: tempIn)
        defer { try? FileManager.default.removeItem(at: tempIn) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", tempIn.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let decompressed = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw VFSError.notSupported("gunzip failed with exit code \(process.terminationStatus)")
        }

        return decompressed
    }
}
