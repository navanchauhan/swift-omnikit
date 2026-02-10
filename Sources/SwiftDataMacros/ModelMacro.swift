import SwiftSyntax
import SwiftSyntaxMacros

/// Stub implementation for SwiftData's `@Model` macro.
///
/// The real SwiftData macro synthesizes persistence + observation metadata. For OmniKit's
/// compatibility layer, we only need the attribute to be recognized by the compiler.
public struct ModelMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }

    public static func expansion(
        of attribute: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        []
    }
}
