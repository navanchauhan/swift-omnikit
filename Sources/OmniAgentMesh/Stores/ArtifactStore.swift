import Foundation

public struct ArtifactPayload: Sendable {
    public var taskID: String?
    public var name: String
    public var contentType: String
    public var data: Data

    public init(taskID: String? = nil, name: String, contentType: String, data: Data) {
        self.taskID = taskID
        self.name = name
        self.contentType = contentType
        self.data = data
    }
}

public protocol ArtifactStore: Sendable {
    func put(_ payload: ArtifactPayload) async throws -> ArtifactRecord
    func data(for artifactID: String) async throws -> Data?
    func list(taskID: String?) async throws -> [ArtifactRecord]
}

public actor FileArtifactStore: ArtifactStore {
    private let rootDirectory: URL
    private let filesDirectory: URL
    private let metadataDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        self.filesDirectory = rootDirectory.appending(path: "files", directoryHint: .isDirectory)
        self.metadataDirectory = rootDirectory.appending(path: "metadata", directoryHint: .isDirectory)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
    }

    public func put(_ payload: ArtifactPayload) async throws -> ArtifactRecord {
        let artifactID = UUID().uuidString
        let ownerDirectory = payload.taskID ?? "_shared"
        let relativePath = "\(ownerDirectory)/\(artifactID)-\(sanitizeFileName(payload.name))"
        let fileURL = filesDirectory.appending(path: relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try payload.data.write(to: fileURL, options: .atomic)

        let record = ArtifactRecord(
            artifactID: artifactID,
            taskID: payload.taskID,
            name: payload.name,
            relativePath: relativePath,
            contentType: payload.contentType,
            byteCount: payload.data.count
        )
        try metadataData(for: record).write(to: metadataURL(for: artifactID), options: .atomic)
        return record
    }

    public func data(for artifactID: String) async throws -> Data? {
        guard let record = try loadRecord(artifactID: artifactID) else {
            return nil
        }
        let fileURL = filesDirectory.appending(path: record.relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return nil
        }
        return try Data(contentsOf: fileURL)
    }

    public func list(taskID: String? = nil) async throws -> [ArtifactRecord] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: metadataDirectory,
            includingPropertiesForKeys: nil
        )
        let records = try contents.compactMap { url -> ArtifactRecord? in
            let data = try Data(contentsOf: url)
            return try decoder.decode(ArtifactRecord.self, from: data)
        }

        guard let taskID else {
            return records.sorted { $0.createdAt < $1.createdAt }
        }
        return records
            .filter { $0.taskID == taskID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func metadataURL(for artifactID: String) -> URL {
        metadataDirectory.appending(path: "\(artifactID).json")
    }

    private func metadataData(for record: ArtifactRecord) throws -> Data {
        try encoder.encode(record)
    }

    private func loadRecord(artifactID: String) throws -> ArtifactRecord? {
        let metadataURL = metadataURL(for: artifactID)
        guard FileManager.default.fileExists(atPath: metadataURL.path()) else {
            return nil
        }
        let data = try Data(contentsOf: metadataURL)
        return try decoder.decode(ArtifactRecord.self, from: data)
    }

    private func sanitizeFileName(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return String(name.map { allowed.contains($0) ? $0 : "_" })
    }
}
