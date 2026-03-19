import Foundation

/// Merged read-only filesystem. Tries children in order; deduplicates readDir.
public struct UnionFS: Sendable, VFSReadDirFS, VFSStatFS {
    private let children: [any VFS]

    public init(_ children: [any VFS]) {
        self.children = children
    }

    // MARK: - VFS

    public func open(_ path: String) throws -> any VFSFile {
        for child in children {
            if let file = try? child.open(path) {
                return file
            }
        }
        throw VFSError.notFound(path)
    }

    // MARK: - VFSReadDirFS

    public func readDir(_ path: String) throws -> [VFSDirEntry] {
        var seen: Set<String> = []
        var result: [VFSDirEntry] = []
        var anySuccess = false

        for child in children {
            guard let dirFS = child as? VFSReadDirFS else { continue }
            guard let entries = try? dirFS.readDir(path) else { continue }
            anySuccess = true
            for entry in entries {
                if seen.insert(entry.name).inserted {
                    result.append(entry)
                }
            }
        }

        if !anySuccess {
            throw VFSError.notFound(path)
        }
        return result.sorted { $0.name < $1.name }
    }

    // MARK: - VFSStatFS

    public func stat(_ path: String) throws -> VFSFileInfo {
        for child in children {
            if let statFS = child as? VFSStatFS {
                if let info = try? statFS.stat(path) {
                    return info
                }
            }
        }
        throw VFSError.notFound(path)
    }
}
