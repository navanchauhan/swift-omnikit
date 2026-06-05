@_exported import Foundation
@_exported import OmniUICore
import Dispatch

public protocol Cancellable {
    func cancel()
}

public final class AnyCancellable: Cancellable, Hashable, @unchecked Sendable {
    private let id = UUID()
    private let cancelHandler: () -> Void
    private let lock = NSLock()
    private var isCancelled = false

    public init(_ cancel: @escaping () -> Void = {}) {
        self.cancelHandler = cancel
    }

    deinit {
        cancel()
    }

    public func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        lock.unlock()
        cancelHandler()
    }

    public func store(in set: inout Set<AnyCancellable>) {
        set.insert(self)
    }

    public static func == (lhs: AnyCancellable, rhs: AnyCancellable) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private final class _AnyCancellableBox: @unchecked Sendable {
    let cancellable: Cancellable

    init(_ cancellable: Cancellable) {
        self.cancellable = cancellable
    }
}

private final class _OmniClosureBox<Input>: @unchecked Sendable {
    private let action: (Input) -> Void

    init(_ action: @escaping (Input) -> Void) {
        self.action = action
    }

    func call(_ value: Input) {
        action(value)
    }
}

private final class _OmniTransformBox<Input, Output>: @unchecked Sendable {
    private let transform: (Input) -> Output

    init(_ transform: @escaping (Input) -> Output) {
        self.transform = transform
    }

    func call(_ value: Input) -> Output {
        transform(value)
    }
}

private final class _OmniPredicateBox<Value>: @unchecked Sendable {
    private let predicate: (Value, Value) -> Bool

    init(_ predicate: @escaping (Value, Value) -> Bool) {
        self.predicate = predicate
    }

    func call(_ lhs: Value, _ rhs: Value) -> Bool {
        predicate(lhs, rhs)
    }
}

private final class _OmniTokenList: @unchecked Sendable {
    private let tokens: [AnyObject]

    init(_ tokens: [AnyObject]) {
        self.tokens = tokens
    }

    func cancel() {
        for token in tokens {
            (token as? _AnyCancellableBox)?.cancellable.cancel()
        }
    }
}

private final class _OmniDropFirstState: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int

    init(_ count: Int) {
        self.remaining = count
    }

    func shouldEmit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if remaining > 0 {
            remaining -= 1
            return false
        }
        return true
    }
}

private final class _OmniRemoveDuplicatesState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var previous: Value?
    private let predicate: _OmniPredicateBox<Value>

    init(predicate: _OmniPredicateBox<Value>) {
        self.predicate = predicate
    }

    func shouldEmit(_ value: Value) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let existing = previous, predicate.call(existing, value) {
            return false
        }
        previous = value
        return true
    }
}

private final class _OmniCombineLatestState<Left, Right>: @unchecked Sendable {
    private let lock = NSLock()
    private var left: Left?
    private var right: Right?

    func updateLeft(_ value: Left) -> (Left, Right)? {
        lock.lock()
        left = value
        let pair = right.map { (value, $0) }
        lock.unlock()
        return pair
    }

    func updateRight(_ value: Right) -> (Left, Right)? {
        lock.lock()
        right = value
        let pair = left.map { ($0, value) }
        lock.unlock()
        return pair
    }
}

private final class _OmniCombineLatest3State<A, B, C>: @unchecked Sendable {
    private let lock = NSLock()
    private var a: A?
    private var b: B?
    private var c: C?

    func updateA(_ value: A) -> (A, B, C)? {
        lock.lock()
        a = value
        let result = b.flatMap { b in c.map { (value, b, $0) } }
        lock.unlock()
        return result
    }

    func updateB(_ value: B) -> (A, B, C)? {
        lock.lock()
        b = value
        let result = a.flatMap { a in c.map { (a, value, $0) } }
        lock.unlock()
        return result
    }

    func updateC(_ value: C) -> (A, B, C)? {
        lock.lock()
        c = value
        let result = a.flatMap { a in b.map { (a, $0, value) } }
        lock.unlock()
        return result
    }
}

private final class _OmniDebounceState: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var isCancelled = false

    func nextGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        return generation
    }

    func shouldDeliver(_ candidate: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isCancelled && candidate == generation
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }
}

private final class _OmniScheduledEmission<Output>: @unchecked Sendable {
    private let value: Output
    private let action: _OmniClosureBox<Output>
    private let state: _OmniDebounceState
    private let generation: Int

    init(
        value: Output,
        action: _OmniClosureBox<Output>,
        state: _OmniDebounceState,
        generation: Int
    ) {
        self.value = value
        self.action = action
        self.state = state
        self.generation = generation
    }

