import Foundation

import OmniHTTP

public protocol ProviderAdapter: Sendable {
    var name: String { get }

    func complete(request: Request) async throws -> Response
    func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error>

    func close() async
    func initialize() throws
    func supportsToolChoice(_ mode: ToolChoiceMode) -> Bool
}

extension ProviderAdapter {
    public func close() async {}
    public func initialize() throws {}
    public func supportsToolChoice(_ mode: ToolChoiceMode) -> Bool { true }
}

public protocol Middleware: Sendable {
    func complete(
        request: Request,
        next: @Sendable @escaping (Request) async throws -> Response
    ) async throws -> Response

    func stream(
        request: Request,
        next: @Sendable @escaping (Request) async throws -> AsyncThrowingStream<StreamEvent, Error>
    ) async throws -> AsyncThrowingStream<StreamEvent, Error>
}

public final class Client: @unchecked Sendable {
    private var providers: [String: ProviderAdapter]
    public let defaultProvider: String?
    public let middleware: [Middleware]
    public let modelCatalog: ModelCatalog

    public init(
        providers: [String: ProviderAdapter],
        defaultProvider: String? = nil,
        middleware: [Middleware] = [],
        modelCatalog: ModelCatalog = .default
    ) throws {
        self.providers = providers
        self.defaultProvider = defaultProvider ?? providers.first?.key
        self.middleware = middleware
        self.modelCatalog = modelCatalog

        for (_, adapter) in providers {
            try adapter.initialize()
        }
    }

    public static func fromEnv(
        environment: [String: String],
        transport: OmniHTTP.HTTPTransport = OmniHTTP.URLSessionHTTPTransport(),
        modelCatalog: ModelCatalog = .default,
        middleware: [Middleware] = []
    ) throws -> Client {
        // Provider adapters are registered only if their env var keys exist.
        // This is implemented in Providers/*.swift.
        let env = environment

        var providers: [String: ProviderAdapter] = [:]

        if let key = env["OPENAI_API_KEY"], !key.isEmpty {
            providers["openai"] = OpenAIAdapter(
                apiKey: key,
                baseURL: env["OPENAI_BASE_URL"],
                organizationID: env["OPENAI_ORG_ID"],
                projectID: env["OPENAI_PROJECT_ID"],
                transport: transport
            )
        }
        if let key = env["ANTHROPIC_API_KEY"], !key.isEmpty {
            providers["anthropic"] = AnthropicAdapter(apiKey: key, baseURL: env["ANTHROPIC_BASE_URL"], transport: transport)
        }
        if let key = (env["GEMINI_API_KEY"] ?? env["GOOGLE_API_KEY"]), !key.isEmpty {
            providers["gemini"] = GeminiAdapter(apiKey: key, baseURL: env["GEMINI_BASE_URL"], transport: transport)
        }

        if providers.isEmpty {
            throw ConfigurationError(message: "No providers configured. Set OPENAI_API_KEY and/or ANTHROPIC_API_KEY and/or GEMINI_API_KEY.")
        }

        return try Client(
            providers: providers,
            defaultProvider: providers.first?.key,
            middleware: middleware,
            modelCatalog: modelCatalog
        )
    }

    public static func fromEnv(
        transport: OmniHTTP.HTTPTransport = OmniHTTP.URLSessionHTTPTransport(),
        modelCatalog: ModelCatalog = .default,
        middleware: [Middleware] = []
    ) throws -> Client {
        try fromEnv(environment: ProcessInfo.processInfo.environment, transport: transport, modelCatalog: modelCatalog, middleware: middleware)
    }

    // Spec-style alias.
    public static func from_env(
        transport: OmniHTTP.HTTPTransport = OmniHTTP.URLSessionHTTPTransport(),
        modelCatalog: ModelCatalog = .default,
        middleware: [Middleware] = []
    ) throws -> Client {
        try fromEnv(transport: transport, modelCatalog: modelCatalog, middleware: middleware)
    }

    public func register(provider name: String, adapter: ProviderAdapter) {
        providers[name] = adapter
    }

    public func close() async {
        for (_, adapter) in providers {
            await adapter.close()
        }
    }

    public func listModels(provider: String? = nil) -> [ModelInfo] {
        modelCatalog.listModels(provider: provider)
    }

    // Spec-style alias.
    public func list_models(provider: String? = nil) -> [ModelInfo] {
        listModels(provider: provider)
    }

    public func getModelInfo(_ id: String) -> ModelInfo? {
        modelCatalog.getModelInfo(id)
    }

    // Spec-style alias.
    public func get_model_info(_ id: String) -> ModelInfo? {
        getModelInfo(id)
    }

    public func getLatestModel(provider: String, capability: ModelCapability? = nil) -> ModelInfo? {
        modelCatalog.getLatestModel(provider: provider, capability: capability)
    }

    // Spec-style alias.
    public func get_latest_model(provider: String, capability: ModelCapability? = nil) -> ModelInfo? {
        getLatestModel(provider: provider, capability: capability)
    }

    public func complete(_ request: Request) async throws -> Response {
        let adapter = try resolveAdapter(for: request)
        let base: @Sendable (Request) async throws -> Response = { req in
            try await adapter.complete(request: req)
        }

        var handler = base
        for m in middleware.reversed() {
            let next = handler
            handler = { req in
                try await m.complete(request: req, next: next)
            }
        }
        return try await handler(request)
    }

    public func stream(_ request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let adapter = try resolveAdapter(for: request)
        let base: @Sendable (Request) async throws -> AsyncThrowingStream<StreamEvent, Error> = { req in
            try await adapter.stream(request: req)
        }

        var handler = base
        for m in middleware.reversed() {
            let next = handler
            handler = { req in
                try await m.stream(request: req, next: next)
            }
        }
        return try await handler(request)
    }

    private func resolveAdapter(for request: Request) throws -> ProviderAdapter {
        if let p = request.provider {
            guard let a = providers[p] else {
                throw ConfigurationError(message: "Provider '\(p)' not configured")
            }
            return a
        }
        guard let def = defaultProvider else {
            throw ConfigurationError(message: "No default provider configured and request.provider is nil")
        }
        guard let a = providers[def] else {
            throw ConfigurationError(message: "Default provider '\(def)' not configured")
        }
        return a
    }
}
