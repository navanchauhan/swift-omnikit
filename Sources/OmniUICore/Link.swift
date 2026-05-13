import Foundation

public struct Link<Label: View>: View {
    public typealias Body = AnyView

    let destination: URL
    let label: Label

    public init(destination: URL, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    public var body: Body {
        AnyView(Button(action: {
            if let runtime = _UIRuntime._current {
                runtime.deliverURL(destination)
            } else {
                _ = OpenURLAction()(destination)
            }
        }, label: {
            label
        }))
    }
}
