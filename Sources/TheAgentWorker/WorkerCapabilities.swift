import Foundation

public struct WorkerCapabilities: Codable, Sendable, Equatable {
    public var labels: [String]

    public init(_ labels: [String]) {
        self.labels = Array(Set(labels)).sorted()
    }

    public func satisfies(_ requirements: [String]) -> Bool {
        Set(requirements).isSubset(of: Set(labels))
    }
}