    func deliverIfCurrent() {
        guard state.shouldDeliver(generation) else { return }
        action.call(value)
    }
}

private final class _OmniDeferredSubjectSend<Output>: @unchecked Sendable {
    private let subject: PassthroughSubject<Output, Never>
    private let value: Output

    init(subject: PassthroughSubject<Output, Never>, value: Output) {
        self.subject = subject
        self.value = value
    }

    func send() {
        subject.send(value)
    }
}

public struct _OmniSchedulerTimeInterval: Hashable, Sendable {
    public let secondsValue: Double

    public static func seconds(_ value: Double) -> _OmniSchedulerTimeInterval {
        _OmniSchedulerTimeInterval(secondsValue: value)
    }

    public static func milliseconds(_ value: Int) -> _OmniSchedulerTimeInterval {
        _OmniSchedulerTimeInterval(secondsValue: Double(value) / 1_000)
    }

    public static func milliseconds(_ value: Double) -> _OmniSchedulerTimeInterval {
        _OmniSchedulerTimeInterval(secondsValue: value / 1_000)
    }
}

public enum Subscribers {
    public enum Completion<Failure: Error>: Sendable {
        case finished
        case failure(Failure)
    }
}

public struct AnyPublisher<Output, Failure: Error>: _OmniReceivePublisher {
    private let subscribeHandler: (@escaping @Sendable (Output) -> Void) -> AnyObject

    public var _omniPublisherIdentity: String

    public init<P: _OmniReceivePublisher>(_ upstream: P) where P.Output == Output {
        self._omniPublisherIdentity = upstream._omniPublisherIdentity
        self.subscribeHandler = { handler in
            upstream._omniSubscribe(handler)
        }
    }

    public init(
        identity: String = UUID().uuidString,
        _ subscribe: @escaping (@escaping @Sendable (Output) -> Void) -> AnyObject
    ) {
        self._omniPublisherIdentity = identity
        self.subscribeHandler = subscribe
    }

    public func _omniSubscribe(_ handler: @escaping @Sendable (Output) -> Void) -> AnyObject {
        subscribeHandler(handler)
    }
}

public struct Empty<Output, Failure: Error>: _OmniReceivePublisher {
    public var _omniPublisherIdentity: String { "empty:\(Output.self)" }

    public init() {}

    public func _omniSubscribe(_ handler: @escaping @Sendable (Output) -> Void) -> AnyObject {
        _ = handler
        return _AnyCancellableBox(AnyCancellable())
    }
}

private final class _PassthroughSubjectStorage<Output>: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UUID: @Sendable (Output) -> Void] = [:]

    func subscribe(_ handler: @escaping @Sendable (Output) -> Void) -> AnyCancellable {
        let id = UUID()
        lock.lock()
        subscribers[id] = handler
        lock.unlock()
        return AnyCancellable { [weak self] in
            self?.lock.lock()
            self?.subscribers.removeValue(forKey: id)
            self?.lock.unlock()
        }
    }

    func send(_ value: Output) {
        lock.lock()
        let handlers = Array(subscribers.values)
        lock.unlock()
        for handler in handlers {
            handler(value)
        }
    }
}

public final class PassthroughSubject<Output, Failure: Error>: _OmniReceivePublisher, @unchecked Sendable {
    private let storage = _PassthroughSubjectStorage<Output>()

    public var _omniPublisherIdentity: String {
        "passthrough:\(ObjectIdentifier(self).debugDescription)"
    }

    public init() {}

    public func send(_ value: Output) {
        storage.send(value)
    }

    public func send() where Output == Void {
        storage.send(())
    }

    public func send(completion: Subscribers.Completion<Failure>) {
        _ = completion
    }

    public func _omniSubscribe(_ handler: @escaping @Sendable (Output) -> Void) -> AnyObject {
        _AnyCancellableBox(storage.subscribe(handler))
    }
}

public final class ObservableObjectPublisher: _OmniReceivePublisher, @unchecked Sendable {
    private let subject = PassthroughSubject<Void, Never>()

    public var _omniPublisherIdentity: String {
        "objectWillChange:\(ObjectIdentifier(self).debugDescription)"
    }

    public init() {}

    public func send() {
        subject.send()
    }

    public func _omniSubscribe(_ handler: @escaping @Sendable (Void) -> Void) -> AnyObject {
        subject._omniSubscribe(handler)
    }
}

private final class _ObservableObjectPublisherStore: @unchecked Sendable {
    static let shared = _ObservableObjectPublisherStore()

    private let lock = NSLock()
    private var publishers: [ObjectIdentifier: ObservableObjectPublisher] = [:]

