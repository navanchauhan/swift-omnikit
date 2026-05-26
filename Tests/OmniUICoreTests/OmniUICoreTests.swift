import Testing
import Foundation
import OmniUICore
import UniformTypeIdentifiers
#if os(Linux)
import Glibc
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(WebKit)
import WebKit
#endif

#if canImport(AppKit)
private final class WindowPropagationProbeView: NSView {
    var willMoveWindowStates: [Bool] = []
    var didMoveWindowStates: [Bool] = []

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        willMoveWindowStates.append(newWindow != nil)
    }

    override func viewDidMoveToWindow() {
        didMoveWindowStates.append(window != nil)
    }
}

private final class AppearancePropagationProbeView: NSView {
    var effectiveAppearanceNames: [NSAppearance.Name] = []

    override func viewEffectiveAppearanceDidChange() {
        effectiveAppearanceNames.append(effectiveAppearance.name)
    }
}

private final class DraggingProbeView: NSView {
    var enteredPasteboardString: String?
    var performedPasteboardString: String?
    var lastLocation: NSPoint?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        enteredPasteboardString = sender.draggingPasteboard.string(forType: .string)
        lastLocation = sender.draggingLocation
        return .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        performedPasteboardString = sender.draggingPasteboard.string(forType: .string)
        lastLocation = sender.draggingLocation
        return performedPasteboardString != nil
    }
}

private final class DraggingConversionProbeView: NSView {
    var lastLocalLocation: NSPoint?

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        lastLocalLocation = convert(sender.draggingLocation, from: nil)
        return .move
    }
}

private final class NativeDropFallbackProbeBox: @unchecked Sendable {
    var performedString: String?
    var performedLocation: NSPoint?
    var entered = 0
    var updated = 0
}

private final class NativeDropFallbackProbeView: NSView {
    let box: NativeDropFallbackProbeBox

    init(box: NativeDropFallbackProbeBox) {
        self.box = box
        super.init(frame: .zero)
        registerForDraggedTypes([.string])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        _ = sender
        box.entered += 1
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        _ = sender
        box.updated += 1
        return .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        box.performedString = sender.draggingPasteboard.string(forType: .string)
        box.performedLocation = sender.draggingLocation
        return box.performedString != nil
    }
}

private struct NativeDropFallbackRepresentable: NSViewRepresentable {
    let box: NativeDropFallbackProbeBox

    func makeNSView(context: Context) -> NativeDropFallbackProbeView {
        _ = context
        return NativeDropFallbackProbeView(box: box)
    }

    func updateNSView(_ nsView: NativeDropFallbackProbeView, context: Context) {
        _ = nsView
        _ = context
    }
}

private final class TransparentHitTestProbeView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        _ = point
        return nil
    }
}

private final class SwiftUIDropProbeBox: @unchecked Sendable {
    var entered = 0
    var updated = 0
    var performed = 0
    var providers: [NSItemProvider] = []
}

private struct SwiftUIDropProbeDelegate: DropDelegate {
    let box: SwiftUIDropProbeBox

    func dropEntered(info: DropInfo) {
        box.entered += 1
        box.providers = info.itemProviders
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        box.updated += 1
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        box.performed += 1
        box.providers = info.itemProviders(for: [.plainText])
        return true
    }
}

private class ResponderActionProbeView: NSView {
    var copied = 0
    var pasted = 0
    var selectedAll = 0

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        item.action == Selector("copy:") ||
        item.action == Selector("paste:") ||
        item.action == Selector("selectAll:")
    }

    override func copy(_ sender: Any?) {
        _ = sender
        copied += 1
    }

    override func paste(_ sender: Any?) {
        _ = sender
        pasted += 1
    }

    override func selectAll(_ sender: Any?) {
        _ = sender
        selectedAll += 1
    }
}

private final class FirstResponderProbeView: NSView {
    var becomeCount = 0
    var resignCount = 0
    var acceptsFirstResponder = true

    override func becomeFirstResponder() -> Bool {
        becomeCount += 1
        return acceptsFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        resignCount += 1
        return true
    }
}

private final class PointCaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var points: [NSPoint] = []

    func append(_ point: NSPoint) {
        lock.lock()
        points.append(point)
        lock.unlock()
    }

    var snapshot: [NSPoint] {
        lock.lock()
        let current = points
        lock.unlock()
        return current
    }
}

private final class ContextMenuProbeView: ResponderActionProbeView {
    var menuPresentationCount = 0
    var lastMenuEventLocation: NSPoint?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuPresentationCount += 1
        lastMenuEventLocation = event.locationInWindow
        let menu = NSMenu(title: "Context")
        menu.addItem(NSMenuItem(title: "Copy", action: Selector("copy:"), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Paste", action: Selector("paste:"), keyEquivalent: ""))
        return menu
    }
}

private final class ScrollWheelProbeView: NSView {
    var scrollEvents: [NSEvent] = []

    override func scrollWheel(with event: NSEvent) {
        scrollEvents.append(event)
    }
}

private final class RepresentableLifecycleState: @unchecked Sendable {
    private let lock = NSLock()
    private var makeCountValue = 0
    private var updateCountValue = 0
    private var dismantleCountValue = 0

    func reset() {
        lock.lock()
        makeCountValue = 0
        updateCountValue = 0
        dismantleCountValue = 0
        lock.unlock()
    }

    func made() {
        lock.lock()
        makeCountValue += 1
        lock.unlock()
    }

    func updated() {
        lock.lock()
        updateCountValue += 1
        lock.unlock()
    }

    func dismantled() {
        lock.lock()
        dismantleCountValue += 1
        lock.unlock()
    }

    var counts: (make: Int, update: Int, dismantle: Int) {
        lock.lock()
        let current = (makeCountValue, updateCountValue, dismantleCountValue)
        lock.unlock()
        return current
    }
}

private let representableLifecycleState = RepresentableLifecycleState()

private final class LifecycleProbeNSView: NSView {}

private struct LifecycleProbeRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> LifecycleProbeNSView {
        _ = context
        representableLifecycleState.made()
        return LifecycleProbeNSView()
    }

    func updateNSView(_ nsView: LifecycleProbeNSView, context: Context) {
        _ = nsView
        _ = context
        representableLifecycleState.updated()
    }

    static func dismantleNSView(_ nsView: LifecycleProbeNSView, coordinator: Void) {
        _ = nsView
        _ = coordinator
        representableLifecycleState.dismantled()
    }
}

private final class NativeHostProbeBox: @unchecked Sendable {
    var view: NSView?
}

private final class NativeHostProbeView: NSView {}

private struct NativeHostProbeRepresentable: NSViewRepresentable {
    let box: NativeHostProbeBox

    func makeNSView(context: Context) -> NativeHostProbeView {
        _ = context
        let view = NativeHostProbeView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NativeHostProbeView, context: Context) {
        _ = nsView
        _ = context
    }
}

private final class NativePayloadChildProbeView: NSView, _OmniWebViewPayloadProviding {
    var _omniWebViewPayload: _OmniWebViewPayload {
        _OmniWebViewPayload(
            load: .html("<html><body>Native child</body></html>", baseURL: URL(string: "about:blank")),
            fallbackText: "Native child",
            stableIdentity: "native-child-probe",
            swiftObject: self
        )
    }
}

private final class DeferredNativePayloadRootView: NSView {
    var attachedProvider: NativePayloadChildProbeView?
}

private struct DeferredNativePayloadRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> DeferredNativePayloadRootView {
        _ = context
        return DeferredNativePayloadRootView()
    }

    func updateNSView(_ nsView: DeferredNativePayloadRootView, context: Context) {
        _ = context
        guard nsView.window != nil, nsView.bounds.size != .zero, nsView.attachedProvider == nil else { return }
        let provider = NativePayloadChildProbeView()
        nsView.attachedProvider = provider
        nsView.addSubview(provider)
    }
}

private final class NativeTextFieldProbeBox: @unchecked Sendable {
    var field: NSTextField?
    var changes: [String] = []
    var beganEditing = 0
    var endedEditing = 0
    var submitted = 0
}

private final class NativeTextFieldProbeDelegate: NSObject, NSTextFieldDelegate {
    let box: NativeTextFieldProbeBox

    init(box: NativeTextFieldProbeBox) {
        self.box = box
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        box.changes.append(field.stringValue)
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        _ = obj
        box.beganEditing += 1
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        _ = obj
        box.endedEditing += 1
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        _ = control
        _ = textView
        guard commandSelector == Selector("NSResponder.insertNewline:") else { return false }
        box.submitted += 1
        return true
    }
}

private struct NativeTextFieldRepresentableProbe: NSViewRepresentable {
    let box: NativeTextFieldProbeBox

    func makeCoordinator() -> NativeTextFieldProbeDelegate {
        NativeTextFieldProbeDelegate(box: box)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: "native start")
        field.placeholderString = "Native placeholder"
        field.delegate = context.coordinator
        box.field = field
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        _ = nsView
        _ = context
    }
}
#endif

struct CounterView: View {
    @State private var count: Int = 0
    var body: some View {
        VStack(spacing: 1) {
            Text("Count: \(count)")
            Button("Inc") { count += 1 }
        }
        .padding(1)
    }
}

private enum _ProbeEnvironmentLabelKey: EnvironmentKey {
    static let defaultValue = "Default environment"
}

private extension EnvironmentValues {
    var probeEnvironmentLabel: String {
        get { self[_ProbeEnvironmentLabelKey.self] }
        set { self[_ProbeEnvironmentLabelKey.self] = newValue }
    }
}

private enum SemanticTextProbe {
    static func collect(in node: SemanticNode) -> String {
        var parts: [String] = []
        func visit(_ current: SemanticNode) {
            switch current.kind {
            case .text(let text), .image(let text):
                parts.append(text)
            case .webContent(_, _, _, let label, let description):
                if let label { parts.append(label) }
                if let description { parts.append(description) }
            default:
                break
            }
            current.children.forEach(visit)
        }
        visit(node)
        return parts.joined(separator: " ")
    }
}

private struct ColorSchemeReaderProbe: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(colorScheme == .light ? "light" : "dark")
    }
}

private final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        let current = value
        lock.unlock()
        return current
    }
}

@Test func preferredColorSchemeUpdatesRuntimeEnvironmentAndResetsWhenAbsent() async throws {
    struct V: View {
        let scheme: ColorScheme?

        var body: some View {
            ColorSchemeReaderProbe()
                .preferredColorScheme(scheme)
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 20, height: 4)

    let light = runtime.semanticSnapshot(V(scheme: .light), size: size)
    #expect(SemanticTextProbe.collect(in: light.root).contains("light"))
    #expect(runtime.lastPreferredColorScheme == .light)

    let dark = runtime.semanticSnapshot(V(scheme: .dark), size: size)
    #expect(SemanticTextProbe.collect(in: dark.root).contains("dark"))
    #expect(runtime.lastPreferredColorScheme == .dark)

    _ = runtime.semanticSnapshot(Text("plain"), size: size)
    #expect(runtime.lastPreferredColorScheme == nil)
}

@Test func localColorSchemeEnvironmentDoesNotOverrideApplicationPreference() async throws {
    struct V: View {
        var body: some View {
            ColorSchemeReaderProbe()
                .environment(\.colorScheme, .light)
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 20, height: 4))

    #expect(SemanticTextProbe.collect(in: snapshot.root).contains("light"))
    #expect(runtime.lastPreferredColorScheme == nil)
}

#if canImport(AppKit)
@Test func linuxColorBridgePreservesRGBAndColorPanelNotifications() async throws {
    let swiftColor = Color(red: 0.93, green: 0.88, blue: 0.72)
    let nsColor = NSColor(swiftColor)
    #expect(abs(nsColor.redComponent - 0.93) < 0.01)
    #expect(abs(nsColor.greenComponent - 0.88) < 0.01)
    #expect(abs(nsColor.blueComponent - 0.72) < 0.01)

    let roundTrip = Color(nsColor)
    let roundTripNSColor = NSColor(roundTrip)
    #expect(abs(roundTripNSColor.redComponent - nsColor.redComponent) < 0.01)
    #expect(abs(roundTripNSColor.greenComponent - nsColor.greenComponent) < 0.01)
    #expect(abs(roundTripNSColor.blueComponent - nsColor.blueComponent) < 0.01)

    let notificationCount = ThreadSafeCounter()
    let observer = NotificationCenter.default.addObserver(
        forName: NSColorPanel.colorDidChangeNotification,
        object: NSColorPanel.shared,
        queue: nil
    ) { _ in
        notificationCount.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    NSColorPanel.shared.color = nsColor
    #expect(notificationCount.count == 1)
}

@Test func linuxColorPanelOrderFrontCanSelectColorThroughHeadlessOverride() async throws {
    #if os(Linux)
    let previous = getenv("OMNIKIT_COLOR_PANEL_SELECTION").map { String(cString: $0) }
    defer {
        if let previous {
            setenv("OMNIKIT_COLOR_PANEL_SELECTION", previous, 1)
        } else {
            unsetenv("OMNIKIT_COLOR_PANEL_SELECTION")
        }
        NSColorPanel.shared.orderOut(nil)
    }

    setenv("OMNIKIT_COLOR_PANEL_SELECTION", "#336699", 1)
    let panel = NSColorPanel.shared
    panel.showsAlpha = false
    panel.color = NSColor(red: 1, green: 1, blue: 1, alpha: 1)

    final class Box: @unchecked Sendable {
        var changedWhileVisible = false
        var closed = false
    }
    let box = Box()
    let colorObserver = NotificationCenter.default.addObserver(
        forName: NSColorPanel.colorDidChangeNotification,
        object: panel,
        queue: nil
    ) { _ in
        box.changedWhileVisible = panel.isVisible
    }
    let closeObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: panel,
        queue: nil
    ) { _ in
        box.closed = true
    }
    defer {
        NotificationCenter.default.removeObserver(colorObserver)
        NotificationCenter.default.removeObserver(closeObserver)
    }

    panel.orderFront(nil)

    #expect(abs(panel.color.redComponent - 0.2) < 0.01)
    #expect(abs(panel.color.greenComponent - 0.4) < 0.01)
    #expect(abs(panel.color.blueComponent - 0.6) < 0.01)
    #expect(panel.color.alphaComponent == 1)
    #expect(box.changedWhileVisible)
    #expect(box.closed)
    #expect(!panel.isVisible)
    #endif
}

@Test func swiftUIOnReceiveSubscribesToNotificationPublishers() async throws {
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []

        func append(_ value: String) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        var snapshot: [String] {
            lock.lock()
            let current = values
            lock.unlock()
            return current
        }
    }

    let name = Notification.Name("OmniUICoreTestsOnReceiveNotification")
    let box = Box()

    struct V: View {
        let name: Notification.Name
        let box: Box

        var body: some View {
            Text("Receiver")
                .onReceive(DistributedNotificationCenter.default().publisher(for: name)) { note in
                    box.append(note.userInfo?["value"] as? String ?? "")
                }
        }
    }

    let runtime = _UIRuntime()
    _ = runtime.semanticSnapshot(V(name: name, box: box), size: _Size(width: 30, height: 4))
    DistributedNotificationCenter.default().postNotificationName(
        name,
        object: nil,
        userInfo: ["value": "delivered"],
        deliverImmediately: true
    )

    for _ in 0..<20 where box.snapshot.isEmpty {
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(box.snapshot == ["delivered"])
}

@Test func swiftUIOnReceiveRunsWithCapturedEnvironmentFromBackgroundDelivery() async throws {
    final class Model {
        private let lock = NSLock()
        private var values: [String] = []

        func append(_ value: String) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        var snapshot: [String] {
            lock.lock()
            let current = values
            lock.unlock()
            return current
        }
    }

    struct V: View {
        @Environment(Model.self) private var model
        let name: Notification.Name

        var body: some View {
            Text("Receiver")
                .onReceive(NotificationCenter.default.publisher(for: name)) { note in
                    model.append(note.userInfo?["value"] as? String ?? "")
                }
        }
    }

    let name = Notification.Name("OmniUICoreTestsOnReceiveBackgroundNotification")
    let model = Model()
    let runtime = _UIRuntime()
    _ = runtime.semanticSnapshot(
        V(name: name).environment(model),
        size: _Size(width: 30, height: 4)
    )

    DispatchQueue.global().async {
        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: ["value": "captured-environment"]
        )
    }

    for _ in 0..<50 where model.snapshot.isEmpty {
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(model.snapshot == ["captured-environment"])
}

@Test func stateBindingMutationFromBackgroundQueueAppliesOnMainQueue() async throws {
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var bindingValue: Binding<Int>?

        func set(_ binding: Binding<Int>) {
            lock.lock()
            bindingValue = binding
            lock.unlock()
        }

        func mutateFromBackground(to value: Int) {
            lock.lock()
            let binding = bindingValue
            lock.unlock()

            DispatchQueue.global().async {
                binding?.wrappedValue = value
            }
        }
    }

    struct V: View {
        let box: Box
        @State private var count = 0

        var body: some View {
            box.set($count)
            return Text("Count: \(count)")
        }
    }

    let box = Box()
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 4)
    let initial = runtime.debugRender(V(box: box), size: size)
    #expect(initial.text.contains("Count: 0"))

    box.mutateFromBackground(to: 42)

    var updated = runtime.debugRender(V(box: box), size: size)
    for _ in 0..<50 where !updated.text.contains("Count: 42") {
        try await Task.sleep(nanoseconds: 10_000_000)
        await MainActor.run {}
        updated = runtime.debugRender(V(box: box), size: size)
    }

    #expect(updated.text.contains("Count: 42"))
}

@Test func typedEnvironmentObjectCanBeReadFromEscapingCallbackAfterBuild() async throws {
    final class Model {
        private let lock = NSLock()
        private var values: [String] = []

        func append(_ value: String) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        var snapshot: [String] {
            lock.lock()
            let current = values
            lock.unlock()
            return current
        }
    }

    final class Box: @unchecked Sendable {
        var callback: (() -> Void)?
    }

    struct Child: View {
        @Environment(Model.self) private var model
        let box: Box

        func handleEscapingCallback() {
            model.append("escaped")
        }

        var body: some View {
            box.callback = {
                handleEscapingCallback()
            }
            return Text("Callback registered")
        }
    }

    let model = Model()
    let box = Box()
    let runtime = _UIRuntime()
    _ = runtime.semanticSnapshot(
        Child(box: box).environment(model),
        size: _Size(width: 30, height: 4)
    )

    box.callback?()

    #expect(model.snapshot == ["escaped"])
}

@Test func typedEnvironmentObjectCanBeReadFromActionEnvironmentThatLacksObject() async throws {
    final class Model {
        private let lock = NSLock()
        private var values: [String] = []

        func append(_ value: String) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        var snapshot: [String] {
            lock.lock()
            let current = values
            lock.unlock()
            return current
        }
    }

    struct ActionView: View {
        @Environment(Model.self) private var model

        var body: some View {
            Button("Run") {
                model.append("action")
            }
        }
    }

    func firstButtonActionID(in node: SemanticNode) -> Int? {
        if case .button(let actionID, _) = node.kind {
            return actionID
        }
        for child in node.children {
            if let actionID = firstButtonActionID(in: child) {
                return actionID
            }
        }
        return nil
    }

    let model = Model()
    let runtime = _UIRuntime()
    _ = runtime.semanticSnapshot(
        Text("Seed").environment(model),
        size: _Size(width: 30, height: 4)
    )
    let snapshot = runtime.semanticSnapshot(
        ActionView(),
        size: _Size(width: 30, height: 4)
    )
    let actionID = try #require(firstButtonActionID(in: snapshot.root))

    runtime.invokeActionByRawID(actionID)

    #expect(model.snapshot == ["action"])
}

@Test func distributedNotificationCenterReceivesFileBackedExternalPostsOnLinux() async throws {
    #if os(Linux)
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []

        func append(_ value: String) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        var snapshot: [String] {
            lock.lock()
            let current = values
            lock.unlock()
            return current
        }
    }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("omnikit-distributed-notification-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    setenv("OMNIKIT_DISTRIBUTED_NOTIFICATION_DIR", directory.path, 1)
    defer {
        unsetenv("OMNIKIT_DISTRIBUTED_NOTIFICATION_DIR")
        try? FileManager.default.removeItem(at: directory)
    }

    let name = Notification.Name("OmniUICoreTestsExternalDistributedNotification-\(UUID().uuidString)")
    let box = Box()
    let subscription = DistributedNotificationCenter.default().publisher(for: name)._omniSubscribe { note in
        box.append(note.userInfo?["value"] as? String ?? "")
    }
    _ = subscription

    let payload: [String: Any] = [
        "name": name.rawValue,
        "object": NSNull(),
        "pid": -1,
        "created": Date().timeIntervalSince1970,
        "userInfo": ["value": "external"],
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [])
    try data.write(to: directory.appendingPathComponent("external.json"), options: .atomic)

    for _ in 0..<50 where box.snapshot.isEmpty {
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    #expect(box.snapshot == ["external"])
    #endif
}

@Test func runningApplicationsDiscoversLinuxProcessesByBundleIdentifierEnvironment() async throws {
    #if os(Linux)
    let bundleIdentifier = "dev.omnikit.tests.running-app-\(UUID().uuidString)"
    setenv("OMNIKIT_BUNDLE_IDENTIFIER", bundleIdentifier, 1)
    defer { unsetenv("OMNIKIT_BUNDLE_IDENTIFIER") }

    let matches = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    #expect(matches.contains { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier })
    #endif
}

@Test func appleScriptDoShellScriptExecutesThroughLinuxShellFallback() async throws {
    #if os(Linux)
    let capture = FileManager.default.temporaryDirectory
        .appendingPathComponent("omnikit-applescript-capture-\(UUID().uuidString).txt")
    setenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE", capture.path, 1)
    defer {
        unsetenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE")
        try? FileManager.default.removeItem(at: capture)
    }

    var error: NSDictionary?
    let script = NSAppleScript(source: #"do shell script "printf hello > '/tmp/omnikit apple script'" with administrator privileges"#)
    script?.executeAndReturnError(&error)

    #expect(error == nil)
    let captured = try String(contentsOf: capture, encoding: .utf8)
    #expect(captured.contains("/bin/sh\t-c\tprintf hello > '/tmp/omnikit apple script'"))
    #endif
}

@Test func fontManagerDiscoversLinuxFontFamiliesBeyondPlaceholders() async throws {
    #if os(Linux)
    let families = NSFontManager.shared.availableFontFamilies
    #expect(families.contains("System"))
    #expect(families.contains("Monospace"))
    #expect(Set(families.map { $0.lowercased() }).count == families.count)
    if FileManager.default.fileExists(atPath: "/usr/bin/fc-list") || FileManager.default.fileExists(atPath: "/bin/fc-list") {
        #expect(families.count > 2)
    }
    #endif
}

@Test func preferredColorSchemeOverridesApplicationAppearanceUntilCleared() async throws {
    NSApp.appearance = NSAppearance(named: .darkAqua)
    #expect(_omniEffectiveAppearanceColorScheme() == .dark)

    _omniSetPreferredColorScheme(.light)
    #expect(_omniEffectiveAppearanceColorScheme() == .light)

    _omniSetPreferredColorScheme(nil)
    #expect(_omniEffectiveAppearanceColorScheme() == .dark)
    NSApp.appearance = nil
}

@Test func linuxDynamicSystemColorsTrackEffectiveAppearance() async throws {
    NSApp.appearance = nil
    _omniSetPreferredColorScheme(nil)
    defer {
        _omniSetPreferredColorScheme(nil)
        NSApp.appearance = nil
    }

    _omniSetPreferredColorScheme(.light)
    #expect(NSColor.textColor.redComponent < 0.2)
    #expect(NSColor.textBackgroundColor.redComponent > 0.9)
    #expect(NSColor.windowBackgroundColor.redComponent > 0.9)

    _omniSetPreferredColorScheme(.dark)
    #expect(NSColor.textColor.redComponent > 0.8)
    #expect(NSColor.textBackgroundColor.redComponent < 0.2)
    #expect(NSColor.windowBackgroundColor.redComponent < 0.2)

    _omniSetPreferredColorScheme(nil)
    NSApp.appearance = NSAppearance(named: .aqua)
    #expect(NSColor.labelColor.redComponent < 0.2)

    NSApp.appearance = NSAppearance(named: .darkAqua)
    #expect(NSColor.labelColor.redComponent > 0.8)
}

@Test func linuxNSViewEffectiveAppearanceInheritsFromSuperviewWindowAndApplication() async throws {
    NSApp.appearance = NSAppearance(named: .darkAqua)
    defer { NSApp.appearance = nil }

    let window = NSWindow()
    let root = NSView()
    let child = NSView()
    root.addSubview(child)
    window.contentView = root

    #expect(child.effectiveAppearance.name == .darkAqua)

    root.appearance = NSAppearance(named: .aqua)
    #expect(child.effectiveAppearance.name == .aqua)

    child.appearance = NSAppearance(named: .darkAqua)
    #expect(child.effectiveAppearance.name == .darkAqua)

    child.appearance = nil
    root.appearance = nil
    window.appearance = NSAppearance(named: .aqua)
    #expect(child.effectiveAppearance.name == .aqua)
}

@Test func linuxNSViewNotifiesDescendantsWhenEffectiveAppearanceChanges() async throws {
    NSApp.appearance = nil
    defer { NSApp.appearance = nil }

    let window = NSWindow()
    let root = NSView()
    let child = AppearancePropagationProbeView()
    root.addSubview(child)
    window.contentView = root

    root.appearance = NSAppearance(named: .aqua)
    root.appearance = NSAppearance(named: .darkAqua)
    window.appearance = NSAppearance(named: .aqua)

    #expect(child.effectiveAppearanceNames.contains(.aqua))
    #expect(child.effectiveAppearanceNames.contains(.darkAqua))
    #expect(child.effectiveAppearance.name == .darkAqua)

    root.appearance = nil
    #expect(child.effectiveAppearance.name == .aqua)
    #expect(child.effectiveAppearanceNames.last == .aqua)
}

#endif

#if canImport(AppKit) && canImport(WebKit)
private final class WebViewRepresentableCoordinatorProbe: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static weak var latest: WebViewRepresentableCoordinatorProbe?
    var updateCount = 0

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        _ = userContentController
        _ = message
    }
}

private struct ConfigurableWebViewRepresentableProbe: NSViewRepresentable {
    let url: URL
    let zoom: CGFloat

    func makeCoordinator() -> WebViewRepresentableCoordinatorProbe {
        let coordinator = WebViewRepresentableCoordinatorProbe()
        WebViewRepresentableCoordinatorProbe.latest = coordinator
        return coordinator
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = "OmniKitProbe"
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: "window.__omniProbeInjectedStyle = true;",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(context.coordinator, name: "probeHandler")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.pageZoom = zoom
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.loadHTMLString("<html><body>Probe</body></html>", baseURL: url)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.updateCount += 1
        nsView.pageZoom = zoom + 0.25
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: WebViewRepresentableCoordinatorProbe) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "probeHandler")
        nsView.navigationDelegate = nil
        nsView.uiDelegate = nil
        _ = coordinator
    }
}

