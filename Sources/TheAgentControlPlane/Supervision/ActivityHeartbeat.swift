import Foundation
import OmniAgentMesh

public struct ActivityHeartbeat: Sendable, Equatable {
    public enum Source: String, Sendable {
        case root
        case worker
        case acp
        case attractor
        case tool
        case mission
        case unknown
    }

    public var taskID: String
    public var source: Source
    public var phase: String
    public var recordedAt: Date
    public var data: [String: String]

    public init(
        taskID: String,
        source: Source,
        phase: String,
        recordedAt: Date,
        data: [String: String] = [:]
    ) {
        self.taskID = taskID
        self.source = source
        self.phase = phase
        self.recordedAt = recordedAt
        self.data = data
    }

    public static func from(event: TaskEvent) -> ActivityHeartbeat {
        let source = Source(rawValue: event.data["heartbeat_source"] ?? "") ?? inferSource(from: event)
        let phase = event.data["heartbeat_phase"] ?? event.kind.rawValue
        return ActivityHeartbeat(
            taskID: event.taskID,
            source: source,
            phase: phase,
            recordedAt: event.createdAt,
            data: event.data
        )
    }

    public static func coverage(from event: TaskEvent) -> ActivityHeartbeat? {
        guard isCoverageEvent(event) else {
            return nil
        }
        return from(event: event)
    }

    private static func isCoverageEvent(_ event: TaskEvent) -> Bool {
        if event.data["heartbeat_source"] != nil || event.data["heartbeat_phase"] != nil {
            return true
        }

        switch event.kind {
        case .submitted, .assigned, .started:
            return false
        case .progress, .waiting, .completed, .failed, .cancelled, .resumed, .toolCall, .artifact:
            return true
        }
    }

    private static func inferSource(from event: TaskEvent) -> Source {
        if event.kind == .toolCall {
            return .tool
        }
        if event.summary?.localizedStandardContains("Attractor") == true ||
            event.data["event_kind"]?.localizedStandardContains("pipeline") == true ||
            event.data["event_kind"]?.localizedStandardContains("stage_") == true {
            return .attractor
        }
        if event.summary?.localizedStandardContains("ACP") == true ||
            event.data["profile_id"] != nil {
            return .acp
        }
        switch event.kind {
        case .submitted, .assigned, .started, .progress, .waiting, .completed, .failed, .cancelled, .resumed:
            return .worker
        case .toolCall:
            return .tool
        case .artifact:
            return .mission
        }
    }
}
