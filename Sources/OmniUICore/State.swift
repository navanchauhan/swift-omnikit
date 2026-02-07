/// A SwiftUI-like `Binding`.
@propertyWrapper
public struct Binding<Value> {
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
}

/// A SwiftUI-like `State` backed by the current `_UIRuntime` via a build context.
///
/// This is intentionally limited and is designed to be portable and strict-concurrency friendly.
@propertyWrapper
public struct State<Value> {
    private let seed: _StateSeed
    private let initial: () -> Value

    public init(wrappedValue: Value, fileID: StaticString = #fileID, line: UInt = #line) {
        self.seed = _StateSeed(fileID: fileID, line: line)
        self.initial = { wrappedValue }
    }

    public var wrappedValue: Value {
        get {
            guard let runtime = _UIRuntime._current, let path = _UIRuntime._currentPath else {
                // Accessing outside a runtime build: fall back to the initial value.
                return initial()
            }
            return runtime._getState(seed: seed, path: path, initial: initial)
        }
        nonmutating set {
            guard let runtime = _UIRuntime._current, let path = _UIRuntime._currentPath else {
                return
            }
            runtime._setState(seed: seed, path: path, value: newValue)
        }
    }

    public var projectedValue: Binding<Value> {
        // Capture the runtime/path at projection time so the binding remains valid when invoked
        // from other event contexts (e.g. a focused TextField receiving keypresses).
        if let runtime = _UIRuntime._current, let path = _UIRuntime._currentPath {
            return Binding(
                get: { runtime._getState(seed: seed, path: path, initial: initial) },
                set: { runtime._setState(seed: seed, path: path, value: $0) }
            )
        }

        return Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
    }
}

struct _StateSeed {
    let fileID: StaticString
    let line: UInt
}