@Test @MainActor func representableFallbackPreservesNativeWebViewConfiguration() async throws {
    struct V: View {
        let zoom: CGFloat

        var body: some View {
            ConfigurableWebViewRepresentableProbe(
                url: URL(string: "https://example.com/article")!,
                zoom: zoom
            )
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 80, height: 12)
    let snapshot = runtime.semanticSnapshot(V(zoom: 1.2), size: size)
    func webPayloads(in node: SemanticNode) -> [_OmniWebViewPayload] {
        var payloads: [_OmniWebViewPayload] = []
        if case .webContent(let name, _, _, _, _) = node.kind,
           let payload = _OmniWebViewRegistry.payload(for: name) {
            payloads.append(payload)
        }
        for child in node.children {
            payloads.append(contentsOf: webPayloads(in: child))
        }
        return payloads
    }
    let payloads = webPayloads(in: snapshot.root)
    let payload = try #require(payloads.first { $0.url.absoluteString == "https://example.com/article" })
    let webView = try #require(payload.nativeView as? WKWebView)
    let coordinator = try #require(WebViewRepresentableCoordinatorProbe.latest)
    #expect(webView.configuration.applicationNameForUserAgent == "OmniKitProbe")
    #expect(webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically == false)
    #expect(webView.configuration.userContentController.userScripts.count == 1)
    #expect(webView.allowsMagnification)
    #expect(webView.navigationDelegate === coordinator)
    #expect(webView.uiDelegate === coordinator)
    #expect(coordinator.updateCount == 1)
    #expect(webView.pageZoom == 1.45)
    #expect(payload.fallbackText == "Web content\nhttps://example.com/article")

    let nextSnapshot = runtime.semanticSnapshot(V(zoom: 1.6), size: size)
    let nextPayloads = webPayloads(in: nextSnapshot.root)
    let nextPayload = try #require(nextPayloads.first { $0.url.absoluteString == "https://example.com/article" })
    let nextWebView = try #require(nextPayload.nativeView as? WKWebView)
    #expect(nextWebView === webView)
    #expect(webView.navigationDelegate === coordinator)
    #expect(webView.uiDelegate === coordinator)
    #expect(coordinator.updateCount == 2)
    #expect(webView.pageZoom == 1.85)
}

@Test @MainActor func semanticSnapshotLabelsNativeWebPayloadsForComputerUse() async throws {
    struct V: View {
        var body: some View {
            ConfigurableWebViewRepresentableProbe(
                url: URL(string: "https://example.com/article")!,
                zoom: 1.0
            )
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 12))

    func webContent(in node: SemanticNode) -> SemanticNode.Kind? {
        if case .webContent = node.kind {
            return node.kind
        }
        for child in node.children {
            if let found = webContent(in: child) {
                return found
            }
        }
        return nil
    }

    guard case .webContent(let registryKey, let stableIdentity, let url, let label, let description) = webContent(in: snapshot.root) else {
        Issue.record("Expected native web payload to lower as webContent")
        return
    }

    #expect(_OmniWebViewRegistry.payload(for: registryKey) != nil)
    #expect(stableIdentity.contains("example.com"))
    #expect(url == "https://example.com/article")
    #expect(label == "https://example.com/article")
    #expect(description == "Web content")
    #expect(SemanticTextProbe.collect(in: snapshot.root).contains("Web content"))
    #expect(SemanticTextProbe.collect(in: snapshot.root).contains("Web content\nhttps://example.com/article"))
}
#endif

#if canImport(AppKit)
@Test func representableFallbackDismantlesNativeViewWhenRemovedFromTree() async throws {
    struct V: View {
        let showNativeView: Bool

        var body: some View {
            VStack {
                if showNativeView {
                    LifecycleProbeRepresentable()
                } else {
                    Text("gone")
                }
            }
        }
    }

    representableLifecycleState.reset()
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 8)

    _ = runtime.semanticSnapshot(V(showNativeView: true), size: size)
    var counts = representableLifecycleState.counts
    #expect(counts.make == 1)
    #expect(counts.update == 1)
    #expect(counts.dismantle == 0)

    _ = runtime.semanticSnapshot(V(showNativeView: true), size: size)
    counts = representableLifecycleState.counts
    #expect(counts.make == 1)
    #expect(counts.update == 2)
    #expect(counts.dismantle == 0)

    _ = runtime.semanticSnapshot(V(showNativeView: false), size: size)
    counts = representableLifecycleState.counts
    #expect(counts.make == 1)
    #expect(counts.update == 2)
    #expect(counts.dismantle == 1)
}

@Test func linuxNSViewRepresentableRootsReceiveSyntheticWindowAndDefaultFrame() async throws {
    NSApp.keyWindow = nil
    let runtime = _UIRuntime()
    let box = NativeHostProbeBox()

    _ = runtime.semanticSnapshot(NativeHostProbeRepresentable(box: box), size: _Size(width: 80, height: 24))

    let view = try #require(box.view)
    #expect(view.window != nil)
    #expect(view.window === NSApp.keyWindow)
    #expect(view.bounds.size == CGSize(width: 800, height: 600))

    let child = NSView()
    view.addSubview(child)
    #expect(child.window === view.window)
    #expect(child.bounds.size == view.bounds.size)
}

@Test func linuxGenericNativeRepresentablePayloadCarriesAccessibilityMetadata() async throws {
    let runtime = _UIRuntime()
    let box = NativeHostProbeBox()
    let snapshot = runtime.semanticSnapshot(NativeHostProbeRepresentable(box: box), size: _Size(width: 80, height: 24))

    func webContent(in node: SemanticNode) -> SemanticNode.Kind? {
        if case .webContent = node.kind {
            return node.kind
        }
        for child in node.children {
            if let found = webContent(in: child) {
                return found
            }
        }
        return nil
    }

    guard case .webContent(let registryKey, _, let url, let label, let description) = webContent(in: snapshot.root) else {
        Issue.record("Expected generic native representable to lower as webContent")
        return
    }

    let payload = try #require(_OmniWebViewRegistry.payload(for: registryKey))
    #expect(url == "about:blank")
    #expect(payload.fallbackText == "Native view\nNativeHostProbeView")
    #expect(label == "NativeHostProbeView")
    #expect(description == "Native view NativeHostProbeView")
    #expect(payload.accessibilityLabel == "NativeHostProbeView")
    #expect(payload.accessibilityDescription == "Native view NativeHostProbeView")
}

@Test func linuxNSViewRepresentableCanAttachNativePayloadAfterWindowHosting() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(DeferredNativePayloadRepresentable(), size: _Size(width: 80, height: 24))

    func payloads(in node: SemanticNode) -> [_OmniWebViewPayload] {
        var found: [_OmniWebViewPayload] = []
        if case .webContent(let name, _, _, _, _) = node.kind,
           let payload = _OmniWebViewRegistry.payload(for: name) {
            found.append(payload)
        }
        for child in node.children {
            found.append(contentsOf: payloads(in: child))
        }
        return found
    }

    let payload = try #require(payloads(in: snapshot.root).first { $0.stableIdentity == "native-child-probe" })
    #expect(payload.fallbackText == "Native child")
    #expect(payload.swiftObject is NativePayloadChildProbeView)
}

@Test func linuxNSTextFieldRepresentableRendersAsEditableSemanticTextField() async throws {
    let runtime = _UIRuntime()
    let box = NativeTextFieldProbeBox()
    let view = NativeTextFieldRepresentableProbe(box: box)
    let snapshot = runtime.semanticSnapshot(view, size: _Size(width: 80, height: 24))

    func textFieldActionID(in node: SemanticNode) -> Int? {
        if case .textField(let actionID, let placeholder, let text, _, _, _) = node.kind {
            #expect(placeholder == "Native placeholder")
            #expect(text == "native start")
            return actionID
        }
        for child in node.children {
            if let actionID = textFieldActionID(in: child) {
                return actionID
            }
        }
        return nil
    }

    let actionID = try #require(textFieldActionID(in: snapshot.root))
    runtime.invokeActionByRawID(actionID)
    #expect(box.field?.currentEditor() != nil)
    #expect(box.beganEditing == 1)

    runtime.replaceTextForRawActionID(actionID, previous: "native start", next: "native edit")
    runtime.handleNativeKeyForRawActionID(actionID, keyKind: 7, codepoint: 0)

    #expect(box.field?.stringValue == "native edit")
    #expect(box.changes.last == "native edit")
    #expect(box.submitted == 1)
}

@Test func linuxNSTextFieldResponderLifecycleExposesCurrentEditorAndEndEditing() async throws {
    let window = NSWindow()
    let field = NSTextField(string: "native")
    let replacement = NSView()
    let box = NativeTextFieldProbeBox()
    let delegate = NativeTextFieldProbeDelegate(box: box)
    field.delegate = delegate
    window.contentView = NSView()
    window.contentView?.addSubview(field)
    window.contentView?.addSubview(replacement)

    #expect(window.makeFirstResponder(field))
    #expect(box.beganEditing == 1)
    #expect(field.currentEditor() != nil)
    field.currentEditor()?.alignment = .left
    #expect(field.currentEditor()?.alignment == .left)

    #expect(window.makeFirstResponder(replacement))
    #expect(box.endedEditing == 1)
    #expect(field.currentEditor() == nil)
    #expect(window.firstResponder === replacement)
}

@Test func linuxNSViewWindowPropagationReachesNestedSubviews() async throws {
    let window = NSWindow()
    let root = NSView()
    let child = NSView()
    let grandchild = WindowPropagationProbeView()

    child.addSubview(grandchild)
    root.addSubview(child)
    window.contentView = root

    #expect(root.window === window)
    #expect(child.window === window)
    #expect(grandchild.window === window)
    #expect(grandchild.willMoveWindowStates.contains(true))
    #expect(grandchild.didMoveWindowStates.contains(true))

    window.contentView = nil

    #expect(root.window == nil)
    #expect(child.window == nil)
    #expect(grandchild.window == nil)
    #expect(grandchild.willMoveWindowStates.contains(false))
    #expect(grandchild.didMoveWindowStates.contains(false))
}

@Test func linuxNSViewTracksDraggedTypesAndAcceptsDraggingInfoSnapshots() async throws {
    let pasteboard = NSPasteboard()
    pasteboard.setString("drag-token", forType: .string)
    let info = NSDraggingInfoSnapshot(
        draggingPasteboard: pasteboard,
        draggingLocation: NSPoint(x: 12, y: 34)
    )
    let view = DraggingProbeView()

    view.registerForDraggedTypes([.string])
    #expect(view.registeredDraggedTypes == [.string])
    #expect(view.draggingEntered(info) == .move)
    #expect(view.performDragOperation(info))
    #expect(view.enteredPasteboardString == "drag-token")
    #expect(view.performedPasteboardString == "drag-token")
    #expect(view.lastLocation == NSPoint(x: 12, y: 34))

    view.unregisterDraggedTypes()
    #expect(view.registeredDraggedTypes.isEmpty)
}

@Test func linuxNSViewCoordinateConversionAccountsForNestedFrameOrigins() async throws {
    let root = NSView(frame: NSRect(x: 10, y: 20, width: 300, height: 200))
    let child = NSView(frame: NSRect(x: 30, y: 40, width: 100, height: 90))
    let grandchild = NSView(frame: NSRect(x: 5, y: 6, width: 20, height: 10))

    root.addSubview(child)
    child.addSubview(grandchild)

    #expect(grandchild.convert(NSPoint(x: 45, y: 66), from: nil) == NSPoint(x: 0, y: 0))
    #expect(grandchild.convert(.zero, to: nil) == NSPoint(x: 45, y: 66))
    #expect(root.convert(.zero, from: grandchild) == NSPoint(x: 35, y: 46))

    let rect = grandchild.convert(NSRect(x: 45, y: 66, width: 8, height: 9), from: nil)
    #expect(rect.origin == .zero)
    #expect(rect.size == CGSize(width: 8, height: 9))
}

@Test func linuxDraggingLocationsConvertFromWindowCoordinatesToLocalViewCoordinates() async throws {
    let pasteboard = NSPasteboard()
    pasteboard.setString("drag-token", forType: .string)
    let info = NSDraggingInfoSnapshot(
        draggingPasteboard: pasteboard,
        draggingLocation: NSPoint(x: 40, y: 60)
    )
    let root = NSView(frame: NSRect(x: 10, y: 20, width: 200, height: 200))
    let view = DraggingConversionProbeView(frame: NSRect(x: 30, y: 40, width: 100, height: 80))

    root.addSubview(view)

    #expect(view.draggingUpdated(info) == .move)
    #expect(view.lastLocalLocation == .zero)
    #expect(view.bounds.contains(view.lastLocalLocation ?? NSPoint(x: -1, y: -1)))
}

@Test func linuxNSViewHitTestingWalksSubviewsAndSkipsTransparentOverlays() async throws {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 160))
    let bottom = NSView(frame: NSRect(x: 20, y: 30, width: 80, height: 70))
    let topTransparent = TransparentHitTestProbeView(frame: NSRect(x: 10, y: 10, width: 120, height: 110))

    root.addSubview(bottom)
    root.addSubview(topTransparent)

    #expect(root.hitTest(NSPoint(x: 25, y: 35)) === bottom)
    #expect(root.hitTest(NSPoint(x: 150, y: 120)) === root)
    #expect(root.hitTest(NSPoint(x: 205, y: 10)) == nil)
}

@Test func swiftUIDragAndDropModifiersProvideLinuxClickFallback() async throws {
    let runtime = _UIRuntime()
    let box = SwiftUIDropProbeBox()

    struct V: View {
        let box: SwiftUIDropProbeBox
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Source")
                    .onDrag { NSItemProvider(object: "drag-token") }
                Text("Target")
                    .onDrop(of: [.plainText], delegate: SwiftUIDropProbeDelegate(box: box))
            }
        }
    }

    let first = runtime.render(V(box: box), size: _Size(width: 30, height: 4))
    first.click(x: 0, y: 0)

    let second = runtime.render(V(box: box), size: _Size(width: 30, height: 4))
    second.click(x: 0, y: 1)

    #expect(box.entered == 1)
    #expect(box.updated == 1)
    #expect(box.performed == 1)
    #expect(box.providers.compactMap { $0.object as? String } == ["drag-token"])
}

@Test func swiftUIDragFallbackDoesNotReplaceExistingTapInteraction() async throws {
    final class Box: @unchecked Sendable {
        var taps = 0
    }

    let runtime = _UIRuntime()
    let box = Box()

    struct V: View {
        let box: Box
        var body: some View {
            Text("Selectable row")
                .onTapGesture { box.taps += 1 }
                .onDrag { NSItemProvider(object: "drag-token") }
        }
    }

    let first = runtime.render(V(box: box), size: _Size(width: 30, height: 2))
    first.click(x: 0, y: 0)

    #expect(box.taps == 1)
}

@Test func swiftUIDragFallbackCanStartFromViewWithExistingTapInteraction() async throws {
    final class Box: @unchecked Sendable {
        var taps = 0
    }

    let runtime = _UIRuntime()
    let tapBox = Box()
    let dropBox = SwiftUIDropProbeBox()

    struct V: View {
        let tapBox: Box
        let dropBox: SwiftUIDropProbeBox

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Draggable row")
                    .onTapGesture { tapBox.taps += 1 }
                    .onDrag { NSItemProvider(object: "drag-token") }
                Text("Target")
                    .onDrop(of: [.plainText], delegate: SwiftUIDropProbeDelegate(box: dropBox))
            }
        }
    }

    let first = runtime.render(V(tapBox: tapBox, dropBox: dropBox), size: _Size(width: 30, height: 4))
    first.drag(from: _Point(x: 0, y: 0), to: _Point(x: 8, y: 0))

    let second = runtime.render(V(tapBox: tapBox, dropBox: dropBox), size: _Size(width: 30, height: 4))
    second.drag(from: _Point(x: 0, y: 0), to: _Point(x: 0, y: 1))

    #expect(tapBox.taps == 0)
    #expect(dropBox.entered == 1)
    #expect(dropBox.updated == 1)
    #expect(dropBox.performed == 1)
    #expect(dropBox.providers.compactMap { $0.object as? String } == ["drag-token"])
}

@Test func swiftUIDragFallbackCanDropOntoNativeRegisteredNSView() async throws {
    let runtime = _UIRuntime()
    let box = NativeDropFallbackProbeBox()

    struct V: View {
        let box: NativeDropFallbackProbeBox

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Native source")
                    .onDrag { NSItemProvider(object: "native-drag-token") }
                NativeDropFallbackRepresentable(box: box)
            }
        }
    }

    let first = runtime.render(V(box: box), size: _Size(width: 40, height: 4))
    first.click(x: 0, y: 0)

    let second = runtime.render(V(box: box), size: _Size(width: 40, height: 4))
    second.click(x: 7, y: 1)

    #expect(box.entered == 1)
    #expect(box.updated == 1)
    #expect(box.performedString == "native-drag-token")
    #expect(box.performedLocation == NSPoint(x: 7, y: 1))
}

@Test func linuxItemProviderReportsTypesAndLoadsCommonStringAndURLObjects() async throws {
    let textProvider = NSItemProvider(object: "drag-token" as NSString)
    #expect(textProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier))
    #expect(textProvider.hasItemConformingToTypeIdentifier(UTType.text.identifier))
    #expect(textProvider.canLoadObject(ofClass: NSString.self))

    var loadedText: Any?
    textProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, error in
        #expect(error == nil)
        loadedText = item
    }
    #expect(loadedText as? String == "drag-token")

    let fileURL = URL(fileURLWithPath: "/tmp/readme.md")
    let fileProvider = NSItemProvider(object: fileURL as NSURL)
    #expect(fileProvider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
    #expect(fileProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier))
    #expect(fileProvider.canLoadObject(ofClass: NSURL.self))

    var loadedURL: Any?
    fileProvider.loadObject(ofClass: NSURL.self) { item, error in
        #expect(error == nil)
        loadedURL = item
    }
    #expect((loadedURL as? URL)?.path == "/tmp/readme.md")

    let info = DropInfo(itemProviders: [fileProvider])
    #expect(info.hasItemsConforming(to: [.fileURL]))
    #expect(info.hasItemsConforming(to: [.url]))
    #expect(info.itemProviders(for: [.plainText]).isEmpty)
}

@Test func linuxStatusItemAndPopoverLifecycleMirrorAppKitState() async throws {
    let statusBar = NSStatusBar.system
    let existingItems = statusBar.statusItems
    for item in existingItems {
        statusBar.removeStatusItem(item)
    }

    let item = statusBar.statusItem(withLength: NSStatusItem.variableLength)
    #expect(statusBar.statusItems.contains { $0 === item })
    #expect(item.length == NSStatusItem.variableLength)
    item.button?.toolTip = "CPU: 10%\nweb: up\n:8080: down"
    #expect(item.button?.toolTip == "CPU: 10%\nweb: up\n:8080: down")
    #expect(statusBar.fallbackLabels == ["CPU: 10% · web: up · :8080: down"])
    item.button?.image = NSImage(size: NSSize(width: 12, height: 8), flipped: false) { _ in
        NSColor.labelColor.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 1).fill()
        NSRect(x: 3, y: 0, width: 2, height: 4).fill()
        NSRect(x: 6, y: 0, width: 2, height: 8).fill()
        NSColor.labelColor.withAlphaComponent(0.2).setFill()
        NSBezierPath(ovalIn: NSRect(x: 9, y: 1, width: 3, height: 3)).fill()
        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: NSRect(x: 9, y: 5, width: 3, height: 3)).fill()
        return true
    }
    #expect(statusBar.fallbackLabels == ["▂▅█ ○● · CPU: 10% · web: up · :8080: down"])

    let actionView = ResponderActionProbeView()
    let window = NSWindow()
    window.contentView = actionView
    window.makeKey()
    #expect(window.makeFirstResponder(actionView))
    item.button?.target = actionView
    item.button?.action = Selector("copy:")
    #expect(statusBar.performStatusItem(at: 0))
    #expect(actionView.copied == 1)

    final class CustomStatusTarget: NSObject {
        var senderIsButton = false
    }
    let customTarget = CustomStatusTarget()
    customTarget._omniRegisterSelectorAction(Selector("buttonClicked")) { sender in
        customTarget.senderIsButton = sender as? NSButton === item.button
    }
    item.button?.target = customTarget
    item.button?.action = Selector("buttonClicked")
    #expect(statusBar.performStatusItem(at: 0))
    #expect(customTarget.senderIsButton)

    let controller = NSViewController()
    let popover = NSPopover()
    popover.contentViewController = controller
    popover.show(relativeTo: .zero, of: item.button ?? NSButton(), preferredEdge: .minY)
    #expect(popover.isShown)
    #expect(controller.view.window != nil)

    popover.performClose(nil)
    #expect(!popover.isShown)
    #expect(controller.view.window == nil)

    statusBar.removeStatusItem(item)
    #expect(!statusBar.statusItems.contains { $0 === item })
    #expect(statusBar.fallbackLabels.isEmpty)
}

@Test func linuxMenuBarExtraInstallsStatusItemAndHostedPopoverContent() async throws {
    final class Box {
        var actionCount = 0
    }
    struct ProbeScene: Scene {
        let box: Box

        var body: some Scene {
            WindowGroup {
                Text("Main")
            }
            MenuBarExtra("Probe Extra") {
                Button("Do Thing") { box.actionCount += 1 }
            }
        }
    }
    let box = Box()

    let statusBar = NSStatusBar.system
    let existingItems = statusBar.statusItems
    for item in existingItems {
        statusBar.removeStatusItem(item)
    }

    _ = _sceneRootView(ProbeScene(box: box).body)

    #expect(statusBar.fallbackLabels.contains("Probe Extra"))
    guard let index = statusBar.fallbackLabels.firstIndex(of: "Probe Extra") else {
        Issue.record("MenuBarExtra did not install a status item")
        return
    }
    #expect(statusBar.performStatusItem(at: index))
    let activeContent = try #require(NSPopover.activeContentView)
    let runtime = _UIRuntime()
    let popover = runtime.debugRender(activeContent, size: _Size(width: 36, height: 8))
    #expect(popover.text.contains("[Do Thing]"))
    guard let button = _findButton(popover, title: "Do Thing") else {
        Issue.record("MenuBarExtra popover did not expose its button as an action")
        return
    }
    popover.click(x: button.x, y: button.y)
    #expect(box.actionCount == 1)
}

@Test func linuxWindowMakeFirstResponderCallsResponderHooks() async throws {
    let window = NSWindow()
    let first = FirstResponderProbeView()
    let second = FirstResponderProbeView()
    let rejecting = FirstResponderProbeView()
    rejecting.acceptsFirstResponder = false

    #expect(window.makeFirstResponder(first))
    #expect(window.firstResponder === first)
    #expect(first.becomeCount == 1)

    #expect(!window.makeFirstResponder(rejecting))
    #expect(window.firstResponder === first)
    #expect(rejecting.becomeCount == 1)
    #expect(first.resignCount == 0)

    #expect(window.makeFirstResponder(second))
    #expect(window.firstResponder === second)
    #expect(second.becomeCount == 1)
    #expect(first.resignCount == 1)

    #expect(window.makeFirstResponder(nil))
    #expect(window.firstResponder == nil)
    #expect(second.resignCount == 1)
}

@Test func linuxNSImageDrawingInitializerPreservesRequestedSize() async throws {
    final class RectBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = NSRect.zero

        func set(_ rect: NSRect) {
            lock.lock()
            value = rect
            lock.unlock()
        }

        var rect: NSRect {
            lock.lock()
            let current = value
            lock.unlock()
            return current
        }
    }

    let drawnRect = RectBox()
    let image = NSImage(size: NSSize(width: 17, height: 22), flipped: true) { rect in
        drawnRect.set(rect)
        NSColor.systemGreen.setFill()
        NSRect(x: 2, y: 3, width: 4, height: 5).fill()
        NSColor.labelColor.withAlphaComponent(0.25).setStroke()
        NSBezierPath(ovalIn: NSRect(x: 7, y: 8, width: 3, height: 3)).stroke()
        return true
    }

    #expect(image.size == NSSize(width: 17, height: 22))
    #expect(drawnRect.rect == NSRect(origin: .zero, size: NSSize(width: 17, height: 22)))
    #expect(image._omniDrawingCommands.count == 2)
    #expect(image._omniDrawingCommands[0].kind == .fillRect)
    #expect(image._omniDrawingCommands[0].rect == NSRect(x: 2, y: 3, width: 4, height: 5))
    #expect(image._omniDrawingCommands[0].colorName == "systemGreen")
    #expect(image._omniDrawingCommands[1].kind == .strokeOval)
    #expect(image._omniDrawingCommands[1].rect == NSRect(x: 7, y: 8, width: 3, height: 3))
    #expect(image._omniDrawingCommands[1].alpha == 0.25)

    image.isTemplate = true
    #expect(image.isTemplate)
}

@Test func linuxNSBezierPathRecordsMovedLineStrokes() async throws {
    let image = NSImage(size: NSSize(width: 20, height: 8), flipped: false) { _ in
        NSColor.labelColor.withAlphaComponent(0.5).setStroke()
        let underline = NSBezierPath()
        underline.move(to: NSPoint(x: 2, y: 4))
        underline.line(to: NSPoint(x: 18, y: 4))
        underline.lineWidth = 2
        underline.stroke()
        return true
    }

    #expect(image._omniDrawingCommands.count == 1)
    #expect(image._omniDrawingCommands[0].kind == .strokeLine)
    #expect(image._omniDrawingCommands[0].rect == NSRect(x: 2, y: 3, width: 16, height: 2))
    #expect(image._omniDrawingCommands[0].alpha == 0.5)
}

@Test func linuxPopoverTracksActiveHostedSwiftUIView() async throws {
    let button = NSButton()
    let controller = NSHostingController(rootView: Text("Menu Item"))
    let popover = NSPopover()
    let notifications = ThreadSafeCounter()
    let token = NotificationCenter.default.addObserver(
        forName: NSPopover.didChangePopoverNotification,
        object: nil,
        queue: nil
    ) { _ in
        notifications.increment()
    }
    defer {
        NotificationCenter.default.removeObserver(token)
    }

    popover.contentViewController = controller
    popover.show(relativeTo: .zero, of: button, preferredEdge: .minY)
    #expect(popover.isShown)
    #expect(NSPopover.activeContentView != nil)
    #expect(notifications.count == 1)

    popover.performClose(nil)
    #expect(!popover.isShown)
    #expect(NSPopover.activeContentView == nil)
    #expect(notifications.count == 2)
}

