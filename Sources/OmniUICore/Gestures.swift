import Foundation

// MARK: - TapGesture

public struct TapGesture: Sendable {
    public var count: Int

    private var _onEnded: (@Sendable () -> Void)?

    public init(count: Int = 1) {
        self.count = count
    }

    public func onEnded(_ action: @escaping @Sendable () -> Void) -> TapGesture {
        var copy = self
        copy._onEnded = action
        return copy
    }

    public func _fireEnded() {
        _onEnded?()
    }
}

/// The kind of gesture attached to a view subtree.
public enum _GestureKind: @unchecked Sendable {
    case drag(DragGesture)
    case longPress(LongPressGesture)
    case tap(TapGesture)
}

// Gesture modifier: defined in Modifiers.swift to avoid circular reference.