    func publisher(for object: AnyObject) -> ObservableObjectPublisher {
        let id = ObjectIdentifier(object)
        lock.lock()
        defer { lock.unlock() }
        if let existing = publishers[id] {
            return existing
        }
        let publisher = ObservableObjectPublisher()
        publishers[id] = publisher
        return publisher
    }
}

public extension ObservableObject {
    var objectWillChange: ObservableObjectPublisher {
        _ObservableObjectPublisherStore.shared.publisher(for: self)
    }
}

@propertyWrapper
public struct Published<Value> {
    private var value: Value
    private let subject = PassthroughSubject<Value, Never>()

    public var wrappedValue: Value {
        get { value }
        set {
            value = newValue
            let emission = _OmniDeferredSubjectSend(subject: subject, value: newValue)
            DispatchQueue.main.async {
                emission.send()
            }
        }
    }

    public init(wrappedValue: Value) {
        self.value = wrappedValue
    }

    public var projectedValue: AnyPublisher<Value, Never> {
        subject.eraseToAnyPublisher()
    }
}

public enum Publishers {
    public struct CombineLatest<A: _OmniReceivePublisher, B: _OmniReceivePublisher>: _OmniReceivePublisher {
        public typealias Output = (A.Output, B.Output)

        let a: A
        let b: B

        public var _omniPublisherIdentity: String {
            "combineLatest:\(a._omniPublisherIdentity):\(b._omniPublisherIdentity)"
        }

        public init(_ a: A, _ b: B) {
            self.a = a
            self.b = b
        }

        public func _omniSubscribe(_ handler: @escaping @Sendable (Output) -> Void) -> AnyObject {
            let state = _OmniCombineLatestState<A.Output, B.Output>()
            let tokenA = a._omniSubscribe { value in
                if let pair = state.updateLeft(value) { handler(pair) }
            }
            let tokenB = b._omniSubscribe { value in
                if let pair = state.updateRight(value) { handler(pair) }
            }
            let tokenList = _OmniTokenList([tokenA, tokenB])
            return _AnyCancellableBox(AnyCancellable { tokenList.cancel() })
        }
    }

    public struct CombineLatest3<A: _OmniReceivePublisher, B: _OmniReceivePublisher, C: _OmniReceivePublisher>: _OmniReceivePublisher {
        public typealias Output = (A.Output, B.Output, C.Output)

        let a: A
        let b: B
        let c: C

        public var _omniPublisherIdentity: String {
            "combineLatest3:\(a._omniPublisherIdentity):\(b._omniPublisherIdentity):\(c._omniPublisherIdentity)"
        }

        public init(_ a: A, _ b: B, _ c: C) {
            self.a = a
            self.b = b
            self.c = c
        }

        public func _omniSubscribe(_ handler: @escaping @Sendable (Output) -> Void) -> AnyObject {
            let state = _OmniCombineLatest3State<A.Output, B.Output, C.Output>()
            let tokenA = a._omniSubscribe { value in
                if let tuple = state.updateA(value) { handler(tuple) }
            }
            let tokenB = b._omniSubscribe { value in
                if let tuple = state.updateB(value) { handler(tuple) }
            }
            let tokenC = c._omniSubscribe { value in
                if let tuple = state.updateC(value) { handler(tuple) }
            }
            let tokenList = _OmniTokenList([tokenA, tokenB, tokenC])
            return _AnyCancellableBox(AnyCancellable { tokenList.cancel() })
        }
    }

    public struct Debounce<Upstream: _OmniReceivePublisher, Scheduler>: _OmniReceivePublisher {
        public typealias Output = Upstream.Output

        let upstream: Upstream
        let interval: _OmniSchedulerTimeInterval
        let scheduler: Scheduler

        public var _omniPublisherIdentity: String {
            "debounce:\(upstream._omniPublisherIdentity):\(interval.secondsValue)"
        }

        public func _omniSubscribe(_ handler: @escaping @Sendable (Output) -> Void) -> AnyObject {
            _ = scheduler
            let state = _OmniDebounceState()
            let action = _OmniClosureBox(handler)
            let milliseconds = max(0, Int((interval.secondsValue * 1_000).rounded(.up)))
            let token = upstream._omniSubscribe { value in
                let generation = state.nextGeneration()
                let emission = _OmniScheduledEmission(
                    value: value,
                    action: action,
                    state: state,
                    generation: generation
                )
                if milliseconds == 0 {
                    DispatchQueue.main.async {
                        emission.deliverIfCurrent()
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                        emission.deliverIfCurrent()
                    }
                }
            }
            let tokenList = _OmniTokenList([token])
            return _AnyCancellableBox(AnyCancellable {
                state.cancel()
                tokenList.cancel()
            })
        }
    }

