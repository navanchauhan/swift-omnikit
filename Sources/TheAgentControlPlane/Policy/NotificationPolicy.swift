import Foundation
import OmniAgentMesh

public struct NotificationPolicy: Sendable, Equatable {
    public var interruptThreshold: NotificationRecord.Importance

    public init(interruptThreshold: NotificationRecord.Importance = .urgent) {
        self.interruptThreshold = interruptThreshold
    }

    public func shouldInterruptUser(for notification: NotificationRecord) -> Bool {
        notification.importance >= interruptThreshold
    }
}
