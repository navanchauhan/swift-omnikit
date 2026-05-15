import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Lightweight fallback for Observation's `@Observable`.
///
/// Synthesizes:
/// 1. `ObservableObject` conformance (extension macro)
/// 2. An `_$observationRegistrar` stored property (member macro)
///
/// The fallback intentionally does not rewrite stored properties into computed
/// properties. That keeps source-compatible initializers valid on toolchains
/// where full Observation is unavailable or unsuitable for Linux app builds.
public struct ObservableMacro: MemberMacro, MemberAttributeMacro, ExtensionMacro {

    // MARK: - MemberMacro

    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        [
            """
            public let _$observationRegistrar = OmniUICore._ObservationRegistrar()
            """
        ]
    }

    // MARK: - MemberAttributeMacro

    public static func expansion(
        of attribute: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        []
    }

    // MARK: - ExtensionMacro

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

/// Accessor macro applied to each stored `var` in an `@Observable` class.
///
/// Compatibility placeholder for sources that reference `_ObservationTracked`.
public struct ObservationTrackedMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        []
    }
}
