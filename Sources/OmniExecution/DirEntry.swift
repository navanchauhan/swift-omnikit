public struct DirEntry: Sendable {
    public var name: String
    public var isDir: Bool
    public var size: Int?

    public init(name: String, isDir: Bool, size: Int? = nil) {
        self.name = name
        self.isDir = isDir
        self.size = size
    }
}
