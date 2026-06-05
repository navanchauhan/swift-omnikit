@MainActor
public protocol PreviewProvider {
    associatedtype Previews: View
    @ViewBuilder static var previews: Previews { get }
}

public struct PreviewLayout: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let sizeThatFits = PreviewLayout("sizeThatFits")
}

@MainActor
public extension View {
    func previewLayout(_ layout: PreviewLayout) -> some View {
        _ = layout
        return self
    }
}
