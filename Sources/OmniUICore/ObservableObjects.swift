// Minimal SwiftUI-like observable object property wrappers.
//
// NOTE: This intentionally does not use Combine (portable to Linux).
// Updates are reflected because the renderer rebuilds the view hierarchy every frame.

/// Observation registrar that tracks interested runtimes and notifies them when
/// an `@Observable` object's properties change.
///
/// The `@Observable` macro synthesizes a `_$observationRegistrar` stored property
/// of this type on each annotated class.  Property wrappers like `@Bindable`,
/// `@ObservedObject`, and `@EnvironmentObject` call ``track()`` during body
/// evaluation so the runtime knows to re-render when ``notify()`` fires.
///
/// Safety: registrations and notifications are driven by the OmniUI render/event
/// loop, and dead weak runtime references are purged before reuse.
public final class _ObservationRegistrar: @unchecked Sendable {
    private struct _Entry {
        weak var runtime: _UIRuntime?
        var path: [Int]
    }
    private var entries: [_Entry] = []

    public init() {}

    /// Register the current runtime / view path as an observer of this object.
    /// Called automatically by property wrappers during view body evaluation.
    public func track() {
        guard let runtime = _UIRuntime._current, let path = _UIRuntime._currentPath else { return }
        // Avoid duplicate registrations for the same runtime + path within one render pass.
        if !entries.contains(where: { $0.runtime === runtime && $0.path == path }) {
            entries.append(_Entry(runtime: runtime, path: path))
        }
    }

    /// Notify all registered runtimes that a property changed.
    /// Call this from property `didSet` or from the macro-synthesized setter.
    public func notify() {
        var didPurge = false
        for entry in entries {
            if let runtime = entry.runtime {
                runtime._markDirtyFromObservation(path: entry.path)
            } else {
                didPurge = true
            }
        }
        if didPurge {
            entries.removeAll(where: { $0.runtime == nil })
        }
    }
}

public protocol ObservableObject: AnyObject {
    /// The registrar that tracks observation interest and delivers change
    /// notifications.  The ``@Observable`` macro synthesizes this automatically.
    var _$observationRegistrar: _ObservationRegistrar { get }
}

/// Default implementation so existing manual `ObservableObject` conformances
/// that predate the registrar continue to compile.  They simply won't get
/// automatic change notifications (bindings still work via `_markDirtyFromBinding`).
extension ObservableObject {
    public var _$observationRegistrar: _ObservationRegistrar {
        _DefaultObservationRegistrar.shared
    }
}

/// A shared no-op registrar used by the default protocol extension.
private enum _DefaultObservationRegistrar {
    static let shared = _ObservationRegistrar()
}

@propertyWrapper
@dynamicMemberLookup
public struct ObservedObject<ObjectType: AnyObject> {
    public var wrappedValue: ObjectType

    public init(wrappedValue: ObjectType) {
        self.wrappedValue = wrappedValue
    }

    public var projectedValue: ObservedObject<ObjectType> { self }

    public subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Value>) -> Binding<Value> {
        (wrappedValue as? ObservableObject)?._$observationRegistrar.track()
        let runtime = _UIRuntime._current
        let path = _UIRuntime._currentPath
        return Binding(
            get: { wrappedValue[keyPath: keyPath] },
            set: { newValue in
                wrappedValue[keyPath: keyPath] = newValue
                if let runtime, let path { runtime._markDirtyFromBinding(path: path) }
            }
        )
    }
}

@propertyWrapper
@dynamicMemberLookup
public struct StateObject<ObjectType: AnyObject> {
    private let seed: _StateSeed
    private let initial: () -> ObjectType

    public init(wrappedValue: @autoclosure @escaping () -> ObjectType, fileID: StaticString = #fileID, line: UInt = #line) {
        self.seed = _StateSeed(fileID: fileID, line: line)
        self.initial = wrappedValue
    }

    public var wrappedValue: ObjectType {
        get {
            guard let runtime = _UIRuntime._current, let path = _UIRuntime._currentPath else {
                return initial()
            }
            return runtime._getState(seed: seed, path: path, initial: initial)
        }
    }

    public var projectedValue: StateObject<ObjectType> { self }

    public subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Value>) -> Binding<Value> {
        (wrappedValue as? ObservableObject)?._$observationRegistrar.track()
        let runtime = _UIRuntime._current
        let path = _UIRuntime._currentPath
        return Binding(
            get: { wrappedValue[keyPath: keyPath] },
            set: { newValue in
                wrappedValue[keyPath: keyPath] = newValue
                if let runtime, let path { runtime._markDirtyFromBinding(path: path) }
            }
        )
    }
}

// Safety: this cached location is accessed only during single-threaded view evaluation.
final class _EnvironmentObjectLocation<ObjectType: AnyObject>: @unchecked Sendable {
    var object: ObjectType? = nil
    init() {}
}

@propertyWrapper
@dynamicMemberLookup
public struct EnvironmentObject<ObjectType: AnyObject> {
    private let location = _EnvironmentObjectLocation<ObjectType>()

    public init() {}

    public var wrappedValue: ObjectType {
        if let cached = location.object {
            return cached
        }
        let env = _UIRuntime._currentEnvironment
        if let object = env?._getObject(ObjectType.self) {
            location.object = object
            return object
        }
        fatalError("Missing EnvironmentObject<\(ObjectType.self)>. Use .environmentObject(_) on an ancestor view.")
    }

    public var projectedValue: EnvironmentObject<ObjectType> { self }

    public subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Value>) -> Binding<Value> {
        // Capture the object now so later event contexts (keypresses, clicks) don't need TaskLocal environment.
        let object = wrappedValue
        (object as? ObservableObject)?._$observationRegistrar.track()
        let runtime = _UIRuntime._current
        let path = _UIRuntime._currentPath
        return Binding(
            get: { object[keyPath: keyPath] },
            set: { newValue in
                object[keyPath: keyPath] = newValue
                if let runtime, let path { runtime._markDirtyFromBinding(path: path) }
            }
        )
    }
}

// SwiftUI's `@Bindable` comes from Observation; provide a tiny stand-in that works with our
// "always rebuild" renderer model.
@propertyWrapper
@dynamicMemberLookup
public struct Bindable<ObjectType: AnyObject> {
    public var wrappedValue: ObjectType

    public init(wrappedValue: ObjectType) {
        self.wrappedValue = wrappedValue
        // Register observation interest when the wrapper is initialised during a build.
        if let obs = wrappedValue as? ObservableObject {
            obs._$observationRegistrar.track()
        }
    }

    public var projectedValue: Bindable<ObjectType> { self }

    public subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Value>) -> Binding<Value> {
        // Re-track on every binding creation (covers body re-evaluations).
        if let obs = wrappedValue as? ObservableObject {
            obs._$observationRegistrar.track()
        }
        let runtime = _UIRuntime._current
        let path = _UIRuntime._currentPath
        return Binding(
            get: { wrappedValue[keyPath: keyPath] },
            set: { newValue in
                wrappedValue[keyPath: keyPath] = newValue
                if let runtime, let path { runtime._markDirtyFromBinding(path: path) }
            }
        )
    }
}
