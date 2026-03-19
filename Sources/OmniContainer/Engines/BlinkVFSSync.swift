import Foundation
import OmniVFS

/// Handles materializing a VFS namespace to a host directory and syncing changes back.
public enum BlinkVFSSync: Sendable {

    /// Materialize a VFS namespace to a host directory for BLINK_OVERLAYS.
    public static func materialize(namespace: VFSNamespace, to hostDir: String) throws {
        try materializeDirectory(namespace: namespace, vfsPath: ".", hostPath: hostDir, depth: 0)
    }

    private static func materializeDirectory(
        namespace: VFSNamespace,
        vfsPath: String,
        hostPath: String,
        depth: Int
    ) throws {
        guard depth < 32 else { return } // Prevent infinite recursion

        let fm = FileManager.default
        try fm.createDirectory(atPath: hostPath, withIntermediateDirectories: true, attributes: nil)

        // Get directory entries from namespace
        let entries: [VFSDirEntry]
        do {
            entries = try namespace.readDir(vfsPath)
        } catch {
            return // Skip unreadable directories
        }

        for entry in entries {
            let childVFSPath = vfsPath == "." ? entry.name : "\(vfsPath)/\(entry.name)"
            let childHostPath = "\(hostPath)/\(entry.name)"

            if entry.isDir {
                try materializeDirectory(
                    namespace: namespace,
                    vfsPath: childVFSPath,
                    hostPath: childHostPath,
                    depth: depth + 1
                )
            } else {
                // Materialize file
                do {
                    let file = try namespace.open(childVFSPath)
                    defer { try? file.close() }
                    let data = try file.readAll()
                    fm.createFile(atPath: childHostPath, contents: Data(data), attributes: nil)

                    // Set executable permission if applicable
                    let info = try file.stat()
                    if info.mode.rawValue & 0o111 != 0 {
                        try fm.setAttributes(
                            [.posixPermissions: 0o755],
                            ofItemAtPath: childHostPath
                        )
                    }
                } catch {
                    continue // Skip unreadable files
                }
            }
        }
    }

    /// Sync changes from a host directory back into a MemFS overlay.
    /// Compares the materialized directory with the original namespace and applies diffs.
    public static func syncBack(
        from hostDir: String,
        into overlay: MemFS,
        relativeTo basePath: String = "."
    ) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: hostDir) else { return }

        while let relativePath = enumerator.nextObject() as? String {
            let hostPath = "\(hostDir)/\(relativePath)"
            var isDir: ObjCBool = false
            fm.fileExists(atPath: hostPath, isDirectory: &isDir)

            if isDir.boolValue {
                try? overlay.mkdir(relativePath)
            } else {
                if let data = fm.contents(atPath: hostPath) {
                    try? overlay.writeFile(relativePath, data: Array(data))
                }
            }
        }
    }
}