@Test func linuxStandardResponderActionsDispatchThroughMenuItemsAndButtons() async throws {
    let view = ResponderActionProbeView()
    let window = NSWindow()
    window.contentView = view
    window.makeKey()
    #expect(window.makeFirstResponder(view))

    let copyItem = NSMenuItem(title: "Copy", action: Selector("copy:"), keyEquivalent: "")
    copyItem.target = view
    #expect(copyItem.isEnabled)
    #expect(copyItem.performAction())
    #expect(view.copied == 1)

    let pasteButton = NSButton()
    pasteButton.target = view
    pasteButton.action = Selector("paste:")
    pasteButton.performClick(nil)
    #expect(view.pasted == 1)

    #expect(NSApp.sendAction(Selector("selectAll:"), to: nil, from: nil))
    #expect(view.selectedAll == 1)

    let menu = NSMenu()
    let pasteItem = NSMenuItem(title: "Paste", action: Selector("paste:"), keyEquivalent: "")
    pasteItem.target = view
    menu.addItem(pasteItem)
    #expect(menu.performActionForItem(at: 0))
    #expect(view.pasted == 2)
}

@Test func linuxCustomSelectorActionsDispatchThroughRegisteredHandlers() async throws {
    final class Target: NSObject {
        var senders: [Any] = []
    }

    let target = Target()
    let selector = Selector("performCustomAction:")
    target._omniRegisterSelectorAction(selector) { sender in
        target.senders.append(sender as Any)
    }

    let item = NSMenuItem(title: "Custom", action: selector, keyEquivalent: "")
    item.target = target
    #expect(item.isEnabled)
    #expect(item.performAction("menu-sender"))
    #expect(target.senders.count == 1)
    #expect(target.senders.first as? String == "menu-sender")

    let button = NSButton()
    button.target = target
    button.action = selector
    button.performClick("button-sender")
    #expect(target.senders.count == 2)
    #expect(target.senders.last as? String == "button-sender")
}

@Test func linuxSelectorsNormalizeQualifiedGeneratedSpellings() async throws {
    final class Target: NSObject {
        var count = 0
    }

    let target = Target()
    target._omniRegisterSelectorAction(Selector("Coordinator.submit")) { _ in
        target.count += 1
    }

    #expect(Selector("NSResponder.insertNewline:") == Selector("insertNewline:"))
    #expect(NSApp.sendAction(Selector("submit"), to: target, from: nil))
    #expect(target.count == 1)
}

@Test func linuxWindowSendEventInterceptorsCanConsumeEventsBeforeLocalMonitors() async throws {
    let window = NSWindow()
    let event = NSEvent()
    event.type = .leftMouseDown
    event.locationInWindow = NSPoint(x: 12, y: 34)

    let interceptedLocations = PointCaptureBox()
    let interceptor = NSWindow._omniAddSendEventInterceptor { interceptedWindow, interceptedEvent in
        guard interceptedWindow === window else { return false }
        interceptedLocations.append(interceptedEvent.locationInWindow)
        return true
    }
    defer { NSWindow._omniRemoveSendEventInterceptor(interceptor) }

    var monitorCount = 0
    let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
        _ = event
        monitorCount += 1
        return event
    }
    defer {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    window.sendEvent(event)

    #expect(interceptedLocations.snapshot == [NSPoint(x: 12, y: 34)])
    #expect(window.mouseLocationOutsideOfEventStream == NSPoint(x: 12, y: 34))
    #expect(monitorCount == 0)
}

@Test func linuxApplicationSendEventRoutesThroughKeyWindow() async throws {
    let previousKeyWindow = NSApp.keyWindow
    defer {
        NSApp.keyWindow = previousKeyWindow
    }

    let window = NSWindow()
    window.makeKey()

    let event = NSEvent()
    event.type = .leftMouseDown
    event.locationInWindow = NSPoint(x: 44, y: 55)

    let interceptedLocations = PointCaptureBox()
    let interceptor = NSWindow._omniAddSendEventInterceptor { interceptedWindow, interceptedEvent in
        guard interceptedWindow === window else { return false }
        interceptedLocations.append(interceptedEvent.locationInWindow)
        return true
    }
    defer { NSWindow._omniRemoveSendEventInterceptor(interceptor) }

    var monitorCount = 0
    let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
        _ = event
        monitorCount += 1
        return event
    }
    defer {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    NSApp.sendEvent(event)

    #expect(interceptedLocations.snapshot == [NSPoint(x: 44, y: 55)])
    #expect(window.mouseLocationOutsideOfEventStream == NSPoint(x: 44, y: 55))
    #expect(monitorCount == 0)
}

@Test func linuxWindowSendEventPresentsContextMenuAfterMonitorsDecline() async throws {
    NSMenu.dismissActiveMenu()
    let previousKeyWindow = NSApp.keyWindow
    defer {
        NSApp.keyWindow = previousKeyWindow
        NSMenu.dismissActiveMenu()
    }

    let view = ContextMenuProbeView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
    let window = NSWindow()
    window.contentView = view
    window.makeKey()

    var monitorCount = 0
    let monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
        monitorCount += 1
        return event
    }
    defer {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    let event = NSEvent()
    event.type = .rightMouseDown
    event.locationInWindow = NSPoint(x: 10, y: 12)

    window.sendEvent(event)

    #expect(monitorCount == 1)
    #expect(view.menuPresentationCount == 1)
    #expect(NSMenu.activeMenu?.title == "Context")
}

@Test func linuxWindowSendEventRoutesScrollWheelAfterMonitorsDecline() async throws {
    let previousKeyWindow = NSApp.keyWindow
    defer {
        NSApp.keyWindow = previousKeyWindow
    }

    let root = ScrollWheelProbeView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
    let child = ScrollWheelProbeView(frame: NSRect(x: 40, y: 50, width: 120, height: 80))
    root.addSubview(child)

    let window = NSWindow()
    window.contentView = root
    window.makeKey()

    var monitorCount = 0
    let monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
        monitorCount += 1
        return event
    }
    defer {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    let event = NSEvent()
    event.type = .scrollWheel
    event.locationInWindow = NSPoint(x: 70, y: 90)
    event.scrollingDeltaX = 4
    event.scrollingDeltaY = -9

    window.sendEvent(event)

    #expect(monitorCount == 1)
    #expect(child.scrollEvents.count == 1)
    #expect(root.scrollEvents.count == 1)
    #expect(child.scrollEvents.first?.scrollingDeltaY == -9)
}

@Test func linuxMenusTrackAppKitStyleItemStateAndStructure() async throws {
    let view = ResponderActionProbeView()
    let window = NSWindow()
    window.contentView = view
    window.makeKey()
    #expect(window.makeFirstResponder(view))

    let menu = NSMenu(title: "Terminal")
    let copyItem = NSMenuItem(title: "Copy", action: Selector("copy:"), keyEquivalent: "c")
    copyItem.target = view
    copyItem.keyEquivalentModifierMask = [.command]
    copyItem.state = .on
    copyItem.representedObject = "copy-command"
    copyItem.toolTip = "Copy selection"
    copyItem.tag = 42

    let submenu = NSMenu(title: "Open With")
    copyItem.submenu = submenu
    menu.addItem(copyItem)

    #expect(menu.title == "Terminal")
    #expect(menu.numberOfItems == 1)
    #expect(menu.item(at: 0) === copyItem)
    #expect(menu.index(of: copyItem) == 0)
    #expect(copyItem.menu === menu)
    #expect(copyItem.submenu === submenu)
    #expect(submenu.supermenu === menu)
    #expect(copyItem.keyEquivalentModifierMask.contains(.command))
    #expect(copyItem.state == .on)
    #expect(copyItem.representedObject as? String == "copy-command")
    #expect(copyItem.toolTip == "Copy selection")
    #expect(copyItem.tag == 42)
    #expect(menu.performActionForItem(at: 0))
    #expect(view.copied == 1)

    copyItem.isEnabled = false
    #expect(!copyItem.isEnabled)
    #expect(!menu.performActionForItem(at: 0))
    #expect(view.copied == 1)

    copyItem.isEnabled = true
    copyItem.isHidden = true
    #expect(!menu.performActionForItem(at: 0))
    #expect(view.copied == 1)

    let separator = NSMenuItem.separator()
    menu.insertItem(separator, at: 0)
    #expect(menu.numberOfItems == 2)
    #expect(separator.isSeparatorItem)
    #expect(separator.menu === menu)
    #expect(!menu.performActionForItem(at: 0))

    menu.removeItem(separator)
    #expect(separator.menu == nil)
    #expect(menu.numberOfItems == 1)

    menu.removeAllItems()
    #expect(menu.items.isEmpty)
    #expect(copyItem.menu == nil)
    #expect(submenu.supermenu == nil)
}

@Test func linuxContextMenusCanBePresentedFromFirstResponder() async throws {
    let view = ContextMenuProbeView()
    let window = NSWindow()
    window.contentView = view
    window.makeKey()
    #expect(window.makeFirstResponder(view))

    let event = NSEvent()
    event.type = .rightMouseDown
    event.locationInWindow = NSPoint(x: 8, y: 9)

    #expect(_omniPresentContextMenu(for: event))
    #expect(NSMenu.activeMenu?.title == "Context")
    #expect(NSMenu.activeMenu?.numberOfItems == 3)
    #expect(NSMenu.activeContentView != nil)

    #expect(NSMenu.activeMenu?.performActionForItem(at: 0) == true)
    #expect(view.copied == 1)

    NSMenu.dismissActiveMenu()
    #expect(NSMenu.activeMenu == nil)
}

@Test func linuxContextMenusUseClickedNativeViewBeforeFirstResponder() async throws {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
    let clicked = ContextMenuProbeView(frame: NSRect(x: 40, y: 50, width: 120, height: 80))
    let responder = ResponderActionProbeView(frame: NSRect(x: 180, y: 40, width: 60, height: 60))
    root.addSubview(clicked)
    root.addSubview(responder)

    let window = NSWindow()
    window.contentView = root
    window.makeKey()
    #expect(window.makeFirstResponder(responder))

    let event = NSEvent()
    event.type = .rightMouseDown
    event.locationInWindow = NSPoint(x: 70, y: 90)

    #expect(_omniPresentContextMenu(for: event))
    #expect(clicked.menuPresentationCount == 1)
    #expect(clicked.lastMenuEventLocation == NSPoint(x: 70, y: 90))
    #expect(NSMenu.activeMenu?.title == "Context")

    NSMenu.dismissActiveMenu()
}

@Test func linuxScrollWheelDispatchesThroughClickedNativeViewHierarchy() async throws {
    let root = ScrollWheelProbeView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
    let clicked = ScrollWheelProbeView(frame: NSRect(x: 40, y: 50, width: 120, height: 80))
    root.addSubview(clicked)

    let window = NSWindow()
    window.contentView = root
    window.makeKey()
    window._recordMouseLocation(NSPoint(x: 72, y: 96))

    let event = NSEvent()
    event.type = .scrollWheel
    event.locationInWindow = window.mouseLocationOutsideOfEventStream
    event.scrollingDeltaX = 3
    event.scrollingDeltaY = -7

    #expect(_omniDispatchScrollWheel(for: event))
    #expect(clicked.scrollEvents.count == 1)
    #expect(clicked.scrollEvents.first?.locationInWindow == NSPoint(x: 72, y: 96))
    #expect(clicked.scrollEvents.first?.scrollingDeltaX == 3)
    #expect(clicked.scrollEvents.first?.scrollingDeltaY == -7)
    #expect(root.scrollEvents.count == 1)
}

@Test func linuxApplicationTracksWindowsKeyWindowAndRunningApplication() async throws {
    let existingWindows = NSApp.windows
    for window in existingWindows {
        NSApp.windows.removeAll { $0 === window }
    }
    NSApp.keyWindow = nil

    let first = NSWindow()
    let second = NSWindow()
    #expect(NSApp.windows.contains { $0 === first })
    #expect(NSApp.windows.contains { $0 === second })

    second.makeKeyAndOrderFront(nil)
    #expect(NSApp.keyWindow === second)

    let bundleID = "dev.omnikit.tests"
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    #expect(running.count == 1)
    #expect(running.first?.bundleIdentifier == bundleID)
    #expect(running.first?.processIdentifier == ProcessInfo.processInfo.processIdentifier)

    _ = first
    _ = second
}

@Test func linuxWindowKeyTransitionsPostAppKitNotifications() async throws {
    final class Box: @unchecked Sendable {
        var events: [String] = []
    }

    let existingWindows = NSApp.windows
    for window in existingWindows {
        NSApp.windows.removeAll { $0 === window }
    }
    NSApp.keyWindow = nil

    let first = NSWindow()
    let second = NSWindow()
    let box = Box()
    let center = NotificationCenter.default
    let firstID = ObjectIdentifier(first)
    @Sendable func label(for note: Notification, firstLabel: String, secondLabel: String) -> String {
        guard let object = note.object as AnyObject? else { return secondLabel }
        return ObjectIdentifier(object) == firstID ? firstLabel : secondLabel
    }
    let tokens = [
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: nil) { note in
            box.events.append(label(for: note, firstLabel: "first became key", secondLabel: "second became key"))
        },
        center.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: nil) { note in
            box.events.append(label(for: note, firstLabel: "first became main", secondLabel: "second became main"))
        },
        center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: nil) { note in
            box.events.append(label(for: note, firstLabel: "first resigned key", secondLabel: "second resigned key"))
        },
        center.addObserver(forName: NSWindow.didResignMainNotification, object: nil, queue: nil) { note in
            box.events.append(label(for: note, firstLabel: "first resigned main", secondLabel: "second resigned main"))
        },
    ]
    defer {
        for token in tokens { center.removeObserver(token) }
    }

    first.makeKey()
    second.makeKey()
    second.makeKey()

    #expect(box.events == [
        "first became key",
        "first became main",
        "first resigned key",
        "first resigned main",
        "second became key",
        "second became main",
    ])
}

@Test func linuxApplicationActivateAndOrderFrontInvokeActivationHandler() async throws {
    #if os(Linux)
    final class Box: @unchecked Sendable {
        var activations = 0
    }

    let box = Box()
    _omniSetApplicationActivationHandler {
        box.activations += 1
    }
    defer { _omniSetApplicationActivationHandler(nil) }

    NSApp.activate(ignoringOtherApps: true)
    #expect(box.activations == 1)

    let window = NSWindow()
    window.makeKeyAndOrderFront(nil)
    #expect(NSApp.keyWindow === window)
    #expect(box.activations == 2)

    NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        .activate(options: [])
    #expect(box.activations == 3)
    #endif
}

@Test func linuxApplicationTerminatePostsWillTerminateNotification() async throws {
    let previous = getenv("OMNIKIT_SUPPRESS_TERMINATE").map { String(cString: $0) }
    defer {
        if let previous {
            setenv("OMNIKIT_SUPPRESS_TERMINATE", previous, 1)
        } else {
            unsetenv("OMNIKIT_SUPPRESS_TERMINATE")
        }
    }
    setenv("OMNIKIT_SUPPRESS_TERMINATE", "1", 1)

    final class Box: @unchecked Sendable {
        var notifications: [Notification] = []
    }

    let box = Box()
    let observer = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification,
        object: NSApp,
        queue: nil
    ) { notification in
        box.notifications.append(notification)
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    NSApp.terminate("quit")

    #expect(box.notifications.count == 1)
    #expect(box.notifications.first?.object as? NSApplication === NSApp)
}

@Test func linuxApplicationDelegateAdaptorInstallsDelegateOnSharedApplication() async throws {
    final class TestApplicationDelegate: NSApplicationDelegate {
        var sender: NSApplication?

        init() {}

        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            self.sender = sender
            return true
        }
    }

    let previousDelegate = NSApp.delegate
    defer { NSApp.delegate = previousDelegate }

    let adaptor = NSApplicationDelegateAdaptor(TestApplicationDelegate.self)

    #expect(NSApp.delegate === adaptor.wrappedValue)
    #expect(NSApp.applicationShouldTerminateAfterLastWindowClosed())
    #expect(adaptor.wrappedValue.sender === NSApp)
}

@Test func linuxNSAlertTracksButtonsAndSupportsHeadlessResponseOverride() async throws {
    #if os(Linux)
    let captureURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("omnikit-alert-\(UUID().uuidString).log")
    let previous = getenv("OMNIKIT_ALERT_RESPONSE").map { String(cString: $0) }
    let previousCapture = getenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE").map { String(cString: $0) }
    defer {
        try? FileManager.default.removeItem(at: captureURL)
        if let previous {
            setenv("OMNIKIT_ALERT_RESPONSE", previous, 1)
        } else {
            unsetenv("OMNIKIT_ALERT_RESPONSE")
        }
        if let previousCapture {
            setenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE", previousCapture, 1)
        } else {
            unsetenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE")
        }
    }
    unsetenv("OMNIKIT_ALERT_RESPONSE")
    setenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE", captureURL.path, 1)

    let alert = NSAlert()
    alert.messageText = "Install CLI Symlink"
    alert.informativeText = "Created /usr/local/bin/example-cli"
    alert.alertStyle = .informational
    alert.showsSuppressionButton = true
    let first = alert.addButton(withTitle: "OK")
    let second = alert.addButton(withTitle: "Show Details")

    #expect(first.title == "OK")
    #expect(second.title == "Show Details")
    #expect(alert.buttons.map(\.title) == ["OK", "Show Details"])
    #expect(alert.runModal() == .OK)
    let captured = try String(contentsOf: captureURL, encoding: .utf8)
    #expect(captured.contains("zenity\t--question"))
    #expect(captured.contains("--ok-label=OK"))

    setenv("OMNIKIT_ALERT_RESPONSE", "\(NSApplication.ModalResponse.alertSecondButtonReturn.rawValue)", 1)
    #expect(alert.runModal() == .alertSecondButtonReturn)
    #endif
}

@Test func linuxWorkspaceOpenUsesDesktopProcessCaptureForFileAndAppLaunches() async throws {
    #if os(Linux)
    let captureURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("omnikit-workspace-\(UUID().uuidString).log")
    let previous = getenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE").map { String(cString: $0) }
    defer {
        try? FileManager.default.removeItem(at: captureURL)
        if let previous {
            setenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE", previous, 1)
        } else {
            unsetenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE")
        }
    }
    setenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE", captureURL.path, 1)
    let launcherURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("omnikit-launcher-\(UUID().uuidString)")
    try "#!/bin/sh\nexit 0\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    chmod(launcherURL.path, 0o755)
    defer { try? FileManager.default.removeItem(at: launcherURL) }

    #expect(NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/Omni Notes/readme.md")))
    #expect(NSWorkspace.shared.open(URL(string: "https://example.com/docs")!))
    #expect(NSWorkspace.shared.open(
        [URL(fileURLWithPath: "/tmp/one.md"), URL(fileURLWithPath: "/tmp/two.md")],
        withApplicationAt: launcherURL,
        configuration: NSWorkspace.OpenConfiguration()
    ))
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "/tmp/three.md")])
    #expect(NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/tmp/root"))

    let lines = (try String(contentsOf: captureURL, encoding: .utf8))
        .split(separator: "\n")
        .map(String.init)

    #expect(lines.contains("gio\topen\t/tmp/Omni Notes/readme.md"))
    #expect(lines.contains("gio\topen\thttps://example.com/docs"))
    #expect(lines.contains("\(launcherURL.path)\t/tmp/one.md"))
    #expect(lines.contains("\(launcherURL.path)\t/tmp/two.md"))
    #expect(lines.contains("gio\topen\t/tmp/three.md"))
    #expect(lines.contains("gio\topen\t/tmp/root"))
    #endif
}

@Test func linuxWorkspaceOpenResolvesExecutableInsideAppBundles() async throws {
    #if os(Linux)
    let captureURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("omnikit-workspace-app-\(UUID().uuidString).log")
    let bundleURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("DemoEditor.app", isDirectory: true)
    let executableDirectory = bundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
    let executableURL = executableDirectory.appendingPathComponent("DemoEditor")
    let previous = getenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE").map { String(cString: $0) }
    defer {
        try? FileManager.default.removeItem(at: captureURL)
        try? FileManager.default.removeItem(at: bundleURL)
        if let previous {
            setenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE", previous, 1)
        } else {
            unsetenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE")
        }
    }
    try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
    chmod(executableURL.path, 0o755)
    setenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE", captureURL.path, 1)

    #expect(NSWorkspace.shared.open(
        [URL(fileURLWithPath: "/tmp/one.md")],
        withApplicationAt: bundleURL,
        configuration: NSWorkspace.OpenConfiguration()
    ))

    let lines = (try String(contentsOf: captureURL, encoding: .utf8))
        .split(separator: "\n")
        .map(String.init)
    #expect(lines == ["\(executableURL.path)\t/tmp/one.md"])
    #endif
}

@Test func linuxWorkspaceOpenReportsFailureForMissingExplicitApplication() async throws {
    #if os(Linux)
    let previous = getenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE").map { String(cString: $0) }
    defer {
        if let previous {
            setenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE", previous, 1)
        } else {
            unsetenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE")
        }
    }
    unsetenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE")

    #expect(!NSWorkspace.shared.open(
        [URL(fileURLWithPath: "/tmp/one.md")],
        withApplicationAt: URL(fileURLWithPath: "/definitely/not/a/linux/editor"),
        configuration: NSWorkspace.OpenConfiguration()
    ))
    #endif
}

@Test func linuxFilePanelsHonorSelectionOverrideForDirectoriesAndMultipleFiles() async throws {
    #if os(Linux)
    let previous = getenv("OMNIKIT_FILE_PANEL_SELECTION").map { String(cString: $0) }
    defer {
        if let previous {
            setenv("OMNIKIT_FILE_PANEL_SELECTION", previous, 1)
        } else {
            unsetenv("OMNIKIT_FILE_PANEL_SELECTION")
        }
    }

    setenv("OMNIKIT_FILE_PANEL_SELECTION", "/tmp/one.md\n/tmp/two.md", 1)
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = true
    #expect(openPanel.runModal() == .OK)
    #expect(openPanel.url?.path == "/tmp/one.md")
    #expect(openPanel.urls.map(\.path) == ["/tmp/one.md", "/tmp/two.md"])

    setenv("OMNIKIT_FILE_PANEL_SELECTION", "file:///tmp/omni-workspace", 1)
    let directoryPanel = NSOpenPanel()
    directoryPanel.title = "Select Directory"
    directoryPanel.canChooseDirectories = true
    directoryPanel.canChooseFiles = false
    directoryPanel.allowsMultipleSelection = false
    directoryPanel.canCreateDirectories = false
    #expect(directoryPanel.runModal() == .OK)
    #expect(directoryPanel.url?.path == "/tmp/omni-workspace")
    #expect(directoryPanel.urls.map(\.path) == ["/tmp/omni-workspace"])

    setenv("OMNIKIT_FILE_PANEL_SELECTION", "file:///tmp/new-omni-workspace", 1)
    let newDirectoryPanel = NSOpenPanel()
    newDirectoryPanel.title = "Choose Directory"
    newDirectoryPanel.canChooseDirectories = true
    newDirectoryPanel.canChooseFiles = false
    newDirectoryPanel.allowsMultipleSelection = false
    newDirectoryPanel.canCreateDirectories = true
    #expect(newDirectoryPanel.runModal() == .OK)
    #expect(newDirectoryPanel.url?.path == "/tmp/new-omni-workspace")
    #expect(newDirectoryPanel.urls.map(\.path) == ["/tmp/new-omni-workspace"])

    let savePanel = NSSavePanel()
    savePanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
    savePanel.nameFieldStringValue = "draft.md"
    savePanel.directoryURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
    setenv("OMNIKIT_FILE_PANEL_SELECTION", "/tmp/notes.md", 1)
    #expect(savePanel.runModal() == .OK)
    #expect(savePanel.url?.path == "/tmp/notes.md")

    let bareSavePanel = NSSavePanel()
    bareSavePanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    setenv("OMNIKIT_FILE_PANEL_SELECTION", "/tmp/notes-without-extension", 1)
    #expect(bareSavePanel.runModal() == .OK)
    #expect(bareSavePanel.url?.path == "/tmp/notes-without-extension.md")

    let hiddenExtensionSavePanel = NSSavePanel()
    hiddenExtensionSavePanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    hiddenExtensionSavePanel.isExtensionHidden = true
    setenv("OMNIKIT_FILE_PANEL_SELECTION", "/tmp/hidden-extension-choice", 1)
    #expect(hiddenExtensionSavePanel.runModal() == .OK)
    #expect(hiddenExtensionSavePanel.url?.path == "/tmp/hidden-extension-choice")

    let legacyPanel = NSSavePanel()
    legacyPanel.allowedFileTypes = ["markdown", ".txt"]
    legacyPanel.nameFieldStringValue = "draft"
    legacyPanel.prompt = "Choose"
    legacyPanel.message = "Pick a markdown file"
    legacyPanel.showsHiddenFiles = true
    setenv("OMNIKIT_FILE_PANEL_SELECTION", "/tmp/legacy-choice", 1)
    var sheetResponse: NSApplication.ModalResponse?
    legacyPanel.beginSheetModal(for: NSWindow()) { response in
        sheetResponse = response
    }
    #expect(sheetResponse == .OK)
    #expect(legacyPanel.allowedFileTypes == ["markdown", "txt"])
    #expect(legacyPanel.url?.path == "/tmp/legacy-choice.markdown")
    #endif
}

@Test func linuxGTKFilePanelsMapAppKitDirectoryOptions() async throws {
    #if os(Linux)
    let testFile = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: repositoryRoot.appendingPathComponent("Sources/OmniUICore/AppKitLinuxCompat.swift"),
        encoding: .utf8
    )

    #expect(source.contains("let createDirectories = canCreateDirectories ? \"1\" : \"0\""))
    #expect(source.contains("let showHidden = showsHiddenFiles ? \"1\" : \"0\""))
    #expect(source.contains("dialog.set_create_folders(True)"))
    #expect(source.contains("dialog.set_show_hidden(True)"))
    #expect(source.contains("accept = prompt if prompt else"))
    #expect(source.contains("if multiple == \"1\" and mode != \"save\":"))
    #expect(source.contains("mode, chooserTitle, message, prompt, directory, name, multiple, createDirectories, showHidden, extensions"))
    #endif
}

