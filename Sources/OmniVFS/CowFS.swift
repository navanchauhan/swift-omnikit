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

    public var baseFS: any VFS { base }

    public var overlayFS: MemFS { overlay }

    public func whiteoutPaths() -> Set<String> {
        lock.withLock { whiteouts }
    }

    // MARK: - VFS

    public func open(_ path: String) throws -> any VFSFile {
        let resolvedPath = try resolveVisiblePath(path, followFinalSymlink: true)
        if let file = try? overlay.open(resolvedPath) {
            return file
        }
        if isHiddenByWhiteout(resolvedPath) {
            throw VFSError.notFound(path)
        }
        return try base.open(resolvedPath)
    }

    // MARK: - VFSReadDirFS

    public func readDir(_ path: String) throws -> [VFSDirEntry] {
        let resolvedPath = try resolveVisiblePath(path, followFinalSymlink: true)
        var entries: [String: VFSDirEntry] = [:]
        var foundDirectory = false

        if let overlayEntries = try? overlay.readDir(resolvedPath) {
            foundDirectory = true
            for entry in overlayEntries {
                if entry.name.hasPrefix(".wh.") { continue }
                entries[entry.name] = entry
            }
        }

        // Base entries.
        if !isHiddenByWhiteout(resolvedPath),
           let baseDir = base as? VFSReadDirFS {
            if let baseEntries = try? baseDir.readDir(resolvedPath) {
                foundDirectory = true
                for entry in baseEntries {
                    let fullChildPath = PathUtils.joinPath(resolvedPath, entry.name)
                    let childNorm = PathUtils.cleanPath(fullChildPath)
                    if !isHiddenByWhiteout(childNorm) {
                        entries[entry.name] = entry
                    }
                }
            }
        }

        if !foundDirectory {
            if (try? lstatVisiblePath(resolvedPath)) != nil {
                throw VFSError.notDirectory(path)
            }
            throw VFSError.notFound(path)
        }

        return entries.values.sorted { $0.name < $1.name }
    }

    // MARK: - VFSStatFS

    public func stat(_ path: String) throws -> VFSFileInfo {
        let resolvedPath = try resolveVisiblePath(path, followFinalSymlink: false)
        return try lstatVisiblePath(resolvedPath)
    }

    // MARK: - VFSMutableFS

    public func createFile(_ path: String, data: [UInt8]) throws {
        let normPath = PathUtils.cleanPath(path)
        if (try? stat(normPath)) != nil {
            throw VFSError.alreadyExists(path)
        }
        let resolvedPath = try resolveMutationPath(normPath)
        try ensureOverlayParents(resolvedPath)
        _ = lock.withLock { whiteouts.remove(resolvedPath) }
        try overlay.createFile(resolvedPath, data: data)
    }

    public func mkdir(_ path: String) throws {
        let normPath = PathUtils.cleanPath(path)
        if (try? stat(normPath)) != nil {
            throw VFSError.alreadyExists(path)
        }
        let resolvedPath = try resolveMutationPath(normPath)
        try ensureOverlayParents(resolvedPath)
        _ = lock.withLock { whiteouts.remove(resolvedPath) }
        try overlay.mkdir(resolvedPath)
    }

    public func remove(_ path: String) throws {
        let resolvedPath = try resolveVisiblePath(path, followFinalSymlink: false)
        let info = try lstatVisiblePath(resolvedPath)
        if info.isDir {
            try removeOverlayTree(resolvedPath)
        } else {
            try? overlay.remove(resolvedPath)
        }
        _ = lock.withLock { whiteouts.insert(resolvedPath) }
    }

    public func writeFile(_ path: String, data: [UInt8]) throws {
        try writeFile(path, data: data, depth: 0)
    }

    public func rename(from: String, to: String) throws {
        let normFrom = PathUtils.cleanPath(from)
        let normTo = PathUtils.cleanPath(to)
        guard normFrom != normTo else { return }

        _ = try stat(normFrom)
        if (try? stat(normTo)) != nil {
            try remove(normTo)
        }

        let resolvedFrom = try resolveVisiblePath(normFrom, followFinalSymlink: false)
        let resolvedTo = try resolveMutationPath(normTo)
        try ensureOverlayParents(resolvedTo)
        try copyNode(from: resolvedFrom, to: resolvedTo, depth: 0)
        try remove(resolvedFrom)
    }

    public func symlink(target: String, link: String) throws {
        let normLink = PathUtils.cleanPath(link)
        if (try? stat(normLink)) != nil {
            throw VFSError.alreadyExists(link)
        }
        let resolvedLink = try resolveMutationPath(normLink)
        try ensureOverlayParents(resolvedLink)
        _ = lock.withLock { whiteouts.remove(resolvedLink) }
        try overlay.symlink(target: target, link: resolvedLink)
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
        if (try? overlay.stat(parent)) != nil {
            return
        }

        let parentInfo = try stat(parent)
        guard parentInfo.isDir else {
            throw VFSError.notDirectory(parent)
        }
        try overlay.mkdir(parent)
    }

    private func writeFile(_ path: String, data: [UInt8], depth: Int) throws {
        guard depth < 32 else {
            throw VFSError.cyclicResolution("exceeded symlink resolution limit for \(path)")
        }

        let normPath = PathUtils.cleanPath(path)
        let resolvedPath = try resolveMutationPath(normPath)
        if let info = try? lstatVisiblePath(resolvedPath) {
            if info.isDir {
                throw VFSError.isDirectory(path)
            }
            if info.isSymlink, let target = info.symlinkTarget {
                let resolved = resolveSymlinkTarget(from: resolvedPath, target: target)
                try writeFile(resolved, data: data, depth: depth + 1)
                return
            }
        }

        _ = lock.withLock { whiteouts.remove(resolvedPath) }
        try ensureOverlayParents(resolvedPath)
        try overlay.writeFile(resolvedPath, data: data)
    }

    private func isHiddenByWhiteout(_ path: String) -> Bool {
        var current = PathUtils.cleanPath(path)
        while current != "." && current != "/" {
            let isWhitedOut = lock.withLock { whiteouts.contains(current) }
            if isWhitedOut {
                return true
            }
            let (parent, _) = PathUtils.splitPath(current)
            if parent == current {
                break
            }
            current = parent
        }
        return false
    }

    private func removeOverlayTree(_ path: String) throws {
        let normPath = PathUtils.cleanPath(path)

        if let info = try? overlay.stat(normPath) {
            if info.isDir {
                let children = try overlay.readDir(normPath)
                for child in children {
                    try removeOverlayTree(PathUtils.joinPath(normPath, child.name))
                }
            }
            try overlay.remove(normPath)
        }
    }

    private func copyNode(from sourcePath: String, to destinationPath: String, depth: Int) throws {
        guard depth < 32 else {
            throw VFSError.cyclicResolution("exceeded copy depth for \(sourcePath)")
        }

        let info = try lstatVisiblePath(sourcePath)

        if info.isSymlink, let target = info.symlinkTarget {
            try symlink(target: target, link: destinationPath)
            return
        }

        if info.isDir {
            try mkdir(destinationPath)
            let entries = try readDir(sourcePath)
            for entry in entries {
                try copyNode(
                    from: PathUtils.joinPath(sourcePath, entry.name),
                    to: PathUtils.joinPath(destinationPath, entry.name),
                    depth: depth + 1
                )
            }
            return
        }

        let file = try open(sourcePath)
        defer { try? file.close() }
        let data = try file.readAll()
        try createFile(destinationPath, data: data)
    }

    private func resolveSymlinkTarget(from sourcePath: String, target: String) -> String {
        let (parent, _) = PathUtils.splitPath(sourcePath)
        return PathUtils.resolvePath(target, relativeTo: parent)
    }

    private func resolveVisiblePath(
        _ path: String,
        followFinalSymlink: Bool,
        depth: Int = 0
    ) throws -> String {
        guard depth < 32 else {
            throw VFSError.cyclicResolution("exceeded symlink resolution limit for \(path)")
        }

        let normPath = PathUtils.cleanPath(path)
        if normPath == "." || normPath == "/" {
            return normPath
        }

        let components = normPath.split(separator: "/").map(String.init)
        var currentPath = normPath.hasPrefix("/") ? "/" : "."

        for (index, component) in components.enumerated() {
            let nextPath = PathUtils.joinPath(currentPath, component)
            let info = try lstatVisiblePath(nextPath)
            let isFinal = index == components.count - 1

            if info.isSymlink, let target = info.symlinkTarget,
               (!isFinal || followFinalSymlink) {
                let resolvedTarget = resolveSymlinkTarget(from: nextPath, target: target)
                let remaining = isFinal ? "." : components[(index + 1)...].joined(separator: "/")
                let combined = remaining == "." ? resolvedTarget : PathUtils.joinPath(resolvedTarget, remaining)
                return try resolveVisiblePath(
                    combined,
                    followFinalSymlink: followFinalSymlink,
                    depth: depth + 1
                )
            }

            currentPath = nextPath
        }

        return currentPath
    }

    private func resolveMutationPath(_ path: String) throws -> String {
        let normPath = PathUtils.cleanPath(path)
        let (parent, name) = PathUtils.splitPath(normPath)
        if parent == "." || parent == "/" {
            return PathUtils.joinPath(parent, name)
        }
        let resolvedParent = try resolveVisiblePath(parent, followFinalSymlink: true)
        return PathUtils.joinPath(resolvedParent, name)
    }

    private func lstatVisiblePath(_ path: String) throws -> VFSFileInfo {
        let normPath = PathUtils.cleanPath(path)
        if let info = try? overlay.stat(normPath) {
            return info
        }
        if isHiddenByWhiteout(normPath) {
            throw VFSError.notFound(normPath)
        }
        if let baseStat = base as? VFSStatFS {
            return try baseStat.stat(normPath)
        }
        let file = try base.open(normPath)
        defer { try? file.close() }
        return try file.stat()
    }
}
