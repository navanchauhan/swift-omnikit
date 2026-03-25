import Foundation
import OmniAgentMesh

public actor WorkspaceMemoryStore {
    private let rootDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func append(_ candidate: MemoryCandidate) async throws -> MemoryCandidate {
        var candidates = try load(workspaceID: candidate.workspaceID)
        let alreadyExists = candidates.contains { existing in
            existing.missionID == candidate.missionID &&
                existing.taskID == candidate.taskID &&
                existing.summary == candidate.summary
        }
        guard !alreadyExists else {
            return candidates.first {
                $0.missionID == candidate.missionID &&
                    $0.taskID == candidate.taskID &&
                    $0.summary == candidate.summary
            } ?? candidate
        }
        candidates.append(candidate)
        candidates.sort { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.candidateID < rhs.candidateID
        }
        try persist(candidates, workspaceID: candidate.workspaceID)
        return candidate
    }

    public func candidates(workspaceID: WorkspaceID) async throws -> [MemoryCandidate] {
        try load(workspaceID: workspaceID)
    }

    public func candidate(
        workspaceID: WorkspaceID,
        missionID: String
    ) async throws -> MemoryCandidate? {
        try load(workspaceID: workspaceID).first { $0.missionID == missionID }
    }

    private func load(workspaceID: WorkspaceID) throws -> [MemoryCandidate] {
        let fileURL = fileURL(for: workspaceID)
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([MemoryCandidate].self, from: data)
    }

    private func persist(_ candidates: [MemoryCandidate], workspaceID: WorkspaceID) throws {
        let fileURL = fileURL(for: workspaceID)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(candidates)
        try data.write(to: fileURL, options: .atomic)
    }

    private func fileURL(for workspaceID: WorkspaceID) -> URL {
        let sanitized = workspaceID.rawValue.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." ? character : "_"
        }
        return rootDirectory.appending(path: String(sanitized) + ".json")
    }
}
