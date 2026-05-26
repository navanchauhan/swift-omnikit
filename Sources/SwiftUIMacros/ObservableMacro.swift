import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Compatibility implementation for Observation's `@Observable` macro.
///
/// OmniUI's renderer model observes explicit registrar notifications through
/// `ObservableObject`. This macro gives aliased `import Observation` code the
/// same surface without relying on SDK macro expansions that vary by toolchain.
public struct ObservableMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        ["let _$observationRegistrar = OmniUICore._ObservationRegistrar()"]
    }

    public static func expansion(
        of attribute: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let ext: DeclSyntax = "extension \(type.trimmed): OmniUICore.ObservableObject {}"
        return [ext.cast(ExtensionDeclSyntax.self)]
    }
}

/// No-op compatibility implementation for Observation's `@ObservationIgnored`.
///
/// `ObservableMacro` does not rewrite stored property accessors, so ignored
/// properties only need the attribute to be accepted by the parser.
public struct ObservationIgnoredMacro: PeerMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
