import Foundation
import OmniVFS

/// A flat, C-accessible representation of a VFS namespace.
/// All file data is stored in memory as a flat array of entries.
/// Used to pass the VFS to blink's C emulator without disk I/O.
public final class FlatVFS: @unchecked Sendable {

    public struct Entry: Sendable {
        public var path: String        // e.g. "bin/busybox"
        public var type: EntryType
        public var mode: UInt16
        public var data: [UInt8]       // file contents (empty for dirs/symlinks)
        public var symlinkTarget: String // symlink destination (empty for files/dirs)
    }

    public enum EntryType: UInt8, Sendable {
        case file = 0
        case directory = 1
        case symlink = 2
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    /// Build a FlatVFS from a VFSNamespace by walking all entries.
    public static func from(namespace: VFSNamespace) -> FlatVFS {
        let flat = FlatVFS()
        flat.walk(namespace: namespace, vfsPath: ".", depth: 0)
        return flat
    }

    private func walk(namespace: VFSNamespace, vfsPath: String, depth: Int) {
        guard depth < 32 else { return }

        let dirEntries: [VFSDirEntry]
        do {
            dirEntries = try namespace.readDir(vfsPath)
        } catch {
            return
        }

        // Add directory entry itself (except root)
        if vfsPath != "." {
            entries.append(Entry(
                path: vfsPath, type: .directory, mode: 0o755,
                data: [], symlinkTarget: ""))
        }

        for entry in dirEntries {
            let childPath = vfsPath == "." ? entry.name : "\(vfsPath)/\(entry.name)"

            if entry.isSymlink {
                // Get symlink target from stat
                if let info = try? namespace.stat(childPath),
                   let target = info.symlinkTarget {
                    entries.append(Entry(
                        path: childPath, type: .symlink, mode: 0o777,
                        data: [], symlinkTarget: target))
                }
                continue
            }

            if entry.isDir {
                walk(namespace: namespace, vfsPath: childPath, depth: depth + 1)
            } else {
                do {
                    let file = try namespace.open(childPath)
                    defer { try? file.close() }
                    let data = try file.readAll()
                    let info = try file.stat()
                    entries.append(Entry(
                        path: childPath, type: .file, mode: info.mode.rawValue,
                        data: data, symlinkTarget: ""))
                } catch {
                    continue
                }
            }
        }
    }
}
