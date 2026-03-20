import Foundation

/// Read-only filesystem parsed from tar archive bytes.
public final class TarFS: Sendable, VFSReadDirFS, VFSStatFS {
    fileprivate struct TarEntry: Sendable {
        let name: String
        let size: Int64
        let mode: UInt16
        let modTime: Date
        let isDir: Bool
        let isSymlink: Bool
        let symlinkTarget: String?
        let data: ArraySlice<UInt8>
    }

    private struct TarDir: Sendable {
        var entries: [String: Int] // name -> index into allEntries
        var childNames: [String]   // ordered child names for readDir
    }

    private let allEntries: [TarEntry]
    private let dirs: [String: TarDir]   // path -> directory info
    private let entryIndex: [String: Int] // path -> index into allEntries

    public init(data: [UInt8]) throws {
        var entries: [TarEntry] = []
        var entryIdx: [String: Int] = [:]
        var dirMap: [String: TarDir] = [:]

        // Ensure root dir exists.
        dirMap["."] = TarDir(entries: [:], childNames: [])

        var offset = 0
        let count = data.count

        while offset + 512 <= count {
            // Check for end-of-archive (two zero blocks).
            let headerBlock = Array(data[offset..<(offset + 512)])
            if headerBlock.allSatisfy({ $0 == 0 }) { break }

            // Parse header.
            let nameBytes = Array(headerBlock[0..<100])
            let modeBytes = Array(headerBlock[100..<108])
            let sizeBytes = Array(headerBlock[124..<136])
            let mtimeBytes = Array(headerBlock[136..<148])
            let typeFlag = headerBlock[156]
            let linkNameBytes = Array(headerBlock[157..<257])
            let prefixBytes = Array(headerBlock[345..<500])

            let prefix = TarFS.parseString(prefixBytes)
            let baseName = TarFS.parseString(nameBytes)
            var fullName: String
            if prefix.isEmpty {
                fullName = baseName
            } else {
                fullName = prefix + "/" + baseName
            }
            // Normalize: strip leading ./ and trailing /.
            if fullName.hasPrefix("./") { fullName = String(fullName.dropFirst(2)) }
            while fullName.hasSuffix("/") { fullName = String(fullName.dropLast()) }
            if fullName.isEmpty { fullName = "." }

            let mode = UInt16(TarFS.parseOctal(modeBytes))
            let size = Int64(TarFS.parseOctal(sizeBytes))
            let mtime = TimeInterval(TarFS.parseOctal(mtimeBytes))
            let modTime = Date(timeIntervalSince1970: mtime)
            let isDir = typeFlag == 0x35 /* '5' */ || typeFlag == 0x00 && fullName == "."
            let isSymlink = typeFlag == 0x32 /* '2' */
            let isHardLink = typeFlag == 0x31 /* '1' */
            let linkName = TarFS.parseString(linkNameBytes)

            offset += 512
            let dataStart = offset
            let dataSize = Int(size)
            let paddedSize = (dataSize + 511) / 512 * 512
            offset += paddedSize

            guard dataStart + dataSize <= count else { break }

            let entryData = data[dataStart..<(dataStart + dataSize)]

            // Determine symlink target
            let symlinkTarget: String?
            if isSymlink || isHardLink {
                symlinkTarget = linkName.isEmpty ? nil : linkName
            } else {
                symlinkTarget = nil
            }

            let entry = TarEntry(
                name: fullName,
                size: size,
                mode: mode,
                modTime: modTime,
                isDir: isDir,
                isSymlink: isSymlink || isHardLink,
                symlinkTarget: symlinkTarget,
                data: entryData
            )
            let idx = entries.count
            entries.append(entry)
            entryIdx[fullName] = idx

            if isDir {
                if dirMap[fullName] == nil {
                    dirMap[fullName] = TarDir(entries: [:], childNames: [])
                }
            }

            // Register in parent directory.
            if fullName != "." {
                let (parent, childName) = PathUtils.splitPath(fullName)
                if dirMap[parent] == nil {
                    dirMap[parent] = TarDir(entries: [:], childNames: [])
                }
                if dirMap[parent]!.entries[childName] == nil {
                    dirMap[parent]!.entries[childName] = idx
                    dirMap[parent]!.childNames.append(childName)
                }
            }
        }

        self.allEntries = entries
        self.entryIndex = entryIdx
        self.dirs = dirMap
    }

    // MARK: - VFS

