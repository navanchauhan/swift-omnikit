import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftUIMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ObservableMacro.self,
        ObservationIgnoredMacro.self,
        EntryMacro.self,
        PreviewMacro.self
    ]
}
