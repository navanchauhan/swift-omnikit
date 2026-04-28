import Foundation
import OmniAgentMesh

public actor ScheduledPromptRunner {
    public typealias DeliverySink = @Sendable ([IngressDeliveryInstruction]) async throws -> Void

    private let store: any ScheduledPromptStore
    private let gateway: IngressGateway
    private let deliverySink: DeliverySink
    private let retryDelay: TimeInterval

    public init(
        store: any ScheduledPromptStore,
        gateway: IngressGateway,
        retryDelay: TimeInterval = 60,
        deliverySink: @escaping DeliverySink
    ) {
        self.store = store
        self.gateway = gateway
        self.retryDelay = retryDelay
        self.deliverySink = deliverySink
    }

    public func run(pollInterval: Duration = .seconds(15)) async throws {
        while !Task.isCancelled {
            try await fireDuePrompts(now: Date())
            try await Task.sleep(for: pollInterval)
        }
    }

    @discardableResult
    public func fireDuePrompts(now: Date = Date()) async throws -> [String] {
        let duePrompts = try await store.duePrompts(now: now)
        var firedIDs: [String] = []
        for record in duePrompts {
            do {
                let result = try await gateway.handle(envelope(for: record, now: now))
                if !result.deliveries.isEmpty {
                    try await deliverySink(result.deliveries)
                }
                _ = try await store.recordFire(scheduleID: record.scheduleID, firedAt: now)
                firedIDs.append(record.scheduleID)
            } catch {
                _ = try await store.recordFailure(
                    scheduleID: record.scheduleID,
                    error: String(describing: error),
                    retryAt: now.addingTimeInterval(retryDelay)
                )
            }
        }
        return firedIDs
    }

    private func envelope(for record: ScheduledPromptRecord, now: Date) -> IngressEnvelope {
        let eventKind = IngressEnvelope.EventKind(rawValue: record.eventKind) ?? .automationEvent
        let channelKind = IngressEnvelope.ChannelKind(rawValue: record.channelKind) ?? .directMessage
        return IngressEnvelope(
            transport: record.transport,
            payloadKind: .text,
            updateID: "scheduled.\(record.scheduleID).\(Int(now.timeIntervalSince1970))",
            messageID: "scheduled.\(record.scheduleID).\(record.fireCount + 1)",
            actorExternalID: record.actorExternalID,
            actorDisplayName: record.actorDisplayName,
            channelExternalID: record.channelExternalID,
            channelKind: channelKind,
            eventKind: eventKind,
            text: syntheticText(for: record, now: now),
            mentionTriggerActive: true,
            replyContextActive: true,
            metadata: record.metadata.merging([
                "schedule_id": record.scheduleID,
                "schedule_title": record.title,
                "schedule_recurrence": record.recurrence.rawValue,
                "schedule_timezone": record.timezoneIdentifier,
                "scheduled_fire_at": now.ISO8601Format(),
            ]) { _, new in new },
            receivedAt: now
        )
    }

    private func syntheticText(for record: ScheduledPromptRecord, now: Date) -> String {
        """
        Scheduled \(record.eventKind) fired. This is an already-created schedule firing now.
        Do not call `schedule_prompt`, `list_scheduled_prompts`, or `cancel_scheduled_prompt` for this event unless the scheduled instructions explicitly ask you to modify schedules.
        For a scheduled notification/reminder, send the user the reminder now in one short message if the instructions are notify-only.
        If the scheduled instructions ask you to check, look up, search, inspect, summarize, compare, report current state, or otherwise do work, perform that work now using tools as needed, then send the result.
        For a scheduled automation_event, perform the scheduled work now using tools as needed, then send the requested result. Do not merely restate, summarize, or remind the user of the scheduled instructions.

        schedule_id: \(record.scheduleID)
        title: \(record.title)
        fire_time: \(now.ISO8601Format())
        recurrence: \(record.recurrence.rawValue)

        Follow these scheduled instructions:
        \(record.prompt)
        """
    }
}
