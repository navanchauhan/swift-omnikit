public struct GrepOptions: Sendable {
    public var globFilter: String?
    public var caseInsensitive: Bool
    public var maxResults: Int

    public init(globFilter: String? = nil, caseInsensitive: Bool = false, maxResults: Int = 100) {
        self.globFilter = globFilter
        self.caseInsensitive = caseInsensitive
        self.maxResults = maxResults
    }
}
