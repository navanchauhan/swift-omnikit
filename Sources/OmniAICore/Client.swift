import Foundation

import OmniHTTP

public typealias CompleteMiddleware = @Sendable (
    Request,
    @Sendable (Request) async throws -> Response
) async throws -> Response

public typealias StreamMiddleware = @Sendable (
    Request,
    @Sendable (Request) async throws -> AsyncThrowingStream<StreamEvent, Error>
) async throws -> AsyncThrowingStream<StreamEvent, Error>

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

private final class _ClosureMiddleware: Middleware, @unchecked Sendable {
    private let completeClosure: CompleteMiddleware?
    private let streamClosure: StreamMiddleware?

    init(complete: CompleteMiddleware?, stream: StreamMiddleware?) {
        self.completeClosure = complete
        self.streamClosure = stream
    }

    func complete(
        request: Request,
        next: @Sendable @escaping (Request) async throws -> Response
    ) async throws -> Response {
        if let completeClosure {
            return try await completeClosure(request, next)
        }
        return try await next(request)
    }

    func stream(
        request: Request,
        next: @Sendable @escaping (Request) async throws -> AsyncThrowingStream<StreamEvent, Error>
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        if let streamClosure {
            return try await streamClosure(request, next)
        }
        return try await next(request)
    }
}

public final class Client: @unchecked Sendable {
    private var providers: [String: ProviderAdapter]
    private var _defaultProvider: String?
    private var _middleware: [Middleware]
    private let stateLock = NSLock()
    public let modelCatalog: ModelCatalog

    public init(
        providers: [String: ProviderAdapter],
        defaultProvider: String? = nil,
        middleware: [Middleware] = [],
        completeMiddleware: [CompleteMiddleware] = [],
        streamMiddleware: [StreamMiddleware] = [],
        modelCatalog: ModelCatalog = .default
    ) throws {
        self.providers = providers
        self._defaultProvider = defaultProvider ?? providers.first?.key
        self._middleware = middleware
        self._middleware.append(contentsOf: completeMiddleware.map { _ClosureMiddleware(complete: $0, stream: nil) })
        self._middleware.append(contentsOf: streamMiddleware.map { _ClosureMiddleware(complete: nil, stream: $0) })
        self.modelCatalog = modelCatalog

        for (_, adapter) in providers {
            try adapter.initialize()
        }
    }

    public var defaultProvider: String? {
        _withStateLock { _defaultProvider }
    }

    public var defaultProviderName: String? {
        defaultProvider
    }

    public var middleware: [Middleware] {
        _withStateLock { _middleware }
    }

    public static func fromEnv(
        environment: [String: String],
        transport: OmniHTTP.HTTPTransport = OmniHTTP.URLSessionHTTPTransport(),
        modelCatalog: ModelCatalog = .default,
        middleware: [Middleware] = [],
        completeMiddleware: [CompleteMiddleware] = [],
        streamMiddleware: [StreamMiddleware] = [],
        allowEmptyProviders: Bool = false
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
        if let key = env["CEREBRAS_API_KEY"], !key.isEmpty {
            providers["cerebras"] = CerebrasAdapter(apiKey: key, baseURL: env["CEREBRAS_BASE_URL"], transport: transport)
        }

        if providers.isEmpty && !allowEmptyProviders {
            throw ConfigurationError(message: "No providers configured. Set OPENAI_API_KEY and/or ANTHROPIC_API_KEY and/or GEMINI_API_KEY and/or CEREBRAS_API_KEY.")
        }

        return try Client(
            providers: providers,
            defaultProvider: providers.first?.key,
            middleware: middleware,
            completeMiddleware: completeMiddleware,
            streamMiddleware: streamMiddleware,
            modelCatalog: modelCatalog
        )
    }

    public static func fromEnv(
        transport: OmniHTTP.HTTPTransport = OmniHTTP.URLSessionHTTPTransport(),
        modelCatalog: ModelCatalog = .default,
        middleware: [Middleware] = [],
        completeMiddleware: [CompleteMiddleware] = [],
        streamMiddleware: [StreamMiddleware] = [],
        allowEmptyProviders: Bool = false
    ) throws -> Client {
        try fromEnv(
            environment: ProcessInfo.processInfo.environment,
            transport: transport,
            modelCatalog: modelCatalog,
            middleware: middleware,
            completeMiddleware: completeMiddleware,
            streamMiddleware: streamMiddleware,
            allowEmptyProviders: allowEmptyProviders
        )
    }

