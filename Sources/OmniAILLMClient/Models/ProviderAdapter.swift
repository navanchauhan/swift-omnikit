import Foundation

public protocol ProviderAdapter: AnyObject, Sendable {
    var name: String { get }

    func complete(request: Request) async throws -> Response
    func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error>

    // Optional methods with default implementations
    func close() async
    func initialize() async throws
    func supportsToolChoice(mode: String) -> Bool
}

extension ProviderAdapter {
    public func close() async {}
    public func initialize() async throws {}
    public func supportsToolChoice(mode: String) -> Bool { true }
}
