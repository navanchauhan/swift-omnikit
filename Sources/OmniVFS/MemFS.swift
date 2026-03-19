import Foundation

/// In-memory mutable filesystem. Thread-safe via NSLock.
public final class MemFS: @unchecked Sendable, VFSFullFS {
    private enum MemNode {
        case file(Data)
        case directory([String: MemNode])
    }

    private let lock = NSLock()
    private var root: MemNode = .directory([:])
    private var totalBytes: Int = 0
    public let maxBytes: Int

    public init(maxBytes: Int = Int.max) {
        self.maxBytes = maxBytes
    }

    // MARK: - VFS

    public func open(_ path: String) throws -> any VFSFile {
        let normPath = PathUtils.cleanPath(path)
        return try lock.withLock {
            let node = try lookupNode(normPath)
            switch node {
            case .file(let data):
                let (_, name) = PathUtils.splitPath(normPath)
                return MemFSFile(name: name, data: data, isDir: false)
            case .directory:
                let (_, name) = PathUtils.splitPath(normPath)
                return MemFSFile(name: name, data: Data(), isDir: true)
            }
        }
    }

    // MARK: - VFSReadDirFS

    public func readDir(_ path: String) throws -> [VFSDirEntry] {
        let normPath = PathUtils.cleanPath(path)
        return try lock.withLock {
            let node = try lookupNode(normPath)
            guard case .directory(let children) = node else {
                throw VFSError.notDirectory(path)
            }
            return children.map { name, child in
                switch child {
                case .file(let data):
                    return VFSDirEntry(name: name, isDir: false, size: Int64(data.count))
                case .directory:
                    return VFSDirEntry(name: name, isDir: true)
                }
            }.sorted { $0.name < $1.name }
        }
    }

    // MARK: - VFSStatFS

    public func stat(_ path: String) throws -> VFSFileInfo {
        let normPath = PathUtils.cleanPath(path)
        return try lock.withLock {
            let node = try lookupNode(normPath)
            let (_, name) = PathUtils.splitPath(normPath)
            switch node {
            case .file(let data):
                return VFSFileInfo(name: name, size: Int64(data.count), isDir: false)
            case .directory:
                return VFSFileInfo(name: name, size: 0, mode: .defaultDir, isDir: true)
            }
        }
    }

    // MARK: - VFSMutableFS

    public func createFile(_ path: String, data: [UInt8]) throws {
        let normPath = PathUtils.cleanPath(path)
        guard normPath != "." && normPath != "/" else {
            throw VFSError.alreadyExists(path)
        }
        try lock.withLock {
            let newSize = totalBytes + data.count
            if newSize > maxBytes {
                throw VFSError.capacityExceeded("write would exceed maxBytes (\(maxBytes))")
            }
            let (parent, name) = PathUtils.splitPath(normPath)
            var dirNode = try lookupNode(parent)
            guard case .directory(var children) = dirNode else {
                throw VFSError.notDirectory(parent)
            }
            if children[name] != nil {
                throw VFSError.alreadyExists(path)
            }
            children[name] = .file(Data(data))
            dirNode = .directory(children)
            try setNode(parent, dirNode)
            totalBytes = newSize
        }
    }

    public func mkdir(_ path: String) throws {
        let normPath = PathUtils.cleanPath(path)
        guard normPath != "." && normPath != "/" else {
            throw VFSError.alreadyExists(path)
        }
        try lock.withLock {
            let (parent, name) = PathUtils.splitPath(normPath)
            var dirNode = try lookupNode(parent)
            guard case .directory(var children) = dirNode else {
                throw VFSError.notDirectory(parent)
            }
            if children[name] != nil {
                throw VFSError.alreadyExists(path)
            }
            children[name] = .directory([:])
            dirNode = .directory(children)
            try setNode(parent, dirNode)
        }
    }

    public func remove(_ path: String) throws {
        let normPath = PathUtils.cleanPath(path)
        guard normPath != "." && normPath != "/" else {
            throw VFSError.notSupported("cannot remove root")
        }
        try lock.withLock {
            let (parent, name) = PathUtils.splitPath(normPath)
            var dirNode = try lookupNode(parent)
            guard case .directory(var children) = dirNode else {
                throw VFSError.notDirectory(parent)
            }
            guard let existing = children[name] else {
                throw VFSError.notFound(path)
            }
            if case .file(let data) = existing {
                totalBytes -= data.count
            }
            children.removeValue(forKey: name)
            dirNode = .directory(children)
            try setNode(parent, dirNode)
        }
    }

