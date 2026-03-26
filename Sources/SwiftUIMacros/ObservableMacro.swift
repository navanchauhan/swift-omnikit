import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Lightweight fallback for Observation's `@Observable`.
///
/// Synthesizes:
/// 1. `ObservableObject` conformance (extension macro)
/// 2. An `_$observationRegistrar` stored property (member macro)
/// 3. Backing `_propertyName` storage for each mutable stored property (member macro)
/// 4. `@_ObservationTracked` on each mutable stored property (member attribute macro)
///
/// Together these ensure that any mutation of a stored property on an `@Observable` class
/// calls `_$observationRegistrar.notify()`, which marks interested runtimes dirty.
public struct ObservableMacro: MemberMacro, MemberAttributeMacro, ExtensionMacro {

    // MARK: - MemberMacro

    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        var result: [DeclSyntax] = []

        // Synthesize the registrar that powers change notifications.
        result.append("""
            public let _$observationRegistrar = OmniUICore._ObservationRegistrar()
            """)

        // Synthesize backing storage for each stored var.
        for member in declaration.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
                continue
            }
            // Skip computed properties.
            var isComputed = false
            for binding in varDecl.bindings {
                if let accessorBlock = binding.accessorBlock {
                    switch accessorBlock.accessors {
                    case .getter:
                        isComputed = true
                    case .accessors(let list):
                        if !list.isEmpty { isComputed = true }
                    }
                }
            }
            if isComputed { continue }

            for binding in varDecl.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    continue
                }
                let name = identifier.identifier.trimmedDescription
                let typeAnnotation = binding.typeAnnotation
                let initializer = binding.initializer

                if let typeAnnotation, let initializer {
                    result.append("private var _\(raw: name)\(typeAnnotation) \(initializer)")
                } else if let typeAnnotation {
                    result.append("private var _\(raw: name)\(typeAnnotation)")
                } else if let initializer {
                    result.append("private var _\(raw: name) \(initializer)")
                }
            }
        }

        return result
    }

    // MARK: - MemberAttributeMacro

    public static func expansion(
        of attribute: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        // Only attach to mutable stored properties (`var`).
        guard let varDecl = member.as(VariableDeclSyntax.self),
              varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
            return []
        }

        // Skip properties that already have accessors (computed properties).
        for binding in varDecl.bindings {
            if let accessorBlock = binding.accessorBlock {
                switch accessorBlock.accessors {
                case .getter:
                    return []
                case .accessors(let list):
                    if !list.isEmpty { return [] }
                }
            }
        }

        // Skip properties that already have the tracked attribute.
        for attr in varDecl.attributes {
            if case .attribute(let attrSyntax) = attr {
                let name = attrSyntax.attributeName.trimmedDescription
                if name == "_ObservationTracked" || name.hasSuffix("._ObservationTracked") {
                    return []
                }
            }
        }

        return [AttributeSyntax(stringLiteral: "@_ObservationTracked")]
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
/// Converts a plain stored property into a computed one backed by `_propertyName`.
/// The setter calls `_$observationRegistrar.notify()` after mutation so the
/// runtime knows to re-render.
public struct ObservationTrackedMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            return []
        }

        let name = identifier.identifier.trimmedDescription

        let getter: AccessorDeclSyntax = """
            get { _\(raw: name) }
            """

        let setter: AccessorDeclSyntax = """
            set {
                _\(raw: name) = newValue
                _$observationRegistrar.notify()
            }
            """

        return [getter, setter]
    }
}
