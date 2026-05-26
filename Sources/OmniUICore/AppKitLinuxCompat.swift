#if os(Linux)
import Dispatch
import Foundation
import Glibc
import UniformTypeIdentifiers

public typealias NSRect = CGRect
public typealias NSPoint = CGPoint
public typealias NSSize = CGSize

public struct Selector: Hashable, Sendable, ExpressibleByStringLiteral {
    public var name: String

    public init(_ name: String) {
        self.name = Self.normalizedName(name)
    }

    public init(stringLiteral value: String) {
        self.name = Self.normalizedName(value)
    }

    private static func normalizedName(_ name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return name }
        let suffix = name[name.index(after: dot)...]
        return suffix.isEmpty ? name : String(suffix)
    }
}

private final class _OmniSelectorActionRegistry: @unchecked Sendable {
    static let shared = _OmniSelectorActionRegistry()

    private let lock = NSLock()
    private var handlers: [ObjectIdentifier: [Selector: (Any?) -> Void]] = [:]

    func register(target: AnyObject, selector: Selector, handler: @escaping (Any?) -> Void) {
        let id = ObjectIdentifier(target)
        lock.lock()
        var targetHandlers = handlers[id] ?? [:]
        targetHandlers[selector] = handler
        handlers[id] = targetHandlers
        lock.unlock()
    }

    func canPerform(target: AnyObject?, selector: Selector) -> Bool {
        guard let target else { return false }
        lock.lock()
        let hasHandler = handlers[ObjectIdentifier(target)]?[selector] != nil
        lock.unlock()
        return hasHandler
    }

    func perform(target: AnyObject?, selector: Selector, sender: Any?) -> Bool {
        guard let target else { return false }
        lock.lock()
        let handler = handlers[ObjectIdentifier(target)]?[selector]
        lock.unlock()
        guard let handler else { return false }
        handler(sender)
        return true
    }
}

public extension NSObject {
    func _omniRegisterSelectorAction(_ selector: Selector, handler: @escaping (Any?) -> Void) {
        _OmniSelectorActionRegistry.shared.register(target: self, selector: selector, handler: handler)
    }
}

public struct CGColor: Hashable, Sendable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

private final class _OmniAppearanceState: @unchecked Sendable {
    static let shared = _OmniAppearanceState()

    private let lock = NSLock()
    private var appearanceName: NSAppearance.Name?
    private var preferredColorScheme: ColorScheme?
    private var handler: (@Sendable (ColorScheme?) -> Void)?
    private var observers: [UUID: @Sendable (ColorScheme?) -> Void] = [:]

    func setAppearanceName(_ name: NSAppearance.Name?) {
        let scheme = Self.colorScheme(for: name)
        let callbacks: [@Sendable (ColorScheme?) -> Void]
        let effective: ColorScheme?
        let previous: ColorScheme?
        lock.lock()
        previous = preferredColorScheme ?? Self.colorScheme(for: appearanceName) ?? Self.environmentColorSchemeOverride()
        appearanceName = name
        effective = preferredColorScheme ?? scheme ?? Self.environmentColorSchemeOverride()
        callbacks = effective != previous ? [handler].compactMap { $0 } + Array(observers.values) : []
        lock.unlock()
        callbacks.forEach { $0(effective) }
    }

    func currentColorScheme() -> ColorScheme? {
        lock.lock()
        let preferred = preferredColorScheme
        let name = appearanceName
        lock.unlock()
        return preferred ?? Self.colorScheme(for: name) ?? Self.environmentColorSchemeOverride()
    }

    func currentApplicationColorScheme() -> ColorScheme? {
        lock.lock()
        let name = appearanceName
        lock.unlock()
        return Self.colorScheme(for: name)
    }

    func setPreferredColorScheme(_ scheme: ColorScheme?) {
        let callbacks: [@Sendable (ColorScheme?) -> Void]
        let effective: ColorScheme?
        let previous: ColorScheme?
        lock.lock()
        previous = preferredColorScheme ?? Self.colorScheme(for: appearanceName) ?? Self.environmentColorSchemeOverride()
        preferredColorScheme = scheme
        effective = scheme ?? Self.colorScheme(for: appearanceName) ?? Self.environmentColorSchemeOverride()
        callbacks = effective != previous ? [handler].compactMap { $0 } + Array(observers.values) : []
        lock.unlock()
        callbacks.forEach { $0(effective) }
    }

    func setChangeHandler(_ next: (@Sendable (ColorScheme?) -> Void)?) {
        let scheme: ColorScheme?
        lock.lock()
        handler = next
        scheme = preferredColorScheme ?? Self.colorScheme(for: appearanceName) ?? Self.environmentColorSchemeOverride()
        lock.unlock()
        next?(scheme)
    }

    func addChangeObserver(_ next: @escaping @Sendable (ColorScheme?) -> Void) -> _OmniAppearanceChangeObservation {
        let id = UUID()
        let scheme: ColorScheme?
        lock.lock()
        observers[id] = next
        scheme = preferredColorScheme ?? Self.colorScheme(for: appearanceName) ?? Self.environmentColorSchemeOverride()
        lock.unlock()
        next(scheme)
        return _OmniAppearanceChangeObservation { [weak self] in
            self?.removeChangeObserver(id)
        }
    }

    private func removeChangeObserver(_ id: UUID) {
        lock.lock()
        observers[id] = nil
        lock.unlock()
    }

    private static func colorScheme(for name: NSAppearance.Name?) -> ColorScheme? {
        guard let name else { return nil }
        if name == .darkAqua { return .dark }
        if name == .aqua { return .light }
        return nil
    }

    private static func environmentColorSchemeOverride() -> ColorScheme? {
        let environment = ProcessInfo.processInfo.environment
        for key in ["OMNIUI_ADWAITA_COLOR_SCHEME", "OMNIUI_COLOR_SCHEME"] {
            guard let raw = environment[key]?.lowercased(), !raw.isEmpty else { continue }
            if raw == "dark" || raw == "force-dark" { return .dark }
            if raw == "light" || raw == "force-light" { return .light }
            if raw == "system" || raw == "default" { return nil }
        }
        if let gtkTheme = environment["GTK_THEME"]?.lowercased(), gtkTheme.contains(":dark") {
            return .dark
        }
        return nil
    }
}

public final class _OmniAppearanceChangeObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var onInvalidate: (() -> Void)?

    fileprivate init(_ onInvalidate: @escaping () -> Void) {
        self.onInvalidate = onInvalidate
    }

    public func invalidate() {
        let callback: (() -> Void)?
        lock.lock()
        callback = onInvalidate
        onInvalidate = nil
        lock.unlock()
        callback?()
    }

    deinit {
        invalidate()
    }
}

public func _omniSetAppearanceChangeHandler(_ handler: (@Sendable (ColorScheme?) -> Void)?) {
    _OmniAppearanceState.shared.setChangeHandler(handler)
}

public func _omniAddAppearanceChangeHandler(
    _ handler: @escaping @Sendable (ColorScheme?) -> Void
) -> _OmniAppearanceChangeObservation {
    _OmniAppearanceState.shared.addChangeObserver(handler)
}

public func _omniCurrentAppearanceColorScheme() -> ColorScheme? {
    _OmniAppearanceState.shared.currentColorScheme()
}

public func _omniCurrentApplicationAppearanceColorScheme() -> ColorScheme? {
    _OmniAppearanceState.shared.currentApplicationColorScheme()
}

public func _omniEffectiveAppearanceColorScheme() -> ColorScheme {
    _omniCurrentAppearanceColorScheme() ?? .light
}

public func _omniSetPreferredColorScheme(_ scheme: ColorScheme?) {
    _OmniAppearanceState.shared.setPreferredColorScheme(scheme)
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
    public static let shared = NSApp
    public static let willTerminateNotification = Notification.Name("NSApplicationWillTerminateNotification")
    public var windows: [NSWindow] = []
    public weak var delegate: NSApplicationDelegate?
    public weak var keyWindow: NSWindow?
    public var applicationIconImage: NSImage?
    fileprivate var activationHandler: (@Sendable () -> Void)?
    public var appearance: NSAppearance? {
        didSet {
            _OmniAppearanceState.shared.setAppearanceName(appearance?.name)
        }
    }

    public func activate(ignoringOtherApps flag: Bool = true) {
        _ = flag
        activationHandler?()
    }

    public func terminate(_ sender: Any?) {
        _ = sender
        NotificationCenter.default.post(name: Self.willTerminateNotification, object: self)
        guard ProcessInfo.processInfo.environment["OMNIKIT_SUPPRESS_TERMINATE"] != "1" else { return }
        Glibc.exit(0)
    }

    public func applicationShouldTerminateAfterLastWindowClosed() -> Bool {
        delegate?.applicationShouldTerminateAfterLastWindowClosed(self) ?? false
    }

    public func sendEvent(_ event: NSEvent) {
        if let keyWindow {
            keyWindow.sendEvent(event)
        } else {
            _ = NSEvent._deliverLocalMonitors(event)
        }
    }

    @discardableResult
    public func sendAction(_ action: Selector, to target: AnyObject?, from sender: Any?) -> Bool {
        _omniDispatchSelector(action, to: target, from: sender)
    }
}

public func _omniSetApplicationActivationHandler(_ handler: (@Sendable () -> Void)?) {
    NSApp.activationHandler = handler
}

public protocol NSApplicationDelegate: AnyObject {
    init()
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool
}

@propertyWrapper
public struct NSApplicationDelegateAdaptor<Delegate: NSApplicationDelegate> {
    public var wrappedValue: Delegate

    public init(_ delegateType: Delegate.Type) {
        let delegate = delegateType.init()
        self.wrappedValue = delegate
        NSApp.delegate = delegate
    }
}

public let NSApp = NSApplication()

