import Foundation

/// Plan 9-style bind/resolve namespace multiplexer.
public struct VFSNamespace: Sendable, VFS, VFSReadDirFS, VFSStatFS, VFSResolveFS {
    private struct BindTarget: Sendable {
        let fs: any VFS
        let srcPath: String
    }

    public struct BindingSnapshot: Sendable {
        public struct Target: Sendable {
            public let fs: any VFS
            public let srcPath: String

            public init(fs: any VFS, srcPath: String) {
                self.fs = fs
                self.srcPath = srcPath
            }
        }

        public let dstPath: String
        public let targets: [Target]

        public init(dstPath: String, targets: [Target]) {
            self.dstPath = dstPath
            self.targets = targets
        }
    }

    private var bindings: [String: [BindTarget]] = [:]

    /// Maximum resolution depth to prevent cycles.
    private static let maxDepth = 64

    public init() {}

    // MARK: - Bind/Unbind

    /// Bind a filesystem at srcPath to a destination path in the namespace.
    public mutating func bind(src: any VFS, srcPath: String = ".", dstPath: String, mode: BindMode) {
        let normDst = PathUtils.cleanPath(dstPath)
        let target = BindTarget(fs: src, srcPath: srcPath)
        switch mode {
        case .after:
            // Prepend — checked first.
            var list = bindings[normDst] ?? []
            list.insert(target, at: 0)
            bindings[normDst] = list
        case .before:
            // Append — checked last.
            var list = bindings[normDst] ?? []
            list.append(target)
            bindings[normDst] = list
        case .replace:
            bindings[normDst] = [target]
        }
    }

    /// Remove all bindings at the given path.
    public mutating func unbind(dstPath: String) {
        let normDst = PathUtils.cleanPath(dstPath)
        bindings.removeValue(forKey: normDst)
    }

    // MARK: - VFS

    public func open(_ path: String) throws -> any VFSFile {
        let (fs, resolved) = try resolveFS(path)
        return try fs.open(resolved)
    }

    // MARK: - VFSResolveFS

    public func resolveFS(_ path: String) throws -> (any VFS, String) {
        return try resolve(path, depth: 0)
    }

    // MARK: - VFSReadDirFS

    public func readDir(_ path: String) throws -> [VFSDirEntry] {
        let normPath = PathUtils.cleanPath(path)

        // Collect entries from all matching bindings.
        var entries: [String: VFSDirEntry] = [:]
        var anySuccess = false

        // Check exact match bindings.
        if let targets = bindings[normPath] {
            for target in targets {
                guard let dirFS = target.fs as? VFSReadDirFS else { continue }
                guard let dirEntries = try? dirFS.readDir(target.srcPath) else { continue }
                anySuccess = true
                for entry in dirEntries {
                    if entries[entry.name] == nil {
                        entries[entry.name] = entry
                    }
                }
            }
        }

        // Check longest-prefix bindings.
        let (fs, resolvedPath) = try resolve(normPath, depth: 0)
        if let dirFS = fs as? VFSReadDirFS {
            if let dirEntries = try? dirFS.readDir(resolvedPath) {
                anySuccess = true
                for entry in dirEntries {
                    if entries[entry.name] == nil {
                        entries[entry.name] = entry
                    }
                }
            }
        }

        // Also add synthesized entries for child bindings.
        let prefix = normPath == "." ? "" : normPath + "/"
        for key in bindings.keys {
            let relative: String
            if normPath == "." {
                relative = key
            } else if key.hasPrefix(prefix) {
                relative = String(key.dropFirst(prefix.count))
            } else {
                continue
            }
            if relative.isEmpty { continue }
            let components = relative.split(separator: "/", maxSplits: 1)
            guard let first = components.first else { continue }
            let childName = String(first)
            if entries[childName] == nil {
                entries[childName] = VFSDirEntry(name: childName, isDir: true)
            }
        }

        if !anySuccess && entries.isEmpty {
            throw VFSError.notFound(path)
        }

        return entries.values.sorted { $0.name < $1.name }
    }

    // MARK: - VFSStatFS

    public func stat(_ path: String) throws -> VFSFileInfo {
        let (fs, resolvedPath) = try resolveFS(path)
        if let statFS = fs as? VFSStatFS {
            return try statFS.stat(resolvedPath)
        }
        let file = try fs.open(resolvedPath)
        defer { try? file.close() }
        return try file.stat()
    }

    // MARK: - Clone

    /// Returns a copy of this namespace (value type, so automatic).
    public func clone() -> VFSNamespace {
        return self
    }

    public func bindingSnapshots() -> [BindingSnapshot] {
        bindings.map { key, targets in
            BindingSnapshot(
                dstPath: key,
                targets: targets.map { BindingSnapshot.Target(fs: $0.fs, srcPath: $0.srcPath) }
            )
        }
        .sorted {
            let leftDepth = $0.dstPath.split(separator: "/").count
            let rightDepth = $1.dstPath.split(separator: "/").count
            if leftDepth == rightDepth {
                return $0.dstPath < $1.dstPath
            }
            return leftDepth < rightDepth
        }
    }

    // MARK: - Private resolution

    private func resolve(_ path: String, depth: Int) throws -> (any VFS, String) {
        guard depth < Self.maxDepth else {
            throw VFSError.cyclicResolution("exceeded \(Self.maxDepth) resolution hops for: \(path)")
        }
        let normPath = PathUtils.cleanPath(path)

        // Find the longest matching prefix in bindings.
        var bestPrefix = ""
        var bestTargets: [BindTarget]?

        for (bindPath, targets) in bindings {
            if normPath == bindPath || normPath.hasPrefix(bindPath + "/") || bindPath == "." {
                if bindPath.count > bestPrefix.count || (bindPath == "." && bestPrefix.isEmpty) {
                    bestPrefix = bindPath
                    bestTargets = targets
                }
            }
        }

        guard let targets = bestTargets, !targets.isEmpty else {
            throw VFSError.notFound(path)
        }

        // Compute the remainder path.
        let remainder: String
        if bestPrefix == normPath {
            remainder = "."
        } else if bestPrefix == "." {
            // Root binding: the entire normPath is the remainder.
            remainder = normPath == "." ? "." : normPath
        } else {
            let rest = String(normPath.dropFirst(bestPrefix.count + 1))
            remainder = rest.isEmpty ? "." : rest
        }

        // Try each target in order.
        for target in targets {
            let resolvedPath = remainder == "." ? target.srcPath : PathUtils.joinPath(target.srcPath, remainder)

            // If the target is itself a VFSResolveFS, recurse.
            if let resolveFS = target.fs as? VFSResolveFS {
                if let result = try? resolveFS.resolveFS(resolvedPath) {
                    return result
                }
            }

            // Try opening to verify the path exists.
            if let _ = try? target.fs.open(resolvedPath) {
                return (target.fs, resolvedPath)
            }
        }

        // If none resolved, return the first target anyway (it will error on open).
        let target = targets[0]
        let resolvedPath = remainder == "." ? target.srcPath : PathUtils.joinPath(target.srcPath, remainder)
        return (target.fs, resolvedPath)
    }
}
