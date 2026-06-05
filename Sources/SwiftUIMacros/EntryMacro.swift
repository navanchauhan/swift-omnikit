import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct EntryMacro: PeerMacro, AccessorMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let entry = EntryDescription(declaration) else { return [] }
        return [
            """
            private enum \(raw: entry.keyName): OmniUICore.EnvironmentKey {
                static let defaultValue: \(entry.type) = \(entry.initialValue)
            }
            """
        ]
    }

    public static func expansion(
        of attribute: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let entry = EntryDescription(declaration) else { return [] }
        return [
            "get { self[\(raw: entry.keyName).self] }",
            "set { self[\(raw: entry.keyName).self] = newValue }",
        ]
    }
}

private struct EntryDescription {
    let keyName: String
    let type: TypeSyntax
    let initialValue: ExprSyntax

    init?(_ declaration: some DeclSyntaxProtocol) {
        guard let variable = declaration.as(VariableDeclSyntax.self),
              let binding = variable.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              let type = binding.typeAnnotation?.type else {
            return nil
        }
        self.keyName = "_OmniEntryKey_\(pattern.identifier.text)"
        self.type = type
        self.initialValue = binding.initializer?.value ?? ExprSyntax("nil")
    }
}