private enum _OmniDesktopProcess {
    private static var pathDirectories: [String] {
        (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin")
            .split(separator: ":")
            .map(String.init)
    }

    private static func executableExists(_ executable: String) -> Bool {
        guard !executable.isEmpty else { return false }
        if executable.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: executable)
        }
        return pathDirectories.contains { directory in
            FileManager.default.isExecutableFile(atPath: URL(fileURLWithPath: directory).appendingPathComponent(executable).path)
        }
    }

    private static func capture(_ command: [String]) -> Bool {
        guard let capturePath = ProcessInfo.processInfo.environment["OMNIKIT_DESKTOP_PROCESS_CAPTURE"],
              !capturePath.isEmpty else { return false }
        let line = command
            .map { $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\t", with: "\\t") }
            .joined(separator: "\t") + "\n"
        let url = URL(fileURLWithPath: capturePath)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
        return true
    }

    @discardableResult
    static func runDetached(_ command: [String]) -> Bool {
        guard !command.isEmpty else { return false }
        if capture(command) {
            return true
        }
        guard executableExists(command[0]) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func runDetached(firstAvailable commands: [[String]]) -> Bool {
        guard let command = commands.first(where: { command in
            guard let executable = command.first else { return false }
            return capturePathIsSet || executableExists(executable)
        }) else { return false }
        return runDetached(command)
    }

    private static var capturePathIsSet: Bool {
        guard let capturePath = ProcessInfo.processInfo.environment["OMNIKIT_DESKTOP_PROCESS_CAPTURE"] else { return false }
        return !capturePath.isEmpty
    }

    static func run(_ command: [String]) -> Int32? {
        guard !command.isEmpty else { return nil }
        if capture(command) {
            return 0
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return nil
        }
    }

    static func output(_ command: [String]) -> String? {
        guard !command.isEmpty else { return nil }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines)
        } catch {
            return nil
        }
    }

    static func write(_ string: String, to command: [String]) -> Bool {
        guard !command.isEmpty else { return false }
        if capture(command) {
            return true
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.standardInput = pipe
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            if let data = string.data(using: .utf8) {
                pipe.fileHandleForWriting.write(data)
            }
            pipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

public final class NSWorkspace: NSObject, @unchecked Sendable {
    public final class OpenConfiguration: NSObject, @unchecked Sendable {
        public override init() {
            super.init()
        }
    }

    public static let shared = NSWorkspace()

    @discardableResult
    public func open(_ url: URL) -> Bool {
        let target = url.isFileURL ? url.path : url.absoluteString
        return _OmniDesktopProcess.runDetached(firstAvailable: [
            ["gio", "open", target],
            ["xdg-open", target],
        ])
    }

    @discardableResult
    public func open(_ urls: [URL], withApplicationAt applicationURL: URL, configuration: OpenConfiguration) -> Bool {
        let launcher = applicationLauncher(for: applicationURL)
        var launched = true
        for url in urls {
            let target = url.isFileURL ? url.path : url.absoluteString
            if let launcher {
                launched = _OmniDesktopProcess.runDetached([launcher, target]) && launched
            } else if applicationURL.path.isEmpty {
                launched = open(url) && launched
            } else {
                launched = false
            }
        }
        _ = applicationURL
        _ = configuration
        return launched
    }

    private func applicationLauncher(for applicationURL: URL) -> String? {
        let path = applicationURL.path
        guard !path.isEmpty else { return nil }

        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        if exists, !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        guard applicationURL.pathExtension == "app", isDirectory.boolValue else {
            return nil
        }

        let executableDirectory = applicationURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
        let preferredExecutable = executableDirectory
            .appendingPathComponent(applicationURL.deletingPathExtension().lastPathComponent)
        if FileManager.default.isExecutableFile(atPath: preferredExecutable.path) {
            return preferredExecutable.path
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: executableDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        return contents
            .map(\.path)
            .sorted()
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func activateFileViewerSelecting(_ fileURLs: [URL]) {
        for url in fileURLs {
            _ = open(url)
        }
    }

    @discardableResult
    public func selectFile(_ fullPath: String?, inFileViewerRootedAtPath rootFullPath: String) -> Bool {
        if let fullPath, !fullPath.isEmpty {
            return open(URL(fileURLWithPath: fullPath))
        }
        return open(URL(fileURLWithPath: rootFullPath))
    }
}

public final class NSRunningApplication: NSObject, @unchecked Sendable {
    public struct ActivationOptions: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
    }

    public let processIdentifier: Int32
    public let bundleIdentifier: String?

    public init(processIdentifier: Int32 = 0, bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        super.init()
    }

    public static func runningApplications(withBundleIdentifier bundleIdentifier: String) -> [NSRunningApplication] {
        guard !bundleIdentifier.isEmpty else { return [] }
        var applications: [NSRunningApplication] = []
        let currentPID = ProcessInfo.processInfo.processIdentifier
        if process(pid: currentPID, matchesBundleIdentifier: bundleIdentifier) {
            applications.append(NSRunningApplication(processIdentifier: currentPID, bundleIdentifier: bundleIdentifier))
        }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/proc") else {
            return applications
        }
        for entry in entries {
            guard let pid = Int32(entry),
                  pid > 0,
                  pid != currentPID,
                  process(pid: pid, matchesBundleIdentifier: bundleIdentifier) else {
                continue
            }
            applications.append(NSRunningApplication(processIdentifier: pid, bundleIdentifier: bundleIdentifier))
        }
        return applications.sorted { $0.processIdentifier < $1.processIdentifier }
    }

    public func activate(options: ActivationOptions) {
        _ = options
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func process(pid: Int32, matchesBundleIdentifier bundleIdentifier: String) -> Bool {
        let target = normalizedIdentifier(bundleIdentifier)
        let shortTarget = normalizedIdentifier(bundleIdentifier.split(separator: ".").last.map(String.init) ?? bundleIdentifier)
        guard !target.isEmpty else { return false }

        for environmentName in ["OMNIKIT_BUNDLE_IDENTIFIER", "CFBundleIdentifier", "G_APPLICATION_ID"] {
            if let value = processEnvironmentValue(pid: pid, name: environmentName),
               normalizedIdentifier(value) == target {
                return true
            }
        }

        let commandLine = processCommandLine(pid: pid)
        if commandLine.contains(bundleIdentifier) || normalizedIdentifier(commandLine).contains(target) {
            return true
        }

        let executableName = processExecutableName(pid: pid)
        let normalizedExecutable = normalizedIdentifier(executableName)
        return !shortTarget.isEmpty && (
            normalizedExecutable == shortTarget ||
            normalizedExecutable.hasPrefix(shortTarget) ||
            normalizedIdentifier(commandLine).contains(shortTarget)
        )
    }

    private static func processCommandLine(pid: Int32) -> String {
        let path = "/proc/\(pid)/cmdline"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              !data.isEmpty else {
            return ""
        }
        return String(decoding: data.map { $0 == 0 ? 32 : $0 }, as: UTF8.self)
    }

    private static func processExecutableName(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let path = "/proc/\(pid)/exe"
        let count = path.withCString { readlink($0, &buffer, buffer.count - 1) }
        guard count > 0 else { return "" }
        let executablePath = String(decoding: buffer.prefix(Int(count)).map(UInt8.init(bitPattern:)), as: UTF8.self)
        return URL(fileURLWithPath: executablePath).lastPathComponent
    }

    private static func processEnvironmentValue(pid: Int32, name: String) -> String? {
        let path = "/proc/\(pid)/environ"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              !data.isEmpty else {
            return nil
        }
        let prefix = Array((name + "=").utf8)
        let parts = data.split(separator: 0)
        for part in parts where part.starts(with: prefix) {
            return String(decoding: part.dropFirst(prefix.count), as: UTF8.self)
        }
        return nil
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

private final class _OmniCursorState: @unchecked Sendable {
    let lock = NSLock()
    var stack: [String] = []
    var handler: (@Sendable (String?) -> Void)?
}

public final class NSCursor: NSObject, @unchecked Sendable {
    public static let pointingHand = NSCursor(name: "pointer")
    public static let resizeLeftRight = NSCursor(name: "ew-resize")
    public static let resizeUpDown = NSCursor(name: "ns-resize")

    fileprivate static let cursorState = _OmniCursorState()

    private let name: String

    public override convenience init() {
        self.init(name: "default")
    }

    private init(name: String) {
        self.name = name
        super.init()
    }

    public func push() {
        let handler: (@Sendable (String?) -> Void)?
        Self.cursorState.lock.lock()
        Self.cursorState.stack.append(name)
        handler = Self.cursorState.handler
        Self.cursorState.lock.unlock()
        handler?(name)
    }

    public static func pop() {
        let next: String?
        let handler: (@Sendable (String?) -> Void)?
        cursorState.lock.lock()
        if !cursorState.stack.isEmpty {
            cursorState.stack.removeLast()
        }
        next = cursorState.stack.last
        handler = cursorState.handler
        cursorState.lock.unlock()
        handler?(next)
    }

    public static var currentSystemCursorName: String? {
        cursorState.lock.lock()
        defer { cursorState.lock.unlock() }
        return cursorState.stack.last
    }
}

public func _omniSetCursorHandler(_ handler: (@Sendable (String?) -> Void)?) {
    let current: String?
    NSCursor.cursorState.lock.lock()
    NSCursor.cursorState.handler = handler
    current = NSCursor.cursorState.stack.last
    NSCursor.cursorState.lock.unlock()
    handler?(current)
}

public final class NSColor: NSObject, @unchecked Sendable {
    public let name: String
    public let redComponent: CGFloat
    public let greenComponent: CGFloat
    public let blueComponent: CGFloat
    public let alphaComponent: CGFloat

    public init(_ name: String, red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1) {
        self.name = name
        self.redComponent = red
        self.greenComponent = green
        self.blueComponent = blue
        self.alphaComponent = alpha
        super.init()
    }

    public convenience init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init("rgb(\(red),\(green),\(blue))", red: red, green: green, blue: blue, alpha: alpha)
    }

    public convenience init(calibratedRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    public convenience init(calibratedHue hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        let h = hue - floor(hue)
        let s = max(0, min(1, saturation))
        let v = max(0, min(1, brightness))
        let i = Int(floor(h * 6))
        let f = h * 6 - CGFloat(i)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        let rgb: (CGFloat, CGFloat, CGFloat)
        switch i % 6 {
        case 0: rgb = (v, t, p)
        case 1: rgb = (q, v, p)
        case 2: rgb = (p, v, t)
        case 3: rgb = (p, q, v)
        case 4: rgb = (t, p, v)
        default: rgb = (v, p, q)
        }
        self.init(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
    }

    public convenience init(_ color: Color) {
        if let resolved = _resolveColorToRGB(color) {
            self.init(
                color.name,
                red: CGFloat(resolved.r) / 255.0,
                green: CGFloat(resolved.g) / 255.0,
                blue: CGFloat(resolved.b) / 255.0,
                alpha: color.alpha
            )
        } else {
            let (r, g, b) = _OmniPlatformColor._rgb(for: color.name)
            self.init(color.name, red: r, green: g, blue: b, alpha: color.alpha)
        }
    }

    public static var labelColor: NSColor {
        _dynamicSystemColor("labelColor", light: (0.05, 0.05, 0.05), dark: (0.9, 0.9, 0.9))
    }

    public static var textColor: NSColor {
        _dynamicSystemColor("textColor", light: (0.05, 0.05, 0.05), dark: (0.9, 0.9, 0.9))
    }

    public static var textBackgroundColor: NSColor {
        _dynamicSystemColor("textBackgroundColor", light: (1, 1, 1), dark: (0.08, 0.08, 0.08))
    }

    public static var windowBackgroundColor: NSColor {
        _dynamicSystemColor("windowBackgroundColor", light: (0.96, 0.96, 0.96), dark: (0.12, 0.12, 0.12))
    }

    public static var controlBackgroundColor: NSColor {
        _dynamicSystemColor("controlBackgroundColor", light: (0.93, 0.93, 0.93), dark: (0.12, 0.12, 0.12))
    }

    public static var linkColor: NSColor {
        _dynamicSystemColor("linkColor", light: (0.0, 0.25, 0.75), dark: (0.2, 0.5, 1))
    }

    public static var systemGreen: NSColor {
        _dynamicSystemColor("systemGreen", light: (0.0, 0.55, 0.18), dark: (0.2, 0.8, 0.35))
    }

    private static func _dynamicSystemColor(
        _ name: String,
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> NSColor {
        let rgb = _omniEffectiveAppearanceColorScheme() == .light ? light : dark
        return NSColor(name, red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    public var cgColor: CGColor { CGColor(red: redComponent, green: greenComponent, blue: blueComponent, alpha: alphaComponent) }

    public func withAlphaComponent(_ alpha: CGFloat) -> NSColor {
        NSColor(name, red: redComponent, green: greenComponent, blue: blueComponent, alpha: alpha)
    }

    public func setFill() {
        _OmniImageDrawingRecorder.shared.setFill(self)
    }

    public func setStroke() {
        _OmniImageDrawingRecorder.shared.setStroke(self)
    }

    public func usingColorSpace(_ colorSpace: NSColorSpace) -> NSColor? { self }

    public func getHue(
        _ hue: inout CGFloat,
        saturation: inout CGFloat,
        brightness: inout CGFloat,
        alpha: inout CGFloat
    ) {
        let maxValue = max(redComponent, greenComponent, blueComponent)
        let minValue = min(redComponent, greenComponent, blueComponent)
        brightness = maxValue
        alpha = alphaComponent
        let delta = maxValue - minValue
        saturation = maxValue == 0 ? 0 : delta / maxValue
        guard delta != 0 else {
            hue = 0
            return
        }
        if maxValue == redComponent {
            hue = ((greenComponent - blueComponent) / delta).truncatingRemainder(dividingBy: 6) / 6
        } else if maxValue == greenComponent {
            hue = ((blueComponent - redComponent) / delta + 2) / 6
        } else {
            hue = ((redComponent - greenComponent) / delta + 4) / 6
        }
        if hue < 0 { hue += 1 }
    }
}

public final class NSColorSpace: NSObject, @unchecked Sendable {
    public static let sRGB = NSColorSpace()
}

public final class NSFont: NSObject, @unchecked Sendable {
    public struct Weight: Hashable, Sendable {
        public let rawValue: CGFloat

        public init(_ rawValue: CGFloat) {
            self.rawValue = rawValue
        }

        public static let regular = Weight(0)
        public static let medium = Weight(0.23)
        public static let bold = Weight(0.4)
    }

    public static let systemFontSize: CGFloat = 13

    public let fontName: String
    public let pointSize: CGFloat

    public init(_ name: String, size: CGFloat) {
        self.fontName = name
        self.pointSize = size
        super.init()
    }

    public convenience init?(name: String, size: CGFloat) {
        self.init(name, size: size)
    }

    public static func systemFont(ofSize size: CGFloat) -> NSFont {
        NSFont("System", size: size)
    }

    public static func monospacedSystemFont(ofSize size: CGFloat, weight: Weight) -> NSFont {
        _ = weight
        return NSFont("Monospace", size: size)
    }
}

public struct _OmniImageDrawingCommand: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case fillRect
        case strokeRect
        case strokeLine
        case fillOval
        case strokeOval
    }

    public let kind: Kind
    public let rect: NSRect
    public let colorName: String
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat
}

private final class _OmniImageDrawingContext: @unchecked Sendable {
    var fillColor = NSColor.labelColor
    var strokeColor = NSColor.labelColor
    var commands: [_OmniImageDrawingCommand] = []
}

private final class _OmniImageDrawingRecorder: @unchecked Sendable {
    static let shared = _OmniImageDrawingRecorder()

    private let lock = NSRecursiveLock()
    private var stack: [_OmniImageDrawingContext] = []

    func record<T>(_ body: () -> T) -> (T, [_OmniImageDrawingCommand]) {
        lock.lock()
        let context = _OmniImageDrawingContext()
        stack.append(context)
        lock.unlock()

        let result = body()

        lock.lock()
        let commands = stack.popLast()?.commands ?? []
        lock.unlock()
        return (result, commands)
    }

    func setFill(_ color: NSColor) {
        lock.lock()
        stack.last?.fillColor = color
        lock.unlock()
    }

    func setStroke(_ color: NSColor) {
        lock.lock()
        stack.last?.strokeColor = color
        lock.unlock()
    }

    func fill(_ rect: NSRect, oval: Bool = false) {
        append(kind: oval ? .fillOval : .fillRect, rect: rect, color: currentFillColor())
    }

    func stroke(_ rect: NSRect, oval: Bool = false) {
        append(kind: oval ? .strokeOval : .strokeRect, rect: rect, color: currentStrokeColor())
    }

    func strokeLine(from start: NSPoint, to end: NSPoint, lineWidth: CGFloat) {
        let width = max(1, lineWidth)
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let deltaX = abs(end.x - start.x)
        let deltaY = abs(end.y - start.y)
        let rect = NSRect(
            x: deltaX == 0 ? minX - width / 2 : minX,
            y: deltaY == 0 ? minY - width / 2 : minY,
            width: max(width, deltaX),
            height: max(width, deltaY)
        )
        append(kind: .strokeLine, rect: rect, color: currentStrokeColor())
    }

    private func currentFillColor() -> NSColor {
        lock.lock()
        let color = stack.last?.fillColor ?? .labelColor
        lock.unlock()
        return color
    }

    private func currentStrokeColor() -> NSColor {
        lock.lock()
        let color = stack.last?.strokeColor ?? .labelColor
        lock.unlock()
        return color
    }

    private func append(kind: _OmniImageDrawingCommand.Kind, rect: NSRect, color: NSColor) {
        let command = _OmniImageDrawingCommand(
            kind: kind,
            rect: rect,
            colorName: color.name,
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent,
            alpha: color.alphaComponent
        )
        lock.lock()
        stack.last?.commands.append(command)
        lock.unlock()
    }
}

public final class NSImage: NSObject, @unchecked Sendable {
    private let storage: Data?
    private let sourceURL: URL?
    private let imageName: String?
    public private(set) var _omniDrawingCommands: [_OmniImageDrawingCommand] = []
    public var size: NSSize
    public var isTemplate: Bool = false

    public init(size: NSSize, flipped: Bool, drawingHandler: (NSRect) -> Bool) {
        self.storage = nil
        self.sourceURL = nil
        self.imageName = nil
        self.size = size
        super.init()
        _ = flipped
        let (_, commands) = _OmniImageDrawingRecorder.shared.record {
            drawingHandler(NSRect(origin: .zero, size: size))
        }
        self._omniDrawingCommands = commands
    }

    public init?(data: Data) {
        self.storage = data
        self.sourceURL = nil
        self.imageName = nil
        self.size = .zero
        super.init()
    }

    public init?(contentsOf url: URL) {
        self.storage = try? Data(contentsOf: url)
        self.sourceURL = url
        self.imageName = nil
        self.size = .zero
        super.init()
        if storage == nil { return nil }
    }

    public init(named name: String) {
        self.storage = nil
        self.sourceURL = nil
        self.imageName = name
        self.size = .zero
        super.init()
    }

    func _omniPNGRepresentation() -> Data? {
        storage
    }

    func name() -> String? {
        imageName ?? sourceURL?.lastPathComponent
    }

    func _omniCompactDrawingLabel() -> String? {
        guard !_omniDrawingCommands.isEmpty else { return nil }
        let barCommands = _omniDrawingCommands.filter { command in
            command.kind == .fillRect &&
                command.alpha >= 0.5 &&
                command.rect.width <= 4 &&
                command.rect.height > 0 &&
                command.rect.height <= max(1, size.height)
        }
        let dotCommands = _omniDrawingCommands.filter { $0.kind == .fillOval && $0.rect.width <= 8 && $0.rect.height <= 8 }
        var parts: [String] = []
        if !barCommands.isEmpty {
            let glyphs = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
            let denominator = max(1, size.height)
            let bars = barCommands
                .sorted { lhs, rhs in
                    if lhs.rect.minX == rhs.rect.minX { return lhs.rect.minY < rhs.rect.minY }
                    return lhs.rect.minX < rhs.rect.minX
                }
                .map { command in
                    let ratio = max(0, min(1, command.rect.height / denominator))
                    let index = max(0, min(glyphs.count - 1, Int((ratio * CGFloat(glyphs.count - 1)).rounded())))
                    return glyphs[index]
                }
                .joined()
            parts.append(bars)
        }
        if !dotCommands.isEmpty {
            let dots = dotCommands.map { command in
                command.alpha < 0.5 ? "○" : "●"
            }.joined()
            parts.append(dots)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

public class NSPanel: NSWindow, @unchecked Sendable {}

open class NSViewController: NSObject {
    public var view: NSView

    public override init() {
        self.view = NSView()
        super.init()
    }
}

public final class NSHostingController<Content: View>: NSViewController {
    public let rootView: Content
    public let anyRootView: AnyView

    @MainActor
    public init(rootView: Content) {
        self.rootView = rootView
        self.anyRootView = AnyView(rootView)
        super.init()
    }
}

public final class NSButton: NSView {
    var statusItemChangeHandler: (() -> Void)?
    public var title: String = "" {
        didSet { statusItemChangeHandler?() }
    }
    public var isBordered: Bool = true
    public var target: AnyObject?
    public var action: Selector?
    public var image: NSImage? {
        didSet { statusItemChangeHandler?() }
    }
    public var toolTip: String? {
        didSet { statusItemChangeHandler?() }
    }

    public func performClick(_ sender: Any?) {
        guard let action else { return }
        _ = _omniDispatchSelector(action, to: target, from: sender ?? self)
    }
}

public final class NSStatusItem: NSObject {
    public static let variableLength: CGFloat = -1
    public let length: CGFloat
    public let button: NSButton? = NSButton()

    fileprivate init(length: CGFloat) {
        self.length = length
        super.init()
        button?.statusItemChangeHandler = {
            NSStatusBar.system._notifyStatusItemsChanged()
        }
    }
}

public final class NSStatusBar: NSObject, @unchecked Sendable {
    public static let didChangeStatusItemsNotification = Notification.Name("NSStatusBarDidChangeStatusItemsNotification")
    public static let system = NSStatusBar()
    public var thickness: CGFloat = 22
    public private(set) var statusItems: [NSStatusItem] = []

    public func statusItem(withLength length: CGFloat) -> NSStatusItem {
        let item = NSStatusItem(length: length)
        statusItems.append(item)
        _notifyStatusItemsChanged()
        return item
    }

    public func removeStatusItem(_ item: NSStatusItem) {
        statusItems.removeAll { $0 === item }
        _notifyStatusItemsChanged()
    }

    public var fallbackLabels: [String] {
        statusItems.compactMap { item in
            guard let button = item.button else { return nil }
            let imageLabel = button.image?._omniCompactDrawingLabel()
            let tooltipLines = button.toolTip?
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []
            if !tooltipLines.isEmpty {
                let tooltip = tooltipLines.joined(separator: " · ")
                if let imageLabel, !imageLabel.isEmpty {
                    return "\(imageLabel) · \(tooltip)"
                }
                return tooltip
            }
            let title = button.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return title
            }
            if let imageLabel, !imageLabel.isEmpty {
                return imageLabel
            }
            if button.image != nil {
                return "Status"
            }
            return nil
        }
    }

    @discardableResult
    public func performStatusItem(at index: Int) -> Bool {
        guard statusItems.indices.contains(index), let button = statusItems[index].button else { return false }
        button.performClick(button)
        return true
    }

    fileprivate func _notifyStatusItemsChanged() {
        NotificationCenter.default.post(name: Self.didChangeStatusItemsNotification, object: self)
    }
}

public final class NSPopover: NSObject {
    public enum Behavior: Sendable {
        case transient
    }

    public static let didChangePopoverNotification = Notification.Name("NSPopoverDidChangePopoverNotification")
    private static let activeState = _OmniPopoverState()

    public var contentViewController: NSViewController?
    public var behavior: Behavior = .transient
    public private(set) var isShown: Bool = false
    private var hostingWindow: NSPanel?

    @MainActor
    public static var activeContentView: AnyView? {
        activeState.activePopover?.contentViewController.flatMap { controller in
            (controller as? _OmniAnyHostingControllerContent)?._omniAnyRootView
        }
    }

    public func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge) {
        _ = positioningRect
        _ = positioningView
        _ = preferredEdge
        let window = NSPanel()
        window.contentView = contentViewController?.view
        hostingWindow = window
        isShown = true
        Self.activeState.activePopover = self
        NotificationCenter.default.post(name: Self.didChangePopoverNotification, object: self)
    }

    public func performClose(_ sender: Any?) {
        _ = sender
        hostingWindow?.contentView = nil
        hostingWindow = nil
        isShown = false
        if Self.activeState.activePopover === self {
            Self.activeState.activePopover = nil
        }
        NotificationCenter.default.post(name: Self.didChangePopoverNotification, object: self)
    }
}

private final class _OmniPopoverState: @unchecked Sendable {
    private let lock = NSLock()
    private var _activePopover: NSPopover?

    var activePopover: NSPopover? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _activePopover
        }
        set {
            lock.lock()
            _activePopover = newValue
            lock.unlock()
        }
    }
}

private protocol _OmniAnyHostingControllerContent {
    var _omniAnyRootView: AnyView { get }
}

extension NSHostingController: _OmniAnyHostingControllerContent {
    fileprivate var _omniAnyRootView: AnyView { anyRootView }
}

public enum NSRectEdge: Sendable {
    case minY
    case maxY
    case minX
    case maxX
}

public final class NSBezierPath: NSObject {
    private enum PathKind {
        case empty
        case rect(NSRect)
        case oval(NSRect)
    }

    private let kind: PathKind
    private var currentPoint: NSPoint?
    private var lineSegments: [(start: NSPoint, end: NSPoint)] = []
    public var lineWidth: CGFloat = 1

    public override init() {
        self.kind = .empty
        super.init()
    }

    public init(ovalIn rect: NSRect) {
        self.kind = .oval(rect)
        super.init()
    }

    public init(rect: NSRect) {
        self.kind = .rect(rect)
        super.init()
    }

    public func fill() {
        switch kind {
        case .empty:
            break
        case .rect(let rect):
            _OmniImageDrawingRecorder.shared.fill(rect)
        case .oval(let rect):
            _OmniImageDrawingRecorder.shared.fill(rect, oval: true)
        }
    }

    public func stroke() {
        switch kind {
        case .empty:
            for segment in lineSegments {
                _OmniImageDrawingRecorder.shared.strokeLine(from: segment.start, to: segment.end, lineWidth: lineWidth)
            }
        case .rect(let rect):
            _OmniImageDrawingRecorder.shared.stroke(rect)
        case .oval(let rect):
            _OmniImageDrawingRecorder.shared.stroke(rect, oval: true)
        }
    }
    public func move(to point: NSPoint) {
        guard case .empty = kind else { return }
        currentPoint = point
    }
    public func line(to point: NSPoint) {
        guard case .empty = kind else { return }
        if let currentPoint {
            lineSegments.append((start: currentPoint, end: point))
        }
        currentPoint = point
    }
}

public extension CGRect {
    func fill() {
        _OmniImageDrawingRecorder.shared.fill(self)
    }

    func stroke() {
        _OmniImageDrawingRecorder.shared.stroke(self)
    }
}

public final class NSPasteboard: NSObject, @unchecked Sendable {
    public struct PasteboardType: Hashable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
        public static let string = PasteboardType("public.utf8-plain-text")
        public static let fileURL = PasteboardType("public.file-url")
        public static let URL = PasteboardType("public.url")
    }

    public struct ReadingOptionKey: Hashable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
    }

    public static let general = NSPasteboard(syncSystemClipboard: true)
    private let syncSystemClipboard: Bool
    private let lock = NSLock()
    private var strings: [PasteboardType: String] = [:]
    private var dataValues: [PasteboardType: Data] = [:]
    private var propertyLists: [PasteboardType: Any] = [:]
    private var objectURLs: [URL] = []

    public override convenience init() {
        self.init(syncSystemClipboard: false)
    }

    private init(syncSystemClipboard: Bool) {
        self.syncSystemClipboard = syncSystemClipboard
        super.init()
    }
    public var types: [PasteboardType] {
        lock.lock()
        var current = Array(Set(strings.keys).union(dataValues.keys).union(propertyLists.keys))
        if !objectURLs.isEmpty {
            if objectURLs.contains(where: \.isFileURL), !current.contains(.fileURL) {
                current.append(.fileURL)
            }
            if !current.contains(.URL) {
                current.append(.URL)
            }
        }
        lock.unlock()
        return current
    }

    public func clearContents() {
        lock.lock()
        strings.removeAll()
        dataValues.removeAll()
        propertyLists.removeAll()
        objectURLs.removeAll()
        lock.unlock()
        if syncSystemClipboard {
            _ = _OmniDesktopProcess.write("", to: ["wl-copy"])
                || _OmniDesktopProcess.write("", to: ["xclip", "-selection", "clipboard"])
                || _OmniDesktopProcess.write("", to: ["xsel", "--clipboard", "--input"])
        }
    }

    @discardableResult
    public func setString(_ string: String, forType type: PasteboardType) -> Bool {
        lock.lock()
        strings[type] = string
        dataValues[type] = string.data(using: .utf8)
        if type == .fileURL || type == .URL {
            strings[.string] = string
            dataValues[.string] = dataValues[type]
            if let url = Self.url(fromPasteboardString: string, type: type) {
                objectURLs = [url]
            }
        }
        lock.unlock()
        if syncSystemClipboard && type == .string {
            _ = _OmniDesktopProcess.write(string, to: ["wl-copy"])
                || _OmniDesktopProcess.write(string, to: ["xclip", "-selection", "clipboard"])
                || _OmniDesktopProcess.write(string, to: ["xsel", "--clipboard", "--input"])
        }
        return true
    }

    @discardableResult
    public func setData(_ data: Data, forType type: PasteboardType) -> Bool {
        lock.lock()
        dataValues[type] = data
        if let string = String(data: data, encoding: .utf8) {
            strings[type] = string
        }
        lock.unlock()
        return true
    }

    public func data(forType type: PasteboardType) -> Data? {
        lock.lock()
        if let data = dataValues[type] {
            lock.unlock()
            return data
        }
        let string = strings[type]
        lock.unlock()
        return string?.data(using: .utf8)
    }

    @discardableResult
    public func setPropertyList(_ propertyList: Any, forType type: PasteboardType) -> Bool {
        lock.lock()
        propertyLists[type] = propertyList
        if let string = propertyList as? String {
            strings[type] = string
            dataValues[type] = string.data(using: .utf8)
        } else if let array = propertyList as? [String],
                  let data = try? PropertyListSerialization.data(fromPropertyList: array, format: .xml, options: 0) {
            dataValues[type] = data
        } else if let dictionary = propertyList as? [String: Any],
                  let data = try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0) {
            dataValues[type] = data
        }
        lock.unlock()
        return true
    }

    public func propertyList(forType type: PasteboardType) -> Any? {
        lock.lock()
        if let propertyList = propertyLists[type] {
            lock.unlock()
            return propertyList
        }
        let data = dataValues[type]
        lock.unlock()
        guard let data else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    @discardableResult
    public func declareTypes(_ newTypes: [PasteboardType], owner: Any?) -> Int {
        _ = owner
        clearContents()
        lock.lock()
        for type in newTypes {
            strings[type] = ""
            dataValues[type] = Data()
        }
        let count = newTypes.count
        lock.unlock()
        return count
    }

    public func availableType(from types: [PasteboardType]) -> PasteboardType? {
        let current = Set(self.types)
        return types.first { current.contains($0) }
    }

    public func string(forType type: PasteboardType) -> String? {
        if syncSystemClipboard && type == .string {
            if let value = _OmniDesktopProcess.output(["wl-paste", "--no-newline"]) {
                lock.lock()
                strings[type] = value
                lock.unlock()
                return value
            }
            if let value = _OmniDesktopProcess.output(["xclip", "-selection", "clipboard", "-out"]) {
                lock.lock()
                strings[type] = value
                lock.unlock()
                return value
            }
            if let value = _OmniDesktopProcess.output(["xsel", "--clipboard", "--output"]) {
                lock.lock()
                strings[type] = value
                lock.unlock()
                return value
            }
        }
        lock.lock()
        let value = strings[type]
        lock.unlock()
        return value
    }

    @discardableResult
    public func writeObjects(_ objects: [Any]) -> Bool {
        var wrote = false
        var urls: [URL] = []
        for object in objects {
            switch object {
            case let url as URL:
                urls.append(url)
                wrote = setString(url.absoluteString, forType: url.isFileURL ? .fileURL : .URL) || wrote
            case let url as NSURL:
                let swiftURL = url as URL
                urls.append(swiftURL)
                wrote = setString(swiftURL.absoluteString, forType: swiftURL.isFileURL ? .fileURL : .URL) || wrote
            case let string as String:
                wrote = setString(string, forType: .string) || wrote
            case let string as NSString:
                wrote = setString(string as String, forType: .string) || wrote
            default:
                continue
            }
        }
        if !urls.isEmpty {
            lock.lock()
            objectURLs = urls
            if let first = urls.first {
                strings[first.isFileURL ? .fileURL : .URL] = first.absoluteString
            }
            lock.unlock()
        }
        return wrote
    }

    public func readObjects(forClasses classes: [AnyClass], options: [ReadingOptionKey: Any]? = nil) -> [Any]? {
        _ = options
        var result: [Any] = []
        for klass in classes {
            if klass === NSURL.self {
                lock.lock()
                let urls = objectURLs
                lock.unlock()
                if !urls.isEmpty {
                    result.append(contentsOf: urls.map { $0 as NSURL })
                } else if let value = string(forType: .fileURL) ?? string(forType: .URL) ?? string(forType: .string),
                          let url = Self.url(fromPasteboardString: value, type: nil) {
                    result.append(url as NSURL)
                }
            } else if klass === NSString.self {
                if let value = string(forType: .string) ?? string(forType: .fileURL) ?? string(forType: .URL) {
                    result.append(value as NSString)
                }
            }
        }
        return result.isEmpty ? nil : result
    }

    public func canReadObject(forClasses classes: [AnyClass], options: [ReadingOptionKey: Any]? = nil) -> Bool {
        readObjects(forClasses: classes, options: options)?.isEmpty == false
    }

    private static func url(fromPasteboardString value: String, type: PasteboardType?) -> URL? {
        if value.hasPrefix("file://") || value.hasPrefix("http://") || value.hasPrefix("https://") {
            return URL(string: value)
        }
        if type == .URL, let url = URL(string: value) {
            return url
        }
        return URL(fileURLWithPath: value)
    }
}

public protocol NSTextFieldDelegate: AnyObject {
    func controlTextDidChange(_ obj: Notification)
    func controlTextDidBeginEditing(_ obj: Notification)
    func controlTextDidEndEditing(_ obj: Notification)
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool
}

public extension NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) { _ = obj }
    func controlTextDidBeginEditing(_ obj: Notification) { _ = obj }
    func controlTextDidEndEditing(_ obj: Notification) { _ = obj }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        _ = control
        _ = textView
        _ = commandSelector
        return false
    }
}

public enum NSTextAlignment: Sendable {
    case left
    case center
    case right
    case natural
}

public enum NSLineBreakMode: Sendable {
    case byClipping
}

public final class NSTextFieldCell: NSObject {
    public var alignment: NSTextAlignment = .natural
    public var wraps: Bool = false
    public var isScrollable: Bool = true
}

open class NSTextView: NSView {
    public var alignment: NSTextAlignment = .natural
}

open class NSControl: NSView {
    public enum StateValue: Int, Sendable {
        case mixed = -1
        case off = 0
        case on = 1
    }
}

open class NSTextField: NSControl {
    public static let textDidChangeNotification = Notification.Name("NSTextDidChangeNotification")
    public static let textDidBeginEditingNotification = Notification.Name("NSTextDidBeginEditingNotification")
    public static let textDidEndEditingNotification = Notification.Name("NSTextDidEndEditingNotification")
    public var stringValue: String = ""
    public var placeholderString: String?
    public weak var delegate: NSTextFieldDelegate?
    public var isBordered: Bool = true
    public var drawsBackground: Bool = true
    public var isEditable: Bool = true
    public var isSelectable: Bool = true
    public var target: AnyObject?
    public var action: Selector?
    public var alignment: NSTextAlignment = .natural
    public var cell: NSTextFieldCell? = NSTextFieldCell()
    public enum BezelStyle: Sendable { case roundedBezel }
    public var bezelStyle: BezelStyle = .roundedBezel
    public var isBezeled: Bool = true
    public var lineBreakMode: NSLineBreakMode = .byClipping
    public var font: NSFont?
    private var editor: NSTextView?

    public convenience init(string: String) {
        self.init()
        self.stringValue = string
    }

    open override func becomeFirstResponder() -> Bool {
        if editor == nil {
            let textView = NSTextView()
            textView.alignment = alignment
            editor = textView
        }
        delegate?.controlTextDidBeginEditing(Notification(name: Self.textDidBeginEditingNotification, object: self))
        return true
    }

    open override func resignFirstResponder() -> Bool {
        delegate?.controlTextDidEndEditing(Notification(name: Self.textDidEndEditingNotification, object: self))
        editor = nil
        return true
    }

    open func currentEditor() -> NSTextView? { editor }
}

public final class NSFontManager: NSObject, @unchecked Sendable {
    public static let shared = NSFontManager()
    public lazy var availableFontFamilies: [String] = Self.discoverAvailableFontFamilies()

    private static func discoverAvailableFontFamilies() -> [String] {
        var families: [String] = []
        var seen = Set<String>()

        func append(_ family: String) {
            let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return }
            families.append(trimmed)
        }

        for family in ["System", "Monospace"] {
            append(family)
        }

        if let output = _OmniDesktopProcess.output(["fc-list", ":", "family"]) {
            for line in output.split(separator: "\n") {
                for candidate in line.split(separator: ",") {
                    append(String(candidate))
                }
            }
        }

        let fontDirectories = [
            "/usr/share/fonts",
            "/usr/local/share/fonts",
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/share/fonts"),
            (NSHomeDirectory() as NSString).appendingPathComponent(".fonts"),
        ]
        for directory in fontDirectories {
            guard let enumerator = FileManager.default.enumerator(atPath: directory) else { continue }
            for case let entry as String in enumerator {
                let url = URL(fileURLWithPath: entry)
                let ext = url.pathExtension.lowercased()
                guard ["ttf", "otf", "ttc", "otc"].contains(ext) else { continue }
                let stem = url.deletingPathExtension().lastPathComponent
                append(stem.replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression))
            }
        }

        return families.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

open class NSScrollView: NSView {
    public enum ScrollerStyle: Sendable { case overlay }
    public enum ScrollElasticity: Sendable { case none }

    public var hasHorizontalScroller: Bool = false
    public var hasVerticalScroller: Bool = false
    public var scrollerStyle: ScrollerStyle = .overlay
    public var autohidesScrollers: Bool = true
    public var drawsBackground: Bool = false
    public var horizontalScrollElasticity: ScrollElasticity = .none
    public var verticalScrollElasticity: ScrollElasticity = .none
    public let contentView = NSClipView()
    public var documentView: NSView? {
        willSet {
            if documentView !== newValue {
                documentView?.removeFromSuperview()
            }
        }
        didSet {
            if let documentView {
                contentView.addSubview(documentView)
            }
        }
    }

    public override init() {
        super.init()
        addSubview(contentView)
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(contentView)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        addSubview(contentView)
    }

    open override func layout() {
        super.layout()
        contentView.frame = bounds
        contentView.layoutSubtreeIfNeeded()
    }

    open override func scrollWheel(with event: NSEvent) {
        documentView?.scrollWheel(with: event)
    }
}

open class NSClipView: NSView {
    public var documentView: NSView? { subviews.first }
    public var documentVisibleRect: NSRect { bounds }

    public func scroll(to newOrigin: NSPoint) {
        frame.origin = newOrigin
    }
}

public final class NSEvent: NSObject {
    public enum EventType: Hashable, Sendable {
        case leftMouseDown
        case leftMouseUp
        case rightMouseDown
        case rightMouseUp
        case mouseMoved
        case flagsChanged
        case keyDown
        case scrollWheel
    }

    public struct ModifierFlags: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = ModifierFlags(rawValue: 1 << 0)
        public static let control = ModifierFlags(rawValue: 1 << 1)
        public static let option = ModifierFlags(rawValue: 1 << 2)
        public static let shift = ModifierFlags(rawValue: 1 << 3)
    }

    public var scrollingDeltaX: CGFloat = 0
    public var scrollingDeltaY: CGFloat = 0
    public var modifierFlags: ModifierFlags = []
    public var charactersIgnoringModifiers: String?
    public var locationInWindow: NSPoint = .zero
    public var type: EventType = .mouseMoved
    public var clickCount: Int = 0

    public static func _omniMacCompatibleModifierFlags(rawValue: Int, eventType: EventType) -> ModifierFlags {
        var flags = ModifierFlags(rawValue: rawValue)
        if eventType == .keyDown,
           flags.contains(.control),
           !flags.contains(.command) {
            flags.remove(.control)
            flags.insert(.command)
        }
        return flags
    }

    public struct EventTypeMask: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let keyDown = EventTypeMask(rawValue: 1 << 0)
        public static let leftMouseDown = EventTypeMask(rawValue: 1 << 1)
        public static let flagsChanged = EventTypeMask(rawValue: 1 << 2)
        public static let mouseMoved = EventTypeMask(rawValue: 1 << 3)
        public static let rightMouseDown = EventTypeMask(rawValue: 1 << 4)
        public static let leftMouseUp = EventTypeMask(rawValue: 1 << 5)
        public static let rightMouseUp = EventTypeMask(rawValue: 1 << 6)
        public static let scrollWheel = EventTypeMask(rawValue: 1 << 7)
    }

    public static func addLocalMonitorForEvents(matching mask: EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        _OmniEventMonitorStore.shared.addLocal(mask: mask, handler: handler)
    }

    public static func addGlobalMonitorForEvents(matching mask: EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? {
        _OmniEventMonitorStore.shared.addGlobal(mask: mask, handler: handler)
    }

    public static func removeMonitor(_ monitor: Any) {
        guard let token = monitor as? _OmniEventMonitorToken else { return }
        _OmniEventMonitorStore.shared.remove(token)
    }

    public static func _deliverLocalMonitors(_ event: NSEvent) -> NSEvent? {
        _OmniEventMonitorStore.shared.deliver(event)
    }

    fileprivate var _mask: EventTypeMask {
        switch type {
        case .keyDown: return .keyDown
        case .leftMouseDown: return .leftMouseDown
        case .leftMouseUp: return .leftMouseUp
        case .rightMouseDown: return .rightMouseDown
        case .rightMouseUp: return .rightMouseUp
        case .mouseMoved: return .mouseMoved
        case .flagsChanged: return .flagsChanged
        case .scrollWheel: return .scrollWheel
        }
    }
}