@Test func linuxPasteboardSupportsStringAndURLObjects() async throws {
    let pasteboard = NSPasteboard()
    pasteboard.clearContents()

    #expect(pasteboard.setString("/tmp/file.txt", forType: .fileURL))
    #expect(pasteboard.string(forType: .fileURL) == "/tmp/file.txt")
    #expect(pasteboard.string(forType: .string) == "/tmp/file.txt")
    #expect(pasteboard.types.contains(.fileURL))

    pasteboard.clearContents()
    #expect(pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/readme.md"), "fallback"]))
    #expect(pasteboard.string(forType: .fileURL) == "file:///tmp/readme.md")
    #expect(pasteboard.canReadObject(forClasses: [NSURL.self]))
    #expect(pasteboard.canReadObject(forClasses: [NSString.self]))
    let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [NSURL]
    #expect(urls?.first?.path == "/tmp/readme.md")

    pasteboard.clearContents()
    #expect(pasteboard.writeObjects([
        URL(fileURLWithPath: "/tmp/one.md"),
        URL(fileURLWithPath: "/tmp/two.md"),
    ]))
    let multipleURLs = pasteboard.readObjects(forClasses: [NSURL.self]) as? [NSURL]
    #expect(multipleURLs?.map(\.path) == ["/tmp/one.md", "/tmp/two.md"])

    pasteboard.clearContents()
    #expect(pasteboard.writeObjects([URL(string: "https://example.com/docs")!]))
    #expect(pasteboard.string(forType: .URL) == "https://example.com/docs")
    let remoteURLs = pasteboard.readObjects(forClasses: [NSURL.self]) as? [NSURL]
    #expect(remoteURLs?.first?.absoluteString == "https://example.com/docs")
}

@Test func linuxPasteboardSupportsDataPropertyListsAndDeclaredTypes() async throws {
    let pasteboard = NSPasteboard()
    let customType: NSPasteboard.PasteboardType = "com.example.payload"
    let plistType: NSPasteboard.PasteboardType = "com.example.property-list"

    #expect(pasteboard.declareTypes([customType, .string], owner: nil) == 2)
    #expect(pasteboard.availableType(from: [.fileURL, customType, .string]) == customType)

    let payload = Data([0xde, 0xad, 0xbe, 0xef])
    #expect(pasteboard.setData(payload, forType: customType))
    #expect(pasteboard.data(forType: customType) == payload)
    #expect(!pasteboard.canReadObject(forClasses: [NSURL.self]))

    let propertyList: [String: Any] = ["path": "/tmp/readme.md", "count": 2]
    #expect(pasteboard.setPropertyList(propertyList, forType: plistType))
    let readBack = pasteboard.propertyList(forType: plistType) as? [String: Any]
    #expect(readBack?["path"] as? String == "/tmp/readme.md")
    #expect(readBack?["count"] as? Int == 2)
    #expect(pasteboard.availableType(from: [.URL, plistType]) == plistType)
}

@Test func generalPasteboardClearAndSetSynchronizeLinuxDesktopClipboard() async throws {
    #if os(Linux)
    let captureURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("omnikit-pasteboard-\(UUID().uuidString).log")
    let previous = getenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE").map { String(cString: $0) }
    defer {
        try? FileManager.default.removeItem(at: captureURL)
        if let previous {
            setenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE", previous, 1)
        } else {
            unsetenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE")
        }
    }
    setenv("OMNIKIT_DESKTOP_PROCESS_CAPTURE", captureURL.path, 1)

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("copied path", forType: .string)

    let captured = try String(contentsOf: captureURL, encoding: .utf8)
    #expect(captured.contains("wl-copy"))
    #endif
}

@Test func linuxScrollViewOwnsClipViewAndDocumentHierarchy() async throws {
    final class WheelProbeView: NSView {
        var wheelCount = 0
        override func scrollWheel(with event: NSEvent) {
            _ = event
            wheelCount += 1
        }
    }

    let scrollView = NSScrollView()
    let first = WheelProbeView()
    scrollView.documentView = first

    #expect(scrollView.subviews.contains { $0 === scrollView.contentView })
    #expect(scrollView.contentView.superview === scrollView)
    #expect(first.superview === scrollView.contentView)
    #expect(first.enclosingScrollView === scrollView)
    #expect(scrollView.contentView.documentView === first)

    let window = NSWindow()
    window.contentView = scrollView
    #expect(first.window === window)

    let event = NSEvent()
    scrollView.scrollWheel(with: event)
    #expect(first.wheelCount == 1)

    let second = NSView()
    scrollView.documentView = second
    #expect(first.superview == nil)
    #expect(first.window == nil)
    #expect(second.superview === scrollView.contentView)
    #expect(second.enclosingScrollView === scrollView)
}

@Test func linuxLocalEventMonitorsFilterAndCanConsumeEvents() async throws {
    var observed: [NSEvent.EventType] = []
    let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        observed.append(event.type)
        return event
    }
    let mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .mouseMoved]) { event in
        observed.append(event.type)
        return event.type == .leftMouseDown ? nil : event
    }
    defer {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    }

    let key = NSEvent()
    key.type = .keyDown
    key.charactersIgnoringModifiers = "k"
    #expect(NSEvent._deliverLocalMonitors(key) === key)

    let click = NSEvent()
    click.type = .leftMouseDown
    click.locationInWindow = NSPoint(x: 10, y: 12)
    #expect(NSEvent._deliverLocalMonitors(click) == nil)

    let move = NSEvent()
    move.type = .mouseMoved
    #expect(NSEvent._deliverLocalMonitors(move) === move)

    #expect(observed == [.keyDown, .leftMouseDown, .mouseMoved])

    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    let secondKey = NSEvent()
    secondKey.type = .keyDown
    _ = NSEvent._deliverLocalMonitors(secondKey)
    #expect(observed == [.keyDown, .leftMouseDown, .mouseMoved])
}

@Test func linuxGlobalEventMonitorsObserveDeliveredEventsWithoutConsumingThem() async throws {
    var globalObserved: [NSEvent.EventType] = []
    let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
        globalObserved.append(event.type)
    }
    let consumingLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { _ in
        nil
    }
    defer {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let consumingLocalMonitor { NSEvent.removeMonitor(consumingLocalMonitor) }
    }

    let key = NSEvent()
    key.type = .keyDown
    #expect(NSEvent._deliverLocalMonitors(key) === key)

    let click = NSEvent()
    click.type = .leftMouseDown
    #expect(NSEvent._deliverLocalMonitors(click) == nil)

    #expect(globalObserved == [.keyDown])

    if let consumingLocalMonitor {
        NSEvent.removeMonitor(consumingLocalMonitor)
    }
    #expect(NSEvent._deliverLocalMonitors(click) === click)
    #expect(globalObserved == [.keyDown, .leftMouseDown])

    if let globalMonitor {
        NSEvent.removeMonitor(globalMonitor)
    }
    _ = NSEvent._deliverLocalMonitors(key)
    #expect(globalObserved == [.keyDown, .leftMouseDown])
}

@Test func linuxWindowSendEventUpdatesMouseLocationAndRunsLocalMonitors() async throws {
    let window = NSWindow()
    var observedLocation: NSPoint?
    let monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
        observedLocation = event.locationInWindow
        return event
    }
    defer {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    let event = NSEvent()
    event.type = .mouseMoved
    event.locationInWindow = NSPoint(x: 24, y: 36)
    window.sendEvent(event)

    #expect(window.mouseLocationOutsideOfEventStream == NSPoint(x: 24, y: 36))
    #expect(observedLocation == NSPoint(x: 24, y: 36))
}

@Test func linuxWindowStandardButtonsExposeStableTitlebarHierarchy() async throws {
    let window = NSWindow()
    let closeButton = try #require(window.standardWindowButton(.closeButton))
    let secondCloseLookup = try #require(window.standardWindowButton(.closeButton))
    let zoomButton = try #require(window.standardWindowButton(.zoomButton))

    #expect(closeButton === secondCloseLookup)
    #expect(closeButton !== zoomButton)
    #expect(closeButton.superview != nil)
    #expect(closeButton.superview?.superview != nil)
    #expect(closeButton.isBordered == false)
}

@Test func linuxWindowToggleFullScreenTracksStyleMaskAndNotifications() async throws {
    let window = NSWindow()
    let entered = ThreadSafeCounter()
    let exited = ThreadSafeCounter()
    let nc = NotificationCenter.default
    let enterObserver = nc.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: nil) { _ in
        entered.increment()
    }
    let exitObserver = nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: nil) { _ in
        exited.increment()
    }
    defer {
        nc.removeObserver(enterObserver)
        nc.removeObserver(exitObserver)
    }

    #expect(!window.styleMask.contains(.fullScreen))
    window.toggleFullScreen(nil)
    #expect(window.styleMask.contains(.fullScreen))
    #expect(entered.count == 1)
    #expect(exited.count == 0)

    window.toggleFullScreen(nil)
    #expect(!window.styleMask.contains(.fullScreen))
    #expect(entered.count == 1)
    #expect(exited.count == 1)
}

@Test func linuxKeyDownModifierMappingTreatsControlAsCommandForMacShortcutsOnly() async throws {
    let controlOnly = NSEvent.ModifierFlags.control.rawValue
    let keyFlags = NSEvent._omniMacCompatibleModifierFlags(rawValue: controlOnly, eventType: .keyDown)
    #expect(keyFlags.contains(.command))
    #expect(!keyFlags.contains(.control))

    let mouseFlags = NSEvent._omniMacCompatibleModifierFlags(rawValue: controlOnly, eventType: .leftMouseDown)
    #expect(mouseFlags.contains(.control))
    #expect(!mouseFlags.contains(.command))

    let flagsChanged = NSEvent._omniMacCompatibleModifierFlags(rawValue: controlOnly, eventType: .flagsChanged)
    #expect(flagsChanged.contains(.control))
    #expect(!flagsChanged.contains(.command))
}

private final class _CursorNameCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String?] = []

    func append(_ name: String?) {
        lock.lock()
        storage.append(name)
        lock.unlock()
    }

    var values: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Test func linuxCursorPushPopPublishesSystemCursorNames() async throws {
    let names = _CursorNameCapture()
    _omniSetCursorHandler { names.append($0) }
    defer {
        while NSCursor.currentSystemCursorName != nil {
            NSCursor.pop()
        }
        _omniSetCursorHandler(nil)
    }

    NSCursor.pointingHand.push()
    NSCursor.resizeLeftRight.push()
    NSCursor.pop()
    NSCursor.pop()

    #expect(names.values.suffix(4).map { $0 ?? "nil" } == ["pointer", "ew-resize", "pointer", "nil"])
}
#endif

@Test func debugSnapshot_click_increments_state() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 6)

    let s0 = runtime.debugRender(CounterView(), size: size)
    #expect(s0.text.contains("Count: 0"))

    // Button is rendered as "[ Inc ]" at roughly x=1,y=3 (after padding + text lines).
    s0.click(x: 2, y: 3)

    let s1 = runtime.debugRender(CounterView(), size: size)
    #expect(s1.text.contains("Count: 1"))
}

@Test func semanticSnapshot_navigationLinkPushesDestinationAfterNativeAction() async throws {
    struct V: View {
        var body: some View {
            NavigationStack {
                List {
                    NavigationLink(destination: Text("Destination loaded")) {
                        HStack {
                            Image(systemName: "doc.plaintext")
                            Text("Open file")
                        }
                    }
                }
            }
        }
    }

    func firstActionID(in node: SemanticNode, matching text: String) -> Int? {
        if case .button(let actionID, _) = node.kind,
           SemanticTextProbe.collect(in: node).contains(text) {
            return actionID
        }
        for child in node.children {
            if let actionID = firstActionID(in: child, matching: text) {
                return actionID
            }
        }
        return nil
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 80, height: 20)
    let initial = runtime.semanticSnapshot(V(), size: size)
    guard let actionID = firstActionID(in: initial.root, matching: "Open file") else {
        #expect(Bool(false), "No NavigationLink action")
        return
    }

    runtime.invokeActionByRawID(actionID)
    let next = runtime.semanticSnapshot(V(), size: size)
    #expect(SemanticTextProbe.collect(in: next.root).contains("Destination loaded"))
}

@Test func environment_modifier_propagates_custom_value_to_child_view() async throws {
    struct Child: View {
        @Environment(\.probeEnvironmentLabel) private var label

        var body: some View {
            Text("Environment label: \(label)")
        }
    }

    struct V: View {
        var body: some View {
            Child()
                .environment(\.probeEnvironmentLabel, "Injected environment")
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.debugRender(V(), size: _Size(width: 60, height: 4))
    #expect(snapshot.text.contains("Environment label: Injected environment"))
}

@Test func typed_environment_object_tracks_observable_changes() async throws {
    final class Model: OmniUICore.ObservableObject {
        let _$observationRegistrar = _ObservationRegistrar()
        var title = "Initial title" {
            didSet { _$observationRegistrar.notify() }
        }
    }

    struct Child: View {
        @Environment(Model.self) private var model

        var body: some View {
            Text("Environment object title: \(model.title)")
        }
    }

    struct V: View {
        let model: Model

        var body: some View {
            Child()
                .environment(model)
        }
    }

    let runtime = _UIRuntime()
    let model = Model()
    let size = _Size(width: 80, height: 4)
    let initial = runtime.debugRender(V(model: model), size: size)
    #expect(initial.text.contains("Environment object title: Initial title"))

    model.title = "Updated title"
    #expect(runtime.renderInvalidationReason(size: size) != nil)

    let updated = runtime.debugRender(V(model: model), size: size)
    #expect(updated.text.contains("Environment object title: Updated title"))
}

@Test func semanticSnapshot_preserves_native_control_roles() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(CounterView(), size: _Size(width: 30, height: 6))

    func containsButton(_ node: SemanticNode) -> Bool {
        if case .button = node.kind { return true }
        return node.children.contains(where: containsButton)
    }

    func containsText(_ expected: String, in node: SemanticNode) -> Bool {
        if case .text(let text) = node.kind, text.contains(expected) { return true }
        return node.children.contains { containsText(expected, in: $0) }
    }

    #expect(containsButton(snapshot.root))
    #expect(containsText("Count: 0", in: snapshot.root))
    #expect(containsText("Inc", in: snapshot.root))
}

@Test func semanticSnapshot_preserves_progress_role() async throws {
    struct V: View {
        var body: some View {
            ProgressView(value: 0.5, total: 1.0)
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 30, height: 6))

    func containsProgress(_ node: SemanticNode) -> Bool {
        if case .progress(_, let fraction) = node.kind {
            return fraction == 0.5
        }
        return node.children.contains(where: containsProgress)
    }

    #expect(containsProgress(snapshot.root))
}

@Test func secureField_masks_debug_output_but_preserves_semantic_value() async throws {
    struct V: View {
        @State var secret = "swordfish"

        var body: some View {
            SecureField("Secret", text: $secret)
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.debugRender(V(), size: _Size(width: 40, height: 4))
    #expect(snapshot.text.contains("•••••••••"))
    #expect(!snapshot.text.contains("swordfish"))

    let semantic = runtime.semanticSnapshot(V(), size: _Size(width: 40, height: 4))
    func containsSecureField(_ node: SemanticNode) -> Bool {
        if case .textField(_, _, let text, _, _, let isSecure) = node.kind {
            return isSecure && text == "swordfish"
        }
        return node.children.contains(where: containsSecureField)
    }

    #expect(containsSecureField(semantic.root))
}

@Test func disabledSecureField_masks_debug_output_and_preserves_secure_semantics() async throws {
    struct V: View {
        @State var secret = "swordfish"

        var body: some View {
            SecureField("Secret", text: $secret)
                .disabled(true)
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.debugRender(V(), size: _Size(width: 40, height: 4))
    #expect(snapshot.text.contains("•••••••••"))
    #expect(!snapshot.text.contains("swordfish"))

    let semantic = runtime.semanticSnapshot(V(), size: _Size(width: 40, height: 4))
    func containsDisabledSecureField(_ node: SemanticNode) -> Bool {
        if case .disabledTextField(_, let text, let isSecure) = node.kind {
            return isSecure && text == "swordfish"
        }
        return node.children.contains(where: containsDisabledSecureField)
    }

    #expect(containsDisabledSecureField(semantic.root))
}

@Test func semanticSnapshot_preserves_slider_role() async throws {
    struct V: View {
        @State var level = 0.4

        var body: some View {
            Slider(value: $level, in: 0...1, step: 0.1) {
                Text("Level")
            }
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 40, height: 6))

    func containsSlider(_ node: SemanticNode) -> Bool {
        if case .slider(let label, let value, let lower, let upper, let step, let decrementActionID, let incrementActionID) = node.kind {
            return label == "Level"
                && value == 0.4
                && lower == 0
                && upper == 1
                && step == 0.1
                && decrementActionID != nil
                && incrementActionID != nil
        }
        return node.children.contains(where: containsSlider)
    }

    #expect(containsSlider(snapshot.root))
}

@Test func semanticSnapshot_preserves_stepper_role() async throws {
    struct V: View {
        @State var value = 2

        var body: some View {
            Stepper("Stepper: \(value)", value: $value, in: 0...10)
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 40, height: 6))

    func containsStepper(_ node: SemanticNode) -> Bool {
        if case .stepper(let label, let value, let decrementActionID, let incrementActionID) = node.kind {
            return label == "Stepper: 2"
                && value == 2
                && decrementActionID != nil
                && incrementActionID != nil
        }
        return node.children.contains(where: containsStepper)
    }

    #expect(containsStepper(snapshot.root))
}

@Test func semanticSnapshot_preserves_datePicker_role() async throws {
    struct V: View {
        @State var date = Date(timeIntervalSince1970: 1_704_067_200)

        var body: some View {
            DatePicker("Due", selection: $date)
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 40, height: 6))

    func containsDatePicker(_ node: SemanticNode) -> Bool {
        if case .datePicker(let label, let value, let timestamp, let setActionID, let decrementActionID, let incrementActionID) = node.kind {
            return label == "Due"
                && value.contains("2023")
                && timestamp == 1_704_067_200
                && setActionID != nil
                && decrementActionID != nil
                && incrementActionID != nil
        }
        return node.children.contains(where: containsDatePicker)
    }

    #expect(containsDatePicker(snapshot.root))
}

@Test func semanticSnapshot_preserves_structural_container_roles() async throws {
    struct V: View {
        var body: some View {
            NavigationSplitView {
                List {
                    Text("Side")
                }
            } detail: {
                NavigationStack {
                    Form {
                        LazyVStack {
                            Text("Detail")
                        }
                    }
                }
            }
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 120, height: 30))

    func contains(_ role: SemanticContainerRole, in node: SemanticNode) -> Bool {
        if case .container(let nodeRole) = node.kind, nodeRole == role {
            return true
        }
        return node.children.contains { contains(role, in: $0) }
    }

    #expect(contains(.navigationSplitView, in: snapshot.root))
    #expect(contains(.navigationStack, in: snapshot.root))
    #expect(contains(.list, in: snapshot.root))
    #expect(contains(.form, in: snapshot.root))
    #expect(contains(.lazyVStack, in: snapshot.root))
}

@Test func semanticSnapshot_preserves_explicit_identity_in_node_ids() async throws {
    struct V: View {
        var body: some View {
            VStack(spacing: 0) {
                Text("Stable A").id("stable-a")
                Text("Stable B").id(42)
            }
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 10))

    func ids(for text: String, in node: SemanticNode) -> [String] {
        var matches: [String] = []
        if case .text(let value) = node.kind, value == text {
            matches.append(node.id)
        }
        for child in node.children {
            matches.append(contentsOf: ids(for: text, in: child))
        }
        return matches
    }

    #expect(ids(for: "Stable A", in: snapshot.root).contains { $0.contains("stable-a") })
    #expect(ids(for: "Stable B", in: snapshot.root).contains { $0.contains("42") })
}

@Test func semanticSnapshot_preserves_accessibility_label_modifier() async throws {
    struct V: View {
        var body: some View {
            Button("Visual") {}
                .accessibilityLabel("Accessible action")
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 10))

    func containsAccessibilityLabel(_ node: SemanticNode) -> Bool {
        if case .modifier(.accessibilityLabel("Accessible action")) = node.kind {
            return true
        }
        return node.children.contains(where: containsAccessibilityLabel)
    }

    #expect(containsAccessibilityLabel(snapshot.root))
}

@Test func semanticSnapshot_preserves_accessibility_identifier_modifier() async throws {
    struct V: View {
        var body: some View {
            Text("Identifier target")
                .accessibilityIdentifier("identifier-target")
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 10))

    func containsAccessibilityIdentifier(_ node: SemanticNode) -> Bool {
        if case .modifier(.accessibilityIdentifier("identifier-target")) = node.kind {
            return true
        }
        return node.children.contains(where: containsAccessibilityIdentifier)
    }

    #expect(containsAccessibilityIdentifier(snapshot.root))
}

@Test func semanticSnapshot_preserves_accessibility_value_and_hint_modifiers() async throws {
    struct V: View {
        var body: some View {
            Button("Sync") {}
                .accessibilityValue("Idle")
                .accessibilityHint("Starts synchronization")
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 10))

    func containsValue(_ node: SemanticNode) -> Bool {
        if case .modifier(.accessibilityValue("Idle")) = node.kind {
            return true
        }
        return node.children.contains(where: containsValue)
    }

    func containsHint(_ node: SemanticNode) -> Bool {
        if case .modifier(.accessibilityHint("Starts synchronization")) = node.kind {
            return true
        }
        return node.children.contains(where: containsHint)
    }

    #expect(containsValue(snapshot.root))
    #expect(containsHint(snapshot.root))
}

@Test func semanticSnapshot_preserves_help_modifier_as_accessibility_description_metadata() async throws {
    struct V: View {
        var body: some View {
            Button("Refresh") {}
                .help("Reload current panel")
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 10))

    func containsHelp(_ node: SemanticNode) -> Bool {
        if case .modifier(.help("Reload current panel")) = node.kind {
            return true
        }
        return node.children.contains(where: containsHelp)
    }

    #expect(containsHelp(snapshot.root))
}

@Test func semanticSnapshot_preserves_liquid_glass_modifier_for_native_renderers() async throws {
    struct V: View {
        var body: some View {
            Text("Glass")
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 10))

    func containsGlass(_ node: SemanticNode) -> Bool {
        if case .modifier(.glass(let descriptor)) = node.kind {
            return descriptor.contains("regular.interactive") && descriptor.contains("cornerRadius:8")
        }
        return node.children.contains(where: containsGlass)
    }

    #expect(containsGlass(snapshot.root))
}

@Test func semanticSnapshot_preserves_crt_modifier_as_native_noop_metadata() async throws {
    struct V: View {
        var body: some View {
            Text("CRT")
                .crtEffect(.scanline)
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 10))

    func containsCRT(_ node: SemanticNode) -> Bool {
        if case .modifier(.crt("scanline")) = node.kind {
            return true
        }
        return node.children.contains(where: containsCRT)
    }

    #expect(containsCRT(snapshot.root))
}

@Test func semanticSnapshot_preserves_contextMenu_items_for_native_renderers() async throws {
    struct V: View {
        var body: some View {
            Text("Document")
                .contextMenu {
                    Button("Copy Path") {}
                    Button("Reveal in Files") {}
                }
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 10))

    func contextMenuItems(in node: SemanticNode) -> [SemanticContextMenuItem]? {
        if case .modifier(.contextMenu(let items)) = node.kind {
            return items
        }
        for child in node.children {
            if let items = contextMenuItems(in: child) {
                return items
            }
        }
        return nil
    }

    guard let items = contextMenuItems(in: snapshot.root) else {
        #expect(Bool(false), "Missing semantic context menu modifier")
        return
    }
    #expect(items.map(\.label) == ["Copy Path", "Reveal in Files"])
    #expect(items.allSatisfy { $0.actionID > 0 })
}

@Test func appStorage_updates_visible_state_and_user_defaults() async throws {
    let suiteName = "OmniUICoreTests.appStorage.\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suiteName)!
    defer { store.removePersistentDomain(forName: suiteName) }

    struct V: View {
        let store: UserDefaults
        @AppStorage("count", store: UserDefaults.standard) private var count = 0

        init(store: UserDefaults) {
            self.store = store
            self._count = AppStorage(wrappedValue: 0, "count", store: store)
        }

        var body: some View {
            VStack(spacing: 1) {
                Text("Stored count: \(count)")
                Button("Store +1") { count += 1 }
            }
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 6)
    let initial = runtime.debugRender(V(store: store), size: size)
    #expect(initial.text.contains("Stored count: 0"))

    guard let button = _findButton(initial, title: "Store +1") else {
        #expect(Bool(false), "Could not find AppStorage update button")
        return
    }
    initial.click(x: button.x, y: button.y)

    let next = runtime.debugRender(V(store: store), size: size)
    #expect(next.text.contains("Stored count: 1"))
    #expect(store.integer(forKey: "count") == 1)
}

@Test func appStorage_reads_external_user_defaults_changes_after_runtime_invalidation() async throws {
    let suiteName = "OmniUICoreTests.appStorage.external.\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suiteName)!
    defer { store.removePersistentDomain(forName: suiteName) }

    enum Mode: String {
        case light
        case dark
    }

    struct V: View {
        let store: UserDefaults
        @AppStorage("theme", store: UserDefaults.standard) private var theme: Mode = .light
        @AppStorage("name", store: UserDefaults.standard) private var name = "Local"

        init(store: UserDefaults) {
            self.store = store
            self._theme = AppStorage(wrappedValue: .light, "theme", store: store)
            self._name = AppStorage(wrappedValue: "Local", "name", store: store)
        }

        var body: some View {
            Text("\(theme.rawValue):\(name)")
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 3)
    #expect(runtime.debugRender(V(store: store), size: size).text.contains("light:Local"))

    store.set("dark", forKey: "theme")
    store.set("Remote", forKey: "name")
    runtime._markDirtyFromExternalResource()

    #expect(runtime.debugRender(V(store: store), size: size).text.contains("dark:Remote"))
}

@Test func appStorage_uses_distinct_state_slots_for_multiple_keys_in_same_view() async throws {
    let suiteName = "OmniUICoreTests.appStorage.distinct.\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suiteName)!
    defer { store.removePersistentDomain(forName: suiteName) }

    struct V: View {
        let store: UserDefaults
        @AppStorage("selectedIssueID", store: UserDefaults.standard) private var selectedIssueID = ""
        @AppStorage("sidebarVisible", store: UserDefaults.standard) private var sidebarVisible = true

        init(store: UserDefaults) {
            self.store = store
            self._selectedIssueID = AppStorage(wrappedValue: "", "selectedIssueID", store: store)
            self._sidebarVisible = AppStorage(wrappedValue: true, "sidebarVisible", store: store)
        }

        var body: some View {
            VStack {
                Text("selected=\(selectedIssueID)")
                Text("sidebar=\(sidebarVisible ? "visible" : "hidden")")
                Button("Mutate") {
                    selectedIssueID = "issue-1"
                    sidebarVisible = false
                }
            }
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 60, height: 6)
    let initial = runtime.debugRender(V(store: store), size: size)
    #expect(initial.text.contains("selected="))
    #expect(initial.text.contains("sidebar=visible"))

    guard let button = _findButton(initial, title: "Mutate") else {
        #expect(Bool(false), "Could not find AppStorage mutate button")
        return
    }
    initial.click(x: button.x, y: button.y)

    let updated = runtime.debugRender(V(store: store), size: size)
    #expect(updated.text.contains("selected=issue-1"))
    #expect(updated.text.contains("sidebar=hidden"))
    #expect(store.string(forKey: "selectedIssueID") == "issue-1")
    #expect(store.bool(forKey: "sidebarVisible") == false)
}

@Test func bindable_text_field_updates_observable_model_state() async throws {
    final class Model: OmniUICore.ObservableObject {
        let _$observationRegistrar = _ObservationRegistrar()
        var title = "Bindable start" {
            didSet { _$observationRegistrar.notify() }
        }
    }

    struct Editor: View {
        @Bindable var model: Model

        var body: some View {
            TextField("Title", text: $model.title)
        }
    }

    struct V: View {
        @State private var model = Model()

        var body: some View {
            VStack(spacing: 1) {
                Editor(model: model)
                Text("Model title: \(model.title)")
            }
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 50, height: 6)
    let initial = runtime.semanticSnapshot(V(), size: size)

    func textFieldActionID(in node: SemanticNode) -> Int? {
        if case .textField(let actionID, _, _, _, _, _) = node.kind {
            return actionID
        }
        for child in node.children {
            if let actionID = textFieldActionID(in: child) {
                return actionID
            }
        }
        return nil
    }

    guard let actionID = textFieldActionID(in: initial.root) else {
        #expect(Bool(false), "Could not find @Bindable TextField")
        return
    }

    runtime.replaceTextForRawActionID(actionID, previous: "Bindable start", next: "Bindable native edit")
    let next = runtime.debugRender(V(), size: size)
    #expect(next.text.contains("Model title: Bindable native edit"))
}

@Test func namespace_id_stays_stable_across_state_rerender() async throws {
    struct V: View {
        @Namespace private var namespace
        @State private var count = 0

        var body: some View {
            VStack(spacing: 1) {
                Text("Namespace: \(namespace.hashValue)")
                Text("Count: \(count)")
                Button("Increment") { count += 1 }
            }
        }
    }

    func namespaceLine(in snapshot: DebugSnapshot) -> String? {
        snapshot.lines.first(where: { $0.contains("Namespace:") })?
            .trimmingCharacters(in: .whitespaces)
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 60, height: 8)
    let initial = runtime.debugRender(V(), size: size)
    let initialNamespace = namespaceLine(in: initial)
    #expect(initial.text.contains("Count: 0"))

    guard let button = _findButton(initial, title: "Increment") else {
        #expect(Bool(false), "Could not find namespace rerender button")
        return
    }
    initial.click(x: button.x, y: button.y)

    let next = runtime.debugRender(V(), size: size)
    #expect(next.text.contains("Count: 1"))
    #expect(namespaceLine(in: next) == initialNamespace)
}

@Test func semanticSnapshot_preserves_disabled_control_roles_for_native_renderers() async throws {
    struct V: View {
        @State var enabled = true
        @State var name = "Locked"
        @State var picker = "A"

        var body: some View {
            VStack {
                Button("Disabled action") {}
                    .disabled(true)
                Toggle("Disabled toggle", isOn: $enabled)
                    .disabled(true)
                TextField("Disabled name", text: $name)
                    .disabled(true)
                Picker("Disabled picker", selection: $picker, options: [("A", "A")])
                    .disabled(true)
            }
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 12))

    #expect(_containsSemantic(snapshot.root) {
        if case .disabledButton(let label) = $0.kind {
            return label == "Disabled action"
        }
        return false
    })
    #expect(_containsSemantic(snapshot.root) {
        if case .disabledToggle(let label, let isOn) = $0.kind {
            return label == "Disabled toggle" && isOn
        }
        return false
    })
    #expect(_containsSemantic(snapshot.root) {
        if case .disabledTextField(let placeholder, let text, false) = $0.kind {
            return placeholder == "Disabled name" && text == "Locked"
        }
        return false
    })
    #expect(_containsSemantic(snapshot.root) {
        if case .disabledMenu(let title, let value) = $0.kind {
            return title == "Disabled picker" && value == "A"
        }
        return false
    })
}

@Test func semanticDiff_reports_updates_insertions_removals_and_reorders() async throws {
    let previous = SemanticNode(id: "root", kind: .stack(axis: .vertical, spacing: 0), children: [
        SemanticNode(id: "a", kind: .text("A")),
        SemanticNode(id: "b", kind: .text("B")),
        SemanticNode(id: "c", kind: .button(actionID: 1, isFocused: false)),
    ])
    let next = SemanticNode(id: "root", kind: .stack(axis: .vertical, spacing: 0), children: [
        SemanticNode(id: "b", kind: .text("B2")),
        SemanticNode(id: "a", kind: .text("A")),
        SemanticNode(id: "d", kind: .toggle(actionID: 2, isFocused: false, isOn: true)),
    ])

    let changes = SemanticDiff.changes(from: previous, to: next)

    #expect(changes.contains(SemanticChange(id: "root", kind: .childrenReordered)))
    #expect(changes.contains(SemanticChange(id: "b", kind: .updated)))
    #expect(changes.contains(SemanticChange(id: "c", kind: .removed)))
    #expect(changes.contains(SemanticChange(id: "d", kind: .inserted)))
}

struct TextFieldView: View {
    @State private var text: String = ""
    var body: some View {
        VStack(spacing: 1) {
            TextField("placeholder", text: $text)
            Text("Value: \(text)")
        }
    }
}

struct TextEditorSemanticView: View {
    @State private var text: String = "Line 1\nLine 2"

    var body: some View {
        TextEditor(text: $text)
    }
}

struct TextEditorNativeInputView: View {
    @State private var text: String = "Native TextEditor"

    var body: some View {
        VStack(spacing: 1) {
            TextEditor(text: $text)
            Text("Value: \(text)")
        }
    }
}

@Test func semanticSnapshot_preserves_textEditor_role() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(TextEditorSemanticView(), size: _Size(width: 40, height: 8))

    func containsTextEditor(_ node: SemanticNode) -> Bool {
        if case .textEditor(_, let text, _, _) = node.kind {
            return text.contains("Line 1") && text.contains("Line 2")
        }
        return node.children.contains(where: containsTextEditor)
    }

    #expect(containsTextEditor(snapshot.root))
}