    public static func fromEnvAllowingEmpty(
        environment: [String: String],
        transport: OmniHTTP.HTTPTransport = OmniHTTP.URLSessionHTTPTransport(),
        modelCatalog: ModelCatalog = .default,
        middleware: [Middleware] = [],
        completeMiddleware: [CompleteMiddleware] = [],
        streamMiddleware: [StreamMiddleware] = []
    ) throws -> Client {
        try fromEnv(
            environment: environment,
            transport: transport,
            modelCatalog: modelCatalog,
            middleware: middleware,
            completeMiddleware: completeMiddleware,
            streamMiddleware: streamMiddleware,
            allowEmptyProviders: true
        )
    }

    public static func fromEnvAllowingEmpty(
        transport: OmniHTTP.HTTPTransport = OmniHTTP.URLSessionHTTPTransport(),
        modelCatalog: ModelCatalog = .default,
        middleware: [Middleware] = [],
        completeMiddleware: [CompleteMiddleware] = [],
        streamMiddleware: [StreamMiddleware] = []
    ) throws -> Client {
        try fromEnv(
            environment: ProcessInfo.processInfo.environment,
            transport: transport,
            modelCatalog: modelCatalog,
            middleware: middleware,
            completeMiddleware: completeMiddleware,
            streamMiddleware: streamMiddleware,
            allowEmptyProviders: true
        )
    }

    // Spec-style alias.
    public static func from_env(
        transport: OmniHTTP.HTTPTransport = OmniHTTP.URLSessionHTTPTransport(),
        modelCatalog: ModelCatalog = .default,
        middleware: [Middleware] = [],
        completeMiddleware: [CompleteMiddleware] = [],
        streamMiddleware: [StreamMiddleware] = [],
        allowEmptyProviders: Bool = false
    ) throws -> Client {
        try fromEnv(
            transport: transport,
            modelCatalog: modelCatalog,
            middleware: middleware,
            completeMiddleware: completeMiddleware,
            streamMiddleware: streamMiddleware,
            allowEmptyProviders: allowEmptyProviders
        )
    }

    // Spec-style alias.
    public static func from_env_allowing_empty(
        transport: OmniHTTP.HTTPTransport = OmniHTTP.URLSessionHTTPTransport(),
        modelCatalog: ModelCatalog = .default,
        middleware: [Middleware] = [],
        completeMiddleware: [CompleteMiddleware] = [],
        streamMiddleware: [StreamMiddleware] = []
    ) throws -> Client {
        try fromEnvAllowingEmpty(
            transport: transport,
            modelCatalog: modelCatalog,
            middleware: middleware,
            completeMiddleware: completeMiddleware,
            streamMiddleware: streamMiddleware
        )
    }

    public func register(provider name: String, adapter: ProviderAdapter) {
        _withStateLock {
            providers[name] = adapter
            if _defaultProvider == nil {
                _defaultProvider = name
            }
        }
    }

    public func registerProvider(_ name: String, adapter: ProviderAdapter) {
        register(provider: name, adapter: adapter)
    }

    public func setDefault(provider: String) {
        _withStateLock {
            _defaultProvider = provider
        }
    }

    public func close() async {
        for (_, adapter) in _withStateLock({ providers }) {
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
        let middleware = _withStateLock { _middleware }
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

    public func complete(request: Request) async throws -> Response {
        try await complete(request)
    }

    public func stream(_ request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let adapter = try resolveAdapter(for: request)
        let middleware = _withStateLock { _middleware }
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

    public func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        try await stream(request)
    }

    public func addMiddleware(_ middleware: Middleware) {
        _withStateLock {
            _middleware.append(middleware)
        }
    }

    public func addMiddleware(_ middleware: @escaping CompleteMiddleware) {
        addMiddleware(_ClosureMiddleware(complete: middleware, stream: nil))
    }

    public func addStreamMiddleware(_ middleware: @escaping StreamMiddleware) {
        addMiddleware(_ClosureMiddleware(complete: nil, stream: middleware))
    }

    private func _withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    private func resolveAdapter(for request: Request) throws -> ProviderAdapter {
        try _withStateLock {
            if let p = request.provider {
                guard let a = providers[p] else {
                    throw ConfigurationError(message: "Provider '\(p)' not configured")
                }
                return a
            }
            guard let def = _defaultProvider else {
                throw ConfigurationError(message: "No default provider configured and request.provider is nil")
            }
            guard let a = providers[def] else {
                throw ConfigurationError(message: "Default provider '\(def)' not configured")
            }
            return a
        }
    }
}
