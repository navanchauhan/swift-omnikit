import Foundation

final class StreamingEventBuffer<Element: Sendable>: @unchecked Sendable {
    private let continuation: AsyncThrowingStream<Element, Error>.Continuation
    let stream: AsyncThrowingStream<Element, Error>

    init() {
        var continuationRef: AsyncThrowingStream<Element, Error>.Continuation!
        self.stream = AsyncThrowingStream { continuation in
            continuationRef = continuation
        }
        self.continuation = continuationRef
    }

    func yield(_ element: Element) {
        continuation.yield(element)
    }

    func finish() {
        continuation.finish()
    }

    func fail(_ error: Error) {
        continuation.finish(throwing: error)
    }
}

