#if os(Linux)
import Foundation

private final class _OmniAppearanceState: @unchecked Sendable {
    static let shared = _OmniAppearanceState()

    private let lock = NSLock()
    private var appearanceName: NSAppearance.Name?
    private var handler: (@Sendable (ColorScheme?) -> Void)?

    func setAppearanceName(_ name: NSAppearance.Name?) {
        let scheme = Self.colorScheme(for: name)
        let callback: (@Sendable (ColorScheme?) -> Void)?
        lock.lock()
        appearanceName = name
        callback = handler
        lock.unlock()
        callback?(scheme)
    }

    func currentColorScheme() -> ColorScheme? {
        lock.lock()
        let name = appearanceName
        lock.unlock()
        return Self.colorScheme(for: name)
    }

    func setChangeHandler(_ next: (@Sendable (ColorScheme?) -> Void)?) {
        let scheme: ColorScheme?
        lock.lock()
        handler = next
        scheme = Self.colorScheme(for: appearanceName)
        lock.unlock()
        next?(scheme)
    }

    private static func colorScheme(for name: NSAppearance.Name?) -> ColorScheme? {
        guard let name else { return nil }
        if name == .darkAqua { return .dark }
        if name == .aqua { return .light }
        return nil
    }
}

public func _omniSetAppearanceChangeHandler(_ handler: (@Sendable (ColorScheme?) -> Void)?) {
    _OmniAppearanceState.shared.setChangeHandler(handler)
}

public func _omniCurrentAppearanceColorScheme() -> ColorScheme? {
    _OmniAppearanceState.shared.currentColorScheme()
}

public func _omniEffectiveAppearanceColorScheme() -> ColorScheme {
    _omniCurrentAppearanceColorScheme() ?? .dark
}

public final class NSAppearance: NSObject, @unchecked Sendable {
    public struct Name: RawRepresentable, Equatable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let aqua = Name(rawValue: "aqua")
        public static let darkAqua = Name(rawValue: "darkAqua")
    }

    public let name: Name

    public init?(named name: Name) {
        self.name = name
        super.init()
    }

    public func performAsCurrentDrawingAppearance(_ body: () -> Void) {
        body()
    }
}

public final class NSApplication: NSObject, @unchecked Sendable {
    public var appearance: NSAppearance? {
        didSet {
            _OmniAppearanceState.shared.setAppearanceName(appearance?.name)
        }
    }
}

public let NSApp = NSApplication()

public final class NSWorkspace: NSObject, @unchecked Sendable {
    public static let shared = NSWorkspace()

    public func open(_ url: URL) {
        _ = url
    }
}

public final class NSCursor: NSObject, @unchecked Sendable {
    public static let pointingHand = NSCursor()

    public func push() {}

    public static func pop() {}
}

public final class NSColor: NSObject, @unchecked Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
        super.init()
    }

    public static let labelColor = NSColor("labelColor")
    public static let windowBackgroundColor = NSColor("windowBackgroundColor")
}

public final class NSImage: NSObject, @unchecked Sendable {
    private let storage: Data?
    private let sourceURL: URL?
    private let imageName: String?

    public init?(data: Data) {
        self.storage = data
        self.sourceURL = nil
        self.imageName = nil
        super.init()
    }

    public init?(contentsOf url: URL) {
        self.storage = try? Data(contentsOf: url)
        self.sourceURL = url
        self.imageName = nil
        super.init()
        if storage == nil { return nil }
    }

    public init(named name: String) {
        self.storage = nil
        self.sourceURL = nil
        self.imageName = name
        super.init()
    }

    func _omniPNGRepresentation() -> Data? {
        storage
    }

    func name() -> String? {
        imageName ?? sourceURL?.lastPathComponent
    }
}

public extension Image {
    init(nsImage: NSImage) {
        if let data = nsImage._omniPNGRepresentation() {
            self.init(systemName: _OmniImageRegistry.store(data))
        } else {
            self.init(systemName: nsImage.name() ?? "photo")
        }
    }
}

public extension Color {
    init(_ nsColor: NSColor) {
        self.init(nsColor.name)
    }

    init(nsColor: NSColor) {
        self.init(nsColor)
    }
}
#endif
