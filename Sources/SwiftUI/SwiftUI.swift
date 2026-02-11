@_exported import Foundation
@_exported import OmniUI

@freestanding(declaration, names: named(__OmniPreview))
public macro Preview(_ name: String? = nil, @ViewBuilder _ body: () -> AnyView) = #externalMacro(module: "SwiftUIMacros", type: "PreviewMacro")
