import Foundation

public typealias Middleware = @Sendable (Request, @Sendable (Request) async throws -> Response) async throws -> Response
public typealias StreamMiddleware = @Sendable (Request, @Sendable (Request) async throws -> AsyncThrowingStream<StreamEvent, Error>) async throws -> AsyncThrowingStream<StreamEvent, Error>

public final class LLMClient: @unchecked Sendable {
    private var providers: [String: ProviderAdapter]
    private var defaultProvider: String?
    private var middleware: [Middleware]
    private var streamMiddleware: [StreamMiddleware]

    public init(
        providers: [String: ProviderAdapter] = [:],
        defaultProvider: String? = nil,
        middleware: [Middleware] = [],
        streamMiddleware: [StreamMiddleware] = []
    ) {
        self.providers = providers
        self.defaultProvider = defaultProvider ?? providers.keys.first
        self.middleware = middleware
        self.streamMiddleware = streamMiddleware
    }

    public static func fromEnv() -> LLMClient {
        var providers: [String: ProviderAdapter] = [:]
        var firstProvider: String?

        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
            let baseURL = ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"]
            providers["anthropic"] = AnthropicAdapter(apiKey: key, baseURL: baseURL)
            if firstProvider == nil { firstProvider = "anthropic" }
        }

        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            let baseURL = ProcessInfo.processInfo.environment["OPENAI_BASE_URL"]
            let orgID = ProcessInfo.processInfo.environment["OPENAI_ORG_ID"]
            let projectID = ProcessInfo.processInfo.environment["OPENAI_PROJECT_ID"]
            providers["openai"] = OpenAIAdapter(apiKey: key, baseURL: baseURL, orgID: orgID, projectID: projectID)
            if firstProvider == nil { firstProvider = "openai" }
        }

        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] {
            let baseURL = ProcessInfo.processInfo.environment["GEMINI_BASE_URL"]
            providers["gemini"] = GeminiAdapter(apiKey: key, baseURL: baseURL)
            if firstProvider == nil { firstProvider = "gemini" }
        }

        return LLMClient(providers: providers, defaultProvider: firstProvider)
    }

    public func registerProvider(_ name: String, adapter: ProviderAdapter) {
        providers[name] = adapter
        if defaultProvider == nil {
            defaultProvider = name
        }
    }

    public func setDefault(provider: String) {
        defaultProvider = provider
    }

    public var defaultProviderName: String? {
        defaultProvider
    }

    private func resolveProvider(for request: Request) throws -> (String, ProviderAdapter) {
        let providerName = request.provider ?? defaultProvider
        guard let name = providerName else {
            throw ConfigurationError(message: "No provider specified and no default provider configured")
        }
        guard let adapter = providers[name] else {
            throw ConfigurationError(message: "Provider '\(name)' is not registered")
        }
        return (name, adapter)
    }

    public func complete(request: Request) async throws -> Response {
        let (_, adapter) = try resolveProvider(for: request)

        // Build middleware chain
        let handler: @Sendable (Request) async throws -> Response = { req in
            try await adapter.complete(request: req)
        }

        let chain = middleware.reversed().reduce(handler) { next, mw in
            { req in try await mw(req, next) }
        }

        return try await chain(request)
    }

    public func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let (_, adapter) = try resolveProvider(for: request)

        let handler: @Sendable (Request) async throws -> AsyncThrowingStream<StreamEvent, Error> = { req in
            try await adapter.stream(request: req)
        }

        let chain = streamMiddleware.reversed().reduce(handler) { next, mw in
            { req in try await mw(req, next) }
        }

        return try await chain(request)
    }

    public func close() async {
        for adapter in providers.values {
            await adapter.close()
        }
    }

    public func addMiddleware(_ mw: @escaping Middleware) {
        middleware.append(mw)
    }

    public func addStreamMiddleware(_ mw: @escaping StreamMiddleware) {
        streamMiddleware.append(mw)
    }
}

// MARK: - Module-level default client

private var _defaultClient: LLMClient?
private let _clientLock = NSLock()

public func setDefaultClient(_ client: LLMClient) {
    _clientLock.lock()
    defer { _clientLock.unlock() }
    _defaultClient = client
}

public func getDefaultClient() -> LLMClient {
    _clientLock.lock()
    defer { _clientLock.unlock() }
    if let client = _defaultClient {
        return client
    }
    let client = LLMClient.fromEnv()
    _defaultClient = client
    return client
}
