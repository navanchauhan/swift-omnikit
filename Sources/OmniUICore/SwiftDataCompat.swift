import Foundation

// A small, portable SwiftData-like surface. The goal is not full persistence, just enough API
// for iGopherBrowser's `Schema`/`ModelContainer`/`ModelContext`/`@Query` usage to compile and be usable.

public enum SortOrder: Sendable {
    case forward
    case reverse
}

public struct Schema: @unchecked Sendable {
    public let modelTypes: [Any.Type]

    public init(_ modelTypes: [Any.Type]) {
        self.modelTypes = modelTypes
    }
}

public struct ModelConfiguration: Sendable {
    public let schema: Schema
    public let isStoredInMemoryOnly: Bool

    public init(schema: Schema, isStoredInMemoryOnly: Bool = false) {
        self.schema = schema
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
    }
}

public final class ModelContainer: @unchecked Sendable {
    public let schema: Schema
    public let configurations: [ModelConfiguration]
    public let mainContext: ModelContext

    public init(for schema: Schema, configurations: [ModelConfiguration] = []) throws {
        self.schema = schema
        self.configurations = configurations
        self.mainContext = ModelContext(schema: schema)
    }

    public convenience init(for modelTypes: [Any.Type], inMemory: Bool = false) throws {
        let schema = Schema(modelTypes)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        try self.init(for: schema, configurations: [cfg])
    }
}

/// A minimal in-memory store for SwiftData-like models (`@Model` classes).
public final class ModelContext: @unchecked Sendable {
    private let schema: Schema?
    private let lock = NSLock()
    private var storage: [ObjectIdentifier: [AnyObject]] = [:]

    public init(schema: Schema? = nil) {
        self.schema = schema
    }

    public func insert<T: AnyObject>(_ model: T) {
        lock.lock()
        defer { lock.unlock() }

        _ = schema // reserved for future validation
        let key = ObjectIdentifier(T.self)
        var arr = storage[key] ?? []

        // Avoid duplicate inserts of the same object identity.
        if !arr.contains(where: { $0 === model }) {
            arr.append(model)
            storage[key] = arr
        }
    }

    public func delete<T: AnyObject>(_ model: T) {
        lock.lock()
        defer { lock.unlock() }

        let key = ObjectIdentifier(T.self)
        guard var arr = storage[key] else { return }
        arr.removeAll(where: { $0 === model })
        storage[key] = arr
    }

    public func fetch<T: AnyObject>(_ type: T.Type = T.self) -> [T] {
        lock.lock()
        defer { lock.unlock() }

        let key = ObjectIdentifier(T.self)
        return (storage[key] ?? []).compactMap { $0 as? T }
    }
}

@propertyWrapper
public struct Query<Element: AnyObject> {
    private let sort: ((Element, Element) -> Bool)?

    public init() {
        self.sort = nil
    }

    public init<V>(sort: KeyPath<Element, V>, order: SortOrder = .forward) where V: Comparable {
        self.sort = { lhs, rhs in
            let l = lhs[keyPath: sort]
            let r = rhs[keyPath: sort]
            switch order {
            case .forward:
                return l < r
            case .reverse:
                return l > r
            }
        }
    }

    public var wrappedValue: [Element] {
        let runtime = _UIRuntime._current
        let env = _UIRuntime._currentEnvironment ?? runtime?._baseEnvironment
        let ctx = env?.modelContext
        var items = ctx?.fetch(Element.self) ?? []
        if let sort {
            items.sort(by: sort)
        }
        return items
    }
}