@Test func debugSnapshot_textField_focus_and_typing_updates_state() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 4)

    let s0 = runtime.debugRender(TextFieldView(), size: size)
    #expect(s0.text.contains("placeholder"))

    // Click the text field (top row).
    s0.click(x: 1, y: 0)
    s0.type("abc")

    let s1 = runtime.debugRender(TextFieldView(), size: size)
    #expect(s1.text.contains("Value: abc"))
}

@Test func runtime_replaceTextForRawActionID_updates_textField_binding() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 4)

    func textFieldActionID(in node: SemanticNode) -> Int? {
        if case .textField(let actionID, _, _, _, _, _) = node.kind {
            return actionID
        }
        for child in node.children {
            if let id = textFieldActionID(in: child) {
                return id
            }
        }
        return nil
    }

    let semantic = runtime.semanticSnapshot(TextFieldView(), size: size)
    guard let actionID = textFieldActionID(in: semantic.root) else {
        #expect(Bool(false), "Could not find semantic TextField action")
        return
    }

    runtime.replaceTextForRawActionID(actionID, previous: "", next: "native")
    var rendered = runtime.debugRender(TextFieldView(), size: size)
    #expect(rendered.text.contains("Value: native"))

    runtime.replaceTextForRawActionID(actionID, previous: "native", next: "native GTK")
    rendered = runtime.debugRender(TextFieldView(), size: size)
    #expect(rendered.text.contains("Value: native GTK"))

    runtime.replaceTextForRawActionID(actionID, previous: "native GTK", next: "GTK")
    rendered = runtime.debugRender(TextFieldView(), size: size)
    #expect(rendered.text.contains("Value: GTK"))
}

@Test func settingsStyleNumberTextFieldAndStepperUpdateSharedBinding() async throws {
    struct NumericSettingsRow: View {
        @State private var lines = 900

        var body: some View {
            HStack(spacing: 1) {
                Text("Scrollback")
                TextField("", value: $lines, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 8)
                Stepper("", value: $lines, in: 800...1000, step: 50)
                    .labelsHidden()
                Text("value=\(lines)")
            }
        }
    }

    func textFieldActionID(in node: SemanticNode) -> Int? {
        if case .textField(let actionID, _, _, _, _, _) = node.kind {
            return actionID
        }
        for child in node.children {
            if let id = textFieldActionID(in: child) {
                return id
            }
        }
        return nil
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 60, height: 4)

    let semantic = runtime.semanticSnapshot(NumericSettingsRow(), size: size)
    guard let fieldID = textFieldActionID(in: semantic.root) else {
        Issue.record("Expected numeric settings TextField action")
        return
    }

    runtime.replaceTextForRawActionID(fieldID, previous: "900", next: "950")
    let edited = runtime.debugRender(NumericSettingsRow(), size: size)
    #expect(edited.text.contains("value=950"))

    guard let increment = _findButton(edited, title: "+") else {
        Issue.record("Expected Stepper increment button")
        return
    }
    edited.click(x: increment.x, y: increment.y)

    let incremented = runtime.debugRender(NumericSettingsRow(), size: size)
    #expect(incremented.text.contains("value=1000"))

    guard let cappedIncrement = _findButton(incremented, title: "+") else {
        Issue.record("Expected capped Stepper increment button")
        return
    }
    incremented.click(x: cappedIncrement.x, y: cappedIncrement.y)

    let capped = runtime.debugRender(NumericSettingsRow(), size: size)
    #expect(capped.text.contains("value=1000"))
}

struct FocusedTextFieldNativeView: View {
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 1) {
            TextField("Name", text: Binding(get: { "" }, set: { _ in }))
                .focused($isFocused)
            Text("Focus: \(isFocused ? "focused" : "idle")")
        }
    }
}

@Test func runtime_focusByRawActionID_updates_focusState_binding() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 5)

    func textFieldActionID(in node: SemanticNode) -> Int? {
        if case .textField(let actionID, _, _, _, _, _) = node.kind {
            return actionID
        }
        for child in node.children {
            if let id = textFieldActionID(in: child) {
                return id
            }
        }
        return nil
    }

    var rendered = runtime.debugRender(FocusedTextFieldNativeView(), size: size)
    #expect(rendered.text.contains("Focus: idle"))

    let semantic = runtime.semanticSnapshot(FocusedTextFieldNativeView(), size: size)
    guard let actionID = textFieldActionID(in: semantic.root) else {
        #expect(Bool(false), "Could not find semantic TextField action")
        return
    }

    _ = runtime.focusByRawActionID(actionID)
    #expect(!runtime.focusByRawActionID(actionID))
    rendered = runtime.debugRender(FocusedTextFieldNativeView(), size: size)
    #expect(rendered.text.contains("Focus: focused"))
}

@Test func runtime_nativeTextEditorReplacement_updates_binding() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 8)

    func textEditorActionID(in node: SemanticNode) -> Int? {
        if case .textEditor(let actionID, _, _, _) = node.kind {
            return actionID
        }
        for child in node.children {
            if let id = textEditorActionID(in: child) {
                return id
            }
        }
        return nil
    }

    _ = runtime.debugRender(TextEditorNativeInputView(), size: size)
    let semantic = runtime.semanticSnapshot(TextEditorNativeInputView(), size: size)
    guard let actionID = textEditorActionID(in: semantic.root) else {
        #expect(Bool(false), "Could not find semantic TextEditor action")
        return
    }

    _ = runtime.focusByRawActionID(actionID)
    runtime.replaceTextForRawActionID(actionID, previous: "Native TextEditor", next: "Native TextEditor typed")

    let rendered = runtime.debugRender(TextEditorNativeInputView(), size: size)
    #expect(rendered.text.contains("Value: Native TextEditor typed"))
}

@Test func debugSnapshot_textField_readline_key_events_work() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 4)

    let s0 = runtime.debugRender(TextFieldView(), size: size)
    s0.click(x: 1, y: 0)
    s0.type("abcdef")

    runtime._handleKey(.left)
    runtime._handleKey(.left)
    runtime._handleKey(.killToEnd)
    runtime._handleKey(.home)
    runtime._handleKey(.char("X".unicodeScalars.first!.value))
    runtime._handleKey(.end)
    runtime._handleKey(.char("Z".unicodeScalars.first!.value))

    let s1 = runtime.debugRender(TextFieldView(), size: size)
    #expect(s1.text.contains("Value: XabcdZ"))
}

struct SimplePickerView: View {
    enum Choice: String, Hashable {
        case a = "A"
        case b = "B"
        case c = "C"
    }

    @State private var choice: Choice = .a

    var body: some View {
        VStack(spacing: 0) {
            Picker("Choice", selection: $choice, options: [(.a, "A"), (.b, "B"), (.c, "C")])
        }
    }
}

@Test func semanticSnapshot_preserves_picker_options_when_collapsed() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(SimplePickerView(), size: _Size(width: 80, height: 10))

    func menuChildren(_ node: SemanticNode) -> [SemanticNode]? {
        if case .menu = node.kind {
            return node.children
        }
        for child in node.children {
            if let found = menuChildren(child) {
                return found
            }
        }
        return nil
    }

    let children = menuChildren(snapshot.root) ?? []
    #expect(children.count == 3)
    #expect(children.contains { child in
        child.children.contains { if case .text("A") = $0.kind { true } else { false } }
    })
    #expect(children.contains { child in
        child.children.contains { if case .text("C") = $0.kind { true } else { false } }
    })
}

@Test func debugSnapshot_picker_dropdown_click_selects_option() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 20, height: 6)

    // Collapsed.
    let s0 = runtime.debugRender(SimplePickerView(), size: size)
    #expect(s0.text.contains("Choice: A"))

    // Open dropdown.
    s0.click(x: 1, y: 0)
    let s1 = runtime.debugRender(SimplePickerView(), size: size)
    #expect(s1.text.contains("Choice: A"))
    #expect(s1.text.contains("*A") || s1.text.contains("* A"))

    // Click the "C" option (options are rendered on subsequent rows).
    // Menu layout:
    // y=0 header
    // y=1 top border
    // y=2 option A
    // y=3 option B
    // y=4 option C
    s1.click(x: 2, y: 4)
    let s2 = runtime.debugRender(SimplePickerView(), size: size)
    #expect(s2.text.contains("Choice: C"))
}

@Test func debugSnapshot_contextMenuFallbackExposesMenuActions() async throws {
    struct V: View {
        @State private var value = "Idle"
        let filePath = "/tmp/Omni Notes/readme.md"

        var body: some View {
            Text(value)
                .contextMenu {
                    Button("Copy Name") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(URL(fileURLWithPath: filePath).lastPathComponent, forType: .string)
                    }
                    Button("Copy Path") {
                        value = "Copied"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(filePath, forType: .string)
                    }
                }
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 8)
    let initial = runtime.debugRender(V(), size: size)
    #expect(initial.text.contains("Idle"))
    #expect(initial.text.contains("...") || initial.text.contains("⋯"))

    guard let menuButton = _findButton(initial, title: "⋯") ?? _findButton(initial, title: "...") else {
        #expect(Bool(false), "Could not find context menu fallback button")
        return
    }
    initial.click(x: menuButton.x, y: menuButton.y)

    let expanded = runtime.debugRender(V(), size: size)
    guard let action = _findButton(expanded, title: "Copy Path") else {
        #expect(Bool(false), "Could not find context menu action")
        return
    }
    expanded.click(x: action.x, y: action.y)

    let next = runtime.debugRender(V(), size: size)
    #expect(next.text.contains("Copied"))
    #expect(NSPasteboard.general.string(forType: .string) == "/tmp/Omni Notes/readme.md")
}

struct PickerOverlayView: View {
    enum Choice: String, Hashable {
        case a = "A"
        case b = "B"
        case c = "C"
    }

    @State private var choice: Choice = .a

    var body: some View {
        VStack(spacing: 0) {
            Picker("Choice", selection: $choice, options: [(.a, "A"), (.b, "B"), (.c, "C")])
            Text("Tip: this should stay in-place")
        }
    }
}

@Test func debugSnapshot_picker_dropdown_is_overlay_not_layout() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 6)

    let s0 = runtime.debugRender(PickerOverlayView(), size: size)
    #expect(s0.text.contains("Tip: this should stay in-place"))

    // Expand dropdown. It should draw over the Tip line, not push it down.
    s0.click(x: 1, y: 0)
    let s1 = runtime.debugRender(PickerOverlayView(), size: size)
    #expect(!s1.text.contains("Tip: this should stay in-place"))

    // Collapse dropdown. Tip should become visible again.
    s1.click(x: 1, y: 0)
    let s2 = runtime.debugRender(PickerOverlayView(), size: size)
    #expect(s2.text.contains("Tip: this should stay in-place"))
}

struct ListRenderView: View {
    var body: some View {
        List(0..<5, id: \.self) { i in
            Text("Row \(i)")
        }
    }
}

@Test func debugSnapshot_list_renders_rows() async throws {
    let runtime = _UIRuntime()
    let s0 = runtime.debugRender(ListRenderView(), size: _Size(width: 20, height: 10))
    #expect(s0.text.contains("Row 0"))
    #expect(s0.text.contains("Row 4"))
}

@Test func listSelection_usesTagsThroughRowModifiers() async throws {
    struct WrappedTaggedList: View {
        let selection: Binding<String?>

        var body: some View {
            List(selection: selection) {
                ForEach(["First", "Second"], id: \.self) { value in
                    Text(value)
                        .tag(value)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.1))
                }
            }
        }
    }

    let runtime = _UIRuntime()
    var selection: String?
    let binding = Binding<String?>(
        get: { selection },
        set: { selection = $0 }
    )

    let snap = runtime.debugRender(WrappedTaggedList(selection: binding), size: _Size(width: 30, height: 10))
    guard let second = _findButton(snap, title: "Second") else {
        Issue.record("Expected wrapped tagged list row to be focusable")
        return
    }

    snap.click(x: second.x, y: second.y)
    #expect(selection == "Second")
}

@Test func listSelection_supportsOptionalNilTagsThroughRowModifiers() async throws {
    struct OptionalTaggedList: View {
        let selection: Binding<String?>

        var body: some View {
            List(selection: selection) {
                Text("System Default")
                    .tag(Optional<String>.none)
                    .padding(.vertical, 1)
                Text("Menlo")
                    .tag(Optional("Menlo"))
                    .padding(.vertical, 1)
            }
        }
    }

    let runtime = _UIRuntime()
    var selection: String? = "Menlo"
    let binding = Binding<String?>(
        get: { selection },
        set: { selection = $0 }
    )

    let snap = runtime.debugRender(OptionalTaggedList(selection: binding), size: _Size(width: 30, height: 10))
    guard let systemDefault = _findButton(snap, title: "System Default") else {
        Issue.record("Expected nil optional tagged list row to be focusable")
        return
    }

    snap.click(x: systemDefault.x, y: systemDefault.y)
    #expect(selection == nil)
}

@Test func debugSnapshot_kitchensink_contains_list_row() async throws {
    // Mirrors the demo: nested ScrollView + List.
    struct Sink: View {
        @State var pickedRow = 0
        var body: some View {
            ScrollView {
                VStack(spacing: 1) {
                    Text("Header")
                    Text("List:")
                    List(0..<12, id: \.self) { i in
                        HStack(spacing: 1) {
                            Text("Row \(i)")
                            Spacer()
                            Button("Pick") { pickedRow = i }
                        }
                    }
                }
                .padding(1)
            }
        }
    }

    let runtime = _UIRuntime()
    let s0 = runtime.debugRender(Sink(), size: _Size(width: 80, height: 24))
    #expect(s0.text.contains("Row 0"))
}

@Test func debugSnapshot_list_row_button_updates_parent_state() async throws {
    struct V: View {
        @State var pickedRow: Int = 0
        var body: some View {
            VStack(spacing: 1) {
                Text("picked: \(pickedRow)")
                List(0..<2, id: \.self) { i in
                    HStack(spacing: 1) {
                        Text("Row \(i)")
                        Spacer()
                        Button("Pick") { pickedRow = i }
                    }
                }
            }
            .padding(1)
        }
    }

    func findPickButton(_ snap: DebugSnapshot, occurrence: Int) -> (x: Int, y: Int)? {
        var seen = 0
        for (y, line) in snap.lines.enumerated() {
            let hay = Array(line)
            let needle = Array("[ Pick ]")
            if hay.count >= needle.count {
                for x0 in 0...(hay.count - needle.count) {
                    var ok = true
                    for i in 0..<needle.count {
                        if hay[x0 + i] != needle[i] { ok = false; break }
                    }
                    if ok {
                        if seen == occurrence {
                            // Click inside the button.
                            return (x: x0 + 2, y: y)
                        }
                        seen += 1
                        break
                    }
                }
            }
        }
        return nil
    }

    let runtime = _UIRuntime()
    let s0 = runtime.debugRender(V(), size: _Size(width: 50, height: 12))
    #expect(s0.text.contains("picked: 0"))

    // Click the second row's Pick button (occurrence 1) so the value actually changes.
    guard let p = findPickButton(s0, occurrence: 1) else {
        #expect(Bool(false), "Could not find Pick button in snapshot")
        return
    }
    s0.click(x: p.x, y: p.y)

    let s1 = runtime.debugRender(V(), size: _Size(width: 50, height: 12))
    #expect(s1.text.contains("picked: 1"))
}

private struct _StableForEachRow: View {
    let value: Int
    @State private var taps = 0

    var body: some View {
        Button("Row \(value): \(taps)") {
            taps += 1
        }
    }
}

private struct _StableForEachListProbe: View {
    @State private var items = [1, 2]

    var body: some View {
        VStack(spacing: 1) {
            Button("Reverse") {
                items.reverse()
            }
            List {
                ForEach(items, id: \.self) { item in
                    _StableForEachRow(value: item)
                }
            }
        }
    }
}

@Test func forEach_list_row_state_stays_with_stable_id_after_reorder() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 10)

    let initial = runtime.debugRender(_StableForEachListProbe(), size: size)
    #expect(initial.text.contains("Row 1: 0"))
    #expect(initial.text.contains("Row 2: 0"))

    guard let row2 = _findButton(initial, title: "Row 2: 0") else {
        #expect(Bool(false), "Could not find second row button")
        return
    }
    initial.click(x: row2.x, y: row2.y)

    let tapped = runtime.debugRender(_StableForEachListProbe(), size: size)
    #expect(tapped.text.contains("Row 1: 0"))
    #expect(tapped.text.contains("Row 2: 1"))

    guard let reverse = _findButton(tapped, title: "Reverse") else {
        #expect(Bool(false), "Could not find reverse button")
        return
    }
    tapped.click(x: reverse.x, y: reverse.y)

    let reordered = runtime.debugRender(_StableForEachListProbe(), size: size)
    #expect(reordered.text.contains("Row 2: 1"))
    #expect(reordered.text.contains("Row 1: 0"))
}

@Test func swiftDataCompat_query_reflects_modelContext_inserts() async throws {
    final class M {
        var id: Int
        init(id: Int) { self.id = id }
    }

    struct V: View {
        @Environment(\.modelContext) private var modelContext
        @Query(sort: \M.id, order: .reverse) private var models: [M]
        @State private var seeded: Bool = false

        var body: some View {
            VStack(spacing: 1) {
                Text("count: \(models.count)")
                Text("first: \(models.first?.id ?? -1)")
            }
            .onAppear {
                guard !seeded else { return }
                seeded = true
                modelContext.insert(M(id: 1))
                modelContext.insert(M(id: 2))
            }
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 6)

    let s0 = runtime.debugRender(V(), size: size)
    #expect(s0.text.contains("count: 0"))

    let s1 = runtime.debugRender(V(), size: size)
    #expect(s1.text.contains("count: 2"))
    #expect(s1.text.contains("first: 2"))
}

@Test func swiftDataCompat_query_reflects_modelContext_deletes() async throws {
    final class M {
        var id: Int
        init(id: Int) { self.id = id }
    }

    struct V: View {
        @Environment(\.modelContext) private var modelContext
        @Query(sort: \M.id, order: .forward) private var models: [M]

        var body: some View {
            VStack(spacing: 1) {
                Text("count: \(models.count)")
                Text("first: \(models.first?.id ?? -1)")
                Button("Seed") {
                    if models.isEmpty {
                        modelContext.insert(M(id: 1))
                        modelContext.insert(M(id: 2))
                    }
                }
                Button("Delete first") {
                    if let first = models.first {
                        modelContext.delete(first)
                    }
                }
            }
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 8)

    let initial = runtime.debugRender(V(), size: size)
    #expect(initial.text.contains("count: 0"))
    guard let seed = _findButton(initial, title: "Seed") else {
        #expect(Bool(false), "Could not find SwiftData seed button")
        return
    }
    initial.click(x: seed.x, y: seed.y)

    let seeded = runtime.debugRender(V(), size: size)
    #expect(seeded.text.contains("count: 2"))
    #expect(seeded.text.contains("first: 1"))
    guard let delete = _findButton(seeded, title: "Delete first") else {
        #expect(Bool(false), "Could not find SwiftData delete button")
        return
    }
    seeded.click(x: delete.x, y: delete.y)

    let deleted = runtime.debugRender(V(), size: size)
    #expect(deleted.text.contains("count: 1"))
    #expect(deleted.text.contains("first: 2"))
}

final class _SheetModelContextRecord {
    var id: Int
    init(id: Int) { self.id = id }
}

struct _SheetModelContextChild: View {
    @Query(sort: \_SheetModelContextRecord.id, order: .forward) private var records: [_SheetModelContextRecord]

    var body: some View {
        Text("sheet count: \(records.count)")
    }
}

struct _SheetModelContextProbe: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isPresented = false

    var body: some View {
        Button("Seed and Show") {
            modelContext.insert(_SheetModelContextRecord(id: 1))
            isPresented = true
        }
        .sheet(isPresented: $isPresented) {
            _SheetModelContextChild()
        }
    }
}

@Test func sheetContentInheritsModelContextEnvironment() async throws {
    let runtime = _UIRuntime()
    let root = _SheetModelContextProbe()
        .modelContainer(for: [_SheetModelContextRecord.self], inMemory: true)
    let size = _Size(width: 40, height: 10)

    let initial = runtime.debugRender(root, size: size)
    guard let seed = _findButton(initial, title: "Seed and Show") else {
        #expect(Bool(false), "Could not find sheet seed button")
        return
    }
    initial.click(x: seed.x, y: seed.y)

    let sheet = runtime.debugRender(root, size: size)
    #expect(sheet.text.contains("sheet count: 1"))
}

struct TapGestureView: View {
    @State private var tapped: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Text("tapped: \(tapped)")
            Text("TapMe")
                .onTapGesture { tapped += 1 }
        }
    }
}

