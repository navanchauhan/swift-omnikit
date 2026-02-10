public struct Animation: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static func spring() -> Animation { Animation("spring") }
}

@discardableResult
public func withAnimation<T>(_ animation: Animation? = nil, _ body: () -> T) -> T {
    _ = animation
    return body()
}

