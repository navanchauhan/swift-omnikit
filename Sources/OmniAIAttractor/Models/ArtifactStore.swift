import Foundation

// MARK: - Artifact Info

public struct ArtifactInfo: Sendable {
    public var id: String
    public var name: String
    public var size: Int
    public var contentType: String?
    public var metadata: [String: String]
    public var createdAt: Date

    public init(
        id: String,
        name: String,
        size: Int,
        contentType: String? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.contentType = contentType
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

// MARK: - Artifact Store

public actor ArtifactStore {
    private var inMemory: [String: Any] = [:]
    private var metadata: [String: ArtifactInfo] = [:]
    private let logsRoot: URL
    private let fileSizeThreshold: Int

    public init(logsRoot: URL, fileSizeThreshold: Int = 100_000) {
        self.logsRoot = logsRoot
        self.fileSizeThreshold = fileSizeThreshold
    }

    public func store(
        artifactId: String,
        name: String,
        data: Any,
        contentType: String? = nil,
        artifactMetadata: [String: String] = [:]
    ) throws -> ArtifactInfo {
        let serialized: Data
        if let d = data as? Data {
            serialized = d
        } else if let s = data as? String {
            serialized = Data(s.utf8)
        } else {
            serialized = try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
        }

        let info = ArtifactInfo(
            id: artifactId,
            name: name,
            size: serialized.count,
            contentType: contentType,
            metadata: artifactMetadata
        )
        metadata[artifactId] = info

        if serialized.count > fileSizeThreshold {
            let dir = logsRoot.appendingPathComponent("artifacts")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(artifactId).json")
            try serialized.write(to: file)
        } else {
            inMemory[artifactId] = data
        }
        return info
    }

    public func retrieve(_ artifactId: String) -> Any? {
        if let val = inMemory[artifactId] { return val }

        let file = logsRoot.appendingPathComponent("artifacts/\(artifactId).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    public func has(_ artifactId: String) -> Bool {
        metadata[artifactId] != nil
    }

    public func list() -> [ArtifactInfo] {
        Array(metadata.values)
    }

    public func remove(_ artifactId: String) {
        inMemory.removeValue(forKey: artifactId)
        metadata.removeValue(forKey: artifactId)
        let file = logsRoot.appendingPathComponent("artifacts/\(artifactId).json")
        try? FileManager.default.removeItem(at: file)
    }

    public func clear() {
        inMemory.removeAll()
        metadata.removeAll()
        let dir = logsRoot.appendingPathComponent("artifacts")
        try? FileManager.default.removeItem(at: dir)
    }
}