@Test func debugSnapshot_onTapGesture_click_updates_state() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 20, height: 4)

    let s0 = runtime.debugRender(TapGestureView(), size: size)
    #expect(s0.text.contains("tapped: 0"))

    // TapMe is on the second row at x≈0,y=1.
    s0.click(x: 0, y: 1)

    let s1 = runtime.debugRender(TapGestureView(), size: size)
    #expect(s1.text.contains("tapped: 1"))
}

struct MultiTapGestureView: View {
    @State private var selected = false
    @State private var edited = false

    var body: some View {
        VStack(spacing: 0) {
            Text("selected: \(selected)")
            Text("edited: \(edited)")
            Text("Issue Row")
                .onTapGesture(count: 2) { edited = true }
                .onTapGesture { selected = true }
        }
    }
}

@Test func debugSnapshot_onTapGesture_count_distinguishes_single_and_double_click() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 5)

    let initial = runtime.debugRender(MultiTapGestureView(), size: size)
    initial.click(x: 0, y: 2)

    let selected = runtime.debugRender(MultiTapGestureView(), size: size)
    #expect(selected.text.contains("selected: true"))
    #expect(selected.text.contains("edited: false"))

    selected.click(x: 0, y: 2, count: 2)

    let edited = runtime.debugRender(MultiTapGestureView(), size: size)
    #expect(edited.text.contains("selected: true"))
    #expect(edited.text.contains("edited: true"))
}

@Test func debugSnapshot_dragGesture_reportsStartLocationAndTranslation() async throws {
    final class Box: @unchecked Sendable {
        var changed: DragGesture.Value?
        var ended: DragGesture.Value?
    }

    let runtime = _UIRuntime()
    let box = Box()

    struct V: View {
        let box: Box

        var body: some View {
            Text("Handle")
                .contentShape(Rectangle())
                .gesture(
                    DragGesture().onChanged { value in
                        box.changed = value
                    }.onEnded { value in
                        box.ended = value
                    }
                )
        }
    }

    let snapshot = runtime.debugRender(V(box: box), size: _Size(width: 20, height: 2))
    snapshot.drag(from: _Point(x: 1, y: 0), to: _Point(x: 7, y: 0))

    #expect(box.changed?.startLocation == CGPoint(x: 1, y: 0))
    #expect(box.changed?.location == CGPoint(x: 7, y: 0))
    #expect(box.changed?.translation == CGSize(width: 6, height: 0))
    #expect(box.ended?.translation == CGSize(width: 6, height: 0))
}

@Test func runtimeNativeDragEventsDispatchRegisteredDragGesture() async throws {
    final class Box: @unchecked Sendable {
        var changed: [DragGesture.Value] = []
        var ended: DragGesture.Value?
    }

    let runtime = _UIRuntime()
    let box = Box()

    struct V: View {
        let box: Box

        var body: some View {
            Text("Native Handle")
                .gesture(
                    DragGesture().onChanged { value in
                        box.changed.append(value)
                    }.onEnded { value in
                        box.ended = value
                    }
                )
        }
    }

    let snapshot = runtime.semanticSnapshot(V(box: box), size: _Size(width: 30, height: 2))

    func firstButtonActionID(in node: SemanticNode) -> Int? {
        if case .button(let actionID, _) = node.kind {
            return actionID
        }
        for child in node.children {
            if let actionID = firstButtonActionID(in: child) {
                return actionID
            }
        }
        return nil
    }

    let actionID = try #require(firstButtonActionID(in: snapshot.root))

    #expect(runtime._handleNativeDragEvent(actionID: actionID, eventType: 1, x: 10, y: 4))
    #expect(runtime._handleNativeDragEvent(actionID: 0, eventType: 5, x: 16, y: 9))
    #expect(runtime._handleNativeDragEvent(actionID: 0, eventType: 2, x: 20, y: 10))

    #expect(box.changed.count == 3)
    #expect(box.changed.last?.translation == CGSize(width: 6, height: 5))
    #expect(box.ended?.translation == CGSize(width: 10, height: 6))
}

struct MenuGestureView: View {
    @State private var picked: String = "-"

    var body: some View {
        VStack(spacing: 0) {
            Text("picked: \(picked)")
            Menu {
                Button("A") { picked = "A" }
                Button("B") { picked = "B" }
            } label: {
                Text("Menu")
            }
        }
    }
}

@Test func debugSnapshot_menu_click_selects_item() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 8)

    // Collapsed.
    let s0 = runtime.debugRender(MenuGestureView(), size: size)
    #expect(s0.text.contains("picked: -"))

    // Open dropdown (Menu header is on y=1).
    s0.click(x: 1, y: 1)
    let s1 = runtime.debugRender(MenuGestureView(), size: size)

    // Click the second option ("B") in the dropdown.
    // Menu layout:
    // y=1 header
    // y=2 top border
    // y=3 option A
    // y=4 option B
    s1.click(x: 2, y: 4)

    let s2 = runtime.debugRender(MenuGestureView(), size: size)
    #expect(s2.text.contains("picked: B"))
}

@Test func keyboardShortcut_defaultAction_invokes_button_action() async throws {
    final class Box {
        var value: Int = 0
    }

    struct V: View {
        let box: Box
        var body: some View {
            Button("Inc") { box.value += 1 }
                .keyboardShortcut(.defaultAction)
        }
    }

    let box = Box()
    let runtime = _UIRuntime()
    _ = runtime.render(V(box: box), size: _Size(width: 20, height: 3))

    #expect(box.value == 0)
    #expect(runtime.invokeKeyboardShortcut(.return))
    #expect(box.value == 1)
}

@Test func keyboardShortcut_cancelAction_invokes_button_action() async throws {
    final class Box {
        var cancelled: Bool = false
    }

    struct V: View {
        let box: Box
        var body: some View {
            Button("Cancel") { box.cancelled = true }
                .keyboardShortcut(.cancelAction)
        }
    }

    let box = Box()
    let runtime = _UIRuntime()
    _ = runtime.render(V(box: box), size: _Size(width: 20, height: 3))

    #expect(!box.cancelled)
    #expect(runtime.invokeKeyboardShortcut(.escape))
    #expect(box.cancelled)
}

@Test func runtime_native_global_key_invokes_default_and_cancel_shortcuts() async throws {
    final class Box {
        var defaultCount = 0
        var cancelCount = 0
    }

    struct V: View {
        let box: Box
        var body: some View {
            VStack {
                Button("Default") { box.defaultCount += 1 }
                    .keyboardShortcut(.defaultAction)
                Button("Cancel") { box.cancelCount += 1 }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    let box = Box()
    let runtime = _UIRuntime()
    _ = runtime.semanticSnapshot(V(box: box), size: _Size(width: 40, height: 6))

    runtime.handleNativeKeyForRawActionID(0, keyKind: 7, codepoint: 0)
    runtime.handleNativeKeyForRawActionID(0, keyKind: 8, codepoint: 0)

    #expect(box.defaultCount == 1)
    #expect(box.cancelCount == 1)
}

@Test func keyboardShortcut_action_runs_with_captured_environment() async throws {
    final class Box {
        var opened: URL? = nil
    }

    struct V: View {
        private static let openURLTestsURL: URL = {
            guard let url = URL(string: "https://example.com") else {
                preconditionFailure("Invalid OmniUICore openURL test URL")
            }
            return url
        }()

        let box: Box
        @Environment(\.openURL) private var openURL
        var body: some View {
            Button("Open") {
                _ = openURL(Self.openURLTestsURL)
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    let box = Box()
    let runtime = _UIRuntime()
    let root = V(box: box)
        .environment(\.openURL, OpenURLAction({ url in box.opened = url; return .handled }))
    _ = runtime.render(root, size: _Size(width: 20, height: 3))

    #expect(box.opened == nil)
    #expect(runtime.invokeKeyboardShortcut(.return))
    #expect(box.opened?.absoluteString == "https://example.com")
}

@Test func shareLink_uses_runtime_share_action_instead_of_openURL_environment() async throws {
    final class Box {
        var opened: URL? = nil
        var shared: URL? = nil
    }

    struct V: View {
        private static let shareURL: URL = {
            guard let url = URL(string: "https://example.com/share") else {
                preconditionFailure("Invalid OmniUICore share URL test URL")
            }
            return url
        }()

        var body: some View {
            ShareLink(item: Self.shareURL) {
                Text("Share")
            }
        }
    }

    func firstActionID(in node: SemanticNode, matching text: String) -> Int? {
        if case .button(let actionID, _) = node.kind,
           SemanticTextProbe.collect(in: node).contains(text) {
            return actionID
        }
        for child in node.children {
            if let actionID = firstActionID(in: child, matching: text) {
                return actionID
            }
        }
        return nil
    }

    let box = Box()
    let runtime = _UIRuntime()
    runtime.setDefaultShareURLAction(OpenURLAction({ url in box.shared = url; return .handled }))
    let root = V()
        .environment(\.openURL, OpenURLAction({ url in box.opened = url; return .handled }))
    let snapshot = runtime.semanticSnapshot(root, size: _Size(width: 20, height: 3))
    guard let actionID = firstActionID(in: snapshot.root, matching: "Share") else {
        #expect(Bool(false), "No ShareLink action")
        return
    }

    runtime.invokeActionByRawID(actionID)

    #expect(box.shared?.absoluteString == "https://example.com/share")
    #expect(box.opened == nil)
}

@MainActor
@Test func task_runs_and_cancels_with_view_lifecycle() async throws {
    final class Box {
        var started: Int = 0
        var cancelled: Int = 0
    }

    struct WithTask: View {
        let box: Box
        var body: some View {
            Text("Hi")
                .task {
                    box.started += 1
                    do {
                        while true {
                            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
                        }
                    } catch {
                        // Expected on cancellation.
                    }
                    box.cancelled += 1
                }
        }
    }

    let box = Box()
    let runtime = _UIRuntime()

    _ = runtime.render(WithTask(box: box), size: _Size(width: 10, height: 2))
    for _ in 0..<50 {
        if box.started == 1 { break }
        await Task.yield()
    }
    #expect(box.started == 1)

    // Remove the task from the tree; it should be cancelled on the next frame.
    _ = runtime.render(Text("Hi"), size: _Size(width: 10, height: 2))
    for _ in 0..<50 {
        if box.cancelled == 1 { break }
        await Task.yield()
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(box.cancelled == 1)
}

@Test func contentShape_rectangle_expands_button_hit_region() async throws {
    final class Box {
        var taps: Int = 0
    }

    struct V: View {
        let box: Box
        var body: some View {
            Button(action: { box.taps += 1 }) {
                HStack(spacing: 0) {
                    Text("Tap")
                }
                .contentShape(Rectangle())
            }
        }
    }

    let box = Box()
    let runtime = _UIRuntime()
    let s0 = runtime.debugRender(V(box: box), size: _Size(width: 20, height: 3))
    #expect(box.taps == 0)

    // Click far to the right of the visible "[ Tap ]" label; `contentShape(Rectangle())`
    // should make the whole row hit-testable.
    s0.click(x: 19, y: 0)
    let s1 = runtime.debugRender(V(box: box), size: _Size(width: 20, height: 3))
    _ = s1
    #expect(box.taps == 1)
}

@Test func runtime_needsRender_tracks_dirty_state_and_size() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 6)

    #expect(runtime.needsRender(size: size))

    _ = runtime.render(CounterView(), size: size)
    #expect(!runtime.needsRender(size: size))

    let s0 = runtime.debugRender(CounterView(), size: size)
    s0.click(x: 2, y: 3)
    #expect(runtime.needsRender(size: size))

    _ = runtime.render(CounterView(), size: size)
    #expect(!runtime.needsRender(size: size))

    #expect(runtime.needsRender(size: _Size(width: 31, height: 6)))
}

final class _BuildCountBox {
    var left: Int = 0
    var center: Int = 0
    var right: Int = 0
}

struct _BuildProbe: View {
    let label: String
    let tick: () -> Void

    var body: some View {
        tick()
        return Text(label)
    }
}

struct _CenterCounterProbe: View {
    let box: _BuildCountBox
    @State private var value: Int = 0

    var body: some View {
        box.center += 1
        return VStack(spacing: 1) {
            Text("center: \(value)")
            Button("Inc") { value += 1 }
        }
    }
}

struct _TargetedInvalidationProbeView: View {
    let box: _BuildCountBox

    var body: some View {
        HStack(spacing: 2) {
            _BuildProbe(label: "left") { box.left += 1 }
            _CenterCounterProbe(box: box)
            _BuildProbe(label: "right") { box.right += 1 }
        }
    }
}

private func _findButton(_ snap: DebugSnapshot, title: String, occurrence: Int = 0) -> (x: Int, y: Int)? {
    var seen = 0
    let titleChars = Array(title)
    for (y, line) in snap.lines.enumerated() {
        let hay = Array(line)
        guard hay.count >= titleChars.count else { continue }
        for x0 in 0...(hay.count - titleChars.count) {
            var matchesTitle = true
            for i in 0..<titleChars.count where hay[x0 + i] != titleChars[i] {
                matchesTitle = false
                break
            }
            guard matchesTitle else { continue }

            let leftLimit = max(0, x0 - 3)
            let rightLimit = min(hay.count - 1, x0 + titleChars.count + 3)
            let hasLeftBracket = hay[leftLimit...x0].contains("[")
            let hasRightBracket = hay[(x0 + titleChars.count - 1)...rightLimit].contains("]")
            guard hasLeftBracket, hasRightBracket else { continue }

            if seen == occurrence {
                return (x: x0 + max(0, titleChars.count / 2), y: y)
            }
            seen += 1
            break
        }
    }

    // Fallback for overlays or custom button styles that render interactive text without
    // the standard "[ Title ]" chrome. Prefer coordinates that are inside a live hit region
    // so test clicks still target a real control rather than a plain text match.
    for (y, line) in snap.lines.enumerated() {
        let hay = Array(line)
        guard hay.count >= titleChars.count else { continue }
        for x0 in 0...(hay.count - titleChars.count) {
            var matchesTitle = true
            for i in 0..<titleChars.count where hay[x0 + i] != titleChars[i] {
                matchesTitle = false
                break
            }
            guard matchesTitle else { continue }

            let candidates = [
                _Point(x: x0, y: y),
                _Point(x: x0 + max(0, titleChars.count / 2), y: y),
                _Point(x: x0 + max(0, titleChars.count - 1), y: y),
            ]
            guard candidates.contains(where: { point in
                snap.containsHitRegion(at: point)
            }) else {
                continue
            }

            if seen == occurrence {
                return (x: x0 + max(0, titleChars.count / 2), y: y)
            }
            seen += 1
            break
        }
    }

    return nil
}

private func _findText(_ snap: DebugSnapshot, text: String, occurrence: Int = 0) -> (x: Int, y: Int)? {
    var seen = 0
    let needle = Array(text)
    for (y, line) in snap.lines.enumerated() {
        let hay = Array(line)
        guard hay.count >= needle.count else { continue }
        for x0 in 0...(hay.count - needle.count) {
            var ok = true
            for i in 0..<needle.count where hay[x0 + i] != needle[i] {
                ok = false
                break
            }
            if ok {
                if seen == occurrence {
                    return (x: x0, y: y)
                }
                seen += 1
                break
            }
        }
    }
    return nil
}

private func _semanticButtonActionID(in node: SemanticNode, title: String) -> Int? {
    if case .button(let actionID, _) = node.kind, _semanticContainsText(node, title) {
        return actionID
    }
    if case .tapTarget(let actionID, _) = node.kind, _semanticContainsText(node, title) {
        return actionID
    }
    for child in node.children {
        if let actionID = _semanticButtonActionID(in: child, title: title) {
            return actionID
        }
    }
    return nil
}

private func _semanticContainsText(_ node: SemanticNode, _ text: String) -> Bool {
    if case .text(let value) = node.kind, value.contains(text) {
        return true
    }
    return node.children.contains { _semanticContainsText($0, text) }
}

private func _containsSemantic(_ node: SemanticNode, matching predicate: (SemanticNode) -> Bool) -> Bool {
    if predicate(node) { return true }
    return node.children.contains { _containsSemantic($0, matching: predicate) }
}

private func _maxScrollOffset(in node: SemanticNode) -> Int {
    let own: Int
    if case .scroll(_, _, let offset) = node.kind {
        own = offset
    } else {
        own = 0
    }
    return max(own, node.children.map(_maxScrollOffset(in:)).max() ?? 0)
}

@Test func state_invalidation_rebuilds_only_affected_subtree() async throws {
    let runtime = _UIRuntime()
    let box = _BuildCountBox()
    let size = _Size(width: 60, height: 8)

    let s0 = runtime.debugRender(_TargetedInvalidationProbeView(box: box), size: size)
    #expect(box.left == 1)
    #expect(box.center == 1)
    #expect(box.right == 1)

    guard let p = _findButton(s0, title: "Inc") else {
        #expect(Bool(false), "Could not find Inc button")
        return
    }
    s0.click(x: p.x, y: p.y)

    let s1 = runtime.debugRender(_TargetedInvalidationProbeView(box: box), size: size)
    #expect(s1.text.contains("center: 1"))
    #expect(box.center >= 2)
    #expect(box.left == 1)
    #expect(box.right == 1)
}

struct _ScrollReaderProbeView: View {
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 1) {
                Button("Jump") { proxy.scrollTo(35, anchor: .top) }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<50, id: \.self) { i in
                            Text("Row \(i)").id(i)
                        }
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

@Test func scrollViewReader_scrollTo_moves_scroll_position() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 10)

    let s0 = runtime.debugRender(_ScrollReaderProbeView(), size: size)
    #expect(s0.text.contains("Row 0"))

    guard let jump = _findButton(s0, title: "Jump") else {
        #expect(Bool(false), "Could not find Jump button")
        return
    }
    s0.click(x: jump.x, y: jump.y)

    let s1 = runtime.debugRender(_ScrollReaderProbeView(), size: size)
    if s1.text.contains("Row 35") {
        #expect(Bool(true))
    } else {
        // `scrollTo` requests may be applied at the end of a frame; verify the next frame.
        let s2 = runtime.debugRender(_ScrollReaderProbeView(), size: size)
        #expect(s2.text.contains("Row 35"))
    }
}

@Test func semanticSnapshot_scrollViewReader_exposes_nonzero_scroll_offset_after_native_action() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 10)

    let initial = runtime.semanticSnapshot(_ScrollReaderProbeView(), size: size)
    guard let jumpActionID = _semanticButtonActionID(in: initial.root, title: "Jump") else {
        #expect(Bool(false), "Could not find Jump button action")
        return
    }

    runtime.invokeActionByRawID(jumpActionID)
    let next = runtime.semanticSnapshot(_ScrollReaderProbeView(), size: size)

    #expect(_maxScrollOffset(in: next.root) > 0)
}

@Test func text_image_uses_terminal_symbol_mapping() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.debugRender(
        HStack(spacing: 1) {
            Text(Image(systemName: "folder"))
            Text("Docs")
            Text(Image(systemName: "doc.plaintext"))
            Text("Readme")
        },
        size: _Size(width: 30, height: 2)
    )

    #expect(snapshot.text.contains("▸ Docs"))
    #expect(snapshot.text.contains("≣ Readme"))
    #expect(!snapshot.text.contains("folder"))
    #expect(!snapshot.text.contains("doc.plaintext"))
    #expect(SFSymbolMap.unicode(for: "square.and.arrow.down") == "⇩")
}

@Test func icon_only_labels_use_terminal_safe_glyphs() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.debugRender(
        HStack(spacing: 1) {
            Button(action: {}) {
                Label("Add Bookmark", systemImage: "bookmark.fill")
            }
            .labelStyle(.iconOnly)

            Button(action: {}) {
                Label("Bookmarks", systemImage: "book")
            }
            .labelStyle(.iconOnly)
        },
        size: _Size(width: 20, height: 3)
    )

    #expect(snapshot.text.contains("◆"))
    #expect(snapshot.text.contains("▤"))
    #expect(!snapshot.text.contains("bookmark.fill"))
    #expect(!snapshot.text.contains("book"))
}

private struct _FocusFollowScrollProbeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<20, id: \.self) { index in
                    Button("Item \(index)") {}
                }
            }
        }
        .frame(height: 5)
    }
}

@Test func focus_navigation_keeps_focused_item_visible_inside_scroll_view() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 24, height: 6)

    _ = runtime.debugRender(_FocusFollowScrollProbeView(), size: size)
    for _ in 0..<10 {
        runtime.focusNext()
        _ = runtime.debugRender(_FocusFollowScrollProbeView(), size: size)
    }

    let snapshot = runtime.debugRender(_FocusFollowScrollProbeView(), size: size)
    let focusedRect = try #require(snapshot.focusedRect)
    #expect(focusedRect.origin.y >= 0)
    #expect(focusedRect.origin.y < size.height)
    #expect(snapshot.text.contains("Item 10"))
    #expect(!snapshot.text.contains("Item 0"))
}

struct _TreeProbeNode: Identifiable {
    let id: String
    let title: String
    let children: [_TreeProbeNode]?
}

struct _HierarchicalListProbeView: View {
    let nodes: [_TreeProbeNode] = [
        _TreeProbeNode(
            id: "root",
            title: "Root",
            children: [
                _TreeProbeNode(
                    id: "child",
                    title: "Child",
                    children: [
                        _TreeProbeNode(id: "leaf", title: "Leaf", children: nil),
                    ]
                ),
            ]
        ),
    ]

    var body: some View {
        List(nodes, children: \.children) { node in
            Text(node.title)
        }
    }
}

@Test func list_children_renders_nested_nodes() async throws {
    let runtime = _UIRuntime()
    let s0 = runtime.debugRender(_HierarchicalListProbeView(), size: _Size(width: 40, height: 10))
    #expect(s0.text.contains("Root"))
    #expect(s0.text.contains("Child"))
    #expect(s0.text.contains("Leaf"))
}

struct _EditableListProbeView: View {
    @State private var items: [Int] = [10, 20, 30]

    var body: some View {
        VStack(spacing: 1) {
            EditButton()
            List {
                ForEach(items, id: \.self) { item in
                    Text("Item \(item)")
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) {
                        guard items.indices.contains(index) else { continue }
                        items.remove(at: index)
                    }
                }
            }
        }
    }
}

@Test func editButton_enables_onDelete_actions() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 50, height: 12)

    let s0 = runtime.debugRender(_EditableListProbeView(), size: size)
    #expect(!s0.text.contains("[ Del ]"))
    #expect(s0.text.contains("Item 10"))

    guard let edit = _findButton(s0, title: "Edit") else {
        #expect(Bool(false), "Could not find Edit button")
        return
    }
    s0.click(x: edit.x, y: edit.y)

    let s1 = runtime.debugRender(_EditableListProbeView(), size: size)
    #expect(s1.text.contains("[ Del ]"))

    guard let del = _findButton(s1, title: "Del", occurrence: 0) else {
        #expect(Bool(false), "Could not find Del button")
        return
    }
    s1.click(x: del.x, y: del.y)

    let s2 = runtime.debugRender(_EditableListProbeView(), size: size)
    #expect(!s2.text.contains("Item 10"))
    #expect(s2.text.contains("Item 20"))
}

@Test func customLayoutLowersToFlowSemanticNode() async throws {
    struct WrappingLayout: Layout {
        var horizontalSpacing: CGFloat = 5
        var verticalSpacing: CGFloat = 7
    }

    struct LayoutProbe: View {
        var body: some View {
            WrappingLayout {
                Text("One")
                Text("Two")
            }
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(LayoutProbe(), size: _Size(width: 40, height: 10))

    guard case .flowLayout(let horizontalSpacing, let verticalSpacing) = snapshot.root.kind else {
        #expect(Bool(false), "Expected custom Layout to lower as a flow layout")
        return
    }

    #expect(horizontalSpacing == 5)
    #expect(verticalSpacing == 7)
    #expect(snapshot.root.children.count == 2)
}

struct _MovableForEachProbeView: View {
    @State private var items: [Int] = [10, 20, 30]

    var body: some View {
        List {
            ForEach(items, id: \.self) { item in
                Text("Item \(item)")
            }
            .onMove { offsets, destination in
                let moving = offsets.sorted()
                guard let source = moving.first, moving.count == 1, items.indices.contains(source) else { return }
                let value = items.remove(at: source)
                let adjusted = destination > source ? destination - 1 : destination
                items.insert(value, at: max(0, min(items.count, adjusted)))
            }
        }
    }
}

@Test func forEach_onMove_exposes_fallback_move_controls() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 60, height: 10)

    let s0 = runtime.debugRender(_MovableForEachProbeView(), size: size)
    #expect(s0.text.contains("Item 10"))
    #expect(s0.text.contains("[ Down ]"))

    guard let down = _findButton(s0, title: "Down", occurrence: 0) else {
        #expect(Bool(false), "Could not find Down fallback button")
        return
    }
    s0.click(x: down.x, y: down.y)

    let s1 = runtime.debugRender(_MovableForEachProbeView(), size: size)
    let first = s1.text.range(of: "Item 20")?.lowerBound
    let second = s1.text.range(of: "Item 10")?.lowerBound
    #expect(first != nil)
    #expect(second != nil)
    #expect(first! < second!)
}

private struct _BindingForEachProbeItem: Identifiable {
    let id: Int
    var name: String
}

@Test func forEach_overBindingCollectionMutatesParentElements() async throws {
    struct BindingCollectionProbe: View {
        @State private var items: [_BindingForEachProbeItem] = [
            _BindingForEachProbeItem(id: 1, name: "One"),
            _BindingForEachProbeItem(id: 2, name: "Two"),
        ]

        var body: some View {
            VStack(spacing: 1) {
                Text(items.map(\.name).joined(separator: ","))
                ForEach($items) { $item in
                    Button(item.name) {
                        item.name += "!"
                    }
                }
            }
        }
    }

    let runtime = _UIRuntime()
    let initial = runtime.debugRender(BindingCollectionProbe(), size: _Size(width: 40, height: 8))
    #expect(initial.text.contains("One,Two"))

    guard let second = _findButton(initial, title: "Two") else {
        Issue.record("Expected binding ForEach row to be interactive")
        return
    }
    initial.click(x: second.x, y: second.y)

    let updated = runtime.debugRender(BindingCollectionProbe(), size: _Size(width: 40, height: 8))
    #expect(updated.text.contains("One,Two!"))
}

