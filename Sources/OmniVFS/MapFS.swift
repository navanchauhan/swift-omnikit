import Foundation

/// Dictionary-based synthetic filesystem. Keys are paths, values are VFS instances.
public struct MapFS: Sendable, VFSReadDirFS, VFSStatFS {
    private let mappings: [String: any VFS]

    public init(_ mappings: [String: any VFS]) {
        self.mappings = mappings
    }

    // MARK: - VFS

    public func open(_ path: String) throws -> any VFSFile {
        let normPath = PathUtils.cleanPath(path)
        // Direct mapping: open the root of the mapped VFS.
        if let fs = mappings[normPath] {
            return try fs.open(".")
        }
        // Check if path is under a mapping.
        for (mountPoint, fs) in mappings {
            let prefix = mountPoint + "/"
            if normPath.hasPrefix(prefix) {
                let subPath = String(normPath.dropFirst(prefix.count))
                return try fs.open(subPath)
            }
        }
        // Check if path is a synthesized parent directory.
        if isSynthesizedDir(normPath) {
            return MapFSDirFile(name: (PathUtils.splitPath(normPath)).name)
        }
        throw VFSError.notFound(path)
    }

    // MARK: - VFSReadDirFS

    public func readDir(_ path: String) throws -> [VFSDirEntry] {
        let normPath = PathUtils.cleanPath(path)

        // If the path matches a mapping, delegate.
        if let fs = mappings[normPath], let dirFS = fs as? VFSReadDirFS {
            return try dirFS.readDir(".")
        }

        // Collect children at this path level.
        var entries: [String: VFSDirEntry] = [:]
        let prefix = normPath == "." ? "" : normPath + "/"

        for (mountPoint, _) in mappings {
            let relative: String
            if normPath == "." {
                relative = mountPoint
            } else if mountPoint.hasPrefix(prefix) {
                relative = String(mountPoint.dropFirst(prefix.count))
            } else {
                continue
            }
            // Get the immediate child name.
            let components = relative.split(separator: "/", maxSplits: 1)
            guard let first = components.first else { continue }
            let childName = String(first)
            let isDir = components.count > 1 || isMountPoint(PathUtils.joinPath(normPath, childName))
            if entries[childName] == nil {
                entries[childName] = VFSDirEntry(name: childName, isDir: isDir || isSynthesizedDir(PathUtils.joinPath(normPath, childName)))
            }
        }

        if entries.isEmpty && !isSynthesizedDir(normPath) && normPath != "." {
            throw VFSError.notDirectory(path)
        }

        return entries.values.sorted { $0.name < $1.name }
    }

    // MARK: - VFSStatFS

    public func stat(_ path: String) throws -> VFSFileInfo {
        let normPath = PathUtils.cleanPath(path)
        if let fs = mappings[normPath], let statFS = fs as? VFSStatFS {
            return try statFS.stat(".")
        }
        if isSynthesizedDir(normPath) || normPath == "." {
            let (_, name) = PathUtils.splitPath(normPath)
            return VFSFileInfo(name: name, size: 0, mode: .defaultDir, isDir: true)
        }
        // Check sub-path delegation.
        for (mountPoint, fs) in mappings {
            let prefix = mountPoint + "/"
            if normPath.hasPrefix(prefix) {
                let subPath = String(normPath.dropFirst(prefix.count))
                if let statFS = fs as? VFSStatFS {
                    return try statFS.stat(subPath)
                }
            }
        }
        throw VFSError.notFound(path)
    }

    // MARK: - Private helpers

    private func isMountPoint(_ path: String) -> Bool {
        return mappings[PathUtils.cleanPath(path)] != nil
    }

    /// A path is a synthesized directory if any mapping has it as a prefix.
    private func isSynthesizedDir(_ path: String) -> Bool {
        let normPath = PathUtils.cleanPath(path)
        if normPath == "." { return true }
        let prefix = normPath + "/"
        return mappings.keys.contains { $0.hasPrefix(prefix) }
    }
}

/// Synthetic directory file for MapFS.
private final class MapFSDirFile: Sendable, VFSFile {
    private let name: String

    init(name: String) {
        self.name = name
    }

    func stat() throws -> VFSFileInfo {
        return VFSFileInfo(name: name, size: 0, mode: .defaultDir, isDir: true)
    }

    func read(into buffer: inout [UInt8], count: Int) throws -> Int {
        throw VFSError.isDirectory(name)
    }

    func readAll() throws -> [UInt8] {
        throw VFSError.isDirectory(name)
    }

    func close() throws {}
}