    public struct MergeMany<Upstream: _OmniReceivePublisher>: _OmniReceivePublisher {
        public typealias Output = Upstream.Output

        private let upstreams: [Upstream]

        public var _omniPublisherIdentity: String {
            "mergeMany:\(upstreams.map { $0._omniPublisherIdentity }.joined(separator: ","))"
        }

        public init(_ upstreams: [Upstream]) {
            self.upstreams = upstreams
        }

        public init(_ upstreams: Upstream...) {
            self.upstreams = upstreams
        }

        public func _omniSubscribe(_ handler: @escaping @Sendable (Output) -> Void) -> AnyObject {
            let tokens = upstreams.map { upstream in
                upstream._omniSubscribe(handler)
            }
            let tokenList = _OmniTokenList(tokens)
            return _AnyCancellableBox(AnyCancellable {
                tokenList.cancel()
            })
        }
    }
}

public extension _OmniReceivePublisher {
    func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        let action = _OmniClosureBox(receiveValue)
        let token = _omniSubscribe { value in
            action.call(value)
        }
        let tokenList = _OmniTokenList([token])
        return AnyCancellable {
            tokenList.cancel()
        }
    }

    func receive<S>(on scheduler: S) -> AnyPublisher<Output, Never> {
        _ = scheduler
        return eraseToAnyPublisher()
    }

    func map<T>(_ transform: @escaping (Output) -> T) -> AnyPublisher<T, Never> {
        let transformBox = _OmniTransformBox(transform)
        return AnyPublisher<T, Never>(identity: "map:\(_omniPublisherIdentity)") { handler in
            _omniSubscribe { value in
                handler(transformBox.call(value))
            }
        }
    }

    func map<T>(_ keyPath: KeyPath<Output, T>) -> AnyPublisher<T, Never> {
        map { $0[keyPath: keyPath] }
    }

    func filter(_ isIncluded: @escaping (Output) -> Bool) -> AnyPublisher<Output, Never> {
        let predicateBox = _OmniPredicateBox { (value: Output, _: Output) in isIncluded(value) }
        return AnyPublisher<Output, Never>(identity: "filter:\(_omniPublisherIdentity)") { handler in
            _omniSubscribe { value in
                guard predicateBox.call(value, value) else { return }
                handler(value)
            }
        }
    }

    func dropFirst(_ count: Int = 1) -> AnyPublisher<Output, Never> {
        AnyPublisher<Output, Never>(identity: "dropFirst:\(_omniPublisherIdentity):\(count)") { handler in
            let state = _OmniDropFirstState(count)
            return _omniSubscribe { value in
                guard state.shouldEmit() else { return }
                handler(value)
            }
        }
    }

    func removeDuplicates() -> AnyPublisher<Output, Never> where Output: Equatable {
        removeDuplicates(by: ==)
    }

    func removeDuplicates(by predicate: @escaping (Output, Output) -> Bool) -> AnyPublisher<Output, Never> {
        let predicateBox = _OmniPredicateBox(predicate)
        return AnyPublisher<Output, Never>(identity: "removeDuplicates:\(_omniPublisherIdentity)") { handler in
            let state = _OmniRemoveDuplicatesState(predicate: predicateBox)
            return _omniSubscribe { value in
                guard state.shouldEmit(value) else { return }
                handler(value)
            }
        }
    }

    func debounce<S>(for interval: _OmniSchedulerTimeInterval, scheduler: S) -> Publishers.Debounce<Self, S> {
        Publishers.Debounce(upstream: self, interval: interval, scheduler: scheduler)
    }

    func combineLatest<P: _OmniReceivePublisher>(_ other: P) -> AnyPublisher<(Output, P.Output), Never> {
        AnyPublisher<(Output, P.Output), Never>(identity: "combineLatest:\(_omniPublisherIdentity):\(other._omniPublisherIdentity)") { handler in
            let state = _OmniCombineLatestState<Output, P.Output>()
            let leftToken = _omniSubscribe { value in
                if let pair = state.updateLeft(value) {
                    handler(pair)
                }
            }
            let rightToken = other._omniSubscribe { value in
                if let pair = state.updateRight(value) {
                    handler(pair)
                }
            }
            let tokenList = _OmniTokenList([leftToken, rightToken])
            return _AnyCancellableBox(AnyCancellable {
                tokenList.cancel()
            })
        }
    }

    func eraseToAnyPublisher() -> AnyPublisher<Output, Never> {
        AnyPublisher(self)
    }
}