private final class _OmniEventMonitorToken: @unchecked Sendable {
    let id = UUID()
}

private final class _OmniEventMonitorStore: @unchecked Sendable {
    static let shared = _OmniEventMonitorStore()

    private struct LocalEntry {
        let token: _OmniEventMonitorToken
        let mask: NSEvent.EventTypeMask
        let handler: (NSEvent) -> NSEvent?
    }

    private struct GlobalEntry {
        let token: _OmniEventMonitorToken
        let mask: NSEvent.EventTypeMask
        let handler: (NSEvent) -> Void
    }

    private let lock = NSLock()
    private var localEntries: [LocalEntry] = []
    private var globalEntries: [GlobalEntry] = []

    func addLocal(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> _OmniEventMonitorToken {
        let token = _OmniEventMonitorToken()
        lock.lock()
        localEntries.append(LocalEntry(token: token, mask: mask, handler: handler))
        lock.unlock()
        return token
    }

    func addGlobal(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) -> _OmniEventMonitorToken {
        let token = _OmniEventMonitorToken()
        lock.lock()
        globalEntries.append(GlobalEntry(token: token, mask: mask, handler: handler))
        lock.unlock()
        return token
    }

    func remove(_ token: _OmniEventMonitorToken) {
        lock.lock()
        localEntries.removeAll { $0.token === token }
        globalEntries.removeAll { $0.token === token }
        lock.unlock()
    }

    func deliver(_ event: NSEvent) -> NSEvent? {
        lock.lock()
        let localSnapshot = localEntries
        let globalSnapshot = globalEntries
        lock.unlock()

        var current: NSEvent? = event
        for entry in localSnapshot where entry.mask.contains(event._mask) {
            guard let event = current else { return nil }
            current = entry.handler(event)
        }
        if let delivered = current {
            for entry in globalSnapshot where entry.mask.contains(delivered._mask) {
                entry.handler(delivered)
            }
        }
        return current
    }
}

public struct NSDragOperation: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let move = NSDragOperation(rawValue: 1 << 0)
    public static let copy = NSDragOperation(rawValue: 1 << 1)
    public static let none: NSDragOperation = []
}

