import Foundation

public protocol FileSystem: Sendable {
    var executionRoot: String? { get }
}

public struct RealFileSystem: FileSystem {
    public var executionRoot: String? { nil }

    public init() {}
}

public final class InMemoryFileSystem: FileSystem, @unchecked Sendable {
    public let executionRoot: String?

    public init() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftbash-inmemory-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        self.executionRoot = url.path
    }
}

public final class SandboxedOverlayFileSystem: FileSystem, @unchecked Sendable {
    public struct Configuration: Sendable {
        public var root: String
        public var mountPoint: String

        public init(root: String, mountPoint: String) {
            self.root = root
            self.mountPoint = mountPoint
        }
    }

    public let executionRoot: String?

    public init(_ configuration: Configuration) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftbash-sandbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: configuration.root) {
            let contents = try FileManager.default.contentsOfDirectory(atPath: configuration.root)
            for name in contents {
                let source = URL(fileURLWithPath: configuration.root).appendingPathComponent(name)
                let destination = url.appendingPathComponent(name)
                try FileManager.default.copyItem(at: source, to: destination)
            }
        }
        self.executionRoot = url.path
    }
}

public struct AllowedURLEntry: Sendable, Equatable {
    public var prefix: String

    public init(_ prefix: String) {
        self.prefix = prefix
    }
}

public struct NetworkConfig: Sendable, Equatable {
    public var dangerouslyAllowFullInternetAccess: Bool
    public var allowedURLPrefixes: [AllowedURLEntry]

    public init(dangerouslyAllowFullInternetAccess: Bool) {
        self.dangerouslyAllowFullInternetAccess = dangerouslyAllowFullInternetAccess
        self.allowedURLPrefixes = []
    }

    public init(allowedURLPrefixes: [AllowedURLEntry]) {
        self.dangerouslyAllowFullInternetAccess = false
        self.allowedURLPrefixes = allowedURLPrefixes
    }
}
