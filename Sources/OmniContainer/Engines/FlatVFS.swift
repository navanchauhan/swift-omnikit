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

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Build a FlatVFS from a VFSNamespace by walking all entries.
    public static func from(namespace: VFSNamespace) -> FlatVFS {
        FlatVFS(entries: entries(from: namespace, srcPath: ".", mountedAt: "."))
    }

    /// Build flat entries from any VFS subtree, mounting them at the given destination path.
    public static func entries(
        from fs: any VFS,
        srcPath: String = ".",
        mountedAt mountPath: String = "."
    ) -> [Entry] {
        let flat = FlatVFS()
        flat.walk(fs: fs, sourcePath: srcPath, destinationPath: mountPath, depth: 0)
        return flat.entries
    }

    public func append(entries newEntries: [Entry]) {
        entries.append(contentsOf: newEntries)
    }

    private func walk(
        fs: any VFS,
        sourcePath: String,
        destinationPath: String,
        depth: Int
    ) {
        guard depth < 32 else { return }
        guard let dirFS = fs as? VFSReadDirFS else { return }

        let dirEntries: [VFSDirEntry]
        do {
            dirEntries = try dirFS.readDir(sourcePath)
        } catch {
            return
        }

        // Add directory entry itself (except root)
        if destinationPath != "." {
            entries.append(Entry(
                path: destinationPath, type: .directory, mode: 0o755,
                data: [], symlinkTarget: ""))
        }

        for entry in dirEntries {
            let childSourcePath = sourcePath == "." ? entry.name : "\(sourcePath)/\(entry.name)"
            let childDestinationPath =
                destinationPath == "." ? entry.name : "\(destinationPath)/\(entry.name)"

            if entry.isSymlink {
                // Get symlink target from stat
                if let statFS = fs as? VFSStatFS,
                   let info = try? statFS.stat(childSourcePath),
                   let target = info.symlinkTarget {
                    entries.append(Entry(
                        path: childDestinationPath, type: .symlink, mode: 0o777,
                        data: [], symlinkTarget: target))
                }
                continue
            }

            if entry.isDir {
                walk(
                    fs: fs,
                    sourcePath: childSourcePath,
                    destinationPath: childDestinationPath,
                    depth: depth + 1
                )
            } else {
                do {
                    let file = try fs.open(childSourcePath)
                    defer { try? file.close() }
                    let data = try file.readAll()
                    let info = try file.stat()
                    entries.append(Entry(
                        path: childDestinationPath, type: .file, mode: info.mode.rawValue,
                        data: data, symlinkTarget: ""))
                } catch {
                    continue
                }
            }
        }
    }
}