public protocol NSDraggingInfo {
    var draggingPasteboard: NSPasteboard { get }
    var draggingLocation: NSPoint { get }
}

public final class NSDraggingInfoSnapshot: NSObject, NSDraggingInfo {
    public let draggingPasteboard: NSPasteboard
    public let draggingLocation: NSPoint

    public init(draggingPasteboard: NSPasteboard, draggingLocation: NSPoint) {
        self.draggingPasteboard = draggingPasteboard
        self.draggingLocation = draggingLocation
        super.init()
    }
}

public final class NSAlert: NSObject, @unchecked Sendable {
    public enum Style: Sendable {
        case warning
        case informational
        case critical
    }

    public var messageText: String = ""
    public var informativeText: String = ""
    public var alertStyle: Style = .warning
    public var icon: NSImage?
    public var showsSuppressionButton: Bool = false
    public private(set) var buttons: [NSButton] = []
    public let suppressionButton: NSButton = NSButton()

    @discardableResult
    public func addButton(withTitle title: String) -> NSButton {
        let button = NSButton()
        button.title = title
        buttons.append(button)
        return button
    }

    public func runModal() -> NSApplication.ModalResponse {
        let response = ProcessInfo.processInfo.environment["OMNIKIT_ALERT_RESPONSE"]
            .flatMap(Int.init)
            .map(NSApplication.ModalResponse.init(rawValue:))
        if let response {
            return response
        }
        return _runDesktopAlert() ?? .OK
    }

