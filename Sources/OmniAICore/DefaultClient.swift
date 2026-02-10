import Foundation

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

/// Overrides the module-level default client used by high-level functions like `generate()` and `stream()`.
public func setDefaultClient(_ client: Client?) async {
    await _DefaultClientStore.shared.set(client)
}

/// Spec-style alias.
public func set_default_client(_ client: Client?) async {
    await setDefaultClient(client)
}

/// Returns the module-level default client, lazily initialized from environment variables on first use.
public func defaultClient() async throws -> Client {
    try await _DefaultClientStore.shared.getOrInitialize()
}

/// Spec-style alias.
public func get_default_client() async throws -> Client {
    try await defaultClient()
}

