import Foundation
import Dispatch

// Module-level default client support (Spec Section 2.5 / DoD 8.1).

private actor _DefaultClientStore {
    static let shared = _DefaultClientStore()

    private var client: Client?

    func set(_ client: Client?) {
        self.client = client
    }

    func getOrInitialize() throws -> Client {
        if let client { return client }
        let created = try Client.fromEnv()
        client = created
        return created
    }
}

private final class _ClientResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<Client, Error>?

    func set(_ result: Result<Client, Error>) {
        lock.lock()
        value = result
        lock.unlock()
    }

    func get() -> Result<Client, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private func _setDefaultClientSync(_ client: Client?) {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        await _DefaultClientStore.shared.set(client)
        semaphore.signal()
    }
    semaphore.wait()
}

private func _getOrInitializeDefaultClientSync() throws -> Client {
    let semaphore = DispatchSemaphore(value: 0)
    let box = _ClientResultBox()
    Task {
        do {
            box.set(.success(try await _DefaultClientStore.shared.getOrInitialize()))
        } catch {
            box.set(.failure(error))
        }
        semaphore.signal()
    }
    semaphore.wait()
    guard let result = box.get() else {
        throw ConfigurationError(message: "Failed to resolve default client")
    }
    return try result.get()
}

/// Overrides the module-level default client used by high-level functions like `generate()` and `stream()`.
public func setDefaultClient(_ client: Client?) async {
    await _DefaultClientStore.shared.set(client)
}

/// Synchronous overload for compatibility with closure-based call sites.
public func setDefaultClient(_ client: Client?) {
    _setDefaultClientSync(client)
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
    try await _DefaultClientStore.shared.getOrInitialize()
}

/// Synchronous overload for compatibility with existing non-async call sites.
public func defaultClient() throws -> Client {
    try _getOrInitializeDefaultClientSync()
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