    private func _runDesktopAlert() -> NSApplication.ModalResponse? {
        let title = messageText.isEmpty ? "Alert" : messageText
        let text = informativeText.isEmpty ? title : informativeText
        if buttons.count >= 2 {
            if let status = _OmniDesktopProcess.run([
                "zenity",
                "--question",
                "--title=\(title)",
                "--text=\(text)",
                "--ok-label=\(buttons[0].title)",
                "--cancel-label=\(buttons[1].title)",
            ]) {
                return status == 0 ? .alertFirstButtonReturn : .alertSecondButtonReturn
            }
            if let status = _OmniDesktopProcess.run([
                "kdialog",
                "--title", title,
                "--yes-label", buttons[0].title,
                "--no-label", buttons[1].title,
                "--yesno", text,
            ]) {
                return status == 0 ? .alertFirstButtonReturn : .alertSecondButtonReturn
            }
        }

        let zenityKind: String
        let kdialogKind: String
        switch alertStyle {
        case .critical:
            zenityKind = "--error"
            kdialogKind = "--error"
        case .informational:
            zenityKind = "--info"
            kdialogKind = "--msgbox"
        case .warning:
            zenityKind = "--warning"
            kdialogKind = "--sorry"
        }
        if _OmniDesktopProcess.run(["zenity", zenityKind, "--title=\(title)", "--text=\(text)"]) != nil {
            return .OK
        }
        if _OmniDesktopProcess.run(["kdialog", "--title", title, kdialogKind, text]) != nil {
            return .OK
        }
        return nil
    }
}