    public func open(_ path: String) throws -> any VFSFile {
        let normPath = PathUtils.cleanPath(path)
        if let idx = entryIndex[normPath] {
            let entry = allEntries[idx]
            // If this is a symlink, resolve it
            if entry.isSymlink, let target = entry.symlinkTarget {
                let resolvedPath = resolveSymlinkTarget(from: normPath, target: target)
                return try open(resolvedPath)
            }
            return TarFSFile(entry: entry)
        }
        // Check if it's a directory that has no explicit entry.
        if dirs[normPath] != nil {
            return TarFSFile(entry: TarEntry(
                name: normPath, size: 0, mode: 0o755, modTime: Date(),
                isDir: true, isSymlink: false, symlinkTarget: nil, data: [][...])
            )
        }
        throw VFSError.notFound(path)
    }

    // MARK: - VFSReadDirFS

    public func readDir(_ path: String) throws -> [VFSDirEntry] {
        let normPath = PathUtils.cleanPath(path)
        guard let dir = dirs[normPath] else {
            // The path might be a symlink to a directory — try resolving
            if let idx = entryIndex[normPath] {
                let entry = allEntries[idx]
                if entry.isSymlink, let target = entry.symlinkTarget {
                    let resolvedPath = resolveSymlinkTarget(from: normPath, target: target)
                    return try readDir(resolvedPath)
                }
            }
            throw VFSError.notDirectory(path)
        }
        return dir.childNames.map { name in
            let idx = dir.entries[name]!
            let entry = allEntries[idx]
            return VFSDirEntry(
                name: name,
                isDir: entry.isDir,
                isSymlink: entry.isSymlink,
                size: entry.isDir ? nil : entry.size
            )
        }
    }

    // MARK: - VFSStatFS

    public func stat(_ path: String) throws -> VFSFileInfo {
        let normPath = PathUtils.cleanPath(path)
        if let idx = entryIndex[normPath] {
            let entry = allEntries[idx]
            let (_, name) = PathUtils.splitPath(normPath)
            return VFSFileInfo(
                name: name,
                size: entry.size,
                mode: VFSFileMode(rawValue: entry.mode),
                modTime: entry.modTime,
                isDir: entry.isDir,
                isSymlink: entry.isSymlink,
                symlinkTarget: entry.symlinkTarget
            )
        }
        if dirs[normPath] != nil {
            let (_, name) = PathUtils.splitPath(normPath)
            return VFSFileInfo(name: name, size: 0, mode: .defaultDir, isDir: true)
        }
        throw VFSError.notFound(path)
    }

    // MARK: - Symlink resolution

    /// Resolve a symlink target relative to the entry that contains it.
    private func resolveSymlinkTarget(from sourcePath: String, target: String, depth: Int = 0) -> String {
        guard depth < 32 else { return target }

        let resolved: String
        if target.hasPrefix("/") {
            // Absolute symlink — strip leading /
            resolved = PathUtils.cleanPath(String(target.dropFirst()))
        } else {
            // Relative symlink — resolve relative to parent of source
            let (parent, _) = PathUtils.splitPath(sourcePath)
            resolved = PathUtils.cleanPath(PathUtils.joinPath(parent, target))
        }
        return resolved
    }

    // MARK: - Tar parsing helpers

    private static func parseString(_ bytes: [UInt8]) -> String {
        // Null-terminated ASCII string.
        let trimmed: [UInt8]
        if let nullIdx = bytes.firstIndex(of: 0) {
            trimmed = Array(bytes[..<nullIdx])
        } else {
            trimmed = bytes
        }
        return String(bytes: trimmed, encoding: .utf8) ?? ""
    }

    private static func parseOctal(_ bytes: [UInt8]) -> Int {
        let str = parseString(bytes).trimmingCharacters(in: .whitespaces)
        return Int(str, radix: 8) ?? 0
    }
}

/// File handle for TarFS.
private final class TarFSFile: @unchecked Sendable, VFSFile {
    private let entry: TarFS.TarEntry
    private let lock = NSLock()
    private var offset: Int = 0

    // Make TarEntry accessible within this file.
    fileprivate typealias TarEntry = TarFS.TarEntry

    init(entry: TarFS.TarEntry) {
        self.entry = entry
    }

    func stat() throws -> VFSFileInfo {
        let (_, name) = PathUtils.splitPath(entry.name)
        return VFSFileInfo(
            name: name,
            size: entry.size,
            mode: VFSFileMode(rawValue: entry.mode),
            modTime: entry.modTime,
            isDir: entry.isDir,
            isSymlink: entry.isSymlink,
            symlinkTarget: entry.symlinkTarget
        )
    }

    func read(into buffer: inout [UInt8], count: Int) throws -> Int {
        return lock.withLock {
            let remaining = entry.data.count - offset
            let toRead = min(count, remaining)
            if toRead <= 0 { return 0 }
            let start = entry.data.startIndex + offset
            for i in 0..<toRead {
                buffer[i] = entry.data[start + i]
            }
            offset += toRead
            return toRead
        }
    }

    func readAll() throws -> [UInt8] {
        return Array(entry.data)
    }

    func close() throws {
        // No-op for tar entries.
    }
}
