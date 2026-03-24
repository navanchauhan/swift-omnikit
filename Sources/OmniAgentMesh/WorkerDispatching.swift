import Foundation

public protocol WorkerDispatching: Sendable {
    var workerID: String { get }
    var advertisedCapabilities: [String] { get }

    func register(at: Date, metadata: [String: String]) async throws -> WorkerRecord
    func drainOnce(now: Date) async throws -> TaskRecord?
    func runNextTaskInBackground(now: Date) async throws -> TaskRecord?
}
