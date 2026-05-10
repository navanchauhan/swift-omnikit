// Compatibility namespace for code that still uses qualified SwiftUI symbols
// after importing OmniUI as a drop-in replacement.

public enum SwiftUI {
    public typealias Section<Parent: View, Content: View, Footer: View> = OmniUICore.Section<Parent, Content, Footer>
}