public final class NSAppleScript: NSObject, @unchecked Sendable {
    public let source: String

    public init?(source: String) {
        self.source = source
        super.init()
    }

    public func executeAndReturnError(_ errorInfo: UnsafeMutablePointer<NSDictionary?>?) {
        guard let command = Self.shellCommand(from: source) else {
            errorInfo?.pointee = ["NSAppleScriptErrorMessage": "Unsupported AppleScript source"]
            return
        }
        let requiresAdministrator = source.localizedCaseInsensitiveContains("with administrator privileges")
        let status: Int32?
        if requiresAdministrator, Glibc.geteuid() != 0 {
            status = _OmniDesktopProcess.run(["pkexec", "/bin/sh", "-c", command])
                ?? _OmniDesktopProcess.run(["/bin/sh", "-c", command])
        } else {
            status = _OmniDesktopProcess.run(["/bin/sh", "-c", command])
        }
        if status == 0 {
            errorInfo?.pointee = nil
        } else {
            errorInfo?.pointee = [
                "NSAppleScriptErrorMessage": "Shell command failed",
                "NSAppleScriptErrorNumber": status ?? -1,
            ]
        }
    }

    private static func shellCommand(from source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.localizedCaseInsensitiveContains("do shell script"),
              let firstQuote = trimmed.firstIndex(of: "\"") else {
            return nil
        }
        var result = ""
        var index = trimmed.index(after: firstQuote)
        var escaped = false
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if escaped {
                switch character {
                case "\"", "\\":
                    result.append(character)
                case "n":
                    result.append("\n")
                case "r":
                    result.append("\r")
                case "t":
                    result.append("\t")
                default:
                    result.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return result
            } else {
                result.append(character)
            }
            index = trimmed.index(after: index)
        }
        return nil
    }
}

public protocol NSValidatedUserInterfaceItem {
    var action: Selector? { get }
}

open class NSMenuItem: NSObject, NSValidatedUserInterfaceItem {
    public var title: String
    public var action: Selector?
    public var keyEquivalent: String
    public weak var target: AnyObject?
    public weak var menu: NSMenu?
    public var keyEquivalentModifierMask: NSEvent.ModifierFlags = []
    public var state: NSControl.StateValue = .off
    public var isHidden: Bool = false
    public var representedObject: Any?
    public var submenu: NSMenu? {
        didSet {
            oldValue?.supermenu = nil
            submenu?.supermenu = menu
        }
    }
    public var image: NSImage?
    public var toolTip: String?
    public var tag: Int = 0
    private var explicitIsEnabled: Bool?
    private var separatorItem: Bool = false

    public override init() {
        self.title = ""
        self.keyEquivalent = ""
        super.init()
    }

    public init(title: String, action: Selector?, keyEquivalent: String) {
        self.title = title
        self.action = action
        self.keyEquivalent = keyEquivalent
        super.init()
    }

    public static func separator() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.separatorItem = true
        return item
    }

    public var isSeparatorItem: Bool {
        separatorItem
    }

    public var isEnabled: Bool {
        get { explicitIsEnabled ?? validate() }
        set { explicitIsEnabled = newValue }
    }

    public func validate() -> Bool {
        guard !isHidden, !isSeparatorItem else { return false }
        guard let action else { return false }
        if let validator = target as? NSView {
            return validator.validateUserInterfaceItem(self)
        }
        if let window = target as? NSWindow, let responder = window.firstResponder {
            return responder.validateUserInterfaceItem(self)
        }
        if target == nil, let responder = NSApp.keyWindow?.firstResponder {
            return responder.validateUserInterfaceItem(self)
        }
        return _omniCanDispatchSelector(action, to: target)
    }

    @discardableResult
    public func performAction(_ sender: Any? = nil) -> Bool {
        guard isEnabled, !isHidden, !isSeparatorItem, let action else { return false }
        return _omniDispatchSelector(action, to: target, from: sender ?? self)
    }
}

open class NSMenu: NSObject {
    public static let didChangeActiveMenuNotification = Notification.Name("NSMenuDidChangeActiveMenuNotification")
    private static let activeState = _OmniMenuState()

    public var title: String
    public private(set) var items: [NSMenuItem] = []
    public weak var supermenu: NSMenu?

    public init(title: String) {
        self.title = title
        super.init()
    }

    public override init() {
        self.title = ""
        super.init()
    }

    public var numberOfItems: Int {
        items.count
    }

    public func addItem(_ item: NSMenuItem) {
        item.menu = self
        item.submenu?.supermenu = self
        items.append(item)
    }

    public func insertItem(_ item: NSMenuItem, at index: Int) {
        item.menu = self
        item.submenu?.supermenu = self
        items.insert(item, at: max(0, min(index, items.count)))
    }

    public func removeItem(_ item: NSMenuItem) {
        guard let index = index(of: item) else { return }
        removeItem(at: index)
    }

    public func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items.remove(at: index)
        item.menu = nil
        item.submenu?.supermenu = nil
    }

    public func removeAllItems() {
        for item in items {
            item.menu = nil
            item.submenu?.supermenu = nil
        }
        items.removeAll()
    }

    public func item(at index: Int) -> NSMenuItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    public func index(of item: NSMenuItem) -> Int? {
        items.firstIndex { $0 === item }
    }

    public static var activeMenu: NSMenu? {
        activeState.activeMenu
    }

    @MainActor
    public static var activeContentView: AnyView? {
        guard let menu = activeMenu else { return nil }
        return AnyView(_OmniMenuPresentationView(menu: menu))
    }

    public func popUp(positioning item: NSMenuItem?, at location: NSPoint, in view: NSView?) -> Bool {
        _ = item
        _ = location
        _ = view
        guard items.contains(where: { !$0.isHidden && !$0.isSeparatorItem }) else { return false }
        Self.activeState.activeMenu = self
        NotificationCenter.default.post(name: Self.didChangeActiveMenuNotification, object: self)
        return true
    }

    public static func dismissActiveMenu() {
        activeState.activeMenu = nil
        NotificationCenter.default.post(name: Self.didChangeActiveMenuNotification, object: nil)
    }

    @discardableResult
    public func performActionForItem(at index: Int) -> Bool {
        guard items.indices.contains(index) else { return false }
        let item = items[index]
        guard !item.isHidden, !item.isSeparatorItem else { return false }
        return item.performAction(self)
    }
}

private final class _OmniMenuState: @unchecked Sendable {
    private let lock = NSLock()
    private weak var _activeMenu: NSMenu?

    var activeMenu: NSMenu? {
        get {
            lock.lock()
            let menu = _activeMenu
            lock.unlock()
            return menu
        }
        set {
            lock.lock()
            _activeMenu = newValue
            lock.unlock()
        }
    }
}

private struct _OmniMenuPresentationView: View {
    let menu: NSMenu

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(menu.items.enumerated()), id: \.offset) { _, item in
                if item.isSeparatorItem {
                    Divider()
                } else if !item.isHidden {
                    Button(item.title.isEmpty ? "Item" : item.title) {
                        _ = item.performAction(menu)
                        NSMenu.dismissActiveMenu()
                    }
                    .disabled(!item.isEnabled)
                }
            }
        }
        .padding(8)
    }
}

public func _omniPresentContextMenu(for event: NSEvent) -> Bool {
    guard event.type == .rightMouseDown || event.type == .rightMouseUp else { return false }
    guard let window = NSApp.keyWindow else { return false }

    var candidates: [NSView] = []
    if let contentView = window.contentView {
        let localPoint = contentView.convert(event.locationInWindow, from: nil)
        if let hitView = contentView.hitTest(localPoint) {
            var current: NSView? = hitView
            while let view = current {
                candidates.append(view)
                current = view.superview
            }
        } else {
            candidates.append(contentView)
        }
    }
    if let firstResponder = window.firstResponder, !candidates.contains(where: { $0 === firstResponder }) {
        candidates.append(firstResponder)
    }

    for view in candidates {
        if let menu = view.menu(for: event) {
            return menu.popUp(positioning: nil, at: event.locationInWindow, in: view)
        }
    }
    return false
}

@discardableResult
public func _omniDispatchScrollWheel(for event: NSEvent) -> Bool {
    guard event.type == .scrollWheel, let window = NSApp.keyWindow else { return false }
    var candidates: [NSView] = []
    if let contentView = window.contentView {
        let localPoint = contentView.convert(event.locationInWindow, from: nil)
        if let hitView = contentView.hitTest(localPoint) {
            var current: NSView? = hitView
            while let view = current {
                candidates.append(view)
                current = view.superview
            }
        } else {
            candidates.append(contentView)
        }
    }
    if let firstResponder = window.firstResponder, !candidates.contains(where: { $0 === firstResponder }) {
        candidates.append(firstResponder)
    }
    guard !candidates.isEmpty else { return false }
    for view in candidates {
        view.scrollWheel(with: event)
    }
    return true
}

private func _omniCanDispatchSelector(_ selector: Selector, to target: AnyObject?) -> Bool {
    if _OmniSelectorActionRegistry.shared.canPerform(target: target, selector: selector) {
        return true
    }
    switch selector.name {
    case "copy:", "paste:", "selectAll:":
        return target is NSView || target is NSWindow || (target == nil && NSApp.keyWindow?.firstResponder != nil)
    default:
        return false
    }
}

@discardableResult
private func _omniDispatchSelector(_ selector: Selector, to target: AnyObject?, from sender: Any?) -> Bool {
    if _OmniSelectorActionRegistry.shared.perform(target: target, selector: selector, sender: sender) {
        return true
    }

    let view: NSView?
    if let targetView = target as? NSView {
        view = targetView
    } else if let window = target as? NSWindow {
        view = window.firstResponder
    } else if target == nil {
        view = NSApp.keyWindow?.firstResponder
    } else {
        view = nil
    }

    guard let view else { return false }
    switch selector.name {
    case "copy:":
        view.copy(sender)
        return true
    case "paste:":
        view.paste(sender)
        return true
    case "selectAll:":
        view.selectAll(sender)
        return true
    default:
        return false
    }
}

open class NSResponder: NSObject {
    public static func insertNewline(_ sender: Any?) {
        _ = sender
    }
}

public final class DistributedNotificationCenter: NSObject {
    public static func `default`() -> DistributedNotificationCenter {
        DistributedNotificationCenter()
    }

    public func publisher(for name: Notification.Name, object: AnyObject? = nil) -> _OmniNotificationPublisher {
        _OmniDistributedNotificationBus.shared.subscribe(to: name)
        return _OmniNotificationPublisher(center: .default, name: name, object: object)
    }

    public func postNotificationName(_ name: Notification.Name, object: String?, userInfo: [AnyHashable: Any]?, deliverImmediately: Bool) {
        NotificationCenter.default.post(name: name, object: object, userInfo: userInfo)
        _OmniDistributedNotificationBus.shared.post(name: name, object: object, userInfo: userInfo)
        if deliverImmediately {
            _OmniDistributedNotificationBus.shared.drainOnce()
        }
    }
}

private final class _OmniDistributedNotificationBus: @unchecked Sendable {
    static let shared = _OmniDistributedNotificationBus()

    private let lock = NSLock()
    private var subscribedNames = Set<String>()
    private var seenFiles = Set<String>()
    private var started = false

