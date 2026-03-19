import Foundation

/// Copy-on-Write filesystem. Reads fall through to base; writes go to overlay.
public final class CowFS: @unchecked Sendable, VFSFullFS {
    private let lock = NSLock()
    private let base: any VFS
    private let overlay: MemFS
    private var whiteouts: Set<String> = []

    public init(base: any VFS, overlay: MemFS = MemFS()) {
        self.base = base
        self.overlay = overlay
    }

    // MARK: - VFS

    public func open(_ path: String) throws -> any VFSFile {
        let normPath = PathUtils.cleanPath(path)
        let isWhitedOut = lock.withLock { whiteouts.contains(normPath) }
        if isWhitedOut { throw VFSError.notFound(path) }
        // Try overlay first.
        if let file = try? overlay.open(normPath) {
            return file
        }
        return try base.open(normPath)
    }

    // MARK: - VFSReadDirFS

    public func readDir(_ path: String) throws -> [VFSDirEntry] {
        let normPath = PathUtils.cleanPath(path)
        var entries: [String: VFSDirEntry] = [:]

        // Base entries.
        if let baseDir = base as? VFSReadDirFS {
            if let baseEntries = try? baseDir.readDir(normPath) {
                for entry in baseEntries {
                    let fullChildPath = PathUtils.joinPath(normPath, entry.name)
                    let childNorm = PathUtils.cleanPath(fullChildPath)
                    let isWhitedOut = lock.withLock { whiteouts.contains(childNorm) }
                    if !isWhitedOut {
                        entries[entry.name] = entry
                    }
                }
            }
        }

        // Overlay entries override base.
        if let overlayEntries = try? overlay.readDir(normPath) {
            for entry in overlayEntries {
                // Skip whiteout sentinel files.
                if entry.name.hasPrefix(".wh.") { continue }
                entries[entry.name] = entry
            }
        }

        return entries.values.sorted { $0.name < $1.name }
    }

    // MARK: - VFSStatFS

    public func stat(_ path: String) throws -> VFSFileInfo {
        let normPath = PathUtils.cleanPath(path)
        let isWhitedOut = lock.withLock { whiteouts.contains(normPath) }
        if isWhitedOut { throw VFSError.notFound(path) }
        if let info = try? overlay.stat(normPath) {
            return info
        }
        if let baseStat = base as? VFSStatFS {
            return try baseStat.stat(normPath)
        }
        // Fall back to opening the file.
        let file = try base.open(normPath)
        defer { try? file.close() }
        return try file.stat()
    }

    // MARK: - VFSMutableFS

    public func createFile(_ path: String, data: [UInt8]) throws {
        let normPath = PathUtils.cleanPath(path)
        lock.withLock { whiteouts.remove(normPath) }
        try overlay.createFile(normPath, data: data)
    }

    public func mkdir(_ path: String) throws {
        let normPath = PathUtils.cleanPath(path)
        lock.withLock { whiteouts.remove(normPath) }
        try overlay.mkdir(normPath)
    }

    public func remove(_ path: String) throws {
        let normPath = PathUtils.cleanPath(path)
        // Try removing from overlay.
        try? overlay.remove(normPath)
        // Record whiteout so base entry is hidden.
        lock.withLock { whiteouts.insert(normPath) }
    }

    public func writeFile(_ path: String, data: [UInt8]) throws {
        let normPath = PathUtils.cleanPath(path)
        lock.withLock { whiteouts.remove(normPath) }
        // Ensure parent directories exist in overlay.
        try ensureOverlayParents(normPath)
        try overlay.writeFile(normPath, data: data)
    }

    public func rename(from: String, to: String) throws {
        let normFrom = PathUtils.cleanPath(from)
        let normTo = PathUtils.cleanPath(to)
        // Read from current view, write to overlay, then remove source.
        let file = try open(normFrom)
        let data = try file.readAll()
        try file.close()
        try ensureOverlayParents(normTo)
        // Remove old whiteout if any.
        lock.withLock { whiteouts.remove(normTo) }
        try? overlay.remove(normTo)
        let (_, _) = PathUtils.splitPath(normTo)
        // Write or create in overlay.
        do {
            try overlay.createFile(normTo, data: data)
        } catch {
            try overlay.writeFile(normTo, data: data)
        }
        // Remove source.
        try? overlay.remove(normFrom)
        lock.withLock { whiteouts.insert(normFrom) }
    }

    public func symlink(target: String, link: String) throws {
        throw VFSError.notSupported("symlinks not supported in CowFS")
    }

    // MARK: - VFSResolveFS

    public func resolveFS(_ path: String) throws -> (any VFS, String) {
        return (self, path)
    }

    // MARK: - Private helpers

    private func ensureOverlayParents(_ path: String) throws {
        let (parent, _) = PathUtils.splitPath(path)
        if parent == "." || parent == "/" { return }
        // Recursively ensure parent exists.
        try ensureOverlayParents(parent)
        // Create if missing.
        if (try? overlay.stat(parent)) == nil {
            try? overlay.mkdir(parent)
        }
    }
}
