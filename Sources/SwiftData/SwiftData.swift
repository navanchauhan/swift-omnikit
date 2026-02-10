// Minimal SwiftData compatibility surface.
//
// This module intentionally does not attempt to implement SwiftData's persistence.
// It exists so `import SwiftData` and common call sites (e.g. `@Model`, `@Query`)
// compile when targeting non-Apple platforms.

@attached(member, names: arbitrary)
@attached(extension, names: arbitrary)
public macro Model() = #externalMacro(module: "SwiftDataMacros", type: "ModelMacro")

public enum SortOrder: Sendable {
    case forward
    case reverse
}

@propertyWrapper
public struct Query<Element> {
    public var wrappedValue: [Element]

    public init() {
        self.wrappedValue = []
    }

    public init<V>(sort: KeyPath<Element, V>, order: SortOrder = .forward) where V: Comparable {
        // Stub: real implementation should read from a `ModelContext` and keep results live.
        self.wrappedValue = []
    }
}

