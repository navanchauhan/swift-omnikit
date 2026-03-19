/// Minimal filesystem: open a file by path (Go fs.FS equivalent).
public protocol VFS: Sendable {
    func open(_ path: String) throws -> any VFSFile
}

/// File handle returned by VFS.open().
public protocol VFSFile: AnyObject, Sendable {
    func stat() throws -> VFSFileInfo
    func read(into buffer: inout [UInt8], count: Int) throws -> Int
    func readAll() throws -> [UInt8]
    func close() throws
}

/// Directory listing capability.
public protocol VFSReadDirFS: VFS {
    func readDir(_ path: String) throws -> [VFSDirEntry]
}

/// Stat without opening.
public protocol VFSStatFS: VFS {
    func stat(_ path: String) throws -> VFSFileInfo
}

/// Namespace resolution: given a path, return (filesystem, resolvedPath).
public protocol VFSResolveFS: VFS {
    func resolveFS(_ path: String) throws -> (any VFS, String)
}

/// Write support.
public protocol VFSMutableFS: VFS {
    func createFile(_ path: String, data: [UInt8]) throws
    func mkdir(_ path: String) throws
    func remove(_ path: String) throws
    func writeFile(_ path: String, data: [UInt8]) throws
    func rename(from: String, to: String) throws
    func symlink(target: String, link: String) throws
}

/// Writable file handle.
public protocol VFSWritableFile: VFSFile {
    func write(_ data: [UInt8]) throws -> Int
}

/// Seekable file handle.
public protocol VFSSeekableFile: VFSFile {
    func seek(offset: Int64, whence: SeekWhence) throws -> Int64
    func pread(into buffer: inout [UInt8], count: Int, offset: Int64) throws -> Int
    func pwrite(_ data: [UInt8], offset: Int64) throws -> Int
}

/// Combined read-write filesystem.
public protocol VFSFullFS: VFSReadDirFS, VFSStatFS, VFSMutableFS, VFSResolveFS {}
