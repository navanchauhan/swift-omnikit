import Foundation
import OmniAgentMesh

public struct DeployHealthOutcome: Sendable, Equatable {
    public var status: DeploymentRecord.HealthStatus
    public var summary: String
    public var metadata: [String: String]
    public var checkedAt: Date

    public init(
        status: DeploymentRecord.HealthStatus,
        summary: String,
        metadata: [String: String] = [:],
        checkedAt: Date = Date()
    ) {
        self.status = status
        self.summary = summary
        self.metadata = metadata
        self.checkedAt = checkedAt
    }
}

public actor DeployHealthService {
    public typealias Probe = @Sendable (DeploymentRecord) async -> DeployHealthOutcome

    private let warmupTimeout: TimeInterval
    private let steadyStateTimeout: TimeInterval
    private let probe: Probe

    public init(
        warmupTimeout: TimeInterval = 30,
        steadyStateTimeout: TimeInterval = 120,
        probe: @escaping Probe = { _ in
            DeployHealthOutcome(status: .healthy, summary: "default health probe passed")
        }
    ) {
        self.warmupTimeout = max(1, warmupTimeout)
        self.steadyStateTimeout = max(self.warmupTimeout, steadyStateTimeout)
        self.probe = probe
    }

    public func evaluateCanary(_ deployment: DeploymentRecord) async -> DeployHealthOutcome {
        var outcome = await probe(deployment)
        outcome.metadata["warmup_timeout_seconds"] = String(Int(warmupTimeout))
        outcome.metadata["steady_state_timeout_seconds"] = String(Int(steadyStateTimeout))
        return outcome
    }
}
