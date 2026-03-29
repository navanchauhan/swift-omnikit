import Foundation

/// Host-directory-backed filesystem.
/// Safety: callers serialize VFS mutations, and the per-instance `FileManager`
/// is immutable after initialization.
public final class DiskFS: @unchecked Sendable, VFSFullFS {
    private let rootPath: String
    private let fileManager: FileManager

    public init(root: String) {
        // Resolve symlinks and standardize the root path.
        self.rootPath = (root as NSString).standardizingPath
        self.fileManager = FileManager()
    }

    // MARK: - Path mapping

    private func hostPath(_ vfsPath: String) throws -> String {
        let clean = PathUtils.cleanPath(vfsPath)
        let mapped: String
        if clean == "." || clean == "/" {
            mapped = rootPath
        } else {
            let stripped = PathUtils.stripLeadingSlash(clean)
            mapped = (rootPath as NSString).appendingPathComponent(stripped)
        }
        // Resolve symlinks to guard against path traversal.
        let resolved = (mapped as NSString).resolvingSymlinksInPath
        let resolvedRoot = (rootPath as NSString).resolvingSymlinksInPath
        guard resolved.hasPrefix(resolvedRoot) else {
            throw VFSError.pathTraversal("resolved path escapes root: \(vfsPath)")
        }
        return mapped
    }

    // MARK: - VFS

    public func open(_ path: String) throws -> any VFSFile {
        let hp = try hostPath(path)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: hp, isDirectory: &isDir) else {
            throw VFSError.notFound(path)
        }
        return DiskFSFile(hostPath: hp, isDirectory: isDir.boolValue)
    }

    // MARK: - VFSReadDirFS

    public func readDir(_ path: String) throws -> [VFSDirEntry] {
        let hp = try hostPath(path)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: hp, isDirectory: &isDir), isDir.boolValue else {
            throw VFSError.notDirectory(path)
        }
        let contents = try fileManager.contentsOfDirectory(atPath: hp)
        return try contents.map { name in
            let childPath = (hp as NSString).appendingPathComponent(name)
            var childIsDir: ObjCBool = false
            fileManager.fileExists(atPath: childPath, isDirectory: &childIsDir)
            let attrs = try fileManager.attributesOfItem(atPath: childPath)
            let size = attrs[.size] as? Int64
            return VFSDirEntry(name: name, isDir: childIsDir.boolValue, size: size)
        }.sorted { $0.name < $1.name }
    }

    // MARK: - VFSStatFS

    public func stat(_ path: String) throws -> VFSFileInfo {
        let hp = try hostPath(path)
        let attrs = try fileManager.attributesOfItem(atPath: hp)
        let name = (hp as NSString).lastPathComponent
        let size = attrs[.size] as? Int64 ?? 0
        let modDate = attrs[.modificationDate] as? Date ?? Date()
        let fileType = attrs[.type] as? FileAttributeType
        let isDir = fileType == .typeDirectory
        let isSymlink = fileType == .typeSymbolicLink
        let posixPerms = attrs[.posixPermissions] as? UInt16 ?? 0o644
        return VFSFileInfo(
            name: name,
            size: size,
            mode: VFSFileMode(rawValue: posixPerms),
            modTime: modDate,
            isDir: isDir,
            isSymlink: isSymlink
        )
    }

    // MARK: - VFSMutableFS

    public func createFile(_ path: String, data: [UInt8]) throws {
        let hp = try hostPath(path)
        guard !fileManager.fileExists(atPath: hp) else {
            throw VFSError.alreadyExists(path)
        }
        guard fileManager.createFile(atPath: hp, contents: Data(data)) else {
            throw VFSError.permissionDenied(path)
        }
    }

    public func mkdir(_ path: String) throws {
        let hp = try hostPath(path)
        try fileManager.createDirectory(atPath: hp, withIntermediateDirectories: false)
    }

    public func remove(_ path: String) throws {
        let hp = try hostPath(path)
        guard fileManager.fileExists(atPath: hp) else {
            throw VFSError.notFound(path)
        }
        try fileManager.removeItem(atPath: hp)
    }

    public func writeFile(_ path: String, data: [UInt8]) throws {
        let hp = try hostPath(path)
        try Data(data).write(to: URL(fileURLWithPath: hp))
    }

    public func rename(from: String, to: String) throws {
        let fromHP = try hostPath(from)
        let toHP = try hostPath(to)
        try fileManager.moveItem(atPath: fromHP, toPath: toHP)
    }

    public func symlink(target: String, link: String) throws {
        let linkHP = try hostPath(link)
        try fileManager.createSymbolicLink(atPath: linkHP, withDestinationPath: target)
    }

    // MARK: - VFSResolveFS

    public func resolveFS(_ path: String) throws -> (any VFS, String) {
        return (self, path)
    }

    /// Returns a stable host path for mounting this subtree directly into blink.
    public func mountSourcePath(for path: String = ".") throws -> String {
        let mapped = try hostPath(path)
        let baseURL: URL
        if mapped.hasPrefix("/") {
            baseURL = URL(fileURLWithPath: mapped)
        } else {
            baseURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appending(path: mapped)
        }
        return baseURL.standardizedFileURL.path
    }
}

/// File handle for DiskFS.
private final class DiskFSFile: @unchecked Sendable, VFSFile {
    private let hostPath: String
    private let isDirectory: Bool
    private let lock = NSLock()
    private var handle: FileHandle?
    private var closed = false

    init(hostPath: String, isDirectory: Bool) {
        self.hostPath = hostPath
        self.isDirectory = isDirectory
    }

    func stat() throws -> VFSFileInfo {
        let attrs = try FileManager.default.attributesOfItem(atPath: hostPath)
        let name = (hostPath as NSString).lastPathComponent
        let size = attrs[.size] as? Int64 ?? 0
        let modDate = attrs[.modificationDate] as? Date ?? Date()
        let posixPerms = attrs[.posixPermissions] as? UInt16 ?? 0o644
        return VFSFileInfo(
            name: name,
            size: size,
            mode: VFSFileMode(rawValue: posixPerms),
            modTime: modDate,
            isDir: isDirectory
        )
    }

    func read(into buffer: inout [UInt8], count: Int) throws -> Int {
        return try lock.withLock {
            guard !closed else { return 0 }
            let fh = try getOrOpenHandle()
            let data = fh.readData(ofLength: count)
            let readCount = data.count
            data.copyBytes(to: &buffer, count: readCount)
            return readCount
        }
    }

    func readAll() throws -> [UInt8] {
        return try lock.withLock {
            guard !closed else { return [] }
            let data = try Data(contentsOf: URL(fileURLWithPath: hostPath))
            return [UInt8](data)
        }
    }

    func close() throws {
        lock.withLock {
            closed = true
            handle?.closeFile()
            handle = nil
        }
    }

    private func getOrOpenHandle() throws -> FileHandle {
        if let h = handle { return h }
        let h = try FileHandle(forReadingFrom: URL(fileURLWithPath: hostPath))
        handle = h
        return h
    }
}