    func subscribe(to name: Notification.Name) {
        lock.lock()
        subscribedNames.insert(name.rawValue)
        let shouldStart = !started
        if shouldStart {
            started = true
        }
        lock.unlock()

        if shouldStart {
            trace("subscribe name=\(name.rawValue) dir=\(directoryURL.path)")
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.run()
            }
        } else {
            trace("subscribe name=\(name.rawValue) dir=\(directoryURL.path)")
        }
    }

    func post(name: Notification.Name, object: String?, userInfo: [AnyHashable: Any]?) {
        guard ensureDirectoryExists() else { return }
        let payload: [String: Any] = [
            "name": name.rawValue,
            "object": object ?? NSNull(),
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "created": Date().timeIntervalSince1970,
            "userInfo": serializableUserInfo(userInfo),
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }
        let id = UUID().uuidString
        let finalURL = directoryURL.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-\(ProcessInfo.processInfo.processIdentifier)-\(id).json")
        let tempURL = directoryURL.appendingPathComponent(".\(id).tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            try FileManager.default.moveItem(at: tempURL, to: finalURL)
            trace("post name=\(name.rawValue) file=\(finalURL.lastPathComponent)")
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            trace("post-failed name=\(name.rawValue) error=\(error)")
        }
    }

    func drainOnce() {
        scan()
    }

    private func run() {
        while true {
            scan()
            usleep(200_000)
        }
    }

    private func scan() {
        guard ensureDirectoryExists(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            trace("scan-failed dir=\(directoryURL.path)")
            return
        }

        let now = Date()
        for file in files where file.pathExtension == "json" {
            let path = file.path
            lock.lock()
            let alreadySeen = seenFiles.contains(path)
            if !alreadySeen {
                seenFiles.insert(path)
            }
            lock.unlock()
            guard !alreadySeen else { continue }
            deliver(file: file)
            cleanupIfStale(file: file, now: now)
        }
    }

    private func deliver(file: URL) {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawName = object["name"] as? String else {
            return
        }
        lock.lock()
        let shouldDeliver = subscribedNames.contains(rawName)
        lock.unlock()
        guard shouldDeliver else {
            trace("skip-unsubscribed name=\(rawName) file=\(file.lastPathComponent)")
            return
        }
        if let pid = object["pid"] as? Int,
           pid == Int(ProcessInfo.processInfo.processIdentifier) {
            trace("skip-own-pid name=\(rawName) file=\(file.lastPathComponent)")
            return
        }
        let userInfo = object["userInfo"] as? [String: Any]
        trace("deliver name=\(rawName) file=\(file.lastPathComponent)")
        NotificationCenter.default.post(
            name: Notification.Name(rawName),
            object: object["object"] as? String,
            userInfo: userInfo
        )
    }

    private func cleanupIfStale(file: URL, now: Date) {
        guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
              let modified = values.contentModificationDate,
              now.timeIntervalSince(modified) > 120 else {
            return
        }
        try? FileManager.default.removeItem(at: file)
    }

    private func ensureDirectoryExists() -> Bool {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    private var directoryURL: URL {
        if let raw = getenv("OMNIKIT_DISTRIBUTED_NOTIFICATION_DIR"),
           let value = String(validatingCString: raw),
           !value.isEmpty {
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("omnikit-distributed-notifications", isDirectory: true)
    }

    private var traceEnabled: Bool {
        guard let raw = getenv("OMNIKIT_DISTRIBUTED_NOTIFICATION_TRACE"),
              let value = String(validatingCString: raw) else {
            return false
        }
        return !value.isEmpty && value != "0" && value.lowercased() != "false"
    }

    private func trace(_ message: String) {
        guard traceEnabled else { return }
        let line = "[OmniKit DNC pid=\(ProcessInfo.processInfo.processIdentifier)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private func serializableUserInfo(_ userInfo: [AnyHashable: Any]?) -> [String: Any] {
        guard let userInfo else { return [:] }
        var result: [String: Any] = [:]
        for (key, value) in userInfo {
            let keyString = String(describing: key.base)
            switch value {
            case let value as String:
                result[keyString] = value
            case let value as NSNumber:
                result[keyString] = value
            case let value as Bool:
                result[keyString] = value
            case let value as Int:
                result[keyString] = value
            case let value as Double:
                result[keyString] = value
            case let value as UUID:
                result[keyString] = value.uuidString
            case let value as URL:
                result[keyString] = value.absoluteString
            default:
                result[keyString] = String(describing: value)
            }
        }
        return result
    }
}

open class NSSavePanel: NSObject {
    public var allowedContentTypes: [UTType] = []
    public var allowedFileTypes: [String]? {
        get {
            let extensions = _allowedFilenameExtensions
            return extensions.isEmpty ? nil : extensions
        }
        set {
            allowedContentTypes = newValue?.compactMap { UTType(filenameExtension: $0) } ?? []
        }
    }
    public var nameFieldStringValue: String = ""
    public var url: URL?
    public var title: String = ""
    public var message: String = ""
    public var prompt: String = ""
    public var directoryURL: URL?
    public var canCreateDirectories: Bool = false
    public var canChooseDirectories: Bool = false
    public var canChooseFiles: Bool = true
    public var allowsMultipleSelection: Bool = false
    public var urls: [URL] = []
    public var isExtensionHidden: Bool = false
    public var canSelectHiddenExtension: Bool = true
    public var showsHiddenFiles: Bool = false
    public var treatsFilePackagesAsDirectories: Bool = false
    public var resolvesAliases: Bool = true

    open func begin(completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
        completionHandler(runModal())
    }

    open func beginSheetModal(for window: NSWindow, completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
        _ = window
        begin(completionHandler: completionHandler)
    }

    open func runModal() -> NSApplication.ModalResponse {
        if let selected = _runPortalLikeChooser(save: true) {
            let resolved = _urlByAppendingDefaultExtensionIfNeeded(selected)
            url = resolved
            urls = [resolved]
            return .OK
        }
        return .cancel
    }

    fileprivate func _runPortalLikeChooser(save: Bool) -> URL? {
        if let override = ProcessInfo.processInfo.environment["OMNIKIT_FILE_PANEL_SELECTION"],
           !override.isEmpty {
            let selectedURLs = override
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { String($0) }
                .map { value -> URL in
                    let expanded = (value as NSString).expandingTildeInPath
                    if expanded.hasPrefix("file://"), let url = URL(string: expanded) {
                        return url
                    }
                    return URL(fileURLWithPath: expanded)
                }
            urls = allowsMultipleSelection ? selectedURLs : Array(selectedURLs.prefix(1))
            return urls.first
        }

        if let selected = _runGTKFileChooser(save: save) {
            return selected
        }

        var args = ["--file-selection"]
        if save {
            args.append("--save")
            if !nameFieldStringValue.isEmpty {
                args.append("--filename=\((directoryURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).appendingPathComponent(nameFieldStringValue).path)")
            }
        } else if canChooseDirectories && !canChooseFiles {
            args.append("--directory")
            if allowsMultipleSelection {
                args.append("--multiple")
                args.append("--separator=\n")
            }
        } else if allowsMultipleSelection {
            args.append("--multiple")
            args.append("--separator=\n")
        }
        if !title.isEmpty {
            args.append("--title=\(title)")
        }
        if !prompt.isEmpty {
            args.append("--ok-label=\(prompt)")
        }
        for ext in _allowedFilenameExtensions {
            args.append("--file-filter=*.\(ext)")
        }
        if let directoryURL, !save {
            args.append("--filename=\(directoryURL.path)/")
        }

        if let selection = _OmniDesktopProcess.output(["zenity"] + args), !selection.isEmpty {
            let paths = selection.split(separator: "\n").map(String.init)
            let selectedURLs = paths.map { URL(fileURLWithPath: $0) }
            urls = selectedURLs
            return selectedURLs.first
        }

        var kdialogArgs = ["kdialog"] + (save ? ["--getsavefilename"] : ["--getopenfilename"]) + [directoryURL?.path ?? FileManager.default.currentDirectoryPath]
        let kdialogFilter = _allowedFilenameExtensions.map { "*.\($0)" }.joined(separator: " ")
        if !kdialogFilter.isEmpty {
            kdialogArgs.append(kdialogFilter)
        }
        if let selection = _OmniDesktopProcess.output(kdialogArgs),
           !selection.isEmpty {
            let selected = URL(fileURLWithPath: selection)
            urls = [selected]
            return selected
        }

        return nil
    }

    private func _runGTKFileChooser(save: Bool) -> URL? {
        let mode: String
        if save {
            mode = "save"
        } else if canChooseDirectories && !canChooseFiles {
            mode = "folder"
        } else {
            mode = "open"
        }
        let chooserTitle: String
        if !title.isEmpty {
            chooserTitle = title
        } else if save {
            chooserTitle = "Save"
        } else {
            chooserTitle = "Open"
        }
        let directory = directoryURL?.path ?? ""
        let name = nameFieldStringValue
        let multiple = allowsMultipleSelection ? "1" : "0"
        let createDirectories = canCreateDirectories ? "1" : "0"
        let showHidden = showsHiddenFiles ? "1" : "0"
        let extensions = _allowedFilenameExtensions.joined(separator: ",")
        let script = #"""
import sys
try:
    import gi
    gi.require_version("Gtk", "4.0")
    from gi.repository import Gio, GLib, Gtk
except Exception:
    sys.exit(2)

mode, title, message, prompt, directory, name, multiple, create_dirs, show_hidden, extensions = sys.argv[1:11]
result = []
app = Gtk.Application(application_id=None, flags=Gio.ApplicationFlags.FLAGS_NONE)

def path_for_file(file):
    path = file.get_path()
    return path if path is not None else file.get_uri()

def on_activate(application):
    window = Gtk.ApplicationWindow(application=application)
    window.set_default_size(1, 1)
    action = Gtk.FileChooserAction.SAVE if mode == "save" else Gtk.FileChooserAction.SELECT_FOLDER if mode == "folder" else Gtk.FileChooserAction.OPEN
    accept = prompt if prompt else "_Save" if mode == "save" else "_Open"
    dialog = Gtk.FileChooserNative.new(title, window, action, accept, "_Cancel")
    if message:
        dialog.set_title(title + " - " + message)
    if directory:
        try:
            dialog.set_current_folder(Gio.File.new_for_path(directory))
        except Exception:
            pass
    if mode == "save" and name:
        dialog.set_current_name(name)
    if create_dirs == "1":
        dialog.set_create_folders(True)
    if show_hidden == "1":
        dialog.set_show_hidden(True)
    if multiple == "1" and mode != "save":
        dialog.set_select_multiple(True)
    if extensions:
        filter = Gtk.FileFilter()
        filter.set_name("Allowed files")
        for ext in extensions.split(","):
            if ext:
                filter.add_pattern("*." + ext)
        dialog.add_filter(filter)

    def on_response(dialog, response):
        if response == Gtk.ResponseType.ACCEPT:
            if multiple == "1" and mode != "save":
                files = dialog.get_files()
                for index in range(files.get_n_items()):
                    item = files.get_item(index)
                    if item is not None:
                        result.append(path_for_file(item))
            else:
                file = dialog.get_file()
                if file is not None:
                    result.append(path_for_file(file))
        dialog.destroy()
        application.quit()

    dialog.connect("response", on_response)
    dialog.show()

app.connect("activate", on_activate)
status = app.run([])
if result:
    print("\n".join(result))
sys.exit(status)
"""#
        guard let output = _OmniDesktopProcess.output(["python3", "-c", script, mode, chooserTitle, message, prompt, directory, name, multiple, createDirectories, showHidden, extensions]),
              !output.isEmpty else {
            return nil
        }
        let selectedURLs = output
            .split(separator: "\n")
            .map(String.init)
            .map { value -> URL in
                if value.hasPrefix("file://"), let url = URL(string: value) {
                    return url
                }
                return URL(fileURLWithPath: value)
            }
        guard let selected = selectedURLs.first else { return nil }
        urls = selectedURLs
        return selected
    }

    fileprivate var _allowedFilenameExtensions: [String] {
        var seen = Set<String>()
        return allowedContentTypes.compactMap { type in
            type.preferredFilenameExtension?.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        }.filter { ext in
            !ext.isEmpty && seen.insert(ext).inserted
        }
    }

    fileprivate func _urlByAppendingDefaultExtensionIfNeeded(_ selected: URL) -> URL {
        guard selected.isFileURL,
              !isExtensionHidden,
              selected.pathExtension.isEmpty,
              let ext = _allowedFilenameExtensions.first else {
            return selected
        }
        return selected.deletingLastPathComponent()
            .appendingPathComponent(selected.lastPathComponent + ".\(ext)")
    }
}

open class NSOpenPanel: NSSavePanel {
    open override func runModal() -> NSApplication.ModalResponse {
        if let selected = _runPortalLikeChooser(save: false) {
            url = selected
            if urls.isEmpty {
                urls = [selected]
            }
            return .OK
        }
        return .cancel
    }
}

public extension NSApplication {
    struct ModalResponse: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let OK = ModalResponse(rawValue: 1_000)
        public static let cancel = ModalResponse(rawValue: 1_001)
        public static let stop = ModalResponse(rawValue: 1_000)
        public static let abort = ModalResponse(rawValue: 1_001)
        public static let `continue` = ModalResponse(rawValue: 1_002)
        public static let alertFirstButtonReturn = ModalResponse(rawValue: 1_000)
        public static let alertSecondButtonReturn = ModalResponse(rawValue: 1_001)
        public static let alertThirdButtonReturn = ModalResponse(rawValue: 1_002)
    }
}

public struct NSWindowStyleMask: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let fullScreen = NSWindowStyleMask(rawValue: 1 << 0)
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
        self.init(
            red: nsColor.redComponent,
            green: nsColor.greenComponent,
            blue: nsColor.blueComponent,
            opacity: nsColor.alphaComponent
        )
    }

    init(nsColor: NSColor) {
        self.init(nsColor)
    }
}

public final class NSScreen: NSObject, @unchecked Sendable {
    public static let main: NSScreen? = NSScreen()
    public var frame: NSRect = NSRect(x: 0, y: 0, width: 1200, height: 800)
}

public final class NSColorPanel: NSWindow, @unchecked Sendable {
    public static let shared = NSColorPanel()
    public static let colorDidChangeNotification = Notification.Name("NSColorPanelColorDidChangeNotification")
    public var color: NSColor = .windowBackgroundColor {
        didSet {
            NotificationCenter.default.post(name: Self.colorDidChangeNotification, object: self)
        }
    }
    public var isVisible: Bool = false
    public var showsAlpha: Bool = true
    public var isContinuous: Bool = false

    public func orderFront(_ sender: Any?) {
        _ = sender
        isVisible = true
        if let selected = Self.selectedColorOverride() ?? Self.runColorChooser(initialColor: color),
           let parsed = Self.parseColor(selected, includeAlpha: showsAlpha) {
            color = parsed
            orderOut(nil)
        }
    }

    public func orderOut(_ sender: Any?) {
        _ = sender
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: self)
        isVisible = false
    }

    private static func selectedColorOverride() -> String? {
        guard let value = ProcessInfo.processInfo.environment["OMNIKIT_COLOR_PANEL_SELECTION"],
              !value.isEmpty else { return nil }
        return value
    }

    private static func runColorChooser(initialColor: NSColor) -> String? {
        let hex = hexString(for: initialColor)
        return _OmniDesktopProcess.output(["zenity", "--color-selection", "--show-palette", "--color=\(hex)"])
    }

    private static func hexString(for color: NSColor) -> String {
        func channel(_ value: CGFloat) -> Int {
            max(0, min(255, Int((value * 255).rounded())))
        }
        return String(
            format: "#%02X%02X%02X",
            channel(color.redComponent),
            channel(color.greenComponent),
            channel(color.blueComponent)
        )
    }

    private static func parseColor(_ raw: String, includeAlpha: Bool) -> NSColor? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            let hex = String(trimmed.dropFirst())
            guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
            let red: CGFloat
            let green: CGFloat
            let blue: CGFloat
            let alpha: CGFloat
            if hex.count == 8 {
                red = CGFloat((value >> 24) & 0xff) / 255
                green = CGFloat((value >> 16) & 0xff) / 255
                blue = CGFloat((value >> 8) & 0xff) / 255
                alpha = includeAlpha ? CGFloat(value & 0xff) / 255 : 1
            } else {
                red = CGFloat((value >> 16) & 0xff) / 255
                green = CGFloat((value >> 8) & 0xff) / 255
                blue = CGFloat(value & 0xff) / 255
                alpha = 1
            }
            return NSColor(red: red, green: green, blue: blue, alpha: alpha)
        }

        let lower = trimmed.lowercased()
        guard lower.hasPrefix("rgb(") || lower.hasPrefix("rgba("),
              let start = trimmed.firstIndex(of: "("),
              let end = trimmed.lastIndex(of: ")") else {
            return nil
        }
        let channels = trimmed[trimmed.index(after: start)..<end]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard channels.count >= 3,
              let redValue = Double(channels[0]),
              let greenValue = Double(channels[1]),
              let blueValue = Double(channels[2]) else {
            return nil
        }
        let scale = max(redValue, greenValue, blueValue) > 255 ? 65535.0 : 255.0
        let alphaValue = channels.count > 3 ? Double(channels[3]) ?? 1 : 1
        return NSColor(
            red: CGFloat(max(0, min(1, redValue / scale))),
            green: CGFloat(max(0, min(1, greenValue / scale))),
            blue: CGFloat(max(0, min(1, blueValue / scale))),
            alpha: includeAlpha ? CGFloat(max(0, min(1, alphaValue))) : 1
        )
    }
}

public extension NSAttributedString.Key {
    static let font = NSAttributedString.Key("NSFont")
}

public extension NSString {
    func size(withAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSSize {
        let font = attrs?[.font] as? NSFont
        let charWidth = (font?.pointSize ?? NSFont.systemFontSize) * 0.58
        return NSSize(width: CGFloat(length) * charWidth, height: font?.pointSize ?? NSFont.systemFontSize)
    }
}

public final class NSItemProvider: NSObject, @unchecked Sendable {
    public let object: Any

    public init(object: Any) {
        self.object = object
        super.init()
    }

    public var registeredTypeIdentifiers: [String] {
        Self.typeIdentifiers(for: object)
    }

    public func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool {
        Self.typeIdentifiers(for: object).contains { Self.typeIdentifier($0, conformsTo: typeIdentifier) }
    }

    public func canLoadObject(ofClass objectClass: AnyClass) -> Bool {
        switch object {
        case is String, is NSString:
            return objectClass == NSString.self
        case is URL, is NSURL:
            return objectClass == NSURL.self
        default:
            return (object as? NSObject)?.isKind(of: objectClass) ?? false
        }
    }

    @discardableResult
    public func loadItem(
        forTypeIdentifier typeIdentifier: String,
        options: [AnyHashable: Any]? = nil,
        completionHandler: ((Any?, Error?) -> Void)? = nil
    ) -> Progress? {
        _ = options
        let value = hasItemConformingToTypeIdentifier(typeIdentifier) ? itemValue(for: typeIdentifier) : nil
        completionHandler?(value, nil)
        let progress = Progress(totalUnitCount: 1)
        progress.completedUnitCount = 1
        return progress
    }

    @discardableResult
    public func loadObject(
        ofClass objectClass: AnyClass,
        completionHandler: ((Any?, Error?) -> Void)? = nil
    ) -> Progress? {
        let value: Any?
        if objectClass == NSString.self {
            value = stringValue()
        } else if objectClass == NSURL.self {
            value = urlValue()
        } else if (object as? NSObject)?.isKind(of: objectClass) == true {
            value = object
        } else {
            value = nil
        }
        completionHandler?(value, nil)
        let progress = Progress(totalUnitCount: 1)
        progress.completedUnitCount = 1
        return progress
    }

    private func itemValue(for typeIdentifier: String) -> Any? {
        if Self.textTypeIdentifiers.contains(typeIdentifier) {
            return stringValue()
        }
        if typeIdentifier == UTType.fileURL.identifier || typeIdentifier == NSPasteboard.PasteboardType.fileURL.rawValue {
            return fileURLString()
        }
        if typeIdentifier == UTType.url.identifier || typeIdentifier == NSPasteboard.PasteboardType.URL.rawValue {
            return urlValue()?.absoluteString
        }
        return object
    }

    private func stringValue() -> String? {
        if let string = object as? String { return string }
        if let string = object as? NSString { return string as String }
        if let url = urlValue() { return url.absoluteString }
        return nil
    }

    private func urlValue() -> URL? {
        if let url = object as? URL { return url }
        if let url = object as? NSURL { return url as URL }
        if let string = object as? String { return URL(string: string) ?? URL(fileURLWithPath: string) }
        if let string = object as? NSString {
            let value = string as String
            return URL(string: value) ?? URL(fileURLWithPath: value)
        }
        return nil
    }

    private func fileURLString() -> String? {
        guard let url = urlValue() else { return nil }
        return url.isFileURL ? url.absoluteString : nil
    }

    private static let textTypeIdentifiers: Set<String> = [
        UTType.plainText.identifier,
        UTType.text.identifier,
        "public.utf8-plain-text",
        NSPasteboard.PasteboardType.string.rawValue
    ]

    private static func typeIdentifiers(for object: Any) -> [String] {
        switch object {
        case is String, is NSString:
            return Array(textTypeIdentifiers)
        case let url as URL:
            return url.isFileURL
                ? [UTType.fileURL.identifier, NSPasteboard.PasteboardType.fileURL.rawValue, UTType.url.identifier, NSPasteboard.PasteboardType.URL.rawValue, UTType.item.identifier]
                : [UTType.url.identifier, NSPasteboard.PasteboardType.URL.rawValue, UTType.item.identifier]
        case let url as NSURL:
            let swiftURL = url as URL
            return swiftURL.isFileURL
                ? [UTType.fileURL.identifier, NSPasteboard.PasteboardType.fileURL.rawValue, UTType.url.identifier, NSPasteboard.PasteboardType.URL.rawValue, UTType.item.identifier]
                : [UTType.url.identifier, NSPasteboard.PasteboardType.URL.rawValue, UTType.item.identifier]
        default:
            return [UTType.data.identifier, UTType.item.identifier]
        }
    }

    private static func typeIdentifier(_ candidate: String, conformsTo requested: String) -> Bool {
        if candidate == requested { return true }
        if requested == UTType.item.identifier { return true }
        if requested == UTType.data.identifier {
            return candidate == UTType.data.identifier
        }
        if requested == UTType.text.identifier {
            return textTypeIdentifiers.contains(candidate)
        }
        if requested == UTType.plainText.identifier || requested == "public.utf8-plain-text" {
            return textTypeIdentifiers.contains(candidate)
        }
        if requested == UTType.url.identifier || requested == NSPasteboard.PasteboardType.URL.rawValue {
            return candidate == UTType.url.identifier ||
                candidate == NSPasteboard.PasteboardType.URL.rawValue ||
                candidate == UTType.fileURL.identifier ||
                candidate == NSPasteboard.PasteboardType.fileURL.rawValue
        }
        if requested == UTType.fileURL.identifier || requested == NSPasteboard.PasteboardType.fileURL.rawValue {
            return candidate == UTType.fileURL.identifier ||
                candidate == NSPasteboard.PasteboardType.fileURL.rawValue
        }
        return false
    }
}
#endif
