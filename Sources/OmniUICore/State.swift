import Foundation

/// A SwiftUI-like `Binding`.
@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value>: @unchecked Sendable {
    public var wrappedValue: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }

    public var projectedValue: Binding<Value> { self }

    let get: () -> Value
    let set: (Value) -> Void

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = set
    }

    public init(projectedValue: Binding<Value>) {
        self = projectedValue
    }

    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        Binding<Subject>(
            get: { wrappedValue[keyPath: keyPath] },
            set: { wrappedValue[keyPath: keyPath] = $0 }
        )
    }
}

extension Binding: Sequence where Value: MutableCollection {}

extension Binding: Collection where Value: MutableCollection {
    public typealias Index = Value.Index
    public typealias Element = Binding<Value.Element>

    public var startIndex: Index { wrappedValue.startIndex }
    public var endIndex: Index { wrappedValue.endIndex }

    public func index(after i: Index) -> Index {
        wrappedValue.index(after: i)
    }

    public subscript(position: Index) -> Element {
        Binding<Value.Element>(
            get: { wrappedValue[position] },
            set: { wrappedValue[position] = $0 }
        )
    }
}

extension Binding: BidirectionalCollection where Value: BidirectionalCollection & MutableCollection {
    public func index(before i: Index) -> Index {
        wrappedValue.index(before: i)
    }
}

extension Binding: RandomAccessCollection where Value: RandomAccessCollection & MutableCollection {}

extension Binding: Identifiable where Value: Identifiable {
    public var id: Value.ID { wrappedValue.id }
}

/// A SwiftUI-like `State` backed by the current `_UIRuntime` via a build context.
///
/// This is intentionally limited and is designed to be portable and strict-concurrency friendly.
@propertyWrapper
@dynamicMemberLookup
public struct State<Value> {
    private let seed: _StateSeed
    private let initial: () -> Value
    private let location: _StateLocation

    public init(wrappedValue: Value, fileID: StaticString = #fileID, line: UInt = #line) {
        self.seed = _StateSeed(fileID: fileID, line: line)
        self.initial = { wrappedValue }
        self.location = _StateLocation()
    }

    public init(initialValue: Value, fileID: StaticString = #fileID, line: UInt = #line) {
        self.init(wrappedValue: initialValue, fileID: fileID, line: line)
    }

    public var wrappedValue: Value {
        get {
            if let resolved = location.resolved {
                return resolved.runtime._getState(seed: seed, path: resolved.path, initial: initial)
            }
            guard let runtime = _UIRuntime._current, let path = _UIRuntime._currentPath else {
                // Accessing outside a runtime build: fall back to the initial value.
                return initial()
            }
            // Resolve the owning view path the first time we access this State during a build.
            // This ensures mutations from nested event contexts (e.g. inside ForEach rows) still
            // update the same state slot instead of keying off the event's TaskLocal path.
            location.resolved = (runtime: runtime, path: path)
            return runtime._getState(seed: seed, path: path, initial: initial)
        }
        nonmutating set {
            if let resolved = location.resolved {
                setStateValue(runtime: resolved.runtime, path: resolved.path, value: newValue)
                return
            }
            guard let runtime = _UIRuntime._current, let path = _UIRuntime._currentPath else { return }
            location.resolved = (runtime: runtime, path: path)
            setStateValue(runtime: runtime, path: path, value: newValue)
        }
    }

    public var projectedValue: Binding<Value> {
        // Capture the runtime/path at projection time so the binding remains valid when invoked
        // from other event contexts (e.g. a focused TextField receiving keypresses).
        if let resolved = location.resolved {
            return Binding(
                get: { resolved.runtime._getState(seed: seed, path: resolved.path, initial: initial) },
                set: { setStateValue(runtime: resolved.runtime, path: resolved.path, value: $0) }
            )
        }

        if let runtime = _UIRuntime._current, let path = _UIRuntime._currentPath {
            location.resolved = (runtime: runtime, path: path)
            return Binding(
                get: { runtime._getState(seed: seed, path: path, initial: initial) },
                set: { setStateValue(runtime: runtime, path: path, value: $0) }
            )
        }

        return Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
    }

    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        projectedValue[dynamicMember: keyPath]
    }

    private func setStateValue(runtime: _UIRuntime, path: [Int], value: Value) {
        runtime._setState(seed: seed, path: path, value: value)
    }
}

struct _StateSeed {
    let fileID: StaticString
    let line: UInt
}

final class _StateLocation: @unchecked Sendable {
    // Resolved at first build-time access.
    var resolved: (runtime: _UIRuntime, path: [Int])? = nil
    init() {}
}

/// A SwiftUI-like PreferenceKey protocol for bottom-up data propagation.
/// Note: Preference callbacks fire after the current render pass completes.
/// State changes from callbacks take effect on the next render frame.
public protocol PreferenceKey {
    associatedtype Value
    static var defaultValue: Value { get }
    static func reduce(value: inout Value, nextValue: () -> Value)
}
