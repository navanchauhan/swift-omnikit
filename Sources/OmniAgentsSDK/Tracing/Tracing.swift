import Foundation
import OmniAICore

public struct TracingConfig: Sendable, Equatable {
    public var disabled: Bool
    public var exportAPIKey: String?

    public init(disabled: Bool = false, exportAPIKey: String? = nil) {
        self.disabled = disabled
        self.exportAPIKey = exportAPIKey
    }
}

public struct SpanData: Sendable, Equatable, Codable {
    public var kind: String
    public var attributes: [String: JSONValue]

    public init(kind: String, attributes: [String: JSONValue] = [:]) {
        self.kind = kind
        self.attributes = attributes
    }
}

public typealias AgentSpanData = SpanData
public typealias GenerationSpanData = SpanData
public typealias FunctionSpanData = SpanData
public typealias GuardrailSpanData = SpanData
public typealias HandoffSpanData = SpanData
public typealias MCPListToolsSpanData = SpanData
public typealias CustomSpanData = SpanData

public struct Span: Sendable, Equatable {
    public var id: String
    public var name: String
    public var data: SpanData?
    public var startedAt: Date
    public var endedAt: Date?
    public var error: SpanError?

    public init(id: String = genSpanID(), name: String, data: SpanData? = nil, startedAt: Date = Date(), endedAt: Date? = nil, error: SpanError? = nil) {
        self.id = id
        self.name = name
        self.data = data
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.error = error
    }
}

public struct Trace: Sendable, Equatable {
    public var id: String
    public var name: String
    public var groupID: String?
    public var metadata: [String: JSONValue]?
    public var startedAt: Date
    public var endedAt: Date?
    public var spans: [Span]

    public init(id: String = genTraceID(), name: String, groupID: String? = nil, metadata: [String: JSONValue]? = nil, startedAt: Date = Date(), endedAt: Date? = nil, spans: [Span] = []) {
        self.id = id
        self.name = name
        self.groupID = groupID
        self.metadata = metadata
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.spans = spans
    }
}

public protocol TracingProcessor: Sendable {
    func process(trace: Trace) async
}

public final class ClosureTracingProcessor: TracingProcessor, @unchecked Sendable {
    private let closure: @Sendable (Trace) async -> Void
    public init(_ closure: @escaping @Sendable (Trace) async -> Void) { self.closure = closure }
    public func process(trace: Trace) async { await closure(trace) }
}

private final class TracingState: @unchecked Sendable {
    static let shared = TracingState()

    private let lock = NSLock()
    private var currentTrace: Trace?
    private var currentSpan: Span?
    private var processors: [TracingProcessor] = []

    func setCurrentTrace(_ trace: Trace?) {
        lock.lock()
        currentTrace = trace
        lock.unlock()
    }

    func getCurrentTrace() -> Trace? {
        lock.lock(); defer { lock.unlock() }
        return currentTrace
    }

    func setCurrentSpan(_ span: Span?) {
        lock.lock()
        currentSpan = span
        lock.unlock()
    }

    func getCurrentSpan() -> Span? {
        lock.lock(); defer { lock.unlock() }
        return currentSpan
    }

    func setProcessors(_ processors: [TracingProcessor]) {
        lock.lock()
        self.processors = processors
        lock.unlock()
    }

    func addProcessor(_ processor: TracingProcessor) {
        lock.lock()
        processors.append(processor)
        lock.unlock()
    }

    func getProcessors() -> [TracingProcessor] {
        lock.lock(); defer { lock.unlock() }
        return processors
    }
}

private struct TraceSpanAdapter: ErrorTracingSpan {
    let spanID: String
    let traceID: String?
    func setError(_ error: SpanError) {}
}

public func genTraceID() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "") }
public func genSpanID() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "") }

public func setTraceProcessors(_ processors: [TracingProcessor]) {
    TracingState.shared.setProcessors(processors)
}

public func addTraceProcessor(_ processor: TracingProcessor) {
    TracingState.shared.addProcessor(processor)
}

public func getCurrentTrace() -> Trace? {
    TracingState.shared.getCurrentTrace()
}

public func getCurrentSpan() -> Span? {
    TracingState.shared.getCurrentSpan()
}

public func createTraceForRun(name: String, groupID: String? = nil, metadata: [String: JSONValue]? = nil) -> Trace {
    let trace = Trace(name: name, groupID: groupID, metadata: metadata)
    TracingState.shared.setCurrentTrace(trace)
    return trace
}

public func finishTrace(_ trace: Trace) async {
    var finished = trace
    finished.endedAt = Date()
    for processor in TracingState.shared.getProcessors() {
        await processor.process(trace: finished)
    }
    TracingState.shared.setCurrentTrace(nil)
}

public func withSpan<T>(name: String, data: SpanData? = nil, operation: () async throws -> T) async rethrows -> T {
    let span = Span(name: name, data: data)
    TracingState.shared.setCurrentSpan(span)
    setCurrentErrorTracingSpanProvider {
        TraceSpanAdapter(spanID: span.id, traceID: getCurrentTrace()?.id)
    }
    defer {
        TracingState.shared.setCurrentSpan(nil)
        setCurrentErrorTracingSpanProvider(nil)
    }
    return try await operation()
}
