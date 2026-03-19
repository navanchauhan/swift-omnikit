import Foundation

public struct VFSFileInfo: Sendable {
    public var name: String
    public var size: Int64
    public var mode: VFSFileMode
    public var modTime: Date
    public var isDir: Bool
    public var isSymlink: Bool

    public init(
        name: String,
        size: Int64,
        mode: VFSFileMode = .defaultFile,
        modTime: Date = Date(),
        isDir: Bool = false,
        isSymlink: Bool = false
    ) {
        self.name = name
        self.size = size
        self.mode = mode
        self.modTime = modTime
        self.isDir = isDir
        self.isSymlink = isSymlink
    }
}

public struct VFSDirEntry: Sendable {
    public var name: String
    public var isDir: Bool
    public var size: Int64?

    public init(name: String, isDir: Bool, size: Int64? = nil) {
        self.name = name
        self.isDir = isDir
        self.size = size
    }
}

public struct VFSFileMode: RawRepresentable, Sendable, Equatable {
    public var rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let defaultFile = VFSFileMode(rawValue: 0o644)
    public static let defaultDir = VFSFileMode(rawValue: 0o755)
    public static let executable = VFSFileMode(rawValue: 0o755)
    public static let readOnly = VFSFileMode(rawValue: 0o444)
}

public enum SeekWhence: Sendable {
    case set, current, end
}

public enum BindMode: Sendable {
    /// New binding prepended to list (checked first) — Wanix ModeAfter.
    case after
    /// New binding appended to list (checked last) — Wanix ModeBefore.
    case before
    /// Replaces all existing bindings at path — Wanix ModeReplace.
    case replace
}

public enum VFSError: Error, Sendable {
    case notFound(String)
    case permissionDenied(String)
    case isDirectory(String)
    case notDirectory(String)
    case alreadyExists(String)
    case notSupported(String)
    case pathTraversal(String)
    case invalidPath(String)
    case capacityExceeded(String)
    case cyclicResolution(String)
    case isClosed
}
