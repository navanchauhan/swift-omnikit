import Foundation
import OmniVFS

public struct BlinkHostMount: Sendable, Equatable {
    public let hostPath: String
    public let guestPath: String

    public init(hostPath: String, guestPath: String) {
        self.hostPath = hostPath
        self.guestPath = guestPath
    }
}

public struct BlinkVFSLaunchPlan: @unchecked Sendable {
    public let flatVFS: FlatVFS
    public let hostMounts: [BlinkHostMount]

    public init(flatVFS: FlatVFS, hostMounts: [BlinkHostMount] = []) {
        self.flatVFS = flatVFS
        self.hostMounts = hostMounts
    }
}

private final class BlinkReadonlySnapshotCache: @unchecked Sendable {
    private struct CacheKey: Hashable, Sendable {
        let objectID: ObjectIdentifier
        let srcPath: String
        let mountPath: String
    }

    private let lock = NSLock()
    private var entriesByKey: [CacheKey: [FlatVFS.Entry]] = [:]

    func entries(
        for fs: any VFS,
        srcPath: String,
        mountedAt mountPath: String
    ) -> [FlatVFS.Entry]? {
        guard let tarFS = fs as? TarFS else {
            return nil
        }

        let key = CacheKey(
            objectID: ObjectIdentifier(tarFS),
            srcPath: PathUtils.cleanPath(srcPath),
            mountPath: PathUtils.cleanPath(mountPath)
        )

        if let cached = lock.withLock({ entriesByKey[key] }) {
            return cached
        }

        let entries = FlatVFS.entries(from: tarFS, srcPath: srcPath, mountedAt: mountPath)
        return lock.withLock {
            if let cached = entriesByKey[key] {
                return cached
            }
            entriesByKey[key] = entries
            return entries
        }
    }
}

public enum BlinkVFSPlanner {
    private static let snapshotCache = BlinkReadonlySnapshotCache()

    public static func buildLaunchPlan(namespace: VFSNamespace) -> BlinkVFSLaunchPlan {
        let bindings = namespace.bindingSnapshots()
        guard !bindings.isEmpty else {
            return BlinkVFSLaunchPlan(flatVFS: FlatVFS.from(namespace: namespace))
        }
        guard bindings.allSatisfy({ $0.targets.count == 1 }) else {
            return BlinkVFSLaunchPlan(flatVFS: FlatVFS.from(namespace: namespace))
        }

        var entryMap: [String: FlatVFS.Entry] = [:]
        var hostMounts: [BlinkHostMount] = []

        for binding in bindings {
            let target = binding.targets[0]
            removeMountedSubtree(binding.dstPath, from: &entryMap)

            if let hostMount = passthroughHostMount(
                for: binding,
                target: target,
                allBindings: bindings
            ) {
                hostMounts.append(hostMount)
                continue
            }

            if let cow = target.fs as? CowFS {
                let baseEntries =
                    snapshotCache.entries(
                        for: cow.baseFS,
                        srcPath: target.srcPath,
                        mountedAt: binding.dstPath
                    )
                    ?? FlatVFS.entries(
                        from: cow.baseFS,
                        srcPath: target.srcPath,
                        mountedAt: binding.dstPath
                    )
                let filteredBaseEntries = filterEntries(
                    baseEntries,
                    whiteouts: cow.whiteoutPaths(),
                    srcPath: target.srcPath,
                    mountPath: binding.dstPath
                )
                for entry in filteredBaseEntries {
                    entryMap[entry.path] = entry
                }

                let overlayEntries = FlatVFS.entries(
                    from: cow.overlayFS,
                    srcPath: target.srcPath,
                    mountedAt: binding.dstPath
                )
                for entry in overlayEntries {
                    entryMap[entry.path] = entry
                }
                continue
            }

            let entries =
                snapshotCache.entries(
                    for: target.fs,
                    srcPath: target.srcPath,
                    mountedAt: binding.dstPath
                )
                ?? FlatVFS.entries(
                    from: target.fs,
                    srcPath: target.srcPath,
                    mountedAt: binding.dstPath
                )
            for entry in entries {
                entryMap[entry.path] = entry
            }
        }

        let sortedEntries = entryMap.values.sorted { lhs, rhs in
            let lhsDepth = lhs.path.split(separator: "/").count
            let rhsDepth = rhs.path.split(separator: "/").count
            if lhsDepth == rhsDepth {
                return lhs.path < rhs.path
            }
            return lhsDepth < rhsDepth
        }
        let sortedHostMounts = hostMounts.sorted { lhs, rhs in
            let lhsDepth = lhs.guestPath.split(separator: "/").count
            let rhsDepth = rhs.guestPath.split(separator: "/").count
            if lhsDepth == rhsDepth {
                return lhs.guestPath < rhs.guestPath
            }
            return lhsDepth < rhsDepth
        }

        return BlinkVFSLaunchPlan(
            flatVFS: FlatVFS(entries: sortedEntries),
            hostMounts: sortedHostMounts
        )
    }