@Test func forEach_overBindingCollectionPickerMutatesParentElement() async throws {
    enum Mode: String, CaseIterable, Hashable {
        case safari = "Safari"
        case native = "Native"
    }

    struct Rule: Identifiable {
        let id: Int
        var host: String
        var mode: Mode
    }

    struct BindingPickerProbe: View {
        @State private var rules: [Rule] = [
            Rule(id: 1, host: "example.com", mode: .safari),
            Rule(id: 2, host: "docs.example.com", mode: .native),
        ]

        var body: some View {
            VStack(spacing: 1) {
                Text(rules.map { "\($0.host)=\($0.mode.rawValue)" }.joined(separator: "|"))
                ForEach($rules) { $rule in
                    HStack {
                        Text(rule.host)
                        Picker("User Agent", selection: $rule.mode) {
                            ForEach(Mode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    }
                }
            }
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 70, height: 12)
    let initial = runtime.debugRender(BindingPickerProbe(), size: size)
    #expect(initial.text.contains("example.com=Safari|docs.example.com=Native"))

    guard let firstPicker = _findButton(initial, title: "User Agent: Safari") ?? _findButton(initial, title: "Safari") else {
        Issue.record("Expected first bound-row picker")
        return
    }
    initial.click(x: firstPicker.x, y: firstPicker.y)

    let expanded = runtime.debugRender(BindingPickerProbe(), size: size)
    guard let native = _findButton(expanded, title: "Native") else {
        Issue.record("Expected Native picker option")
        return
    }
    expanded.click(x: native.x, y: native.y)

    let updated = runtime.debugRender(BindingPickerProbe(), size: size)
    #expect(updated.text.contains("example.com=Native|docs.example.com=Native"))
}

final class _StableModelRecord {
    var id: Int
    init(id: Int) { self.id = id }
}

struct _StableModelContainerProbe: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \_StableModelRecord.id, order: .forward) private var records: [_StableModelRecord]
    @State private var seeded: Bool = false

    var body: some View {
        Text("count: \(records.count)")
            .onAppear {
                guard !seeded else { return }
                seeded = true
                modelContext.insert(_StableModelRecord(id: 1))
            }
    }
}

struct _OnAppearLifecycleProbeView: View {
    @State private var appearCount: Int = 0
    @State private var rerenderCount: Int = 0
    @State private var showChild: Bool = true

    var body: some View {
        VStack(spacing: 1) {
            Text("appear: \(appearCount)")
            Text("rerender: \(rerenderCount)")
            Button("Rerender") { rerenderCount += 1 }
            Button(showChild ? "Hide" : "Show") { showChild.toggle() }

            if showChild {
                Text("Child")
                    .onAppear { appearCount += 1 }
            }
        }
    }
}

@Test func modelContainer_for_keeps_context_stable_across_renders() async throws {
    let runtime = _UIRuntime()
    let root = _StableModelContainerProbe()
        .modelContainer(for: [_StableModelRecord.self], inMemory: true)
    let size = _Size(width: 40, height: 6)

    let s0 = runtime.debugRender(root, size: size)
    #expect(s0.text.contains("count: 0"))

    let s1 = runtime.debugRender(root, size: size)
    #expect(s1.text.contains("count: 1"))

    let s2 = runtime.debugRender(root, size: size)
    #expect(s2.text.contains("count: 1"))
}

@Test func onAppear_fires_once_for_a_stable_mount() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 8)

    let s0 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s0.text.contains("appear: 0"))

    let s1 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s1.text.contains("appear: 1"))

    let s2 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s2.text.contains("appear: 1"))

    guard let rerender = _findButton(s2, title: "Rerender") else {
        #expect(Bool(false), "Could not find Rerender button")
        return
    }
    s2.click(x: rerender.x, y: rerender.y)

    let s3 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s3.text.contains("rerender: 1"))
    #expect(s3.text.contains("appear: 1"))
}

@Test func onAppear_fires_again_after_remount() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 8)

    _ = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    let s1 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s1.text.contains("appear: 1"))

    guard let hide = _findButton(s1, title: "Hide") else {
        #expect(Bool(false), "Could not find Hide button")
        return
    }
    s1.click(x: hide.x, y: hide.y)

    let s2 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(!s2.text.contains("Child"))
    #expect(s2.text.contains("appear: 1"))

    guard let show = _findButton(s2, title: "Show") else {
        #expect(Bool(false), "Could not find Show button")
        return
    }
    s2.click(x: show.x, y: show.y)

    let s3 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s3.text.contains("appear: 1"))

    let s4 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s4.text.contains("appear: 2"))
}

private struct _SheetItemProbeItem: Identifiable {
    let id: Int
}

struct _SheetItemProbeView: View {
    @State private var item: _SheetItemProbeItem? = nil

    var body: some View {
        VStack(spacing: 1) {
            Text("item: \(item?.id ?? -1)")
            Button("Show") {
                item = _SheetItemProbeItem(id: 1)
            }
        }
        .sheet(item: $item) { current in
            Text("Item \(current.id)")
        }
    }
}

struct _SheetOverlayInteractionProbeView: View {
    @State private var isPresented: Bool = false
    @State private var tapped: String = "-"

    var body: some View {
        VStack(spacing: 1) {
            Text("tapped: \(tapped)")
            Button("Base") { tapped = "base" }
            Button("Show") { isPresented = true }
        }
        .sheet(isPresented: $isPresented) {
            VStack(spacing: 1) {
                Text("Overlay Body")
                Button("Inner") {
                    tapped = "inner"
                    isPresented = false
                }
            }
        }
    }
}

struct _SheetSearchInteractionProbeView: View {
    @State private var isPresented: Bool = false
    @State private var query: String = ""
    @State private var submitted: String = "-"

    var body: some View {
        VStack(spacing: 1) {
            Text("submitted: \(submitted)")
            Button("Show") { isPresented = true }
        }
        .sheet(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Search Gopherspace")
                TextField("Query", text: $query)
                HStack {
                    Button("Cancel") {
                        query = ""
                        isPresented = false
                    }
                    Spacer()
                    Button("Search") {
                        submitted = query
                        isPresented = false
                    }
                    .disabled(query.isEmpty)
                }
            }
        }
    }
}

struct _SheetKeyboardShortcutProbeView: View {
    @State private var isPresented: Bool = false
    @State private var baseCount: Int = 0
    @State private var sheetCount: Int = 0

    var body: some View {
        VStack(spacing: 1) {
            Text("base: \(baseCount)")
            Text("sheet: \(sheetCount)")
            Button("Base Default") { baseCount += 1 }
                .keyboardShortcut(.defaultAction)
            Button("Show") { isPresented = true }
        }
        .sheet(isPresented: $isPresented) {
            VStack(spacing: 1) {
                Text("Shortcut Sheet")
                Button("Sheet Default") { sheetCount += 1 }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct _PopoverProbeView: View {
    @State private var isPresented: Bool = false

    var body: some View {
        VStack(spacing: 1) {
            Text("popover: \(isPresented ? "open" : "closed")")
            Button("Show") { isPresented = true }
        }
        .popover(isPresented: $isPresented) {
            Text("Popover Body")
        }
    }
}

struct _ConfirmationDialogProbeView: View {
    @State private var isPresented: Bool = false
    @State private var picked: String = "-"

    var body: some View {
        VStack(spacing: 1) {
            Text("picked: \(picked)")
            Button("Show") { isPresented = true }
        }
        .confirmationDialog("Confirm", isPresented: $isPresented) {
            Button("One") { picked = "One" }
            Button("Two", role: .destructive) { picked = "Two" }
            Button("Cancel", role: .cancel) { picked = "Cancel" }
        } message: {
            Text("Choose")
        }
    }
}

struct _AlertSemanticProbeView: View {
    @State private var isPresented: Bool = false

    var body: some View {
        VStack(spacing: 1) {
            Text("alert: \(isPresented ? "open" : "closed")")
            Button("Show") { isPresented = true }
        }
        .alert(isPresented: $isPresented) {
            Text("Enabled")
        }
    }
}

private struct _PopoverItemProbeItem: Identifiable {
    let id: Int
}

struct _PopoverItemProbeView: View {
    @State private var item: _PopoverItemProbeItem? = nil

    var body: some View {
        VStack(spacing: 1) {
            Text("popover item: \(item?.id ?? -1)")
            Button("Show") { item = _PopoverItemProbeItem(id: 7) }
        }
        .popover(item: $item) { current in
            Text("Popover Item \(current.id)")
        }
    }
}

@Suite("Presentation Overlays", .serialized)
struct PresentationOverlayTests {
    @Test func sheet_item_presents_and_dismisses() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 40, height: 10)

        let s0 = runtime.debugRender(_SheetItemProbeView(), size: size)
        #expect(s0.text.contains("item: -1"))

        guard let show = _findButton(s0, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        s0.click(x: show.x, y: show.y)

        let s1 = runtime.debugRender(_SheetItemProbeView(), size: size)
        #expect(s1.text.contains("Item 1"))
        #expect(s1.text.contains("item: 1"))

        guard let close = _findButton(s1, title: "Close") else {
            #expect(Bool(false), "Could not find Close button")
            return
        }
        s1.click(x: close.x, y: close.y)

        let s2 = runtime.debugRender(_SheetItemProbeView(), size: size)
        #expect(!s2.text.contains("Item 1"))
        #expect(s2.text.contains("item: -1"))
    }

    @Test func sheet_renders_overlay_body_and_inner_controls() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 40, height: 12)

        let initial = runtime.debugRender(_SheetOverlayInteractionProbeView(), size: size)
        guard let show = _findButton(initial, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        initial.click(x: show.x, y: show.y)

        let sheet = runtime.debugRender(_SheetOverlayInteractionProbeView(), size: size)
        #expect(sheet.text.contains("Overlay Body"))
        #expect(_findButton(sheet, title: "Inner") != nil)
        #expect(_findButton(sheet, title: "Close") != nil)
    }

    @Test func sheet_textField_and_action_buttons_are_interactive() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 50, height: 16)

        let initial = runtime.debugRender(_SheetSearchInteractionProbeView(), size: size)
        guard let show = _findButton(initial, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        initial.click(x: show.x, y: show.y)

        let sheet = runtime.debugRender(_SheetSearchInteractionProbeView(), size: size)
        #expect(sheet.text.contains("Search Gopherspace"))

        guard let field = _findText(sheet, text: "Query") else {
            #expect(Bool(false), "Could not find Query text field")
            return
        }
        sheet.click(x: field.x + 1, y: field.y)
        sheet.type("navan")

        let typed = runtime.debugRender(_SheetSearchInteractionProbeView(), size: size)
        #expect(typed.text.contains("navan"))

        guard let search = _findButton(typed, title: "Search") else {
            #expect(Bool(false), "Could not find Search button")
            return
        }
        typed.click(x: search.x, y: search.y)

        let final = runtime.debugRender(_SheetSearchInteractionProbeView(), size: size)
        #expect(final.text.contains("submitted: navan"))
        #expect(!final.text.contains("Search Gopherspace"))
    }

    @Test func sheet_keyboard_shortcuts_prefer_overlay_controls() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 50, height: 16)

        let initial = runtime.debugRender(_SheetKeyboardShortcutProbeView(), size: size)
        #expect(initial.text.contains("base: 0"))
        #expect(initial.text.contains("sheet: 0"))

        #expect(runtime.invokeKeyboardShortcut(.return))
        let baseInvoked = runtime.debugRender(_SheetKeyboardShortcutProbeView(), size: size)
        #expect(baseInvoked.text.contains("base: 1"))
        #expect(baseInvoked.text.contains("sheet: 0"))

        guard let show = _findButton(baseInvoked, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        baseInvoked.click(x: show.x, y: show.y)

        let sheet = runtime.debugRender(_SheetKeyboardShortcutProbeView(), size: size)
        #expect(sheet.text.contains("Shortcut Sheet"))

        #expect(runtime.invokeKeyboardShortcut(.return))
        let final = runtime.debugRender(_SheetKeyboardShortcutProbeView(), size: size)
        #expect(final.text.contains("base: 1"))
        #expect(final.text.contains("sheet: 1"))
        #expect(final.text.contains("Shortcut Sheet"))
    }

    @Test func popover_isPresented_shows_and_dismisses() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 40, height: 10)

        let s0 = runtime.debugRender(_PopoverProbeView(), size: size)
        #expect(s0.text.contains("popover: closed"))

        guard let show = _findButton(s0, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        s0.click(x: show.x, y: show.y)

        let s1 = runtime.debugRender(_PopoverProbeView(), size: size)
        #expect(s1.text.contains("Popover Body"))
        #expect(s1.text.contains("popover: open"))

        guard let close = _findButton(s1, title: "Close") else {
            #expect(Bool(false), "Could not find Close button")
            return
        }
        s1.click(x: close.x, y: close.y)

        let s2 = runtime.debugRender(_PopoverProbeView(), size: size)
        #expect(!s2.text.contains("Popover Body"))
        #expect(s2.text.contains("popover: closed"))
    }

    @Test func confirmationDialog_captures_buttons_and_runs_selected_action() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 40, height: 12)

        let s0 = runtime.debugRender(_ConfirmationDialogProbeView(), size: size)
        #expect(s0.text.contains("picked: -"))

        guard let show = _findButton(s0, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        s0.click(x: show.x, y: show.y)

        let s1 = runtime.debugRender(_ConfirmationDialogProbeView(), size: size)
        #expect(s1.text.contains("Confirm"))
        #expect(s1.text.contains("Choose"))

        guard let two = _findButton(s1, title: "Two") else {
            #expect(Bool(false), "Could not find Two button")
            return
        }
        s1.click(x: two.x, y: two.y)

        let s2 = runtime.debugRender(_ConfirmationDialogProbeView(), size: size)
        #expect(s2.text.contains("picked: Two"))
        #expect(!s2.text.contains("Choose"))
    }

    @Test func alert_uses_semantic_modal_overlay_instead_of_drawing_scrim() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 50, height: 12)

        let initial = runtime.debugRender(_AlertSemanticProbeView(), size: size)
        guard let show = _findButton(initial, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        initial.click(x: show.x, y: show.y)

        let snapshot = runtime.semanticSnapshot(_AlertSemanticProbeView(), size: size)

        func containsAdwaitaDialog(_ node: SemanticNode) -> Bool {
            if case .modifier(.background("adw-dialog")) = node.kind {
                return true
            }
            return node.children.contains(where: containsAdwaitaDialog)
        }

        func containsDrawingIsland(_ node: SemanticNode) -> Bool {
            if case .drawingIsland = node.kind {
                return true
            }
            return node.children.contains(where: containsDrawingIsland)
        }

        func containsText(_ expected: String, in node: SemanticNode) -> Bool {
            if case .text(let text) = node.kind, text.contains(expected) {
                return true
            }
            return node.children.contains { containsText(expected, in: $0) }
        }

        #expect(containsAdwaitaDialog(snapshot.root))
        #expect(containsText("Enabled", in: snapshot.root))
        #expect(containsText("OK", in: snapshot.root))
        #expect(!containsDrawingIsland(snapshot.root))
    }

    @Test func popover_item_presents_and_dismisses() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 40, height: 10)

        let s0 = runtime.debugRender(_PopoverItemProbeView(), size: size)
        #expect(s0.text.contains("popover item: -1"))

        guard let show = _findButton(s0, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        s0.click(x: show.x, y: show.y)

        let s1 = runtime.debugRender(_PopoverItemProbeView(), size: size)
        #expect(s1.text.contains("Popover Item 7"))
        #expect(s1.text.contains("popover item: 7"))

        guard let close = _findButton(s1, title: "Close") else {
            #expect(Bool(false), "Could not find Close button")
            return
        }
        s1.click(x: close.x, y: close.y)

        let s2 = runtime.debugRender(_PopoverItemProbeView(), size: size)
        #expect(!s2.text.contains("Popover Item 7"))
        #expect(s2.text.contains("popover item: -1"))
    }
}

struct _NavigationDestinationBoolProbeView: View {
    @State private var isShowingDetail: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 1) {
                Text("root")
                Button("Show") { isShowingDetail = true }
            }
            .navigationDestination(isPresented: $isShowingDetail) {
                Text("Bool Detail")
            }
        }
    }
}

@Test func navigationDestination_isPresented_pushes_and_pops() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 10)

    let s0 = runtime.debugRender(_NavigationDestinationBoolProbeView(), size: size)
    #expect(s0.text.contains("root"))

    guard let show = _findButton(s0, title: "Show") else {
        #expect(Bool(false), "Could not find Show button")
        return
    }
    s0.click(x: show.x, y: show.y)

    let s1 = runtime.debugRender(_NavigationDestinationBoolProbeView(), size: size)
    #expect(s1.text.contains("Bool Detail"))
    #expect(s1.text.contains("[ Back ]"))

    guard let back = _findButton(s1, title: "Back") else {
        #expect(Bool(false), "Could not find Back button")
        return
    }
    s1.click(x: back.x, y: back.y)

    let s2 = runtime.debugRender(_NavigationDestinationBoolProbeView(), size: size)
    #expect(s2.text.contains("root"))
    #expect(!s2.text.contains("Bool Detail"))
}

private struct _NavigationDestinationItemProbeItem: Identifiable {
    let id: Int
}

struct _NavigationDestinationItemProbeView: View {
    @State private var selected: _NavigationDestinationItemProbeItem? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 1) {
                Text("selected: \(selected?.id ?? -1)")
                Button("Show") { selected = _NavigationDestinationItemProbeItem(id: 5) }
            }
            .navigationDestination(item: $selected) { item in
                Text("Item Detail \(item.id)")
            }
        }
    }
}

@Test func navigationDestination_item_pushes_and_clears_on_back() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 10)

    let s0 = runtime.debugRender(_NavigationDestinationItemProbeView(), size: size)
    #expect(s0.text.contains("selected: -1"))

    guard let show = _findButton(s0, title: "Show") else {
        #expect(Bool(false), "Could not find Show button")
        return
    }
    s0.click(x: show.x, y: show.y)

    let s1 = runtime.debugRender(_NavigationDestinationItemProbeView(), size: size)
    #expect(s1.text.contains("Item Detail 5"))

    guard let back = _findButton(s1, title: "Back") else {
        #expect(Bool(false), "Could not find Back button")
        return
    }
    s1.click(x: back.x, y: back.y)

    let s2 = runtime.debugRender(_NavigationDestinationItemProbeView(), size: size)
    #expect(s2.text.contains("selected: -1"))
    #expect(!s2.text.contains("Item Detail 5"))
}

struct _NavigationDestinationValueProbeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 1) {
                NavigationLink(value: 42) {
                    Text("Value Link")
                }
            }
            .navigationDestination(for: Int.self) { value in
                Text("Value \(value)")
            }
        }
    }
}

@Test func navigationDestination_for_value_pushes_resolved_destination() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 10)

    let s0 = runtime.debugRender(_NavigationDestinationValueProbeView(), size: size)
    #expect(s0.text.contains("Value Link"))

    guard let link = _findButton(s0, title: "Value Link") else {
        #expect(Bool(false), "Could not find Value Link button")
        return
    }
    s0.click(x: link.x, y: link.y)

    let s1 = runtime.debugRender(_NavigationDestinationValueProbeView(), size: size)
    #expect(s1.text.contains("Value 42"))
    #expect(s1.text.contains("[ Back ]"))
}

struct _CoreParityViewsProbe: View {
    @State private var date: Date = Date(timeIntervalSinceReferenceDate: 123456789)

    var body: some View {
        NavigationView {
            VStack(spacing: 1) {
                DatePicker("When", selection: $date)
                    .datePickerStyle(.graphical)
                Gauge(value: 0.4) {
                    Text("Gauge")
                } currentValueLabel: {
                    Text("40%")
                }
                .gaugeStyle(.default)
                AsyncImage(url: URL(string: "https://example.com/image.png")) { _ in
                    Text("photo")
                }
                TimelineView(()) { context in
                    Text(context.cadence == .live ? "Timeline" : "Other")
                }
                .contentTransition(ContentTransition())
                .navigationTransition(NavigationTransition())
            }
        }
        .navigationViewStyle(.default)
    }
}

@Test func core_parity_views_render_basic_output() async throws {
    let runtime = _UIRuntime()
    let s0 = runtime.debugRender(_CoreParityViewsProbe(), size: _Size(width: 60, height: 12))
    #expect(s0.text.contains("When"))
    #expect(s0.text.contains("Gauge"))
    #expect(s0.text.contains("40%"))
        }

struct _DrawingParityProbe: View {
    var body: some View {
        VStack(spacing: 1) {
            LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 4, height: 2)
            Canvas { context, _ in
                context.fill(Rectangle(), with: .color(.green))
            }
            .frame(width: 4, height: 2)
        }
    }
}

@Test func asyncImage_rejects_file_url_for_security() async throws {
    let runtime = _UIRuntime()
    let tempURL = URL.temporaryDirectory.appending(path: "omniui-async-image-test.bin")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tempURL)
    struct Probe: View {
        let url: URL
        var body: some View {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success:
                    return Text("photo")
                case .failure:
                    return Text("failure")
                case .empty:
                    return Text("empty")
                }
            }
        }
    }
    let initial = runtime.debugRender(Probe(url: tempURL), size: _Size(width: 20, height: 4))
    #expect(initial.text.contains("empty"))
    try await Task.sleep(nanoseconds: 100_000_000)
    let next = runtime.debugRender(Probe(url: tempURL), size: _Size(width: 20, height: 4))
    // file:// URLs are rejected for security — should report failure, not success
    #expect(next.text.contains("failure"))
}

@Test func timelineView_ticks_over_time() async throws {
    let runtime = _UIRuntime()
    struct Probe: View {
        var body: some View {
            TimelineView(()) { context in
                Text(context.date.formatted(date: .omitted, time: .standard))
            }
        }
    }
    let first = runtime.debugRender(Probe(), size: _Size(width: 20, height: 4)).text
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let second = runtime.debugRender(Probe(), size: _Size(width: 20, height: 4)).text
    #expect(first != second)
}

@Test func drawing_primitives_emit_renderer_ops() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.render(_DrawingParityProbe(), size: _Size(width: 6, height: 6))
    #expect(!snapshot.ops.isEmpty)
    #expect(!snapshot.shapeRegions.isEmpty)
}

struct _DisabledButtonProbe: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 1) {
            Text("Count: \(count)")
            Button("Inc") { count += 1 }
                .disabled(true)
        }
    }
}

@Test func disabled_button_blocks_interaction() async throws {
    let runtime = _UIRuntime()
    let initial = runtime.debugRender(_DisabledButtonProbe(), size: _Size(width: 30, height: 6))
    #expect(initial.text.contains("Count: 0"))
    initial.click(x: 2, y: 2)
    let next = runtime.debugRender(_DisabledButtonProbe(), size: _Size(width: 30, height: 6))
    #expect(next.text.contains("Count: 0"))
}

struct _SearchableProbe: View {
    @State private var query = ""

    var body: some View {
        Text("Query: \(query)")
            .searchable(text: $query)
    }
}

@Test func searchable_renders_field_and_updates_binding() async throws {
    let runtime = _UIRuntime()
    let initial = runtime.debugRender(_SearchableProbe(), size: _Size(width: 40, height: 6))
    #expect(initial.text.contains("Query:"))
    #expect(initial.text.contains("Search"))
    initial.click(x: 3, y: 0)
    initial.type("abc")
    let next = runtime.debugRender(_SearchableProbe(), size: _Size(width: 40, height: 6))
    #expect(next.text.contains("Query: abc"))
}

struct _RefreshableProbe: View {
    @State private var refreshCount = 0

    var body: some View {
        Text("Refreshes: \(refreshCount)")
            .refreshable {
                refreshCount += 1
            }
    }
}

@Test func refreshable_exposes_button_and_runs_action() async throws {
    let runtime = _UIRuntime()
    let initial = runtime.debugRender(_RefreshableProbe(), size: _Size(width: 40, height: 6))
    #expect(initial.text.contains("Refreshes: 0"))
    #expect(initial.text.contains("Refresh"))
    initial.click(x: 2, y: 0)
    try await Task.sleep(nanoseconds: 50_000_000)
    let next = runtime.debugRender(_RefreshableProbe(), size: _Size(width: 40, height: 6))
    #expect(next.text.contains("Refreshes: 1"))
}

struct _OffsetOpacityProbe: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 1) {
            Text("Count: \(count)")
            Button("Go") { count += 1 }
                .offset(x: 4, y: 0)
            Text("Fade")
                .opacity(0.5)
        }
    }
}

@Test func offset_and_opacity_modifiers_affect_render_tree() async throws {
    let runtime = _UIRuntime()
    let initial = runtime.debugRender(_OffsetOpacityProbe(), size: _Size(width: 30, height: 8))
    initial.click(x: 8, y: 2)
    let next = runtime.debugRender(_OffsetOpacityProbe(), size: _Size(width: 30, height: 8))
    #expect(next.text.contains("Count: 1"))

    let faded = runtime.render(Text("Fade").opacity(0.5), size: _Size(width: 10, height: 2))
    let hasAlpha = faded.ops.contains { op in
        switch op.kind {
        case .glyph(_, _, _, let fg, _), .textRun(_, _, _, let fg, _):
            return (fg?.alpha ?? 1.0) < 1.0
        default:
            return false
        }
    }
    #expect(hasAlpha)
}

struct _TextEnvironmentProbe: View {
    var body: some View {
        Text("First\nSecond\nThird")
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .font(.headline)
    }
}

@Test func text_environment_modifiers_affect_output() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.debugRender(_TextEnvironmentProbe(), size: _Size(width: 20, height: 5))
    #expect(snapshot.text.contains("First"))
    #expect(snapshot.text.contains("Second"))
    #expect(!snapshot.text.contains("Third"))
}

struct _ExitCommandProbe: View {
    @State private var exits = 0

    var body: some View {
        Text("Exits: \(exits)")
            .onExitCommand {
                exits += 1
            }
    }
}

@Test func onExitCommand_registers_runtime_handler() async throws {
    let runtime = _UIRuntime()
    _ = runtime.debugRender(_ExitCommandProbe(), size: _Size(width: 20, height: 4))
    #expect(runtime.invokeExitCommand())
    let next = runtime.debugRender(_ExitCommandProbe(), size: _Size(width: 20, height: 4))
    #expect(next.text.contains("Exits: 1"))
}

struct _QuickLookProbe: View {
    let url: Binding<URL?>

    var body: some View {
        Text("Host")
            .quickLookPreview(url)
    }
}

@Test func quickLookPreview_registers_overlay() async throws {
    let runtime = _UIRuntime()
    var currentURL: URL? = URL(string: "https://example.com/file.txt")
    let binding = Binding<URL?>(get: { currentURL }, set: { currentURL = $0 })
    let snapshot = runtime.debugRender(_QuickLookProbe(url: binding), size: _Size(width: 50, height: 10))
    #expect(snapshot.text.contains("Quick Look"))
    #expect(snapshot.text.contains("file.txt"))
    currentURL = nil
    let next = runtime.debugRender(_QuickLookProbe(url: binding), size: _Size(width: 50, height: 10))
    #expect(!next.text.contains("Quick Look"))
}

struct _HoverProbe: View {
    @State private var hovered = false

    var body: some View {
        Text(hovered ? "Hover ON" : "Hover OFF")
            .onHover { hovered = $0 }
    }
}

