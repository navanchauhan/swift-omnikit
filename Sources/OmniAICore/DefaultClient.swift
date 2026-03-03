import Foundation

// Module-level default client support (Spec Section 2.5 / DoD 8.1).
//
// Uses a lock-based store instead of an actor so that synchronous callers
// can access the default client without hopping to the cooperative thread
// pool (which causes deadlocks when DispatchSemaphore is used to bridge).

private final class _DefaultClientStore: @unchecked Sendable {
    static let shared = _DefaultClientStore()

    private let lock = NSLock()
    private var client: Client?

    func set(_ client: Client?) {
        lock.lock()
        self.client = client
        lock.unlock()
    }

    func getOrInitialize() throws -> Client {
        lock.lock()
        defer { lock.unlock() }
        if let client { return client }
        let created = try Client.fromEnv()
        client = created
        return created
    }
}

/// Overrides the module-level default client used by high-level functions like `generate()` and `stream()`.
public func setDefaultClient(_ client: Client?) async {
    _DefaultClientStore.shared.set(client)
}

/// Synchronous overload for compatibility with closure-based call sites.
public func setDefaultClient(_ client: Client?) {
    _DefaultClientStore.shared.set(client)
}

/// Spec-style alias.
public func set_default_client(_ client: Client?) async {
    await setDefaultClient(client)
}

/// Spec-style alias.
public func set_default_client(_ client: Client?) {
    setDefaultClient(client)
}

/// Returns the module-level default client, lazily initialized from environment variables on first use.
public func defaultClient() async throws -> Client {
    try _DefaultClientStore.shared.getOrInitialize()
}

/// Synchronous overload for compatibility with existing non-async call sites.
public func defaultClient() throws -> Client {
    try _DefaultClientStore.shared.getOrInitialize()
}

/// Spec-style alias.
public func get_default_client() async throws -> Client {
    try await defaultClient()
}

/// Spec-style alias.
public func get_default_client() throws -> Client {
    try defaultClient()
}

/// Compatibility alias with `OmniAILLMClient` naming.
public func getDefaultClient() throws -> Client {
    try defaultClient()
}