    public func writeFile(_ path: String, data: [UInt8]) throws {
        let normPath = PathUtils.cleanPath(path)
        guard normPath != "." && normPath != "/" else {
            throw VFSError.isDirectory(path)
        }
        try lock.withLock {
            let (parent, name) = PathUtils.splitPath(normPath)
            var dirNode = try lookupNode(parent)
            guard case .directory(var children) = dirNode else {
                throw VFSError.notDirectory(parent)
            }
            var oldSize = 0
            if let existing = children[name] {
                if case .directory = existing {
                    throw VFSError.isDirectory(path)
                }
                if case .file(let oldData) = existing {
                    oldSize = oldData.count
                }
            }
            let newTotal = totalBytes - oldSize + data.count
            if newTotal > maxBytes {
                throw VFSError.capacityExceeded("write would exceed maxBytes (\(maxBytes))")
            }
            children[name] = .file(Data(data))
            dirNode = .directory(children)
            try setNode(parent, dirNode)
            totalBytes = newTotal
        }
    }

    public func rename(from: String, to: String) throws {
        let normFrom = PathUtils.cleanPath(from)
        let normTo = PathUtils.cleanPath(to)
        try lock.withLock {
            let node = try lookupNode(normFrom)
            let (fromParent, fromName) = PathUtils.splitPath(normFrom)
            let (toParent, toName) = PathUtils.splitPath(normTo)
            // Remove from source.
            var srcDirNode = try lookupNode(fromParent)
            guard case .directory(var srcChildren) = srcDirNode else {
                throw VFSError.notDirectory(fromParent)
            }
            srcChildren.removeValue(forKey: fromName)
            srcDirNode = .directory(srcChildren)
            try setNode(fromParent, srcDirNode)
            // Add to destination.
            var dstDirNode = try lookupNode(toParent)
            guard case .directory(var dstChildren) = dstDirNode else {
                throw VFSError.notDirectory(toParent)
            }
            dstChildren[toName] = node
            dstDirNode = .directory(dstChildren)
            try setNode(toParent, dstDirNode)
        }
    }

    public func symlink(target: String, link: String) throws {
        // MemFS does not support symlinks; store as a file with the target path.
        throw VFSError.notSupported("symlinks not supported in MemFS")
    }

    // MARK: - VFSResolveFS

    public func resolveFS(_ path: String) throws -> (any VFS, String) {
        return (self, path)
    }

    // MARK: - Internal helpers (must be called under lock)

    private func lookupNode(_ path: String) throws -> MemNode {
        let normPath = PathUtils.cleanPath(path)
        if normPath == "." || normPath == "/" { return root }
        let components = normPath.split(separator: "/")
        var current = root
        for component in components {
            guard case .directory(let children) = current else {
                throw VFSError.notDirectory(String(component))
            }
            guard let next = children[String(component)] else {
                throw VFSError.notFound(normPath)
            }
            current = next
        }
        return current
    }

    private func setNode(_ path: String, _ node: MemNode) throws {
        let normPath = PathUtils.cleanPath(path)
        if normPath == "." || normPath == "/" {
            root = node
            return
        }
        let components = normPath.split(separator: "/").map(String.init)
        root = try setNodeRecursive(root, components: components, index: 0, value: node)
    }

    private func setNodeRecursive(
        _ current: MemNode,
        components: [String],
        index: Int,
        value: MemNode
    ) throws -> MemNode {
        guard case .directory(var children) = current else {
            throw VFSError.notDirectory(components[index])
        }
        if index == components.count - 1 {
            children[components[index]] = value
            return .directory(children)
        }
        guard let child = children[components[index]] else {
            throw VFSError.notFound(components[index])
        }
        children[components[index]] = try setNodeRecursive(
            child, components: components, index: index + 1, value: value
        )
        return .directory(children)
    }
}

/// File handle for MemFS.
private final class MemFSFile: @unchecked Sendable, VFSFile {
    private let lock = NSLock()
    private let name: String
    private let data: Data
    private let isDirectory: Bool
    private var offset: Int = 0
    private var closed = false

    init(name: String, data: Data, isDir: Bool) {
        self.name = name
        self.data = data
        self.isDirectory = isDir
    }

    func stat() throws -> VFSFileInfo {
        return VFSFileInfo(
            name: name,
            size: Int64(data.count),
            mode: isDirectory ? .defaultDir : .defaultFile,
            isDir: isDirectory
        )
    }

    func read(into buffer: inout [UInt8], count: Int) throws -> Int {
        return lock.withLock {
            guard !closed else { return 0 }
            let remaining = data.count - offset
            let toRead = min(count, remaining)
            if toRead <= 0 { return 0 }
            data.copyBytes(to: &buffer, from: offset..<(offset + toRead))
            offset += toRead
            return toRead
        }
    }

    func readAll() throws -> [UInt8] {
        return lock.withLock {
            guard !closed else { return [] }
            return [UInt8](data)
        }
    }

    func close() throws {
        lock.withLock { closed = true }
    }
}