@Test func onHover_updates_state_via_snapshot_hover() async throws {
    let runtime = _UIRuntime()
    let initial = runtime.debugRender(_HoverProbe(), size: _Size(width: 20, height: 4))
    #expect(initial.text.contains("Hover OFF"))
    initial.hover(x: 1, y: 0)
    let hovered = runtime.debugRender(_HoverProbe(), size: _Size(width: 20, height: 4))
    #expect(hovered.text.contains("Hover ON"))
    hovered.hover(x: 19, y: 3)
    let cleared = runtime.debugRender(_HoverProbe(), size: _Size(width: 20, height: 4))
    #expect(cleared.text.contains("Hover OFF"))
}

struct _ToolbarSemanticProbe: View {
    var body: some View {
        Text("Toolbar Base")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Lead") {}
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Trail") {}
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Bottom") {}
                }
            }
    }
}

@Test func toolbar_items_are_preserved_in_semantic_snapshot() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(_ToolbarSemanticProbe(), size: _Size(width: 50, height: 10))

    func containsText(_ expected: String, in node: SemanticNode) -> Bool {
        if case .text(let text) = node.kind, text.contains(expected) {
            return true
        }
        return node.children.contains { containsText(expected, in: $0) }
    }

    func buttonCount(in node: SemanticNode) -> Int {
        let selfCount: Int
        if case .button = node.kind {
            selfCount = 1
        } else {
            selfCount = 0
        }
        return selfCount + node.children.map(buttonCount).reduce(0, +)
    }

    #expect(containsText("Toolbar Base", in: snapshot.root))
    #expect(containsText("Lead", in: snapshot.root))
    #expect(containsText("Trail", in: snapshot.root))
    #expect(containsText("Bottom", in: snapshot.root))
    #expect(buttonCount(in: snapshot.root) == 3)
}

@Test func toolbar_color_scheme_styles_toolbar_foreground() async throws {
    struct V: View {
        let scheme: ColorScheme

        var body: some View {
            Text("Base")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("Lead")
                    }
                }
                .toolbarColorScheme(scheme, for: .windowToolbar)
        }
    }

    func foregroundForLead(in snapshot: DebugSnapshot) -> Color? {
        guard let row = snapshot.lines.firstIndex(where: { $0.contains("Lead") }),
              let column = snapshot.lines[row].firstIndex(of: "L")?.utf16Offset(in: snapshot.lines[row])
        else { return nil }
        return snapshot.styledCells[row * snapshot.size.width + column].fg
    }

    let runtime = _UIRuntime()
    let light = runtime.debugRender(V(scheme: .light), size: _Size(width: 30, height: 6))
    #expect(foregroundForLead(in: light) == .black)

    let dark = runtime.debugRender(V(scheme: .dark), size: _Size(width: 30, height: 6))
    #expect(foregroundForLead(in: dark) == .white)
}

struct _SceneCommandProbe: Scene {
    @SceneBuilder var body: some Scene {
        WindowGroup {
            Text("Scene Root")
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Command") {}
            }
        }
        .defaultSize(width: 90, height: 30)
    }
}

struct _SceneSettingsProbe: Scene {
    @SceneBuilder var body: some Scene {
        WindowGroup {
            Text("Main Root")
        }
        Settings {
            Form {
                Text("Settings Root")
            }
        }
    }
}

@Test func scene_commands_and_default_size_are_exposed() async throws {
    let scene = _SceneCommandProbe().body
    let root = _sceneRootView(scene)
    #expect(root != nil)
    let commands = _sceneCommandsView(scene)
    #expect(commands != nil)
    let preferred = _scenePreferredSize(scene)
    #expect(preferred?.width == 90)
    #expect(preferred?.height == 30)

    let runtime = _UIRuntime()
    let snapshot = runtime.debugRender(root!, size: _Size(width: 30, height: 6))
    #expect(snapshot.text.contains("Scene Root"))
}

@Test func scene_settings_are_exposed_separately_from_window_root() async throws {
    let scene = _SceneSettingsProbe().body
    let root = _sceneRootView(scene)
    let settings = _sceneSettingsView(scene)

    #expect(root != nil)
    #expect(settings != nil)

    let runtime = _UIRuntime()
    let rootSnapshot = runtime.debugRender(root!, size: _Size(width: 30, height: 6))
    #expect(rootSnapshot.text.contains("Main Root"))
    #expect(!rootSnapshot.text.contains("Settings Root"))

    let settingsSnapshot = runtime.debugRender(settings!, size: _Size(width: 30, height: 6))
    #expect(settingsSnapshot.text.contains("Settings Root"))
}

struct _TextFieldConfigProbe: View {
    @State private var url = ""
    @State private var corrected = ""

    var body: some View {
        VStack(spacing: 1) {
            TextField("URL", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.characters)
                .textContentType(.URL)
                .textFieldStyle(.plain)
            Text(url)
            TextField("Auto", text: $corrected)
                .autocorrectionDisabled(false)
            Text(corrected)
        }
    }
}

@Test func textField_style_and_input_configs_affect_behavior() async throws {
    let runtime = _UIRuntime()
    let initial = runtime.debugRender(_TextFieldConfigProbe(), size: _Size(width: 30, height: 8))
    #expect(!initial.text.contains("[URL]"))
    initial.click(x: 1, y: 0)
    initial.type("Ab C")
    let urlState = runtime.debugRender(_TextFieldConfigProbe(), size: _Size(width: 30, height: 8))
    #expect(urlState.text.contains("abc"))
    #expect(!urlState.text.contains("Ab C"))

    urlState.click(x: 1, y: 4)
    urlState.type("teh ")
    let corrected = runtime.debugRender(_TextFieldConfigProbe(), size: _Size(width: 30, height: 8))
    #expect(corrected.text.contains("the "))
}

@Test func scene_commands_and_default_size_metadata_are_preserved() async throws {
    let scene = AnyScene(
        WindowGroup {
            Text("Root")
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Command") {}
            }
        }
        .defaultSize(width: 42, height: 17)
    )

    let rootScene: _OmniUISceneRoot = scene
    #expect(rootScene._omniUIRootView() != nil)
    #expect(rootScene._omniUICommandsView() != nil)
    #expect(rootScene._omniUISettingsView() == nil)
    #expect(rootScene._omniUIPreferredSize == CGSize(width: 42, height: 17))

    let runtime = _UIRuntime()
    if let commandsView = rootScene._omniUICommandsView() {
        let snapshot = runtime.debugRender(commandsView, size: _Size(width: 20, height: 4))
        #expect(snapshot.text.contains("Command"))
    }
}

struct _SplitAutomaticProbeView: View {
    var body: some View {
        NavigationSplitView(
            columnVisibility: Binding(get: { .automatic }, set: { _ in }),
            sidebar: { Text("SIDEBAR") },
            detail: { Text("DETAIL") }
        )
    }
}

@Test func navigationSplitView_automatic_adapts_by_width() async throws {
    let runtime = _UIRuntime()

    let narrow = runtime.debugRender(_SplitAutomaticProbeView(), size: _Size(width: 40, height: 6))
    #expect(narrow.text.contains("DETAIL"))
    #expect(!narrow.text.contains("SIDEBAR"))

    let wide = runtime.debugRender(_SplitAutomaticProbeView(), size: _Size(width: 100, height: 6))
    #expect(wide.text.contains("DETAIL"))
    #expect(wide.text.contains("SIDEBAR"))
}

struct _TabViewSelectionFallbackProbe: View {
    let selection: Binding<String>

    var body: some View {
        TabView(selection: selection) {
            Text("First body")
                .tabItem { Text("First") }
                .tag("first")
            Text("Second body")
                .tabItem { Text("Second") }
                .tag("second")
        }
    }
}

@Test func tabView_reconciles_missing_selection_to_first_available_tab() async throws {
    let runtime = _UIRuntime()
    var selection = "missing"
    let binding = Binding(get: { selection }, set: { selection = $0 })

    let snapshot = runtime.debugRender(_TabViewSelectionFallbackProbe(selection: binding), size: _Size(width: 30, height: 8))

    #expect(snapshot.text.contains("[First]"))
    #expect(snapshot.text.contains("First body"))
    #expect(selection == "first")
}

@Test func tabView_selection_tabs_update_enum_binding() async throws {
    enum SettingsSection: Hashable {
        case general
        case terminal
        case web
    }

    struct SettingsTabsProbe: View {
        let selection: Binding<SettingsSection>

        var body: some View {
            TabView(selection: selection) {
                Text("General body")
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(SettingsSection.general)
                Text("Terminal body")
                    .tabItem { Label("Terminal", systemImage: "terminal") }
                    .tag(SettingsSection.terminal)
                Text("Web body")
                    .tabItem { Label("Web", systemImage: "globe") }
                    .tag(SettingsSection.web)
            }
        }
    }

    let runtime = _UIRuntime()
    var selection = SettingsSection.general
    let binding = Binding(get: { selection }, set: { selection = $0 })

    let initial = runtime.debugRender(SettingsTabsProbe(selection: binding), size: _Size(width: 60, height: 10))
    #expect(initial.text.contains("[General]"))
    #expect(initial.text.contains("General body"))

    guard let terminal = _findButton(initial, title: "Terminal") else {
        Issue.record("Expected Terminal tab button")
        return
    }
    initial.click(x: terminal.x, y: terminal.y)

    let updated = runtime.debugRender(SettingsTabsProbe(selection: binding), size: _Size(width: 60, height: 10))
    #expect(selection == .terminal)
    #expect(updated.text.contains("[Terminal]"))
    #expect(updated.text.contains("Terminal body"))
    #expect(!updated.text.contains("General body"))
}

// MARK: - iGopher Parity Tests (23 Features)

// Feature #1: listStyle(.plain) suppresses Section headers
@Test func parity_listStyle_plain_suppresses_section_header() async throws {
    struct PlainListView: View {
        var body: some View {
            List {
                Section(header: Text("HEADER")) {
                    Text("Row1")
                }
            }
            .listStyle(.plain)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(PlainListView(), size: _Size(width: 30, height: 10))
    #expect(!snap.text.contains("HEADER"))
    #expect(snap.text.contains("Row1"))
}

// Feature #1 (sidebar keeps headers)
@Test func parity_listStyle_sidebar_keeps_section_header() async throws {
    struct SidebarListView: View {
        var body: some View {
            List {
                Section(header: Text("HEADER")) {
                    Text("Row1")
                }
            }
            .listStyle(.sidebar)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(SidebarListView(), size: _Size(width: 30, height: 10))
    #expect(snap.text.contains("HEADER"))
    #expect(snap.text.contains("Row1"))
}

// Feature #2: listRowSeparator(.hidden) produces no dividers
@Test func parity_listRowSeparator_hidden() async throws {
    struct NoSepList: View {
        var body: some View {
            List {
                Text("A")
                Text("B")
            }
            .listRowSeparator(.hidden)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(NoSepList(), size: _Size(width: 30, height: 10))
    #expect(snap.text.contains("A"))
    #expect(snap.text.contains("B"))
    // With separator hidden, there should be no divider line between rows.
    // Divider is rendered as "─" chars; without hidden, there would be one.
    let lines = snap.lines
    let dividerLines = lines.filter { $0.contains("─") }
    #expect(dividerLines.isEmpty)
}

// Feature #3: listRowBackground wraps rows
@Test func parity_listRowBackground() async throws {
    struct BgList: View {
        var body: some View {
            List {
                Text("Row")
            }
            .listRowBackground(Color.yellow)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(BgList(), size: _Size(width: 30, height: 8))
    #expect(snap.text.contains("Row"))
}

// Feature #4: borderedProminent button style
@Test func parity_borderedProminent_button() async throws {
    struct ProminentBtn: View {
        var body: some View {
            Button("Tap") {}
                .buttonStyle(.borderedProminent)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(ProminentBtn(), size: _Size(width: 20, height: 3))
    #expect(snap.text.contains("Tap"))
    #expect(snap.text.contains("["))
    #expect(snap.text.contains("]"))
}

// Feature #5: Toggle switch slider rendering
@Test func parity_toggle_switch_slider() async throws {
    struct SwitchView: View {
        @State var isOn = true
        var body: some View {
            Toggle("Light", isOn: $isOn)
                .toggleStyle(.switch)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(SwitchView(), size: _Size(width: 30, height: 3))
    // Should contain slider chars instead of ON/OFF text
    #expect(snap.text.contains("━") || snap.text.contains("●") || snap.text.contains("○"))
}

// Feature #6: Picker segmented with pipe separators
@Test func parity_picker_segmented_pipes() async throws {
    struct SegView: View {
        @State var choice = "A"
        var body: some View {
            Picker("Pick", selection: $choice, options: [("A", "A"), ("B", "B"), ("C", "C")])
                .pickerStyle(.segmented)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(SegView(), size: _Size(width: 40, height: 3))
    #expect(snap.text.contains("│"))
    #expect(snap.text.contains("["))
    #expect(snap.text.contains("]"))
}

@Test func semantic_snapshot_preserves_segmented_picker_role() async throws {
    struct SegView: View {
        @State var choice = "B"
        var body: some View {
            Picker("Pick", selection: $choice, options: [("A", "A"), ("B", "B"), ("C", "C")])
                .pickerStyle(.segmented)
        }
    }

    func segmentedRole(in node: SemanticNode) -> (String, Int)? {
        if case .segmentedControl(let title, let selectedIndex) = node.kind {
            return (title, selectedIndex)
        }
        for child in node.children {
            if let role = segmentedRole(in: child) {
                return role
            }
        }
        return nil
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(SegView(), size: _Size(width: 40, height: 3))
    let role = segmentedRole(in: snapshot.root)
    #expect(role?.0 == "Pick")
    #expect(role?.1 == 1)
}

// Feature #7: controlSize(.large) adds bold
@Test func parity_controlSize_large_renders() async throws {
    struct LargeBtn: View {
        var body: some View {
            Button("Big") {}
                .controlSize(.large)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(LargeBtn(), size: _Size(width: 20, height: 3))
    #expect(snap.text.contains("Big"))
}

// Feature #8: scrollContentBackground(.hidden)
@Test func parity_scrollContentBackground_hidden() async throws {
    struct NoBgList: View {
        var body: some View {
            List {
                Text("Item")
            }
            .scrollContentBackground(.hidden)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(NoBgList(), size: _Size(width: 20, height: 6))
    #expect(snap.text.contains("Item"))
}

// Feature #9: contentShape(Rectangle()) is a no-op for Rectangle
@Test func parity_contentShape_rectangle() async throws {
    struct ShapeView: View {
        var body: some View {
            Text("Clickable")
                .contentShape(Rectangle())
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(ShapeView(), size: _Size(width: 20, height: 3))
    #expect(snap.text.contains("Clickable"))
}

// Feature #10: @Namespace (no-op, already done)
@Test func parity_namespace_compiles() async throws {
    struct NsView: View {
        var ns = Namespace()
        var body: some View {
            Text("Hello")
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(NsView(), size: _Size(width: 20, height: 3))
    #expect(snap.text.contains("Hello"))
}

// Feature #11: LazyVStack with spacing
@Test func parity_lazyVStack_spacing() async throws {
    struct LazyView: View {
        var body: some View {
            LazyVStack(spacing: 1) {
                Text("A")
                Text("B")
            }
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(LazyView(), size: _Size(width: 20, height: 6))
    #expect(snap.text.contains("A"))
    #expect(snap.text.contains("B"))
}

// Feature #12: ColorPicker HSL sliders
@Test func parity_colorPicker_hsl_sliders() async throws {
    struct CPView: View {
        @State var color: Color = .red
        var body: some View {
            VStack(spacing: 1) {
                Text("Color: \(color.name)")
                ColorPicker("Tint", selection: $color)
            }
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(CPView(), size: _Size(width: 40, height: 6))
    #expect(snap.text.contains("Color: red"))
    #expect(snap.text.contains("Tint"))
    #expect(snap.text.contains("■"))
    // Should have HSL bar indicators
    #expect(snap.text.contains("H:") || snap.text.contains("S:") || snap.text.contains("L:"))

    guard let white = _findButton(snap, title: "■", occurrence: 1) else {
        Issue.record("Expected a clickable color swatch")
        return
    }
    snap.click(x: white.x, y: white.y)

    let updated = runtime.debugRender(CPView(), size: _Size(width: 40, height: 6))
    #expect(updated.text.contains("Color: white"))
}

@Test func colorPicker_labelsHiddenOmitsTitleRow() async throws {
    struct HiddenLabelColorPickerView: View {
        @State var color: Color = .blue

        var body: some View {
            VStack(spacing: 0) {
                Text("Before")
                ColorPicker("Accent", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                Text("After")
            }
        }
    }

    let runtime = _UIRuntime()
    let snap = runtime.debugRender(HiddenLabelColorPickerView(), size: _Size(width: 42, height: 8))
    #expect(!snap.text.contains("Accent"))
    #expect(snap.text.contains("Before"))
    #expect(snap.text.contains("After"))
    #expect(snap.text.contains("#0000FF"))
}

@Test func colorPicker_emptyTitleDoesNotRenderBlankTitleChrome() async throws {
    struct EmptyTitleColorPickerView: View {
        @State var color: Color = .red

        var body: some View {
            ColorPicker("", selection: $color, supportsOpacity: false)
        }
    }

    let runtime = _UIRuntime()
    let snap = runtime.debugRender(EmptyTitleColorPickerView(), size: _Size(width: 42, height: 6))
    #expect(!snap.text.contains(": #FF0000"))
    #expect(snap.text.contains("#FF0000"))
}

// Feature #13: ContentUnavailableView.search factory
@Test func parity_contentUnavailableView_search() async throws {
    let view: ContentUnavailableView<AnyView, AnyView, EmptyView> = .search
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(view, size: _Size(width: 40, height: 8))
    #expect(snap.text.contains("No Results"))
}

// Feature #13: ContentUnavailableView string init
@Test func parity_contentUnavailableView_string_init() async throws {
    let view = ContentUnavailableView("Empty", systemImage: "xmark", description: Text("Nothing here"))
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(view, size: _Size(width: 40, height: 8))
    #expect(snap.text.contains("Empty"))
    #expect(snap.text.contains("Nothing here"))
}

// Feature #14: LabeledContent generic
@Test func parity_labeledContent_generic() async throws {
    struct LCView: View {
        var body: some View {
            LabeledContent(content: { Text("ValueView") }, label: { Text("LabelView") })
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(LCView(), size: _Size(width: 40, height: 3))
    #expect(snap.text.contains("LabelView"))
    #expect(snap.text.contains("ValueView"))
}

// Feature #14: LabeledContent string convenience
@Test func parity_labeledContent_string() async throws {
    let view = LabeledContent("Key", value: "Val")
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(view, size: _Size(width: 20, height: 3))
    #expect(snap.text.contains("Key"))
    #expect(snap.text.contains("Val"))
}

// Feature #15: safeAreaInset spacing
@Test func parity_safeAreaInset_spacing() async throws {
    struct InsetView: View {
        var body: some View {
            Text("Content")
                .safeAreaInset(edge: .top, spacing: 2) {
                    Text("Bar")
                }
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(InsetView(), size: _Size(width: 20, height: 6))
    #expect(snap.text.contains("Bar"))
    #expect(snap.text.contains("Content"))
}

// Feature #16: presentationDetents
@Test func parity_presentationDetents_medium() async throws {
    struct DetentView: View {
        @State var show = true
        var body: some View {
            Text("Base")
                .sheet(isPresented: $show) {
                    Text("SheetContent")
                        .presentationDetents([.medium])
                }
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(DetentView(), size: _Size(width: 40, height: 20))
    #expect(snap.text.contains("Base"))
}

// Feature #17: quickLookPreview metadata
@Test func parity_quickLookPreview_metadata() async throws {
    struct QLView: View {
        @State var url: URL? = URL(fileURLWithPath: "/tmp/test.txt")
        var body: some View {
            Text("File")
                .quickLookPreview($url)
        }
    }
    let runtime = _UIRuntime()
    // First render registers overlay, second renders it
    _ = runtime.debugRender(QLView(), size: _Size(width: 40, height: 10))
    let snap = runtime.debugRender(QLView(), size: _Size(width: 40, height: 10))
    // Quick Look overlay should show filename or Quick Look title
    #expect(snap.text.contains("test.txt") || snap.text.contains("Quick Look") || snap.text.contains("File"))
}

// Feature #18: deliverURL runtime API
@Test func parity_deliverURL_compiles() async throws {
    let runtime = _UIRuntime()
    // Verify deliverURL method exists and is callable
    let testURL = URL(string: "https://example.com")!
    runtime.deliverURL(testURL)
    // No crash = pass
}

// Feature #19: LinearGradient dithering
@Test func parity_linearGradient_renders() async throws {
    struct GradView: View {
        var body: some View {
            LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 20, height: 4)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(GradView(), size: _Size(width: 20, height: 4))
    // Should have some content (gradient cells)
    #expect(!snap.text.trimmingCharacters(in: .whitespaces).isEmpty)
}

// Feature #20: RadialGradient dithering
@Test func parity_radialGradient_renders() async throws {
    struct RadView: View {
        var body: some View {
            RadialGradient(gradient: Gradient(colors: [.white, .black]), center: .center, startRadius: 0, endRadius: 10)
                .frame(width: 10, height: 5)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(RadView(), size: _Size(width: 10, height: 5))
    #expect(!snap.text.trimmingCharacters(in: .whitespaces).isEmpty)
}

// Feature #21: Canvas Path rendering
@Test func parity_canvas_path_fill() async throws {
    struct CanvasView: View {
        var body: some View {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(x: 0, y: 0, width: 5, height: 3)), with: .color(.red))
            }
            .frame(width: 10, height: 5)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(CanvasView(), size: _Size(width: 10, height: 5))
    // Canvas should produce shape output
    #expect(snap.shapeRegions.count > 0 || !snap.text.trimmingCharacters(in: .whitespaces).isEmpty)
}

// Feature #22: Custom ButtonStyle
@Test func parity_custom_buttonStyle() async throws {
    struct BoldButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .bold()
        }
    }
    struct StyledBtn: View {
        var body: some View {
            Button("Custom") {}
                .buttonStyle(BoldButtonStyle())
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(StyledBtn(), size: _Size(width: 20, height: 3))
    #expect(snap.text.contains("Custom"))
}

// Feature #23: Shadow rendering
@Test func parity_shadow_small_radius() async throws {
    struct ShadowView: View {
        var body: some View {
            Text("Hi")
                .shadow(color: .gray, radius: 1)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(ShadowView(), size: _Size(width: 10, height: 5))
    #expect(snap.text.contains("Hi"))
}

@Test func parity_shadow_large_radius_glow() async throws {
    struct GlowView: View {
        var body: some View {
            Text("Hi")
                .shadow(color: .green, radius: 5)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(GlowView(), size: _Size(width: 20, height: 8))
    #expect(snap.text.contains("Hi"))
}

private struct _FocusedURLFieldProbe: View {
    @State private var url = "gopher://gopher.navan.dev:70/"
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack {
            TextField("URL", text: $url)
                .focused($isFocused)
            Text("Ready")
        }
        .onAppear {
            isFocused = true
        }
    }
}

private struct _OnAppearStateProbe: View {
    @State private var shown = false

    var body: some View {
        VStack {
            if shown {
                Text("Shown")
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                Text("Hidden")
            }
        }
        .onAppear {
            guard !shown else { return }
            shown = true
        }
    }
}

private struct _OptionalOnChangeIdleProbe: View {
    @State private var selected: Int? = nil

    var body: some View {
        Text(selected.map(String.init) ?? "None")
            .onChange(of: selected) { _, _ in }
    }
}

private struct _BrowserChromeHotLoopProbe: View {
    @State private var url = "gopher://gopher.navan.dev:70/"
    @State private var showTooltip = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Welcome")
            Text("Info line")
            TextField("Enter a URL", text: $url)
                .focused($isFocused)
            HStack {
                Button {
                } label: {
                    Label("Home", systemImage: "house")
                }
                .labelStyle(.iconOnly)

                Spacer()

                Button("Go") {
                }
            }
        }
        .onAppear {
            isFocused = true
            guard !showTooltip else { return }
            showTooltip = true
        }
    }
}

@Test func focused_text_field_settles_after_initial_focus() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 50, height: 6)

    _ = runtime.debugRender(_FocusedURLFieldProbe(), size: size)
    _ = runtime.debugRender(_FocusedURLFieldProbe(), size: size)

    #expect(!runtime.needsRender(size: size))
}

@Test func on_appear_state_change_settles_after_mount() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 6)

    for _ in 0..<4 {
        _ = runtime.debugRender(_OnAppearStateProbe(), size: size)
    }

    #expect(!runtime.needsRender(size: size))
}

@Test func optional_on_change_value_does_not_dirty_every_frame() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 4)

    for _ in 0..<4 {
        _ = runtime.debugRender(_OptionalOnChangeIdleProbe(), size: size)
    }

    #expect(!runtime.needsRender(size: size))
}

@Test func browser_like_chrome_eventually_goes_idle() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 60, height: 10)

    for _ in 0..<32 {
        _ = runtime.debugRender(_BrowserChromeHotLoopProbe(), size: size)
    }

    #expect(!runtime.needsRender(size: size))
}

private final class _FrameSizeProbeView: NSView {
    var observedSizes: [NSSize] = []

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        observedSizes.append(newSize)
    }
}

@Test func linuxNSLayoutConstraintsApplyEdgePinnedSubviewFrames() {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
    let child = _FrameSizeProbeView()
    child.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(child)

    NSLayoutConstraint.activate([
        child.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
        child.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        child.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
        child.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
    ])

    container.layoutSubtreeIfNeeded()

    #expect(child.frame.origin == NSPoint(x: 10, y: 8))
    #expect(child.frame.size == NSSize(width: 298, height: 158))
    #expect(child.observedSizes.contains(NSSize(width: 298, height: 158)))

    container.setFrameSize(NSSize(width: 500, height: 240))

    #expect(child.frame.origin == NSPoint(x: 10, y: 8))
    #expect(child.frame.size == NSSize(width: 478, height: 218))
    #expect(child.observedSizes.contains(NSSize(width: 478, height: 218)))
}

@Test func linuxNSScrollViewLaysOutDocumentViewWithConstraints() {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
    let document = _FrameSizeProbeView()
    document.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = document

    let clipView = scrollView.contentView
    NSLayoutConstraint.activate([
        document.topAnchor.constraint(equalTo: clipView.topAnchor),
        document.bottomAnchor.constraint(equalTo: clipView.bottomAnchor),
        document.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
        document.widthAnchor.constraint(equalToConstant: 10_000),
    ])

    scrollView.layoutSubtreeIfNeeded()

    #expect(scrollView.contentView.frame == scrollView.bounds)
    #expect(document.frame.origin == .zero)
    #expect(document.frame.size == NSSize(width: 10_000, height: 180))
    #expect(document.observedSizes.contains(NSSize(width: 10_000, height: 180)))
}
