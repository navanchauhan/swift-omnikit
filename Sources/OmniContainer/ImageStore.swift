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
        sha256: "1a694899e406ce55d32334c47ac0b2efb6c06d7e878102d1840892ad44cd5239",
        url: "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-minirootfs-3.21.3-x86_64.tar.gz"
    )

    public init() {
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        self.cacheDir = URL.cachesDirectory.appending(path: "omnikit/images", directoryHint: .isDirectory)
#else
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.cacheDir = home.appending(path: ".omnikit/images", directoryHint: .isDirectory)
#endif
    }

    /// Resolve an image reference to a VFS (TarFS backed by cached rootfs).
    public func resolve(_ ref: String) async throws -> any VFS {
        if let cached = cache[ref] { return cached }

        let tarData = try await bundledOrCachedArchiveData(for: ref)
        let decompressed = try decompressGzip(tarData)
        let tarFS = try TarFS(data: Array(decompressed))
        cache[ref] = tarFS
        return tarFS
    }

    private func bundledOrCachedArchiveData(for ref: String) async throws -> Data {
        if let bundledData = try bundledArchiveData(for: ref) {
            return bundledData
        }

        // Check disk cache
        let cacheFile = cacheDir.appending(path: sanitizeRef(ref) + ".tar.gz")
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

    private func bundledArchiveData(for ref: String) throws -> Data? {
        let resourceName: String
        switch ref {
        case "alpine:minirootfs":
            resourceName = "alpine-minirootfs-3.21.3-x86_64"
        case "alpine:codex-ios":
            resourceName = "alpine-codex-ios-3.21.3-x86_64"
        default:
            return nil
        }

        guard let archiveURL = Bundle.module.url(
            forResource: resourceName,
            withExtension: "tar.gz"
        ) else {
            return nil
        }

        return try Data(contentsOf: archiveURL)
    }

    private func sanitizeRef(_ ref: String) -> String {
        ref.replacing("/", with: "_")
           .replacing(":", with: "_")
    }

    private func decompressGzip(_ data: Data) throws -> Data {
        try GzipDecoder.decompress(data)
    }
}