    private static func passthroughHostMount(
        for binding: VFSNamespace.BindingSnapshot,
        target: VFSNamespace.BindingSnapshot.Target,
        allBindings: [VFSNamespace.BindingSnapshot]
    ) -> BlinkHostMount? {
        guard let diskFS = target.fs as? DiskFS else {
            return nil
        }

        let normalizedMountPath = PathUtils.cleanPath(binding.dstPath)
        guard normalizedMountPath != "." else {
            return nil
        }
        guard !hasNestedBinding(under: normalizedMountPath, in: allBindings) else {
            return nil
        }

        guard let hostPath = try? diskFS.mountSourcePath(for: target.srcPath) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: hostPath, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return nil
        }

        return BlinkHostMount(
            hostPath: hostPath,
            guestPath: guestMountPath(for: normalizedMountPath)
        )
    }

    private static func hasNestedBinding(
        under mountPath: String,
        in bindings: [VFSNamespace.BindingSnapshot]
    ) -> Bool {
        bindings.contains { binding in
            let candidate = PathUtils.cleanPath(binding.dstPath)
            guard candidate != mountPath else {
                return false
            }
            return path(candidate, isDescendantOf: mountPath)
        }
    }

    private static func guestMountPath(for path: String) -> String {
        let normalizedPath = PathUtils.cleanPath(path)
        if normalizedPath == "." || normalizedPath == "/" {
            return "/"
        }
        return normalizedPath.hasPrefix("/") ? normalizedPath : "/\(normalizedPath)"
    }

    private static func removeMountedSubtree(
        _ mountPath: String,
        from entryMap: inout [String: FlatVFS.Entry]
    ) {
        let normalizedMountPath = PathUtils.cleanPath(mountPath)
        entryMap = entryMap.filter { key, _ in
            !path(key, isSameOrDescendantOf: normalizedMountPath)
        }
    }

    private static func filterEntries(
        _ entries: [FlatVFS.Entry],
        whiteouts: Set<String>,
        srcPath: String,
        mountPath: String
    ) -> [FlatVFS.Entry] {
        let mountedWhiteouts = projectedWhiteouts(
            whiteouts,
            srcPath: srcPath,
            mountPath: mountPath
        )
        guard !mountedWhiteouts.isEmpty else {
            return entries
        }
        return entries.filter { entry in
            !mountedWhiteouts.contains { path(entry.path, isSameOrDescendantOf: $0) }
        }
    }

    private static func projectedWhiteouts(
        _ whiteouts: Set<String>,
        srcPath: String,
        mountPath: String
    ) -> [String] {
        let normalizedSrcPath = PathUtils.cleanPath(srcPath)
        let normalizedMountPath = PathUtils.cleanPath(mountPath)

        return whiteouts.compactMap { whiteout in
            let normalizedWhiteout = PathUtils.cleanPath(whiteout)
            let relativePath: String

            if normalizedSrcPath == "." {
                relativePath = normalizedWhiteout
            } else if normalizedWhiteout == normalizedSrcPath {
                relativePath = "."
            } else if normalizedWhiteout.hasPrefix(normalizedSrcPath + "/") {
                relativePath = String(normalizedWhiteout.dropFirst(normalizedSrcPath.count + 1))
            } else {
                return nil
            }

            if relativePath == "." {
                return normalizedMountPath
            }
            return normalizedMountPath == "."
                ? relativePath
                : PathUtils.joinPath(normalizedMountPath, relativePath)
        }
    }

    private static func path(_ path: String, isDescendantOf ancestor: String) -> Bool {
        let normalizedPath = PathUtils.cleanPath(path)
        let normalizedAncestor = PathUtils.cleanPath(ancestor)
        if normalizedAncestor == "." || normalizedAncestor == "/" {
            return normalizedPath != "." && normalizedPath != "/"
        }
        guard normalizedPath != normalizedAncestor else {
            return false
        }
        return normalizedPath.hasPrefix(normalizedAncestor + "/")
    }

    private static func path(_ path: String, isSameOrDescendantOf ancestor: String) -> Bool {
        let normalizedPath = PathUtils.cleanPath(path)
        let normalizedAncestor = PathUtils.cleanPath(ancestor)
        if normalizedAncestor == "." || normalizedAncestor == "/" {
            return true
        }
        return normalizedPath == normalizedAncestor
            || normalizedPath.hasPrefix(normalizedAncestor + "/")
    }
}
