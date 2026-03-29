import Foundation

private final class _AbortSignalState: @unchecked Sendable {
    // Safety: all mutable fields are accessed under `lock`, and continuations are
    // resumed only after state is moved out from behind the lock.
    let lock = NSLock()
    var isAborted = false
    var waiters: [CheckedContinuation<Void, Never>] = []

    func abort() {
        let waiters: [CheckedContinuation<Void, Never>]
        lock.lock()
        if isAborted {
            lock.unlock()
            return
        }
        isAborted = true
        waiters = self.waiters
        self.waiters.removeAll(keepingCapacity: true)
        lock.unlock()

        for waiter in waiters {
            waiter.resume(returning: ())
        }
    }

    func isCurrentlyAborted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isAborted
    }

    func enqueueWaiterUnlessAborted(_ continuation: CheckedContinuation<Void, Never>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isAborted {
            return false
        }
        waiters.append(continuation)
        return true
    }
}

public final class AbortSignal: @unchecked Sendable {
    // Safety: this class provides synchronous cancellation for mixed sync/async
    // call sites. All mutable state lives in `_AbortSignalState` and is protected
    // by its lock; `wait()` suspends only after the continuation is stored.
    private let state = _AbortSignalState()

    public init() {}

    public func abort() {
        state.abort()
    }

    public var isAborted: Bool {
        get async {
            state.isCurrentlyAborted()
        }
    }

    public func check() async throws {
        if await isAborted {
            throw AbortError(message: "Aborted")
        }
    }

    public func wait() async {
        await withCheckedContinuation { continuation in
            if !state.enqueueWaiterUnlessAborted(continuation) {
                continuation.resume(returning: ())
            }
        }
    }
}
