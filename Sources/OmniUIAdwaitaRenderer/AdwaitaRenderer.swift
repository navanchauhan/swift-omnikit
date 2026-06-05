import CAdwaita
import Foundation
import OmniUICore
#if canImport(AppKit)
import AppKit
#endif

private let adwaitaCommandActionOffset = 1_000_000
private let adwaitaSettingsActionOffset = 2_000_000
private let adwaitaStatusItemActionOffset = 3_000_000
private let adwaitaInternalPresentSettingsActionID = -1001

public enum OmniUIAdwaitaRendererError: Error {
    case unableToCreateApplication
    case unableToCreateNode(String)
}

public final class AdwaitaApp<Root: View>: @unchecked Sendable {
    private let appID: String
    private let title: String
    private let root: @MainActor () -> Root
    private let settings: (@MainActor () -> AnyView)?
    private let commands: (@MainActor () -> AnyView)?
    private let runtime = _UIRuntime()
    private let settingsRuntime = _UIRuntime()
    private let commandRuntime = _UIRuntime()
    private let popoverRuntime = _UIRuntime()
    private let size: _Size

    public init(
        appID: String = "dev.omnikit.KitchenSinkAdwaita",
        title: String = "OmniUI Adwaita",
        size: _Size = _Size(width: 120, height: 42),
        settings: (@MainActor () -> AnyView)? = nil,
        commands: (@MainActor () -> AnyView)? = nil,
        @ViewBuilder root: @escaping @MainActor () -> Root
    ) {
        self.appID = appID
        self.title = title
        self.size = size
        self.settings = settings
        self.commands = commands
        self.root = root
    }

    @MainActor
    public func run() async throws {
        _omniAdwaitaRendererEntryTrace("run begin")
        let box = Unmanaged.passRetained(CallbackBox(runtime: runtime, settingsRuntime: settingsRuntime, commandRuntime: commandRuntime, popoverRuntime: popoverRuntime, rerender: {}))
        var cApp: OpaquePointer?
        let callback: omni_adw_action_callback = { actionID, context in
            guard let context else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            let rawID = Int(actionID)
            if rawID == adwaitaInternalPresentSettingsActionID {
                if box.previousSettingsRoot == nil,
                   invokeAdwaitaSettingsFallback(box: box) {
                    box.runtime._markDirtyFromExternalResource()
                    box.rerender()
                    return
                }
                box.settingsRuntime._markDirtyFromExternalResource()
                box.runtime._markDirtyFromExternalResource()
                box.rerender()
                return
            }
            invokeAdwaitaRawAction(rawID, box: box)
            box.settingsRuntime._markDirtyFromExternalResource()
            box.runtime._markDirtyFromExternalResource()
            box.rerender()
        }
        let textCallback: omni_adw_text_callback = { actionID, text, context in
            guard let context else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            let rawID = Int(actionID)
            let next = text.map(String.init(cString:)) ?? ""
            if rawID >= adwaitaSettingsActionOffset {
                let settingsRawID = rawID - adwaitaSettingsActionOffset
                if let timestamp = TimeInterval(next), box.settingsRuntime.setDateForRawActionID(settingsRawID, timestamp: timestamp) {
                    box.settingsRuntime._markDirtyFromExternalResource()
                    box.runtime._markDirtyFromExternalResource()
                    box.rerender()
                    return
                }
                if let value = Double(next), box.settingsRuntime.setDoubleForRawActionID(settingsRawID, value: value) {
                    box.settingsRuntime._markDirtyFromExternalResource()
                    box.runtime._markDirtyFromExternalResource()
                    box.rerender()
                    return
                }
                if box.settingsRuntime.setStringForRawActionID(settingsRawID, value: next) {
                    box.settingsRuntime._markDirtyFromExternalResource()
                    box.runtime._markDirtyFromExternalResource()
                    box.rerender()
                    return
                }
                let previous = box.textValuesByActionID[rawID] ?? ""
                _ = box.settingsRuntime.focusByRawActionID(settingsRawID)
                box.settingsRuntime.replaceTextForRawActionID(settingsRawID, previous: previous, next: next)
                box.textValuesByActionID[rawID] = next
                box.settingsRuntime._markDirtyFromExternalResource()
                box.runtime._markDirtyFromExternalResource()
                box.rerender()
                return
            }
            if let timestamp = TimeInterval(next), box.runtime.setDateForRawActionID(rawID, timestamp: timestamp) {
                box.rerender()
                return
            }
            if let value = Double(next), box.runtime.setDoubleForRawActionID(rawID, value: value) {
                box.rerender()
                return
            }
            if box.runtime.setStringForRawActionID(rawID, value: next) {
                box.rerender()
                return
            }
            let previous = box.textValuesByActionID[rawID] ?? ""
            let belongsToPresentedModal = box.previousModalRoot.map {
                AdwaitaNodeBuilder.textValues(in: $0).keys.contains(rawID)
            } ?? false
            _ = box.runtime.focusByRawActionID(rawID)
            box.runtime.replaceTextForRawActionID(rawID, previous: previous, next: next)
            box.textValuesByActionID[rawID] = next
            if !belongsToPresentedModal {
                box.rerender()
            }
        }
        let keyCallback: omni_adw_key_callback = { actionID, keyKind, codepoint, context in
            guard let context else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            let rawID = Int(actionID)
            if rawID >= adwaitaSettingsActionOffset {
                box.settingsRuntime.handleNativeKeyForRawActionID(rawID - adwaitaSettingsActionOffset, keyKind: Int(keyKind), codepoint: codepoint)
                box.settingsRuntime._markDirtyFromExternalResource()
                box.runtime._markDirtyFromExternalResource()
            } else {
                box.runtime.handleNativeKeyForRawActionID(rawID, keyKind: Int(keyKind), codepoint: codepoint)
            }
            box.rerender()
        }
        let focusCallback: omni_adw_focus_callback = { actionID, context in
            guard let context else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            let rawID = Int(actionID)
            let changed: Bool
            if rawID >= adwaitaSettingsActionOffset {
                changed = box.settingsRuntime.focusByRawActionID(rawID - adwaitaSettingsActionOffset)
            } else {
                changed = box.runtime.focusByRawActionID(rawID)
            }
            if changed {
                box.rerender()
            }
        }
        let eventCallback: omni_adw_event_callback = { eventType, x, y, clickCount, modifiers, keyval, codepoint, context in
            guard let context else { return 0 }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            let rawActionID = Int(keyval)
            if eventType == 1 || eventType == 2 || eventType == 5 {
                if eventType == 1, rawActionID > 0 {
                    if rawActionID >= adwaitaStatusItemActionOffset {
                        // Status-item actions do not originate from native drop targets.
                    } else if rawActionID >= adwaitaSettingsActionOffset {
                        box.settingsRuntime._recordNativeActivationPoint(
                            actionID: rawActionID - adwaitaSettingsActionOffset,
                            x: x,
                            y: y
                        )
                    } else if rawActionID >= adwaitaCommandActionOffset {
                        box.commandRuntime._recordNativeActivationPoint(
                            actionID: rawActionID - adwaitaCommandActionOffset,
                            x: x,
                            y: y
                        )
                    } else {
                        box.runtime._recordNativeActivationPoint(actionID: rawActionID, x: x, y: y)
                    }
                }
                let consumedByDrag: Bool
                if rawActionID >= adwaitaSettingsActionOffset {
                    consumedByDrag = box.settingsRuntime._handleNativeDragEvent(
                        actionID: rawActionID - adwaitaSettingsActionOffset,
                        eventType: Int(eventType),
                        x: x,
                        y: y
                    )
                } else {
                    consumedByDrag = box.runtime._handleNativeDragEvent(
                        actionID: rawActionID,
                        eventType: Int(eventType),
                        x: x,
                        y: y
                    )
                }
                if consumedByDrag {
                    box.rerender()
                    return 1
                }
            }
            let consumed = dispatchNativeEventToLocalMonitors(
                eventType: Int(eventType),
                x: x,
                y: y,
                clickCount: Int(clickCount),
                modifiers: modifiers,
                codepoint: codepoint
            )
            let passiveHighFrequencyEvent = eventType == 5 || eventType == 8
            if consumed || !passiveHighFrequencyEvent {
                box.rerender()
            }
            return consumed ? 1 : 0
        }
        let lifecycleCallback: omni_adw_lifecycle_callback = { eventType, _ in
            switch eventType {
            case 1:
                #if os(Linux)
                guard NSApp.applicationShouldTerminateAfterLastWindowClosed() else { return 0 }
                NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApp)
                return 1
                #else
                return 1
                #endif
            case 2:
                NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApp)
                return 1
            default:
                return 1
            }
        }

        _omniAdwaitaRendererEntryTrace("run before app_new")
        cApp = omni_adw_app_new(appID, title, callback, textCallback, keyCallback, focusCallback, box.toOpaque())
        _omniAdwaitaRendererEntryTrace("run after app_new")
        guard let cApp else {
            box.release()
            throw OmniUIAdwaitaRendererError.unableToCreateApplication
        }
        omni_adw_app_set_event_callback(cApp, eventCallback)
        omni_adw_app_set_lifecycle_callback(cApp, lifecycleCallback)
        let appHandle = cApp
        #if os(Linux)
        let appHandleBits = UInt(bitPattern: appHandle)
        _omniSetApplicationActivationHandler {
            if let handle = OpaquePointer(bitPattern: appHandleBits) {
                omni_adw_app_present_main_window(handle)
            }
        }
        _omniSetCursorHandler { cursorName in
            guard let handle = OpaquePointer(bitPattern: appHandleBits) else { return }
            if let cursorName {
                cursorName.withCString { pointer in
                    omni_adw_app_set_cursor(handle, pointer)
                }
            } else {
                omni_adw_app_set_cursor(handle, nil)
            }
        }
        #endif
        defer {
            #if os(Linux)
            _omniSetApplicationActivationHandler(nil)
            _omniSetCursorHandler(nil)
            #endif
        }
        runtime.setDefaultOpenURLAction(OpenURLAction { url in
            url.absoluteString.withCString { value in
                omni_adw_app_share_url(appHandle, value)
            }
            return .handled
        })
        runtime.setDefaultShareURLAction(OpenURLAction { url in
            url.absoluteString.withCString { value in
                omni_adw_app_share_url(appHandle, value)
            }
            return .handled
        })
        runtime.setDefaultOpenSettingsAction(OpenSettingsAction {
            omni_adw_app_present_settings(appHandle)
        })
        let windowSize = nativeWindowSize(for: size)
        let renderSize = semanticRenderSize(for: size)
        omni_adw_app_set_default_size(cApp, Int32(windowSize.width), Int32(windowSize.height))
        var initialPreferredColorScheme: ColorScheme?
        if let settings {
            let snapshot = settingsRuntime.semanticSnapshot(settings(), size: renderSize)
            initialPreferredColorScheme = settingsRuntime.lastPreferredColorScheme
            let settingsRoot = AdwaitaNodeBuilder.offsetActionIDs(in: snapshot.root, by: adwaitaSettingsActionOffset)
            box.takeUnretainedValue().previousSettingsRoot = settingsRoot
            AdwaitaSemanticDumper.dumpIfRequested(settingsRoot, section: "SETTINGS")
            if let node = AdwaitaNodeBuilder.build(settingsRoot) {
                omni_adw_app_set_settings(cApp, node)
            }
        }
        if let commands {
            let snapshot = commandRuntime.semanticSnapshot(commands(), size: renderSize)
            let commandRoot = AdwaitaNodeBuilder.offsetActionIDs(in: snapshot.root, by: adwaitaCommandActionOffset)
            box.takeUnretainedValue().previousCommandRoot = commandRoot
            AdwaitaSemanticDumper.dumpIfRequested(commandRoot, section: "COMMANDS")
            if let node = AdwaitaNodeBuilder.build(commandRoot) {
                omni_adw_app_set_commands(cApp, node)
            }
        }
        #if os(Linux) || os(macOS)
        if initialPreferredColorScheme != nil {
            syncPreferredColorScheme(initialPreferredColorScheme)
        }
        #endif
        defer {
            omni_adw_app_free(cApp)
            box.release()
        }

        let rerender: @MainActor () -> Void = { [runtime, settingsRuntime, popoverRuntime, root, settings, renderSize] in
            let traceRenders = ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_RENDER_TRACE"] == "1"
            if traceRenders {
                print("OmniUI Adwaita rerender: begin")
            }
            var activePreferredColorScheme: ColorScheme?
            if let settings {
                let settingsSnapshot = settingsRuntime.semanticSnapshot(settings(), size: renderSize)
                activePreferredColorScheme = settingsRuntime.lastPreferredColorScheme
                let settingsRoot = AdwaitaNodeBuilder.offsetActionIDs(in: settingsSnapshot.root, by: adwaitaSettingsActionOffset)
                box.takeUnretainedValue().previousSettingsRoot = settingsRoot
                AdwaitaSemanticDumper.dumpIfRequested(settingsRoot, section: "SETTINGS")
                if let node = AdwaitaNodeBuilder.build(settingsRoot) {
                    omni_adw_app_set_settings(cApp, node)
                }
            }
            let snapshot = runtime.semanticSnapshot(root(), size: renderSize)
            activePreferredColorScheme = runtime.lastPreferredColorScheme ?? activePreferredColorScheme
            if traceRenders {
                print("OmniUI Adwaita rerender: semantic snapshot ready")
            }
            #if os(Linux) || os(macOS)
            syncPreferredColorScheme(activePreferredColorScheme)
            #endif
            AdwaitaSemanticDumper.dumpIfRequested(snapshot.root, section: "RAW")
            let presentation = AdwaitaPresentationExtractor.extract(from: snapshot.root)
            AdwaitaSemanticDumper.dumpToolbarIfRequested(presentation.toolbar)
            let displaySnapshot = SemanticSnapshot(
                root: presentation.root,
                size: snapshot.size,
                focusedActionID: snapshot.focusedActionID,
                activeMenu: snapshot.activeMenu,
                activePicker: snapshot.activePicker,
                activeTextField: snapshot.activeTextField
            )
            AdwaitaSemanticDumper.dumpIfRequested(displaySnapshot.root, section: "MAIN")
            if let title = presentation.toolbar.title {
                title.withCString { omni_adw_app_set_header_title(cApp, $0) }
            }
            syncNativeHeaderEntry(presentation.toolbar.entry, app: cApp)
            syncNativeHeaderActions(presentation.toolbar.actions, app: cApp)
            let callbackBox = box.takeUnretainedValue()
            callbackBox.previousToolbar = presentation.toolbar
            let previousModalRoot = callbackBox.previousModalRoot
            let transientPresentation = presentation.modal ?? appKitTransientPresentation(runtime: popoverRuntime, size: renderSize)
            if let transientPresentation {
                AdwaitaSemanticDumper.dumpIfRequested(transientPresentation, section: "MODAL")
            }
            let changes = callbackBox.previousSnapshot.map {
                SemanticDiff.changes(from: $0, to: displaySnapshot)
            } ?? []
            if traceRenders {
                print("OmniUI Adwaita rerender: changes=\(changes.count)")
            }
            callbackBox.lastChanges = changes
            callbackBox.textValuesByActionID = adwaitaTextValues(box: callbackBox, displayRoot: displaySnapshot.root, modalRoot: transientPresentation)
            if let entry = presentation.toolbar.entry {
                callbackBox.textValuesByActionID[entry.actionID] = entry.text
            }
            if changes.isEmpty, callbackBox.previousSnapshot != nil {
                syncNativePresentation(transientPresentation, previous: previousModalRoot, focusedActionID: displaySnapshot.focusedActionID, app: cApp)
                callbackBox.previousModalRoot = transientPresentation
                callbackBox.previousSnapshot = displaySnapshot
                return
            }
            if !changes.isEmpty, AdwaitaNodeBuilder.applyLeafUpdates(changes: changes, snapshot: displaySnapshot, app: cApp) {
                syncNativePresentation(transientPresentation, previous: previousModalRoot, focusedActionID: displaySnapshot.focusedActionID, app: cApp)
                callbackBox.previousModalRoot = transientPresentation
                callbackBox.previousSnapshot = displaySnapshot
                return
            }
            if
                !changes.isEmpty,
                let previousSnapshot = callbackBox.previousSnapshot,
                AdwaitaNodeBuilder.applyStructuralReplacement(
                    changes: changes,
                    previous: previousSnapshot.root,
                    next: displaySnapshot.root,
                    focusedActionID: displaySnapshot.focusedActionID,
                    app: cApp
                )
            {
                syncNativePresentation(transientPresentation, previous: previousModalRoot, focusedActionID: displaySnapshot.focusedActionID, app: cApp)
                callbackBox.previousModalRoot = transientPresentation
                callbackBox.previousSnapshot = displaySnapshot
                return
            }
            guard let node = AdwaitaNodeBuilder.build(displaySnapshot.root) else { return }
            omni_adw_app_set_root_focused(cApp, node, Int32(displaySnapshot.focusedActionID ?? 0))
            syncNativePresentation(transientPresentation, previous: previousModalRoot, focusedActionID: displaySnapshot.focusedActionID, app: cApp)
            callbackBox.previousModalRoot = transientPresentation
            callbackBox.previousSnapshot = displaySnapshot
            if traceRenders {
                print("OmniUI Adwaita rerender: full root set")
            }
        }
        box.takeUnretainedValue().rerender = {
            scheduleAdwaitaRender(rerender)
        }
        #if os(Linux) || os(macOS)
        _omniSetAppearanceChangeHandler { [runtime, settingsRuntime, commandRuntime, popoverRuntime, box] scheme in
            let nativeScheme = nativeColorSchemeName(preferredScheme: scheme)
            nativeScheme.withCString { omni_adw_set_color_scheme($0) }
            Task { @MainActor in
                runtime._markDirtyFromExternalResource()
                settingsRuntime._markDirtyFromExternalResource()
                commandRuntime._markDirtyFromExternalResource()
                popoverRuntime._markDirtyFromExternalResource()
                box.takeUnretainedValue().rerender()
            }
        }
        defer {
            _omniSetAppearanceChangeHandler(nil)
        }
        #endif
        let remoteDocumentObserver = NotificationCenter.default.addObserver(
            forName: _OmniRemoteDocumentRegistry.didUpdateNotification,
            object: nil,
            queue: nil
        ) { [runtime] _ in
            Task { @MainActor in
                runtime._markDirtyFromExternalResource()
                rerender()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(remoteDocumentObserver)
        }
        let userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil
        ) { [runtime, settingsRuntime, commandRuntime, popoverRuntime] _ in
            Task { @MainActor in
                runtime._markDirtyFromExternalResource()
                settingsRuntime._markDirtyFromExternalResource()
                commandRuntime._markDirtyFromExternalResource()
                popoverRuntime._markDirtyFromExternalResource()
                rerender()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(userDefaultsObserver)
        }
        #if os(Linux)
        let statusItemObserver = NotificationCenter.default.addObserver(
            forName: NSStatusBar.didChangeStatusItemsNotification,
            object: nil,
            queue: nil
        ) { [runtime] _ in
            Task { @MainActor in
                runtime._markDirtyFromExternalResource()
                rerender()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(statusItemObserver)
        }
        let popoverObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didChangePopoverNotification,
            object: nil,
            queue: nil
        ) { [popoverRuntime] _ in
            Task { @MainActor in
                popoverRuntime._markDirtyFromExternalResource()
                rerender()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(popoverObserver)
        }
        let menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didChangeActiveMenuNotification,
            object: nil,
            queue: nil
        ) { [popoverRuntime] _ in
            Task { @MainActor in
                popoverRuntime._markDirtyFromExternalResource()
                rerender()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(menuObserver)
        }
        #endif
        _omniAdwaitaRendererEntryTrace("run initial rerender")
        rerender()
        configureAdwaitaSettingsOnLaunchIfRequested(appHandle)
        runAdwaitaAutomationIfRequested(box: box.takeUnretainedValue(), rerender: rerender)
        _omniAdwaitaRendererEntryTrace("run before gtk")
        let observationRenderLoop = Task { @MainActor [runtime, renderSize] in
            let traceRenders = ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_RENDER_TRACE"] == "1"
            var remoteDocumentVersion = _OmniRemoteDocumentRegistry.version
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000)
                let hadActiveAnimations = runtime._hasActiveAnimations
                if hadActiveAnimations {
                    _ = runtime._tickAnimations()
                }
                let latestRemoteDocumentVersion = _OmniRemoteDocumentRegistry.version
                let hadRemoteDocumentUpdate = latestRemoteDocumentVersion != remoteDocumentVersion
                if hadRemoteDocumentUpdate {
                    remoteDocumentVersion = latestRemoteDocumentVersion
                    runtime._markDirtyFromExternalResource()
                }
                let invalidationReason = runtime.renderInvalidationReason(size: renderSize)
                if hadActiveAnimations || invalidationReason != nil || hadRemoteDocumentUpdate {
                    if traceRenders {
                        let reason = hadRemoteDocumentUpdate ? "remote-document" : (hadActiveAnimations ? "animation" : (invalidationReason ?? "unknown"))
                        print("OmniUI Adwaita render invalidation: \(reason)")
                    }
                    rerender()
                }
            }
        }
        defer {
            observationRenderLoop.cancel()
        }

        let mainRunLoopTick: omni_adw_tick_callback = { _ in
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
        }
        let mainRunLoopTickSource = omni_adw_app_add_tick_callback(cApp, 16, mainRunLoopTick, nil)
        defer {
            omni_adw_app_remove_tick_callback(mainRunLoopTickSource)
        }

        let argc: Int32 = 0
        _ = omni_adw_app_run(cApp, argc, nil)
        _omniAdwaitaRendererEntryTrace("run after gtk")
    }
}

private func syncPreferredColorScheme(_ scheme: ColorScheme?) {
#if os(Linux) || os(macOS)
    _omniSetPreferredColorScheme(scheme)
#endif
    let nativeScheme = nativeColorSchemeName(preferredScheme: scheme)
    nativeScheme.withCString { omni_adw_set_color_scheme($0) }
}

private func nativeColorSchemeName(preferredScheme scheme: ColorScheme?) -> String {
    #if os(Linux) || os(macOS)
    let currentAppearance = _omniCurrentAppearanceColorScheme()
    #else
    let currentAppearance: ColorScheme? = nil
    #endif
    switch scheme ?? currentAppearance ?? environmentColorSchemeOverride() {
    case .some(.light):
        return "light"
    case .some(.dark):
        return "dark"
    case .none:
        return "system"
    }
}

private func environmentColorSchemeOverride() -> ColorScheme? {
    let environment = ProcessInfo.processInfo.environment
    for key in ["OMNIUI_ADWAITA_COLOR_SCHEME", "OMNIUI_COLOR_SCHEME"] {
        guard let value = environment[key]?.lowercased(), !value.isEmpty else { continue }
        if value.contains("dark") { return .dark }
        if value.contains("light") { return .light }
    }
    if let gtkTheme = environment["GTK_THEME"]?.lowercased(), gtkTheme.contains("dark") {
        return .dark
    }
    return nil
}

private func scheduleAdwaitaRender(_ render: @MainActor @escaping () -> Void) {
    #if os(Linux)
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            render()
        }
        return
    }
    #endif
    Task { @MainActor in
        render()
    }
}

@MainActor
private enum AdwaitaSemanticDumper {
    private static var didDumpSections = Set<String>()

    static func dumpIfRequested(_ root: SemanticNode, section: String = "MAIN") {
        let environment = ProcessInfo.processInfo.environment
        let dumpEveryFrame = environment["OMNIUI_ADWAITA_DUMP_SEMANTIC_EACH"] == "1"
        guard environment["OMNIUI_ADWAITA_DUMP_SEMANTIC"] == "1" || dumpEveryFrame else {
            return
        }
        guard dumpEveryFrame || didDumpSections.insert(section).inserted else {
            return
        }
        write("OMNIUI_ADWAITA_SEMANTIC_BEGIN \(section)")
        dump(root, depth: 0)
        write("OMNIUI_ADWAITA_SEMANTIC_END \(section)")
    }

    static func dumpToolbarIfRequested(_ toolbar: AdwaitaHeaderToolbar, section: String = "TOOLBAR") {
        let environment = ProcessInfo.processInfo.environment
        let dumpEveryFrame = environment["OMNIUI_ADWAITA_DUMP_SEMANTIC_EACH"] == "1"
        guard environment["OMNIUI_ADWAITA_DUMP_SEMANTIC"] == "1" || dumpEveryFrame else {
            return
        }
        guard dumpEveryFrame || didDumpSections.insert(section).inserted else {
            return
        }
        write("OMNIUI_ADWAITA_SEMANTIC_BEGIN \(section)")
        if let title = toolbar.title {
            write("  title \(String(reflecting: title))")
        }
        if let entry = toolbar.entry {
            write(
                "  entry(actionID: \(entry.actionID), placeholder: \(String(reflecting: entry.placeholder)), text: \(String(reflecting: entry.text)))"
            )
        }
        for action in toolbar.actions {
            write(
                "  action(actionID: \(action.actionID), placement: \(action.placement), segmented: \(action.isSegmented), selected: \(action.isSelected), label: \(String(reflecting: action.label)))"
            )
        }
        write("OMNIUI_ADWAITA_SEMANTIC_END \(section)")
    }

    private static func dump(_ node: SemanticNode, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        write("\(indent)\(node.id) \(String(describing: node.kind))")
        for child in node.children {
            dump(child, depth: depth + 1)
        }
    }

    private static func write(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

public extension AdwaitaApp where Root == AnyView {
    @MainActor
    convenience init<S: Scene>(
        appID: String = "dev.omnikit.KitchenSinkAdwaita",
        title: String = "OmniUI Adwaita",
        size: _Size = _Size(width: 120, height: 42),
        scene: S
    ) {
        let resolvedSize = _scenePreferredSize(scene).map {
            _Size(width: max(1, Int($0.width.rounded())), height: max(1, Int($0.height.rounded())))
        } ?? size
        let sceneSettings = _sceneSettingsView(scene)
        let sceneCommands = _sceneCommandsView(scene)
        let settingsProvider: (@MainActor () -> AnyView)?
        if let sceneSettings {
            settingsProvider = { sceneSettings }
        } else {
            settingsProvider = nil
        }
        let commandsProvider: (@MainActor () -> AnyView)?
        if let sceneCommands {
            commandsProvider = { sceneCommands }
        } else {
            commandsProvider = nil
        }
        self.init(
            appID: appID,
            title: title,
            size: resolvedSize,
            settings: settingsProvider,
            commands: commandsProvider
        ) {
            _sceneRootView(scene) ?? AnyView(Text("Empty Scene"))
        }
    }

    @MainActor
    convenience init<A: App>(
        appID: String = "dev.omnikit.KitchenSinkAdwaita",
        title: String = "OmniUI Adwaita",
        size: _Size = _Size(width: 120, height: 42),
        _ appType: A.Type
    ) {
        self.init(appID: appID, title: title, size: size, scene: A.init().body)
    }
}

private func nativeWindowSize(for size: _Size) -> (width: Int, height: Int) {
    let width = size.width <= 240 ? size.width * 9 : size.width
    let height = size.height <= 120 ? size.height * 18 : size.height
    return (max(320, width), max(240, height))
}

private func semanticRenderSize(for size: _Size) -> _Size {
    _Size(
        width: size.width > 240 ? max(1, size.width / 9) : size.width,
        height: size.height > 120 ? max(1, size.height / 18) : size.height
    )
}

public extension App {
    @MainActor
    static func adwaitaMain(
        appID: String = "dev.omnikit.OmniUIAdwaita",
        title: String = "OmniUI Adwaita",
        size: _Size = _Size(width: 120, height: 42)
    ) async throws {
        _omniAdwaitaRendererEntryTrace("adwaitaMain begin app=\(String(reflecting: Self.self))")
        try await AdwaitaApp(appID: appID, title: title, size: size, Self.self).run()
        _omniAdwaitaRendererEntryTrace("adwaitaMain end app=\(String(reflecting: Self.self))")
    }
}

private func _omniAdwaitaRendererEntryTrace(_ message: String) {
    guard let raw = getenv("OMNIKIT_ADWAITA_ENTRY_TRACE"),
          let value = String(validatingCString: raw),
          !value.isEmpty,
          value != "0",
          value.lowercased() != "false" else {
        return
    }
    FileHandle.standardError.write(Data("[OmniKit Adwaita entry] \(message)\n".utf8))
}

private final class CallbackBox: @unchecked Sendable {
    let runtime: _UIRuntime
    let settingsRuntime: _UIRuntime
    let commandRuntime: _UIRuntime
    let popoverRuntime: _UIRuntime
    var rerender: @Sendable () -> Void
    var textValuesByActionID: [Int: String] = [:]
    var previousSnapshot: SemanticSnapshot?
    var previousSettingsRoot: SemanticNode?
    var previousCommandRoot: SemanticNode?
    var previousModalRoot: SemanticNode?
    var previousToolbar: AdwaitaHeaderToolbar?
    var didCompleteAutomationSequence = false
    var lastChanges: [SemanticChange] = []

    init(runtime: _UIRuntime, settingsRuntime: _UIRuntime, commandRuntime: _UIRuntime, popoverRuntime: _UIRuntime, rerender: @escaping @Sendable () -> Void) {
        self.runtime = runtime
        self.settingsRuntime = settingsRuntime
        self.commandRuntime = commandRuntime
        self.popoverRuntime = popoverRuntime
        self.rerender = rerender
    }
}

@MainActor
private func invokeAdwaitaRawAction(_ rawID: Int, box: CallbackBox) {
    if rawID >= adwaitaStatusItemActionOffset {
        #if os(Linux)
        NSStatusBar.system.performStatusItem(at: rawID - adwaitaStatusItemActionOffset)
        #endif
    } else if rawID >= adwaitaSettingsActionOffset {
        box.settingsRuntime.invokeActionByRawID(rawID - adwaitaSettingsActionOffset)
        box.settingsRuntime._markDirtyFromExternalResource()
        box.runtime._markDirtyFromExternalResource()
    } else if rawID >= adwaitaCommandActionOffset {
        box.commandRuntime.invokeActionByRawID(rawID - adwaitaCommandActionOffset)
        box.runtime._markDirtyFromExternalResource()
    } else {
        box.runtime.invokeActionByRawID(rawID)
    }
}

@discardableResult
@MainActor
private func invokeAdwaitaSettingsFallback(box: CallbackBox) -> Bool {
    for label in ["Settings", "Preferences"] {
        if invokeAdwaitaLabel(label, box: box) {
            return true
        }
    }
    return false
}

private func adwaitaActionID(matchingVisibleText label: String, in node: SemanticNode) -> Int? {
    switch node.kind {
    case .button(let actionID, _), .tapTarget(let actionID, _), .toggle(let actionID, _, _):
        let accessibleLabel = AdwaitaReconciliation.accessibleLabel(for: node).trimmingCharacters(in: .whitespacesAndNewlines)
        if accessibleLabel == label || adwaitaVisibleText(in: node).contains(label) {
            return actionID
        }
    case .menu(let actionID, let title, let value, _):
        if title == label || value == label {
            return actionID
        }
    case .textField(let actionID, let placeholder, let text, _, _, _):
        if placeholder == label || text == label {
            return actionID
        }
    case .textEditor(let actionID, let text, _, _):
        if text == label {
            return actionID
        }
    case .slider(let title, _, _, _, _, let setActionID, let decrementActionID, let incrementActionID):
        if title == label {
            return setActionID ?? incrementActionID ?? decrementActionID
        }
    case .stepper(let title, _, let decrementActionID, let incrementActionID):
        if title == label {
            return incrementActionID ?? decrementActionID
        }
    case .datePicker(let title, _, _, let setActionID, let decrementActionID, let incrementActionID):
        if title == label {
            return setActionID ?? incrementActionID ?? decrementActionID
        }
    default:
        break
    }
    for child in node.children {
        if let actionID = adwaitaActionID(matchingVisibleText: label, in: child) {
            return actionID
        }
    }
    return nil
}

private func adwaitaVisibleText(in node: SemanticNode) -> [String] {
    var values: [String] = []
    switch node.kind {
    case .text(let value), .image(let value), .disabledButton(let value):
        values.append(value)
    case .textField(_, let placeholder, let text, _, _, _),
         .disabledTextField(let placeholder, let text, _):
        values.append(placeholder)
        values.append(text)
    case .textEditor(_, let text, _, _):
        values.append(text)
    case .menu(_, let title, let value, _),
         .disabledMenu(let title, let value):
        values.append(title)
        values.append(value)
    case .disabledToggle(let label, _),
         .progress(let label, _),
         .slider(let label, _, _, _, _, _, _, _),
         .stepper(let label, _, _, _),
         .datePicker(let label, _, _, _, _, _),
         .segmentedControl(let label, _):
        values.append(label)
    case .webContent(_, _, let url, let label, let description):
        values.append(url)
        if let label { values.append(label) }
        if let description { values.append(description) }
    default:
        break
    }
    for child in node.children {
        values.append(contentsOf: adwaitaVisibleText(in: child))
    }
    return values.filter { !$0.isEmpty }
}

private func adwaitaTextValues(box: CallbackBox, displayRoot: SemanticNode, modalRoot: SemanticNode?) -> [Int: String] {
    var values: [Int: String] = [:]
    if let settingsRoot = box.previousSettingsRoot {
        values.merge(AdwaitaNodeBuilder.textValues(in: settingsRoot), uniquingKeysWith: { _, next in next })
    }
    if let commandRoot = box.previousCommandRoot {
        values.merge(AdwaitaNodeBuilder.textValues(in: commandRoot), uniquingKeysWith: { _, next in next })
    }
    if let modalRoot {
        values.merge(AdwaitaNodeBuilder.textValues(in: modalRoot), uniquingKeysWith: { _, next in next })
    }
    values.merge(AdwaitaNodeBuilder.textValues(in: displayRoot), uniquingKeysWith: { _, next in next })
    return values
}

private func adwaitaTextInput(matchingVisibleText label: String, in node: SemanticNode) -> (actionID: Int, text: String)? {
    switch node.kind {
    case .textField(let actionID, let placeholder, let text, _, _, _):
        if placeholder == label || text == label {
            return (actionID, text)
        }
    case .textEditor(let actionID, let text, _, _):
        if text == label {
            return (actionID, text)
        }
    default:
        break
    }
    for child in node.children {
        if let match = adwaitaTextInput(matchingVisibleText: label, in: child) {
            return match
        }
    }
    return nil
}

private func adwaitaTextInput(matchingVisibleText label: String, box: CallbackBox) -> (actionID: Int, text: String)? {
    let roots = [
        box.previousSettingsRoot,
        box.previousCommandRoot,
        box.previousModalRoot,
        box.previousSnapshot?.root,
    ]
    for root in roots {
        guard let root,
              let match = adwaitaTextInput(matchingVisibleText: label, in: root) else {
            continue
        }
        return match
    }
    return nil
}

@MainActor
private func replaceAdwaitaText(actionID rawID: Int, previous: String, next: String, box: CallbackBox) {
    if rawID >= adwaitaSettingsActionOffset {
        let settingsRawID = rawID - adwaitaSettingsActionOffset
        _ = box.settingsRuntime.focusByRawActionID(settingsRawID)
        box.settingsRuntime.replaceTextForRawActionID(settingsRawID, previous: previous, next: next)
        box.runtime._markDirtyFromExternalResource()
    } else if rawID >= adwaitaCommandActionOffset {
        let commandRawID = rawID - adwaitaCommandActionOffset
        _ = box.commandRuntime.focusByRawActionID(commandRawID)
        box.commandRuntime.replaceTextForRawActionID(commandRawID, previous: previous, next: next)
        box.runtime._markDirtyFromExternalResource()
    } else {
        _ = box.runtime.focusByRawActionID(rawID)
        box.runtime.replaceTextForRawActionID(rawID, previous: previous, next: next)
    }
    box.textValuesByActionID[rawID] = next
}

private func adwaitaPickerOptionActionID(title: String, option: String, in node: SemanticNode) -> Int? {
    if case .menu(_, let menuTitle, _, _) = node.kind,
       menuTitle == title {
        return adwaitaActionID(matchingVisibleText: option, in: node)
    }
    if !title.isEmpty,
       adwaitaVisibleText(in: node).contains(title),
       let actionID = adwaitaMenuOptionActionID(option: option, in: node) {
        return actionID
    }
    for child in node.children {
        if let actionID = adwaitaPickerOptionActionID(title: title, option: option, in: child) {
            return actionID
        }
    }
    return nil
}

private func adwaitaMenuOptionActionID(option: String, in node: SemanticNode) -> Int? {
    if case .menu = node.kind {
        return adwaitaActionID(matchingVisibleText: option, in: node)
    }
    for child in node.children {
        if let actionID = adwaitaMenuOptionActionID(option: option, in: child) {
            return actionID
        }
    }
    return nil
}

private func adwaitaPickerOptionActionID(title: String, option: String, box: CallbackBox) -> Int? {
    let roots = [
        box.previousSettingsRoot,
        box.previousCommandRoot,
        box.previousModalRoot,
        box.previousSnapshot?.root,
    ]
    for root in roots {
        guard let root,
              let actionID = adwaitaPickerOptionActionID(title: title, option: option, in: root) else {
            continue
        }
        return actionID
    }
    return nil
}

private func adwaitaContextMenuActionID(target: String, item: String, in node: SemanticNode) -> Int? {
    if case .modifier(.contextMenu(let items)) = node.kind,
       adwaitaVisibleText(in: node).contains(target),
       let match = items.first(where: { $0.label == item }) {
        return match.actionID
    }
    for child in node.children {
        if let actionID = adwaitaContextMenuActionID(target: target, item: item, in: child) {
            return actionID
        }
    }
    return nil
}

private func adwaitaContextMenuActionID(target: String, item: String, box: CallbackBox) -> Int? {
    let roots = [
        box.previousSettingsRoot,
        box.previousCommandRoot,
        box.previousModalRoot,
        box.previousSnapshot?.root,
    ]
    for root in roots {
        guard let root,
              let actionID = adwaitaContextMenuActionID(target: target, item: item, in: root) else {
            continue
        }
        return actionID
    }
    return nil
}

@MainActor
private func runAdwaitaAutomationIfRequested(box: CallbackBox, rerender: @MainActor @escaping () -> Void) {
    if runAdwaitaAutomationSequenceIfRequested(box: box, rerender: rerender) {
        dumpAdwaitaAutomationPasteboardIfRequested()
        return
    }
    scheduleAdwaitaAutomationSequenceRetriesIfNeeded(box: box, rerender: rerender)
    guard let raw = ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_AUTOMATION_ACTIONS"],
          !raw.isEmpty else {
        runAdwaitaLabelAutomationIfRequested(box: box, rerender: rerender)
        runAdwaitaPickerAutomationIfRequested(box: box, rerender: rerender)
        runAdwaitaContextMenuAutomationIfRequested(box: box, rerender: rerender)
        runAdwaitaTextAutomationIfRequested(box: box, rerender: rerender)
        dumpAdwaitaAutomationPasteboardIfRequested()
        return
    }
    let separators = CharacterSet(charactersIn: ", \n\t")
    let actionIDs = raw
        .components(separatedBy: separators)
        .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    if !actionIDs.isEmpty {
        for actionID in actionIDs {
            invokeAdwaitaRawAction(actionID, box: box)
            rerender()
        }
    }
    runAdwaitaLabelAutomationIfRequested(box: box, rerender: rerender)
    runAdwaitaPickerAutomationIfRequested(box: box, rerender: rerender)
    runAdwaitaContextMenuAutomationIfRequested(box: box, rerender: rerender)
    runAdwaitaTextAutomationIfRequested(box: box, rerender: rerender)
    dumpAdwaitaAutomationPasteboardIfRequested()
}

private func configureAdwaitaSettingsOnLaunchIfRequested(_ appHandle: OpaquePointer) {
    guard ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_PRESENT_SETTINGS"] == "1" else {
        return
    }
    omni_adw_app_present_settings_on_activate(appHandle, 1)
}

@discardableResult
@MainActor
private func runAdwaitaAutomationSequenceIfRequested(box: CallbackBox, rerender: @MainActor () -> Void) -> Bool {
    guard !box.didCompleteAutomationSequence else { return true }
    guard let raw = ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_AUTOMATION_SEQUENCE"],
          !raw.isEmpty else {
        return false
    }
    let steps = raw
        .components(separatedBy: CharacterSet.newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !steps.isEmpty else { return false }
    for step in steps {
        if let rawAction = step.droppingAdwaitaAutomationPrefix("action:"),
           let actionID = Int(rawAction.trimmingCharacters(in: .whitespacesAndNewlines)) {
            invokeAdwaitaRawAction(actionID, box: box)
            rerender()
            continue
        }
        if let label = step.droppingAdwaitaAutomationPrefix("label:") {
            guard invokeAdwaitaLabel(label.trimmingCharacters(in: .whitespacesAndNewlines), box: box) else {
                return false
            }
            rerender()
            continue
        }
        if let assignment = step.droppingAdwaitaAutomationPrefix("picker:"),
           let parsed = parseAdwaitaAutomationAssignment(assignment, trimValue: true),
           let actionID = adwaitaPickerOptionActionID(title: parsed.key, option: parsed.value, box: box) {
            invokeAdwaitaRawAction(actionID, box: box)
            rerender()
            continue
        }
        if let assignment = step.droppingAdwaitaAutomationPrefix("context:"),
           let parsed = parseAdwaitaAutomationAssignment(assignment, trimValue: true),
           let actionID = adwaitaContextMenuActionID(target: parsed.key, item: parsed.value, box: box) {
            invokeAdwaitaRawAction(actionID, box: box)
            rerender()
            continue
        }
        if let assignment = step.droppingAdwaitaAutomationPrefix("text:"),
           let parsed = parseAdwaitaAutomationAssignment(assignment, trimValue: false),
           let match = adwaitaTextInput(matchingVisibleText: parsed.key, box: box) {
            let previous = box.textValuesByActionID[match.actionID] ?? match.text
            replaceAdwaitaText(actionID: match.actionID, previous: previous, next: parsed.value, box: box)
            rerender()
            continue
        }
        return false
    }
    box.didCompleteAutomationSequence = true
    return true
}

@MainActor
private func scheduleAdwaitaAutomationSequenceRetriesIfNeeded(box: CallbackBox, rerender: @MainActor @escaping () -> Void) {
    guard ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_AUTOMATION_SEQUENCE"]?.isEmpty == false else {
        return
    }
    let delays: [UInt64] = [100_000_000, 300_000_000, 700_000_000, 1_200_000_000]
    for delay in delays {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !box.didCompleteAutomationSequence else { return }
            if runAdwaitaAutomationSequenceIfRequested(box: box, rerender: rerender) {
                dumpAdwaitaAutomationPasteboardIfRequested()
            }
        }
    }
}

private func parseAdwaitaAutomationAssignment(_ line: String, trimValue: Bool) -> (key: String, value: String)? {
    guard let separator = line.firstIndex(of: "=") else { return nil }
    let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
    var value = String(line[line.index(after: separator)...])
    if trimValue {
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard !key.isEmpty else { return nil }
    return (key, value)
}

private extension String {
    func droppingAdwaitaAutomationPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

private func dumpAdwaitaAutomationPasteboardIfRequested() {
    guard let path = ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_AUTOMATION_PASTEBOARD_DUMP"],
          !path.isEmpty else {
        return
    }
    #if canImport(AppKit)
    let value = NSPasteboard.general.string(forType: .string) ?? ""
    try? value.write(toFile: path, atomically: true, encoding: .utf8)
    #else
    try? "".write(toFile: path, atomically: true, encoding: .utf8)
    #endif
}

@MainActor
private func runAdwaitaLabelAutomationIfRequested(box: CallbackBox, rerender: @MainActor () -> Void) {
    guard let raw = ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_AUTOMATION_LABELS"],
          !raw.isEmpty else {
        return
    }
    let labels = raw
        .components(separatedBy: CharacterSet.newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !labels.isEmpty else { return }
    for label in labels {
        if invokeAdwaitaLabel(label, box: box) {
            rerender()
        }
    }
}

@discardableResult
@MainActor
private func invokeAdwaitaLabel(_ label: String, box: CallbackBox) -> Bool {
    let toolbarActionID = box.previousToolbar?.actions.first { $0.label == label }?.actionID
    let settingsActionID = box.previousSettingsRoot.flatMap {
        adwaitaActionID(matchingVisibleText: label, in: $0)
    }
    let commandActionID = box.previousCommandRoot.flatMap {
        adwaitaActionID(matchingVisibleText: label, in: $0)
    }
    let modalActionID = box.previousModalRoot.flatMap {
        adwaitaActionID(matchingVisibleText: label, in: $0)
    }
    let rootActionID = box.previousSnapshot.map { adwaitaActionID(matchingVisibleText: label, in: $0.root) } ?? nil
    guard let actionID = toolbarActionID ?? settingsActionID ?? commandActionID ?? modalActionID ?? rootActionID else {
        return false
    }
    invokeAdwaitaRawAction(actionID, box: box)
    return true
}

@MainActor
private func runAdwaitaPickerAutomationIfRequested(box: CallbackBox, rerender: @MainActor () -> Void) {
    guard let raw = ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_AUTOMATION_PICKERS"],
          !raw.isEmpty else {
        return
    }
    let selections = raw
        .components(separatedBy: CharacterSet.newlines)
        .compactMap { line -> (title: String, option: String)? in
            guard let separator = line.firstIndex(of: "=") else { return nil }
            let title = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let option = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !option.isEmpty else { return nil }
            return (title, option)
        }
    guard !selections.isEmpty else { return }
    for selection in selections {
        guard let actionID = adwaitaPickerOptionActionID(title: selection.title, option: selection.option, box: box) else {
            continue
        }
        invokeAdwaitaRawAction(actionID, box: box)
        rerender()
    }
}

@MainActor
private func runAdwaitaContextMenuAutomationIfRequested(box: CallbackBox, rerender: @MainActor () -> Void) {
    guard let raw = ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_AUTOMATION_CONTEXT_MENUS"],
          !raw.isEmpty else {
        return
    }
    let selections = raw
        .components(separatedBy: CharacterSet.newlines)
        .compactMap { line -> (target: String, item: String)? in
            guard let separator = line.firstIndex(of: "=") else { return nil }
            let target = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let item = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty, !item.isEmpty else { return nil }
            return (target, item)
        }
    guard !selections.isEmpty else { return }
    for selection in selections {
        guard let actionID = adwaitaContextMenuActionID(target: selection.target, item: selection.item, box: box) else {
            continue
        }
        invokeAdwaitaRawAction(actionID, box: box)
        rerender()
    }
}

@MainActor
private func runAdwaitaTextAutomationIfRequested(box: CallbackBox, rerender: @MainActor () -> Void) {
    guard let raw = ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_AUTOMATION_TEXT"],
          !raw.isEmpty else {
        return
    }
    let assignments = raw
        .components(separatedBy: CharacterSet.newlines)
        .compactMap { line -> (label: String, value: String)? in
            guard let separator = line.firstIndex(of: "=") else { return nil }
            let label = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...])
            guard !label.isEmpty else { return nil }
            return (label, value)
        }
    guard !assignments.isEmpty else { return }
    for assignment in assignments {
        guard let match = adwaitaTextInput(matchingVisibleText: assignment.label, box: box) else {
            continue
        }
        let previous = box.textValuesByActionID[match.actionID] ?? match.text
        replaceAdwaitaText(actionID: match.actionID, previous: previous, next: assignment.value, box: box)
        rerender()
    }
}

private struct AdwaitaPresentation {
    var root: SemanticNode
    var modal: SemanticNode?
    var toolbar: AdwaitaHeaderToolbar
}

private struct AdwaitaHeaderToolbar {
    private static let segmentedStyleFlag: Int32 = 1 << 0
    private static let selectedStyleFlag: Int32 = 1 << 1

    var entry: AdwaitaHeaderEntry?
    var title: String?
    var actions: [Action] = []

    struct Action {
        enum Placement: Int32 {
            case start = 0
            case end = 1
        }

        var label: String
        var actionID: Int
        var placement: Placement
        var isSegmented: Bool = false
        var isSelected: Bool = false

        var styleFlags: Int32 {
            (isSegmented ? segmentedStyleFlag : 0) |
            (isSelected ? selectedStyleFlag : 0)
        }
    }

    mutating func merge(_ other: AdwaitaHeaderToolbar) {
        if entry == nil {
            entry = other.entry
        }
        if title == nil {
            title = other.title
        }
        actions.append(contentsOf: other.actions)
    }

    static func extractToolbarBar(from node: SemanticNode) -> AdwaitaHeaderToolbar? {
        guard case .stack(let axis, _) = node.kind, axis == .vertical else { return nil }
        guard node.children.count == 2, isDivider(node.children[1]) else { return nil }
        let row = node.children[0]
        guard case .stack(let rowAxis, _) = row.kind, rowAxis == .horizontal else { return nil }

        if let split = AdwaitaHeaderEntry.extract(from: row.children),
           looksLikeNavigationToolbar(entry: split.entry, nodes: row.children) {
            var toolbar = AdwaitaHeaderToolbar()
            toolbar.entry = split.entry
            let startActions = headerActions(in: Array(row.children[..<split.index]), placement: .start)
            let endActions = headerActions(in: Array(row.children[(split.index + 1)...]), placement: .end)
            toolbar.actions.append(contentsOf: startActions)
            toolbar.actions.append(contentsOf: endActions)
            return toolbar
        }

        let segments = toolbarSegments(in: row.children)
        guard !segments.isEmpty else { return nil }
        var toolbar = AdwaitaHeaderToolbar()
        for (index, segment) in segments.enumerated() {
            let placement: Action.Placement = index == 0 ? .start : .end
            let actions = headerActions(in: segment, placement: placement)
            if actions.isEmpty {
                let title = textLabel(in: segment)
                if toolbar.title == nil, !title.isEmpty {
                    toolbar.title = title
                }
            } else {
                toolbar.actions.append(contentsOf: actions)
            }
        }
        return toolbar.title != nil || !toolbar.actions.isEmpty ? toolbar : nil
    }

    static func extractInlineToolbar(from node: SemanticNode) -> AdwaitaHeaderToolbar? {
        if let child = singleLayoutWrappedChild(in: node) {
            return extractInlineToolbar(from: child)
        }
        guard case .stack(let axis, _) = node.kind, axis == .horizontal else { return nil }
        guard let split = AdwaitaHeaderEntry.extract(from: node.children),
              looksLikeNavigationToolbar(entry: split.entry, nodes: node.children) else { return nil }

        var toolbar = AdwaitaHeaderToolbar()
        toolbar.entry = split.entry
        let startActions = headerActions(in: Array(node.children[..<split.index]), placement: .start)
        let endActions = headerActions(in: Array(node.children[(split.index + 1)...]), placement: .end)
        if startActions.isEmpty,
           endActions.isEmpty,
           !headerActions(in: [node.children[split.index]], placement: .end).isEmpty {
            return nil
        }
        toolbar.actions.append(contentsOf: startActions)
        toolbar.actions.append(contentsOf: endActions)
        return toolbar.entry != nil || !toolbar.actions.isEmpty ? toolbar : nil
    }

    private static func toolbarSegments(in children: [SemanticNode]) -> [[SemanticNode]] {
        var segments: [[SemanticNode]] = [[]]
        for child in children {
            if case .spacer = child.kind {
                if segments.last?.isEmpty == false {
                    segments.append([])
                }
            } else {
                segments[segments.count - 1].append(child)
            }
        }
        return segments.filter { !$0.isEmpty }
    }

    private static func singleLayoutWrappedChild(in node: SemanticNode) -> SemanticNode? {
        guard node.children.count == 1,
              case .modifier(let modifier) = node.kind else { return nil }
        switch modifier {
        case .padding, .frame, .background, .opacity, .offset, .accessibilityIdentifier,
             .accessibilityLabel, .accessibilityValue, .accessibilityHint, .help, .font,
             .foreground, .shadow, .glass, .crt, .noOp:
            return node.children[0]
        case .clip, .badge, .contextMenu, .dragSource:
            return nil
        }
    }

    private static func looksLikeNavigationToolbar(entry: AdwaitaHeaderEntry, nodes: [SemanticNode]) -> Bool {
        let entryText = "\(entry.placeholder) \(entry.text) \(entry.semanticHints.joined(separator: " "))".lowercased()
        let looksLikeURLField = entryText.contains("url") ||
            entryText.contains("gopher") ||
            entryText.contains("http") ||
            entryText.contains("address")
        guard looksLikeURLField else { return false }

        let labels = headerActions(in: nodes, placement: .end).map { $0.label.lowercased() }
        let navigationTerms = ["home", "back", "forward", "go", "share", "bookmark", "settings"]
        return labels.contains { label in
            navigationTerms.contains { label.contains($0) }
        }
    }

    private static func headerActions(in nodes: [SemanticNode], placement: Action.Placement) -> [Action] {
        var actions: [Action] = []
        func visit(_ node: SemanticNode, labelOverride: String? = nil) {
            switch node.kind {
            case .segmentedControl(_, let selectedIndex):
                actions.append(contentsOf: segmentedActions(in: node, placement: placement, selectedIndex: selectedIndex))
            case .button(let actionID, _), .tapTarget(let actionID, _):
                let visualLabel = AdwaitaReconciliation.accessibilityText(in: node).trimmingCharacters(in: .whitespacesAndNewlines)
                let label = (labelOverride ?? AdwaitaReconciliation.accessibleLabel(for: node)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !isSuppressedSystemHeaderAction(label: label, visualLabel: visualLabel) else { return }
                guard !label.isEmpty, label != "Action", label != "☰" else { return }
                actions.append(Action(label: label, actionID: actionID, placement: placement))
            case .disabledButton:
                let visualLabel = AdwaitaReconciliation.accessibilityText(in: node).trimmingCharacters(in: .whitespacesAndNewlines)
                let label = (labelOverride ?? AdwaitaReconciliation.accessibleLabel(for: node)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !isSuppressedSystemHeaderAction(label: label, visualLabel: visualLabel) else { return }
                guard !label.isEmpty, label != "Action", label != "☰" else { return }
                actions.append(Action(label: label, actionID: 0, placement: placement))
            case .menu(let actionID, let title, let value, _):
                let label = labelOverride ?? (value.isEmpty ? title : value)
                guard !label.isEmpty else { return }
                actions.append(Action(label: label, actionID: actionID, placement: placement))
            case .disabledToggle, .disabledMenu, .disabledTextField:
                return
            case .modifier(.accessibilityIdentifier(let identifier)):
                let override = headerLabel(forAccessibilityIdentifier: identifier) ?? labelOverride
                for child in node.children {
                    visit(child, labelOverride: override)
                }
            case .modifier(.help(let help)):
                let override = help.trimmingCharacters(in: .whitespacesAndNewlines)
                for child in node.children {
                    visit(child, labelOverride: override.isEmpty ? labelOverride : override)
                }
            case .stack, .group, .zstack, .container, .modifier:
                for child in node.children {
                    visit(child, labelOverride: labelOverride)
                }
            default:
                return
            }
        }
        for node in nodes {
            visit(node)
        }
        return actions
    }

    private static func headerLabel(forAccessibilityIdentifier identifier: String) -> String? {
        switch identifier {
        case "home-button":
            return "Home"
        case "back-button":
            return "Back"
        case "forward-button":
            return "Forward"
        case "add-bookmark-button":
            return "Add Bookmark"
        case "bookmarks-history-button":
            return "Bookmarks"
        case "share-button":
            return "Share"
        case "settings-button":
            return "Settings"
        case "go-button":
            return "Go"
        default:
            return nil
        }
    }

    private static func isSuppressedSystemHeaderAction(label: String, visualLabel: String) -> Bool {
        visualLabel == "☰" && label == "Toggle Sidebar"
    }

    private static func segmentedActions(in node: SemanticNode, placement: Action.Placement, selectedIndex: Int) -> [Action] {
        var buttons: [(label: String, actionID: Int)] = []
        func collect(_ current: SemanticNode) {
            if case .button(let actionID, _) = current.kind {
                let label = AdwaitaReconciliation.accessibleLabel(for: current).trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty, label != "Action" {
                    buttons.append((label, actionID))
                }
                return
            }
            for child in current.children {
                collect(child)
            }
        }
        collect(node)
        return buttons.enumerated().map { index, button in
            Action(
                label: toolbarSegmentLabel(button.label),
                actionID: button.actionID,
                placement: placement,
                isSegmented: true,
                isSelected: index == selectedIndex
            )
        }
    }

    private static func toolbarSegmentLabel(_ label: String) -> String {
        label == "both" ? "\u{25EB}" : label
    }

    private static func textLabel(in nodes: [SemanticNode]) -> String {
        var parts: [String] = []
        func visit(_ node: SemanticNode) {
            switch node.kind {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    parts.append(trimmed)
                }
            case .image, .webContent, .button, .menu, .toggle, .textField, .textEditor:
                return
            case .stack, .group, .zstack, .container, .modifier:
                for child in node.children {
                    visit(child)
                }
            default:
                return
            }
        }
        for node in nodes {
            visit(node)
        }
        return parts.joined(separator: " ")
    }

    private static func isDivider(_ node: SemanticNode) -> Bool {
        if case .divider = node.kind {
            return true
        }
        return false
    }
}

private struct AdwaitaHeaderEntry: Equatable {
    var placeholder: String
    var text: String
    var actionID: Int
    var semanticHints: [String]

    static func extract(from nodes: [SemanticNode]) -> (entry: AdwaitaHeaderEntry, index: Int)? {
        for (index, node) in nodes.enumerated() {
            if let entry = extract(from: node) {
                return (entry, index)
            }
        }
        return nil
    }

    static func extract(from node: SemanticNode) -> AdwaitaHeaderEntry? {
        switch node.kind {
        case .textField(let actionID, let placeholder, let text, _, _, let isSecure):
            guard !isSecure, actionID > 0 else { return nil }
            return AdwaitaHeaderEntry(
                placeholder: placeholder,
                text: text,
                actionID: actionID,
                semanticHints: semanticHints(in: node)
            )
        case .modifier:
            for child in node.children {
                if var entry = extract(from: child) {
                    entry.semanticHints.append(contentsOf: semanticHints(in: node))
                    return entry
                }
            }
            return nil
        case .stack, .group, .zstack, .container:
            for child in node.children {
                if let entry = extract(from: child) {
                    return entry
                }
            }
            return nil
        default:
            return nil
        }
    }

    private static func semanticHints(in node: SemanticNode) -> [String] {
        var hints: [String] = [node.id]
        if case .modifier(let modifier) = node.kind {
            switch modifier {
            case .accessibilityIdentifier(let value),
                 .accessibilityLabel(let value),
                 .help(let value),
                 .accessibilityHint(let value),
                 .accessibilityValue(let value):
                hints.append(value)
            default:
                break
            }
        }
        for child in node.children {
            hints.append(contentsOf: semanticHints(in: child))
        }
        return hints.filter { !$0.isEmpty }
    }
}

private enum AdwaitaPresentationExtractor {
    static func extract(from root: SemanticNode) -> AdwaitaPresentation {
        var modal: SemanticNode?
        var toolbar = AdwaitaHeaderToolbar()
        let cleaned = stripPresentation(from: root, modal: &modal, toolbar: &toolbar)
        return AdwaitaPresentation(root: cleaned ?? SemanticNode(id: root.id, kind: .empty), modal: modal, toolbar: toolbar)
    }

    private static func stripPresentation(from node: SemanticNode, modal: inout SemanticNode?, toolbar: inout AdwaitaHeaderToolbar) -> SemanticNode? {
        if isAdwaitaDialog(node) {
            modal = nativeDialogContent(from: node)
            return nil
        }
        if let toolbarBar = AdwaitaHeaderToolbar.extractToolbarBar(from: node) {
            toolbar.merge(toolbarBar)
            return nil
        }
        if let inlineToolbar = AdwaitaHeaderToolbar.extractInlineToolbar(from: node) {
            toolbar.merge(inlineToolbar)
            return nil
        }

        let children = node.children.compactMap { stripPresentation(from: $0, modal: &modal, toolbar: &toolbar) }
        if case .zstack = node.kind, children.count == 1 {
            return children[0]
        }
        return SemanticNode(id: node.id, kind: node.kind, children: children)
    }

    private static func isAdwaitaDialog(_ node: SemanticNode) -> Bool {
        if case .modifier(.background("adw-dialog")) = node.kind {
            return true
        }
        return false
    }

    private static func nativeDialogContent(from node: SemanticNode) -> SemanticNode {
        guard case .modifier(.background("adw-dialog")) = node.kind else {
            return node
        }
        let content = node.children.first(where: { $0.id.hasSuffix(".content") }) ?? node
        return presentationChromeContent(from: content) ?? content
    }

    private static func presentationChromeContent(from node: SemanticNode) -> SemanticNode? {
        if case .scroll(axis: .vertical, _, _) = node.kind {
            return node.children.first
        }

        if case .stack(axis: .vertical, _) = node.kind,
           let scroll = node.children.first(where: isVerticalScroll) {
            return scroll.children.first ?? scroll
        }

        if isTransparentPresentationWrapper(node) {
            for child in node.children {
                if let content = presentationChromeContent(from: child) {
                    return content
                }
            }
        }

        return nil
    }

    private static func isVerticalScroll(_ node: SemanticNode) -> Bool {
        if case .scroll(axis: .vertical, _, _) = node.kind {
            return true
        }
        return false
    }

    private static func isTransparentPresentationWrapper(_ node: SemanticNode) -> Bool {
        switch node.kind {
        case .group, .zstack:
            return true
        case .modifier(let modifier):
            switch modifier {
            case .background, .frame, .padding, .clip, .shadow, .glass, .font, .opacity, .offset, .help, .noOp:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}

private func syncNativePresentation(_ modal: SemanticNode?, previous: SemanticNode?, focusedActionID: Int?, app: OpaquePointer?) {
    guard let app else { return }
    guard let modal else {
        omni_adw_app_dismiss_modal(app)
        return
    }
    if let previous {
        let changes = SemanticDiff.changes(from: previous, to: modal)
        if changes.isEmpty {
            return
        }
        if AdwaitaNodeBuilder.applyLeafUpdates(changes: changes, root: modal, app: app) {
            return
        }
        if AdwaitaNodeBuilder.applyStructuralReplacement(
            changes: changes,
            previous: previous,
            next: modal,
            focusedActionID: focusedActionID,
            app: app
        ) {
            return
        }
    }
    if shouldPresentModalInSettingsWindow(modal),
       let node = AdwaitaNodeBuilder.build(modal) {
        omni_adw_app_set_settings(app, node)
        omni_adw_app_present_settings(app)
        return
    }
    guard let node = AdwaitaNodeBuilder.build(modal) else {
        omni_adw_app_dismiss_modal(app)
        return
    }
    omni_adw_app_present_modal(app, node, "Presentation")
}

private func shouldPresentModalInSettingsWindow(_ node: SemanticNode) -> Bool {
    containsFormContainer(node) && !containsDismissButton(node)
}

private func containsFormContainer(_ node: SemanticNode) -> Bool {
    if case .container(.form) = node.kind {
        return true
    }
    return node.children.contains(where: containsFormContainer)
}

private func containsDismissButton(_ node: SemanticNode) -> Bool {
    switch node.kind {
    case .button, .tapTarget:
        let label = adwaitaVisibleText(in: node).joined(separator: " ")
        if ["Cancel", "Close", "Done", "OK"].contains(where: { label.localizedCaseInsensitiveContains($0) }) {
            return true
        }
    default:
        break
    }
    return node.children.contains(where: containsDismissButton)
}

@MainActor
private func appKitTransientPresentation(runtime: _UIRuntime, size: _Size) -> SemanticNode? {
    #if os(Linux)
    if let content = NSMenu.activeContentView {
        return runtime.semanticSnapshot(content, size: size).root
    }
    guard let content = NSPopover.activeContentView else { return nil }
    return runtime.semanticSnapshot(content, size: size).root
    #else
    _ = runtime
    _ = size
    return nil
    #endif
}

@MainActor
private func syncNativeHeaderActions(_ actions: [AdwaitaHeaderToolbar.Action], app: OpaquePointer?) {
    guard let app else { return }
    var allActions = actions
    #if os(Linux)
    allActions.append(contentsOf: NSStatusBar.system.fallbackLabels.enumerated().map { index, label in
        AdwaitaHeaderToolbar.Action(label: label, actionID: adwaitaStatusItemActionOffset + index, placement: .end)
    })
    #endif
    let labels = allActions.map(\.label)
    var ids = allActions.map { Int32($0.actionID) }
    var placements = allActions.map { $0.placement.rawValue }
    var styles = allActions.map(\.styleFlags)
    labels.withCStringArray { labelPointers in
        ids.withUnsafeMutableBufferPointer { idBuffer in
            placements.withUnsafeMutableBufferPointer { placementBuffer in
                styles.withUnsafeMutableBufferPointer { styleBuffer in
                    omni_adw_app_set_header_actions(
                        app,
                        labelPointers,
                        idBuffer.baseAddress,
                        placementBuffer.baseAddress,
                        styleBuffer.baseAddress,
                        Int32(allActions.count)
                    )
                }
            }
        }
    }
}

private func syncNativeHeaderEntry(_ entry: AdwaitaHeaderEntry?, app: OpaquePointer?) {
    guard let app else { return }
    let placeholder = entry?.placeholder ?? ""
    let text = entry?.text ?? ""
    let actionID = Int32(entry?.actionID ?? 0)
    placeholder.withCString { placeholderPointer in
        text.withCString { textPointer in
            omni_adw_app_set_header_entry(app, placeholderPointer, textPointer, actionID)
        }
    }
}

public enum AdwaitaSemanticCoverage {
    public static let supported: [String] = [
        "App", "Scene", "WindowGroup", "Settings", "commands",
        "@State", "@Binding", "@Environment", "@AppStorage", "@FocusState", "@Namespace", "@Bindable",
        "SwiftData @Query", "modelContainer", "modelContext",
        "NavigationStack", "NavigationSplitView", "VStack", "HStack", "ZStack",
        "Form", "List", "ScrollView", "ScrollViewReader", "LazyVStack", "GeometryReader",
        "Text", "Image", "Button", "Toggle", "TextField", "SecureField", "TextEditor", "ProgressView", "Slider", "Stepper", "DatePicker", "Picker", "Menu",
        "Toolbar", "Sheet", "Alert", "layout/style/input/accessibility modifiers",
        "Canvas", "Path", "Shape", "Gradient drawing islands",
        "Liquid Glass and CRT native-style approximations",
    ]

    public static let approximations: [String] = [
        "Canvas/Path/shapes/gradients lower to GTK drawing islands when no native widget exists.",
        "Liquid Glass maps to libadwaita card/header styling; CRT scanlines, vignette gradients, and glow shadows lower to pass-through drawing/CSS overlays.",
        "Arbitrary SwiftUI animation curves are reconciled by rebuilding native widgets after state actions.",
    ]
}

public struct AdwaitaNativeLeafUpdate: Sendable, Equatable {
    public enum Kind: Int32, Sendable, Equatable {
        case text = 0
        case button = 1
        case toggle = 2
        case textField = 3
        case textEditor = 4
        case dropdown = 5
        case progress = 6
        case slider = 7
        case stepper = 8
        case datePicker = 9
        case scroll = 10
        case colorPicker = 11
    }

    public let id: String
    public let kind: Kind
    public let text: String
    public let active: Bool

    public init(id: String, kind: Kind, text: String, active: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.active = active
    }
}

public struct AdwaitaNativeSubtreeReplacement: Sendable, Equatable {
    public let id: String
    public let node: SemanticNode

    public init(id: String, node: SemanticNode) {
        self.id = id
        self.node = node
    }

    public static func == (lhs: AdwaitaNativeSubtreeReplacement, rhs: AdwaitaNativeSubtreeReplacement) -> Bool {
        lhs.id == rhs.id &&
            lhs.node.id == rhs.node.id &&
            lhs.node.kind == rhs.node.kind &&
            lhs.node.children.map(\.id) == rhs.node.children.map(\.id)
    }
}

public enum AdwaitaReconciliation {
    public static func leafUpdates(changes: [SemanticChange], snapshot: SemanticSnapshot) -> [AdwaitaNativeLeafUpdate]? {
        leafUpdates(changes: changes, root: snapshot.root)
    }

    public static func leafUpdates(changes: [SemanticChange], root: SemanticNode) -> [AdwaitaNativeLeafUpdate]? {
        let nodes = nodesByID(in: root)
        var updates: [AdwaitaNativeLeafUpdate] = []
        for change in changes {
            guard change.kind == .updated, let node = nodes[change.id], let update = nativeLeafUpdate(for: node) else {
                return nil
            }
            updates.append(update)
        }
        return updates
    }

    public static func subtreeReplacement(changes: [SemanticChange], previous: SemanticNode, next: SemanticNode) -> AdwaitaNativeSubtreeReplacement? {
        guard !changes.isEmpty else { return nil }
        if leafUpdates(changes: changes, root: next) != nil {
            return nil
        }

        let previousNodes = nodesByID(in: previous)
        let nextNodes = nodesByID(in: next)
        let candidateIDs = Set(changes.compactMap { replacementCandidateID(for: $0) })
        guard let candidateID = replacementAncestor(in: candidateIDs, previousNodes: previousNodes, nextNodes: nextNodes) else { return nil }
        guard let nextNode = nextNodes[candidateID] else { return nil }
        return AdwaitaNativeSubtreeReplacement(id: candidateID, node: nextNode)
    }

    private static func replacementAncestor(
        in candidateIDs: Set<String>,
        previousNodes: [String: SemanticNode],
        nextNodes: [String: SemanticNode]
    ) -> String? {
        let existingCandidates = candidateIDs.filter { previousNodes[$0] != nil && nextNodes[$0] != nil }
        let sorted = existingCandidates.sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs < rhs }
            return lhs.count < rhs.count
        }
        return sorted.first { candidate in
            candidateIDs.allSatisfy { id in
                id == candidate || id.hasPrefix(candidate + ".")
            }
        }
    }

    private static func replacementCandidateID(for change: SemanticChange) -> String? {
        switch change.kind {
        case .childrenReordered:
            return change.id
        case .updated:
            return change.id
        case .inserted, .removed:
            return parentID(of: change.id)
        }
    }

    private static func parentID(of id: String) -> String? {
        if let dot = id.lastIndex(of: ".") {
            let parent = String(id[..<dot])
            return parent.isEmpty ? nil : parent
        }
        return nil
    }

    private static func nodesByID(in root: SemanticNode) -> [String: SemanticNode] {
        var nodes: [String: SemanticNode] = [:]
        func visit(_ node: SemanticNode) {
            nodes[node.id] = node
            for child in node.children {
                visit(child)
            }
        }
        visit(root)
        return nodes
    }

    private static func nativeLeafUpdate(for node: SemanticNode) -> AdwaitaNativeLeafUpdate? {
        switch node.kind {
        case .text(let text):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .text, text: text)
        case .image(let text):
            if _OmniWebViewRegistry.payload(for: text) != nil {
                return nil
            }
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .text, text: _terminalSymbolString(text))
        case .webContent:
            return nil
        case .button, .tapTarget:
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .button, text: accessibleLabel(for: node))
        case .toggle(_, _, let isOn):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .toggle, text: accessibleLabel(for: node), active: isOn)
        case .textField(_, _, let text, _, _, _):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .textField, text: text)
        case .textEditor(_, let text, _, _):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .textEditor, text: text)
        case .menu(_, let title, let value, _):
            if menuItems(in: node).isEmpty {
                return AdwaitaNativeLeafUpdate(id: node.id, kind: .button, text: value.isEmpty ? title : "\(title): \(value)")
            }
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .dropdown, text: value)
        case .progress(let label, let fraction):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .progress, text: progressUpdateText(label: label, fraction: fraction))
        case .slider(let label, let value, _, _, _, _, _, _):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .slider, text: "\(value)\n\(label)")
        case .stepper(let label, let value, _, _):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .stepper, text: "\(value ?? 0)\n\(label)")
        case .datePicker(let label, let value, let timestamp, _, _, _):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .datePicker, text: "\(timestamp)\n\(value)\n\(label)")
        case .colorPicker(let label, let value, _, _):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .colorPicker, text: "\(value)\n\(label)")
        case .segmentedControl:
            return nil
        case .scroll(_, _, let offset):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .scroll, text: "\(offset)")
        default:
            return nil
        }
    }

    fileprivate static func accessibleLabel(for node: SemanticNode) -> String {
        if let label = explicitAccessibilityLabel(in: node) {
            return label
        }
        if case .disabledButton(let label) = node.kind, !label.isEmpty {
            return label
        }
        if case .disabledToggle(let label, _) = node.kind, !label.isEmpty {
            return label
        }
        if case .text(let text) = node.kind, !text.isEmpty {
            return text
        }
        if case .image(let text) = node.kind {
            if let payload = _OmniWebViewRegistry.payload(for: text) {
                return payload.url.absoluteString
            }
            return _terminalSymbolString(text)
        }
        if case .webContent(_, _, let url, let label, let description) = node.kind {
            return label ?? description ?? url
        }
        let collected = accessibilityText(in: node)
        if let helpLabel = explicitHelpLabel(in: node), shouldPreferHelpLabel(over: collected) {
            return helpLabel
        }
        if !collected.isEmpty {
            return collected
        }
        return "Action"
    }

    fileprivate static func accessibilityText(in node: SemanticNode) -> String {
        var parts: [String] = []
        collectAccessibilityText(in: node, into: &parts)
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func collectAccessibilityText(in node: SemanticNode, into parts: inout [String]) {
        switch node.kind {
        case .text(let text):
            parts.append(text)
        case .image(let text):
            if let payload = _OmniWebViewRegistry.payload(for: text) {
                parts.append(payload.url.absoluteString)
            } else {
                parts.append(_terminalSymbolString(text))
            }
        case .webContent(_, _, let url, let label, let description):
            parts.append(label ?? url)
            if let description {
                parts.append(description)
            }
        case .disabledButton(let label), .disabledTextField(_, let label, _):
            parts.append(label)
        case .disabledToggle(let label, _), .disabledMenu(let label, _):
            parts.append(label)
        case .spacer, .empty, .divider, .drawingIsland:
            break
        default:
            break
        }
        for child in node.children {
            collectAccessibilityText(in: child, into: &parts)
        }
    }

    private static func explicitAccessibilityLabel(in node: SemanticNode) -> String? {
        if case .modifier(.accessibilityLabel(let label)) = node.kind, !label.isEmpty {
            return label
        }
        for child in node.children {
            if let label = explicitAccessibilityLabel(in: child) {
                return label
            }
        }
        return nil
    }

    private static func explicitHelpLabel(in node: SemanticNode) -> String? {
        if case .modifier(.help(let label)) = node.kind, !label.isEmpty {
            return label
        }
        for child in node.children {
            if let label = explicitHelpLabel(in: child) {
                return label
            }
        }
        return nil
    }

    private static func shouldPreferHelpLabel(over label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Action" {
            return true
        }
        let symbolicLabels: Set<String> = [
            "⌂", "‹", "›", "↻", "☰", "⚙", "📄", "≣", "↗", "◆", "◇", "🌐", "◫", "⊘", "👁", "⚠", "+", "⌕", "🔍", "✓"
        ]
        return symbolicLabels.contains(trimmed)
    }

    fileprivate static func menuItems(in node: SemanticNode) -> [(label: String, actionID: Int)] {
        node.children.compactMap { child in
            let actionID: Int
            switch child.kind {
            case .button(let id, _), .tapTarget(let id, _):
                actionID = id
            default:
                return nil
            }
            return (accessibleLabel(for: child), actionID)
        }
    }

    fileprivate static func segmentedItems(in node: SemanticNode) -> [(label: String, actionID: Int)] {
        var items: [(label: String, actionID: Int)] = []
        func collect(_ current: SemanticNode) {
            if case .button(let actionID, _) = current.kind {
                let label = accessibleLabel(for: current).trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty, label != "Action" {
                    items.append((label, actionID))
                }
                return
            }
            if case .tapTarget(let actionID, _) = current.kind {
                let label = accessibleLabel(for: current).trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty, label != "Action" {
                    items.append((label, actionID))
                }
                return
            }
            for child in current.children {
                collect(child)
            }
        }
        collect(node)
        return items
    }

    fileprivate static func progressUpdateText(label: String, fraction: Double?) -> String {
        let clamped = max(0, min(1, fraction ?? 0))
        let prefix = label.isEmpty ? "Progress" : label
        let display = fraction.map { "\(prefix) \(Int((max(0, min(1, $0)) * 100).rounded()))%" } ?? prefix
        return "\(clamped)\n\(display)"
    }
}

enum AdwaitaNodeBuilder {
    private enum BuildContext: Equatable {
        case normal
        case sidebar
        case horizontal
        case inline
        case settings
    }

    static func offsetActionIDs(in node: SemanticNode, by offset: Int) -> SemanticNode {
        let kind: SemanticNode.Kind
        switch node.kind {
        case .scroll(let axis, let actionID, let offsetValue):
            kind = .scroll(axis: axis, actionID: actionID + offset, offset: offsetValue)
        case .button(let actionID, let isFocused):
            kind = .button(actionID: actionID + offset, isFocused: isFocused)
        case .tapTarget(let actionID, let tapCount):
            kind = .tapTarget(actionID: actionID + offset, tapCount: tapCount)
        case .toggle(let actionID, let isFocused, let isOn):
            kind = .toggle(actionID: actionID + offset, isFocused: isFocused, isOn: isOn)
        case .textField(let actionID, let placeholder, let text, let cursor, let isFocused, let isSecure):
            kind = .textField(actionID: actionID + offset, placeholder: placeholder, text: text, cursor: cursor, isFocused: isFocused, isSecure: isSecure)
        case .textEditor(let actionID, let text, let cursor, let isFocused):
            kind = .textEditor(actionID: actionID + offset, text: text, cursor: cursor, isFocused: isFocused)
        case .menu(let actionID, let title, let value, let isExpanded):
            kind = .menu(actionID: actionID + offset, title: title, value: value, isExpanded: isExpanded)
        case .slider(let label, let value, let lowerBound, let upperBound, let step, let setActionID, let decrementActionID, let incrementActionID):
            kind = .slider(
                label: label,
                value: value,
                lowerBound: lowerBound,
                upperBound: upperBound,
                step: step,
                setActionID: setActionID.map { $0 + offset },
                decrementActionID: decrementActionID.map { $0 + offset },
                incrementActionID: incrementActionID.map { $0 + offset }
            )
        case .stepper(let label, let value, let decrementActionID, let incrementActionID):
            kind = .stepper(
                label: label,
                value: value,
                decrementActionID: decrementActionID.map { $0 + offset },
                incrementActionID: incrementActionID.map { $0 + offset }
            )
        case .datePicker(let label, let value, let timestamp, let setActionID, let decrementActionID, let incrementActionID):
            kind = .datePicker(
                label: label,
                value: value,
                timestamp: timestamp,
                setActionID: setActionID.map { $0 + offset },
                decrementActionID: decrementActionID.map { $0 + offset },
                incrementActionID: incrementActionID.map { $0 + offset }
            )
        case .segmentedControl:
            kind = node.kind
        case .colorPicker(let label, let value, let supportsOpacity, let setActionID):
            kind = .colorPicker(
                label: label,
                value: value,
                supportsOpacity: supportsOpacity,
                setActionID: setActionID.map { $0 + offset }
            )
        case .disclosureGroup(let label, let isExpanded, let toggleActionID):
            kind = .disclosureGroup(
                label: label,
                isExpanded: isExpanded,
                toggleActionID: toggleActionID.map { $0 + offset }
            )
        case .modifier(.contextMenu(let items)):
            kind = .modifier(.contextMenu(items: items.map {
                SemanticContextMenuItem(label: $0.label, actionID: $0.actionID + offset)
            }))
        default:
            kind = node.kind
        }
        return SemanticNode(
            id: node.id,
            kind: kind,
            children: node.children.map { offsetActionIDs(in: $0, by: offset) }
        )
    }

    static func textValues(in node: SemanticNode) -> [Int: String] {
        var values: [Int: String] = [:]
        collectTextValues(in: node, into: &values)
        return values
    }

    static func build(_ node: SemanticNode) -> OpaquePointer? {
        build(node, context: .normal)
    }

    private static func build(_ node: SemanticNode, context: BuildContext) -> OpaquePointer? {
        let built: OpaquePointer?
        var metadataID = node.id
        switch node.kind {
        case .empty:
            built = omni_adw_box_new(1, 0)
        case .group:
            if let css = crtScanlineOverlayCSSClass(from: node.children) {
                built = omni_adw_frame_new(css, 0)
                if let built {
                    omni_adw_node_set_expand(built, 1, 1)
                }
            } else {
                built = container(vertical: true, spacing: 6, children: node.children, context: context)
            }
        case .zstack(let alignment):
            built = overlay(children: node.children, alignment: alignment, context: context)
        case .spacer:
            built = omni_adw_box_new(1, 0)
        case .stack(let axis, let spacing):
            built = container(vertical: axis == .vertical, spacing: Int32(spacing), children: node.children, context: context)
        case .flowLayout(let horizontalSpacing, let verticalSpacing):
            built = flowContainer(horizontalSpacing: Int32(horizontalSpacing), verticalSpacing: Int32(verticalSpacing), children: node.children, context: context)
        case .text(let text):
            built = omni_adw_text_new(text)
            applyInlineTextLayout(to: built, context: context)
        case .image(let text):
            if let payload = _OmniWebViewRegistry.payload(for: text) {
                built = webViewNode(for: payload)
            } else if let data = _OmniImageRegistry.data(for: text) {
                built = data.withUnsafeBytes { bytes in
                    omni_adw_image_new(bytes.bindMemory(to: UInt8.self).baseAddress, Int32(data.count), "Story image")
                }
            } else {
                let fallback = _terminalSymbolString(text)
                built = omni_adw_symbol_image_new(text, fallback, fallback)
                applyInlineTextLayout(to: built, context: context)
            }
        case .webContent(let registryKey, _, _, _, _):
            if let payload = _OmniWebViewRegistry.payload(for: registryKey) {
                built = webViewNode(for: payload)
            } else {
                built = omni_adw_text_new(accessibleLabel(for: node))
            }
        case .button(let actionID, _):
            let label = accessibleLabel(for: node)
            if rendersAsInlineButton(node, context: context) {
                built = omni_adw_inline_button_new(label, Int32(actionID), foregroundCSSClass(in: node) ?? "")
            } else if rendersComplexButtonContent(node) {
                built = omni_adw_click_container_new(label, Int32(actionID))
            } else {
                built = omni_adw_button_new(label, Int32(actionID))
            }
            if let built, rendersComplexButtonContent(node), let child = node.children.first, let childNode = build(child, context: .inline) {
                if shouldExpandVertically(child) {
                    omni_adw_node_set_expand(childNode, -1, 1)
                }
                omni_adw_node_append(built, childNode)
            }
        case .tapTarget(let actionID, let tapCount):
            if let switchRow = switchStyledRow(in: node) {
                built = context == .settings
                    ? omni_adw_switch_row_new(switchRow.title, switchRow.isOn ? 1 : 0, Int32(switchRow.actionID))
                    : omni_adw_toggle_new(switchRow.title, switchRow.isOn ? 1 : 0, Int32(switchRow.actionID))
            } else {
                let label = accessibleLabel(for: node)
                if rendersAsInlineButton(node, context: context) {
                    built = omni_adw_inline_button_new(label, Int32(actionID), foregroundCSSClass(in: node) ?? "")
                } else if rendersComplexButtonContent(node) {
                    built = omni_adw_click_container_new(label, Int32(actionID))
                } else {
                    built = omni_adw_button_new(label, Int32(actionID))
                }
                if let built {
                    omni_adw_node_set_required_click_count(built, Int32(max(1, tapCount)))
                }
                if let built, rendersComplexButtonContent(node), let child = node.children.first, let childNode = build(child, context: .inline) {
                    if shouldExpandVertically(child) {
                        omni_adw_node_set_expand(childNode, -1, 1)
                    }
                    omni_adw_node_append(built, childNode)
                }
            }
        case .toggle(let actionID, _, let isOn):
            if context == .settings {
                built = omni_adw_switch_row_new(accessibleLabel(for: node), isOn ? 1 : 0, Int32(actionID))
            } else {
                built = omni_adw_toggle_new(accessibleLabel(for: node), isOn ? 1 : 0, Int32(actionID))
            }
        case .textField(let actionID, let placeholder, let text, _, _, let isSecure):
            built = isSecure
                ? omni_adw_secure_entry_new(placeholder, text, Int32(actionID))
                : omni_adw_entry_new(placeholder, text, Int32(actionID))
        case .textEditor(let actionID, let text, _, _):
            built = omni_adw_text_view_new(text, Int32(actionID))
        case .menu(let actionID, let title, let value, let isExpanded):
            let items = menuItems(in: node)
            if items.isEmpty {
                built = omni_adw_button_new(value.isEmpty ? title : "\(title): \(value)", Int32(actionID))
            } else {
                var ids = items.map { Int32($0.actionID) }
                built = items.map(\.label).withCStringArray { labels in
                    ids.withUnsafeMutableBufferPointer { idBuffer in
                        omni_adw_dropdown_new(title, value, labels, idBuffer.baseAddress, Int32(items.count), isExpanded ? 1 : 0)
                    }
                }
            }
        case .disabledButton(let label):
            let resolvedLabel = disabledButtonLabel(label, children: node.children)
            built = omni_adw_button_new(resolvedLabel, 0)
            if let built {
                omni_adw_node_set_sensitive(built, 0)
            }
        case .disabledToggle(let label, let isOn):
            built = context == .settings
                ? omni_adw_switch_row_new(label, isOn ? 1 : 0, 0)
                : omni_adw_toggle_new(label, isOn ? 1 : 0, 0)
            if let built {
                omni_adw_node_set_sensitive(built, 0)
            }
        case .disabledTextField(let placeholder, let text, let isSecure):
            built = isSecure
                ? omni_adw_secure_entry_new(placeholder, text, 0)
                : omni_adw_entry_new(placeholder, text, 0)
            if let built {
                omni_adw_node_set_sensitive(built, 0)
            }
        case .disabledMenu(let title, let value):
            built = omni_adw_button_new(value.isEmpty ? title : "\(title): \(value)", 0)
            if let built {
                omni_adw_node_set_sensitive(built, 0)
            }
        case .progress(let label, let fraction):
            built = omni_adw_progress_new(progressLabel(label: label, fraction: fraction), max(0, min(1, fraction ?? 0)))
        case .slider(let label, let value, let lowerBound, let upperBound, let step, let setActionID, let decrementActionID, let incrementActionID):
            guard let parent = omni_adw_box_new(1, 4) else { return nil }
            if let scale = omni_adw_scale_new(label.isEmpty ? "Slider" : label, value, lowerBound, upperBound, step ?? 0, Int32(setActionID ?? 0), Int32(decrementActionID ?? 0), Int32(incrementActionID ?? 0)) {
                omni_adw_node_set_metadata(scale, node.id, label.isEmpty ? "Slider" : label)
                omni_adw_node_append(parent, scale)
            }
            built = parent
            metadataID = "\(node.id).container"
        case .stepper(let label, let value, let decrementActionID, let incrementActionID):
            guard let parent = omni_adw_box_new(1, 4) else { return nil }
            if let spin = omni_adw_spin_new(label.isEmpty ? "Stepper" : label, value ?? 0, Int32(decrementActionID ?? 0), Int32(incrementActionID ?? 0)) {
                omni_adw_node_set_metadata(spin, node.id, label.isEmpty ? "Stepper" : label)
                omni_adw_node_append(parent, spin)
            }
            built = parent
            metadataID = "\(node.id).container"
        case .datePicker(let label, let value, let timestamp, let setActionID, let decrementActionID, let incrementActionID):
            guard let parent = omni_adw_box_new(1, 4) else { return nil }
            if let date = omni_adw_date_new(label.isEmpty ? "Date" : label, value, timestamp, Int32(setActionID ?? 0), Int32(decrementActionID ?? 0), Int32(incrementActionID ?? 0)) {
                omni_adw_node_set_metadata(date, node.id, label.isEmpty ? "Date" : label)
                omni_adw_node_append(parent, date)
            }
            built = parent
            metadataID = "\(node.id).container"
        case .segmentedControl(let title, let selectedIndex):
            let items = AdwaitaReconciliation.segmentedItems(in: node)
            if items.isEmpty {
                built = container(vertical: false, spacing: 0, children: node.children, context: context)
            } else {
                var ids = items.map { Int32($0.actionID) }
                built = items.map(\.label).withCStringArray { labels in
                    ids.withUnsafeMutableBufferPointer { idBuffer in
                        omni_adw_segmented_new(title, labels, idBuffer.baseAddress, Int32(selectedIndex), Int32(items.count))
                    }
                }
            }
        case .colorPicker(let label, let value, let supportsOpacity, let setActionID):
            built = omni_adw_color_button_new(label.isEmpty ? "Color" : label, value, supportsOpacity ? 1 : 0, Int32(setActionID ?? 0))
        case .labeledContent(let label, let value):
            built = omni_adw_action_row_new(label, value)
        case .disclosureGroup(let label, let isExpanded, let toggleActionID):
            guard let expander = omni_adw_expander_new(label.isEmpty ? "Details" : label, isExpanded ? 1 : 0, Int32(toggleActionID ?? 0)) else { return nil }
            for child in node.children {
                if let builtChild = build(child, context: context) {
                    omni_adw_node_append(expander, builtChild)
                }
            }
            built = expander
        case .groupBox(let label):
            guard let group = omni_adw_preferences_group_new(label, "") else { return nil }
            for child in node.children {
                if let builtChild = buildSettingsRow(child, context: .settings) {
                    omni_adw_node_append(group, builtChild)
                }
            }
            built = group
        case .contentUnavailable(let title, let description):
            guard let status = omni_adw_status_page_new(title, description ?? "") else { return nil }
            if !node.children.isEmpty,
               let actions = container(vertical: false, spacing: 8, children: node.children, context: context) {
                omni_adw_node_append(status, actions)
            }
            built = status
        case .section(let header, let footer):
            guard let group = omni_adw_preferences_group_new(header, footer) else { return nil }
            for child in node.children {
                if let builtChild = buildSettingsRow(child, context: .settings) {
                    omni_adw_node_append(group, builtChild)
                }
            }
            built = group
        case .scroll(let axis, _, let offset):
            guard let scroll = omni_adw_scroll_new(axis == .vertical ? 1 : 0, Double(offset)) else { return nil }
            if let child = container(vertical: true, spacing: 6, children: node.children, context: context) {
                omni_adw_node_append(scroll, child)
            }
            built = scroll
        case .divider:
            built = omni_adw_separator_new()
        case .drawingIsland(let kind):
            switch kind {
            case .shape(let name, let fill, _):
                built = omni_adw_drawing_new("OmniUI shape(\(name))", fill)
            case .gradient(let colors, let startX, let startY, let endX, let endY):
                built = colors.withCStringArray { colorPointers in
                    omni_adw_gradient_new(
                        "OmniUI gradient",
                        colorPointers,
                        Int32(colors.count),
                        startX,
                        startY,
                        endX,
                        endY
                    )
                }
            case .canvas:
                built = omni_adw_drawing_new("OmniUI canvas", nil)
            }
        case .container(let role):
            built = semanticContainer(role, children: node.children, context: context)
        case .modifier(let modifier):
            if case .accessibilityIdentifier(let identifier) = modifier, !identifier.isEmpty {
                metadataID = identifier
            }
            built = modifiedContainer(modifier, children: node.children, context: context)
        }
        if let built {
            omni_adw_node_set_metadata(built, metadataID, metadataLabel(for: node))
        }
        return built
    }

    static func applyLeafUpdates(changes: [SemanticChange], snapshot: SemanticSnapshot, app: OpaquePointer?) -> Bool {
        applyLeafUpdates(changes: changes, root: snapshot.root, app: app)
    }

    static func applyLeafUpdates(changes: [SemanticChange], root: SemanticNode, app: OpaquePointer?) -> Bool {
        guard let app else { return false }
        guard let updates = AdwaitaReconciliation.leafUpdates(changes: changes, root: root) else { return false }
        let traceDiff = ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_DIFF_TRACE"] == "1"
        for update in updates {
            let applied = omni_adw_app_update_node(app, update.id, update.kind.rawValue, update.text, update.active ? 1 : 0)
            if traceDiff {
                print("OmniUI Adwaita leaf update: id=\(update.id) kind=\(update.kind.rawValue) bytes=\(update.text.utf8.count) applied=\(applied)")
            }
            if applied == 0 {
                return false
            }
        }
        return true
    }

    static func applyStructuralReplacement(
        changes: [SemanticChange],
        previous: SemanticNode,
        next: SemanticNode,
        focusedActionID: Int?,
        app: OpaquePointer?
    ) -> Bool {
        guard let app else { return false }
        guard
            let replacement = AdwaitaReconciliation.subtreeReplacement(changes: changes, previous: previous, next: next),
            let node = build(replacement.node)
        else { return false }
        return omni_adw_app_replace_node(app, replacement.id, node, Int32(focusedActionID ?? 0)) != 0
    }

    private static func collectTextValues(in node: SemanticNode, into values: inout [Int: String]) {
        if case .textField(let actionID, _, let text, _, _, _) = node.kind {
            values[actionID] = text
        }
        if case .textEditor(let actionID, let text, _, _) = node.kind {
            values[actionID] = text
        }
        for child in node.children {
            collectTextValues(in: child, into: &values)
        }
    }

    private static func menuItems(in node: SemanticNode) -> [(label: String, actionID: Int)] {
        AdwaitaReconciliation.menuItems(in: node)
    }

    private static func container(vertical: Bool, spacing: Int32, children: [SemanticNode], context: BuildContext) -> OpaquePointer? {
        guard let parent = omni_adw_box_new(vertical ? 1 : 0, spacing) else { return nil }
        let homogeneousHorizontal = !vertical && shouldUseHomogeneousHorizontalBox(children)
        if homogeneousHorizontal {
            omni_adw_box_set_homogeneous(parent, 1)
        }
        for child in children {
            let built: OpaquePointer?
            if case .spacer = child.kind {
                built = omni_adw_box_new(vertical ? 1 : 0, 0)
                if let built {
                    omni_adw_node_set_expand(built, 1, vertical ? 1 : 0)
                }
            } else {
                built = build(child, context: childContext(forContainerVertical: vertical, parent: context))
            }
            if let built {
                if homogeneousHorizontal, !isZeroWidthFrame(child) {
                    omni_adw_node_set_expand(built, 1, -1)
                }
                if shouldExpandVertically(child) {
                    omni_adw_node_set_expand(built, -1, 1)
                }
                omni_adw_node_append(parent, built)
            }
        }
        if children.contains(where: shouldExpandVertically) {
            omni_adw_node_set_expand(parent, -1, 1)
        }
        return parent
    }

    private static func childContext(forContainerVertical vertical: Bool, parent: BuildContext) -> BuildContext {
        if parent == .inline || parent == .settings { return parent }
        if vertical { return parent == .horizontal ? .normal : parent }
        return .horizontal
    }

    private static func applyInlineTextLayout(to node: OpaquePointer?, context: BuildContext) {
        guard let node, context == .horizontal || context == .inline else { return }
        omni_adw_node_set_expand(node, 0, -1)
        omni_adw_node_set_text_wrap(node, 0)
    }

    private static func flowContainer(horizontalSpacing: Int32, verticalSpacing: Int32, children: [SemanticNode], context: BuildContext) -> OpaquePointer? {
        guard let parent = omni_adw_flow_new(horizontalSpacing, verticalSpacing) else { return nil }
        for child in children {
            if let built = build(child, context: context) {
                omni_adw_node_append(parent, built)
            }
        }
        if children.contains(where: shouldExpandVertically) {
            omni_adw_node_set_expand(parent, -1, 1)
        }
        return parent
    }

    private static func overlay(children: [SemanticNode], alignment: String, context: BuildContext) -> OpaquePointer? {
        let renderChildren = overlayRenderableChildren(children)
        if renderChildren.count == 1, let child = renderChildren.first {
            return build(child, context: context)
        }
        guard let parent = omni_adw_overlay_new() else { return nil }
        if context == .horizontal || context == .inline {
            omni_adw_node_set_expand(parent, renderChildren.contains(where: hasFlexibleHorizontalFrame) ? 1 : 0, 0)
        }
        var index = 0
        while index < renderChildren.count {
            if let run = crtScanlineOverlayRun(in: renderChildren, startingAt: index),
               let scanlines = omni_adw_frame_new(run.css, 0) {
                omni_adw_node_set_expand(scanlines, 1, 1)
                omni_adw_node_append_overlay(parent, scanlines, alignment)
                index += run.count
                continue
            }
            let child = renderChildren[index]
            if let built = build(child, context: context) {
                omni_adw_node_append_overlay(parent, built, alignment)
            }
            index += 1
        }
        if renderChildren.contains(where: shouldExpandVertically) {
            omni_adw_node_set_expand(parent, -1, 1)
        }
        return parent
    }

    private static func overlayRenderableChildren(_ children: [SemanticNode]) -> [SemanticNode] {
        let hasTrailingDecorativeOverlay: (Int) -> Bool = { index in
            let trailingStart = index + 1
            guard trailingStart < children.count else { return false }
            return children[trailingStart...].contains(where: isDecorativeDrawing)
        }
        if let firstContent = children.firstIndex(where: { !isDecorativeDrawing($0) }),
           firstContent > 0,
           hasTrailingDecorativeOverlay(firstContent) {
            return Array(children[firstContent...])
        }
        return children
    }

    private static func shouldExpandVertically(_ node: SemanticNode) -> Bool {
        switch node.kind {
        case .scroll(let axis, _, _):
            return axis == .vertical
        case .image(let text):
            return _OmniWebViewRegistry.payload(for: text) != nil
        case .webContent:
            return true
        case .drawingIsland(.gradient):
            return true
        case .button, .tapTarget:
            return node.children.contains(where: shouldExpandVertically)
        case .modifier(.background("native/adwaita")):
            return node.children
                .filter { $0.id.hasSuffix(".content") }
                .contains(where: shouldExpandVertically)
        case .modifier(.frame(_, let height, _, _, _, let maxHeight)):
            if height != nil || maxHeight == 0 { return false }
            if maxHeight != nil { return true }
            return node.children.contains(where: shouldExpandVertically)
        case .modifier(let modifier) where modifierAllowsLayoutDescent(modifier):
            return node.children.contains(where: shouldExpandVertically)
        case .group, .zstack, .stack, .flowLayout, .container:
            return node.children.contains(where: shouldExpandVertically)
        default:
            return false
        }
    }

    private static func shouldUseHomogeneousHorizontalBox(_ children: [SemanticNode]) -> Bool {
        let visibleChildren = children.filter { !isZeroWidthFrame($0) }
        guard visibleChildren.count > 1 else { return false }
        return visibleChildren.allSatisfy(hasRootFlexibleHorizontalFrame)
    }

    private static func webViewNode(for payload: _OmniWebViewPayload) -> OpaquePointer? {
        let urlString: String
        let htmlString: String?
        let baseURLString: String?
        switch payload.load {
        case .url(let url):
            urlString = url.absoluteString
            htmlString = nil
            baseURLString = nil
        case .html(let html, let baseURL):
            urlString = baseURL?.absoluteString ?? "about:blank"
            htmlString = html
            baseURLString = baseURL?.absoluteString
        }

        let scriptSources = payload.userScripts.map(\.source)
        var scriptTimes = payload.userScripts.map(\.injectionTime)
        var scriptMainFrameOnly = payload.userScripts.map { $0.forMainFrameOnly ? Int32(1) : Int32(0) }
        let contentRuleIdentifiers = payload.contentRules.map(\.identifier)
        let contentRuleSources = payload.contentRules.map(\.encodedRules)
        let handlerNames = payload.scriptMessageHandlerNames
        let requestHeaderNames = payload.requestHeaders.map(\.name)
        let requestHeaderValues = payload.requestHeaders.map(\.value)
        let cookieNames = payload.cookies.map(\.name)
        let cookieValues = payload.cookies.map(\.value)
        let cookieDomains = payload.cookies.map(\.domain)
        let cookiePaths = payload.cookies.map(\.path)
        var cookieExpires = payload.cookies.map { $0.expiresAt ?? -1 }
        var cookieSecure = payload.cookies.map { $0.isSecure ? Int32(1) : Int32(0) }
        var cookieHTTPOnly = payload.cookies.map { $0.isHTTPOnly ? Int32(1) : Int32(0) }

        return withCStringArray(scriptSources) { scriptSourcePointers in
            withCStringArray(contentRuleIdentifiers) { contentRuleIdentifierPointers in
                withCStringArray(contentRuleSources) { contentRuleSourcePointers in
                    withCStringArray(handlerNames) { handlerNamePointers in
                        withCStringArray(requestHeaderNames) { requestHeaderNamePointers in
                            withCStringArray(requestHeaderValues) { requestHeaderValuePointers in
                                withCStringArray(cookieNames) { cookieNamePointers in
                                    withCStringArray(cookieValues) { cookieValuePointers in
                                        withCStringArray(cookieDomains) { cookieDomainPointers in
                                            withCStringArray(cookiePaths) { cookiePathPointers in
                                                payload.stableIdentity.withCString { identityPointer in
                                                    urlString.withCString { urlPointer in
                                                        withOptionalCString(htmlString) { htmlPointer in
                                                            withOptionalCString(baseURLString) { baseURLPointer in
                                                                payload.fallbackText.withCString { fallbackPointer in
                                                                    withOptionalCString(payload.userAgentApplicationName) { applicationNamePointer in
                                                                        withOptionalCString(payload.customUserAgent) { customUserAgentPointer in
                                                                            withOptionalCString(payload.accessibilityLabel) { accessibilityLabelPointer in
                                                                                withOptionalCString(payload.accessibilityDescription) { accessibilityDescriptionPointer in
                                                                                    scriptTimes.withUnsafeMutableBufferPointer { scriptTimeBuffer in
                                                                                        scriptMainFrameOnly.withUnsafeMutableBufferPointer { mainFrameBuffer in
                                                                                            cookieExpires.withUnsafeMutableBufferPointer { cookieExpiresBuffer in
                                                                                                cookieSecure.withUnsafeMutableBufferPointer { cookieSecureBuffer in
                                                                                                    cookieHTTPOnly.withUnsafeMutableBufferPointer { cookieHTTPOnlyBuffer in
                                                                                                        omni_adw_web_view_new_ex(
                                                                                                            identityPointer,
                                                                                                            urlPointer,
                                                                                                            htmlPointer,
                                                                                                            baseURLPointer,
                                                                                                            fallbackPointer,
                                                                                                            requestHeaderNamePointers.baseAddress,
                                                                                                            requestHeaderValuePointers.baseAddress,
                                                                                                            Int32(requestHeaderNames.count),
                                                                                                            applicationNamePointer,
                                                                                                            customUserAgentPointer,
                                                                                                            payload.pageZoom,
                                                                                                            payload.allowsBackForwardNavigationGestures ? 1 : 0,
                                                                                                            payload.javaScriptCanOpenWindowsAutomatically ? 1 : 0,
                                                                                                            payload.javaScriptEnabled ? 1 : 0,
                                                                                                            payload.minimumFontSize,
                                                                                                            payload.isInspectable ? 1 : 0,
                                                                                                            payload.allowsInlineMediaPlayback ? 1 : 0,
                                                                                                            payload.mediaPlaybackRequiresUserGesture ? 1 : 0,
                                                                                                            scriptSourcePointers.baseAddress,
                                                                                                            scriptTimeBuffer.baseAddress,
                                                                                                            mainFrameBuffer.baseAddress,
                                                                                                            Int32(scriptSources.count),
                                                                                                            contentRuleIdentifierPointers.baseAddress,
                                                                                                            contentRuleSourcePointers.baseAddress,
                                                                                                            Int32(contentRuleIdentifiers.count),
                                                                                                            handlerNamePointers.baseAddress,
                                                                                                            Int32(handlerNames.count),
                                                                                                            cookieNamePointers.baseAddress,
                                                                                                            cookieValuePointers.baseAddress,
                                                                                                            cookieDomainPointers.baseAddress,
                                                                                                            cookiePathPointers.baseAddress,
                                                                                                            cookieExpiresBuffer.baseAddress,
                                                                                                            cookieSecureBuffer.baseAddress,
                                                                                                            cookieHTTPOnlyBuffer.baseAddress,
                                                                                                            Int32(cookieNames.count),
                                                                                                            accessibilityLabelPointer,
                                                                                                            accessibilityDescriptionPointer,
                                                                                                            nil,
                                                                                                            payload.messageCallback,
                                                                                                            payload.navigationCallback,
                                                                                                            payload.policyCallback,
                                                                                                            payload.responsePolicyCallback,
                                                                                                            payload.downloadDestinationCallback,
                                                                                                            payload.titleCallback,
                                                                                                            payload.progressCallback,
                                                                                                            payload.cookieCallback,
                                                                                                            payload.scriptDialogCallback,
                                                                                                            payload.callbackContext
                                                                                                        )
                                                                                                    }
                                                                                                }
                                                                                            }
                                                                                        }
                                                                                    }
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func withOptionalCString<R>(_ value: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
        guard let value else { return body(nil) }
        return value.withCString(body)
    }

    private static func withCStringArray<R>(_ values: [String], _ body: (UnsafeMutableBufferPointer<UnsafePointer<CChar>?>) -> R) -> R {
        var pointers: [UnsafePointer<CChar>?] = Array(repeating: nil, count: values.count)

        func recurse(_ index: Int) -> R {
            if index == values.count {
                return pointers.withUnsafeMutableBufferPointer { buffer in
                    body(buffer)
                }
            }
            return values[index].withCString { pointer in
                pointers[index] = pointer
                return recurse(index + 1)
            }
        }

        return recurse(0)
    }

    private static func hasFlexibleHorizontalFrame(_ node: SemanticNode) -> Bool {
        switch node.kind {
        case .modifier(.frame(_, _, _, let maxWidth, _, _)):
            return maxWidth == Int.max
        case .button, .tapTarget:
            return node.children.contains(where: hasFlexibleHorizontalFrame)
        case .modifier(let modifier) where modifierAllowsLayoutDescent(modifier):
            return node.children.contains(where: hasFlexibleHorizontalFrame)
        case .group, .zstack, .stack, .container:
            return node.children.contains(where: hasFlexibleHorizontalFrame)
        default:
            return false
        }
    }

    private static func hasRootFlexibleHorizontalFrame(_ node: SemanticNode) -> Bool {
        switch node.kind {
        case .modifier(.frame(_, _, _, let maxWidth, _, _)):
            return maxWidth == Int.max
        case .modifier(let modifier) where modifierAllowsLayoutDescent(modifier):
            return node.children.contains(where: hasRootFlexibleHorizontalFrame)
        default:
            return false
        }
    }

    private static func isZeroWidthFrame(_ node: SemanticNode) -> Bool {
        switch node.kind {
        case .modifier(.frame(let width, _, _, let maxWidth, _, _)):
            return width == 0 || maxWidth == 0
        case .button, .tapTarget:
            return node.children.contains(where: isZeroWidthFrame)
        case .modifier(let modifier) where modifierAllowsLayoutDescent(modifier):
            return node.children.contains(where: isZeroWidthFrame)
        case .group, .zstack, .stack, .container:
            return node.children.contains(where: isZeroWidthFrame)
        default:
            return false
        }
    }

    private static func modifierAllowsLayoutDescent(_ modifier: SemanticModifier) -> Bool {
        switch modifier {
        case .opacity, .clip, .background, .padding, .accessibilityLabel, .accessibilityIdentifier, .accessibilityValue, .accessibilityHint, .help, .noOp, .foreground, .font, .shadow, .glass, .crt, .contextMenu, .dragSource:
            return true
        default:
            return false
        }
    }

    private static func modifiedContainer(_ modifier: SemanticModifier, children: [SemanticNode], context: BuildContext) -> OpaquePointer? {
        func primaryContent() -> OpaquePointer? {
            if let content = children.first(where: { $0.id.hasSuffix(".content") }) {
                return build(content, context: context)
            }
            if children.count == 2 {
                switch modifier {
                case .background:
                    return build(visibleChildren(forOverlayChildren: children).first ?? children[1], context: context)
                default:
                    break
                }
            }
            if let child = children.last {
                return build(child, context: context)
            }
            return nil
        }

        if case .background("native/adwaita") = modifier {
            guard let css = backgroundShapeCSSClass(from: children), css != "omni-bg-clear" else {
                return primaryContent()
            }
            guard let parent = omni_adw_frame_new(css, 0) else { return nil }
            if context == .horizontal || context == .inline {
                omni_adw_node_set_expand(parent, 0, -1)
            }
            for child in visibleChildren(forOverlayChildren: children) {
                if let built = build(child, context: context) {
                    omni_adw_node_append(parent, built)
                }
            }
            return parent
        }

        let css: String
        switch modifier {
        case .dragSource(let actionID):
            guard let node = primaryContent() else { return nil }
            omni_adw_node_set_drag_source_action(node, Int32(actionID))
            return node
        case .contextMenu(let items):
            guard !items.isEmpty else { return primaryContent() }
            var ids = items.map { Int32($0.actionID) }
            guard let wrapper = items.map(\.label).withCStringArray({ labels in
                ids.withUnsafeMutableBufferPointer { idBuffer in
                    omni_adw_context_menu_new(labels, idBuffer.baseAddress, Int32(items.count))
                }
            }) else { return primaryContent() }
            if let content = primaryContent() {
                if children.contains(where: shouldExpandVertically) {
                    omni_adw_node_set_expand(wrapper, -1, 1)
                    omni_adw_node_set_expand(content, -1, 1)
                }
                omni_adw_node_append(wrapper, content)
            }
            return wrapper
        case .background("adw-dialog"):
            guard let parent = omni_adw_frame_new("card adw-dialog", 0) else { return nil }
            if context == .horizontal || context == .inline {
                omni_adw_node_set_expand(parent, 0, -1)
            }
            applyLayoutModifier(modifier, to: parent)
            for child in visibleChildren(forOverlayChildren: children) {
                if let built = build(child, context: context) {
                    omni_adw_node_append(parent, built)
                }
            }
            return parent
        case .foreground(let color):
            css = colorCSSClass(prefix: "omni-fg", color: color)
        case .background(let color):
            guard let parent = omni_adw_frame_new(colorCSSClass(prefix: "omni-bg", color: color), 0) else { return nil }
            if context == .horizontal || context == .inline {
                omni_adw_node_set_expand(parent, 0, -1)
            }
            applyLayoutModifier(modifier, to: parent)
            for child in visibleChildren(forOverlayChildren: children) {
                if let built = build(child, context: context) {
                    omni_adw_node_append(parent, built)
                }
            }
            return parent
        case .font(let size, let weight, _, let italic):
            if let node = primaryContent() {
                omni_adw_node_apply_font(node, size ?? 0, weight ?? "", italic ? 1 : 0)
                return node
            }
            return nil
        case .help(let text), .accessibilityHint(let text):
            if let node = primaryContent() {
                omni_adw_node_set_accessibility_description(node, text)
                return node
            }
            return nil
        case .accessibilityValue(let value):
            if let node = primaryContent() {
                omni_adw_node_set_accessibility_value(node, value)
                return node
            }
            return nil
        case .clip:
            guard containsWebContent(children) else { return primaryContent() }
            guard let content = primaryContent() else { return nil }
            guard let wrapper = omni_adw_frame_new("omni-clip", 0) else { return content }
            omni_adw_node_set_expand(wrapper, 1, 1)
            omni_adw_node_append(wrapper, content)
            return wrapper
        case .glass:
            if let child = children.last,
               let stripped = stripAdwaitaGlassDecoration(from: child) {
                return build(stripped, context: context)
            }
            return primaryContent()
        case .shadow(let color, let radius, let x, let y):
            guard let node = primaryContent() else { return nil }
            if let css = shadowCSSClass(color: color, radius: radius, x: x, y: y) {
                omni_adw_node_add_css_class(node, css)
            }
            return node
        case .crt, .accessibilityLabel, .noOp:
            return primaryContent()
        case .badge:
            css = "accent"
        case .accessibilityIdentifier:
            if children.count == 1, let child = children.first {
                return build(child, context: context)
            }
            return container(vertical: true, spacing: 0, children: children, context: context)
        case .frame(let width, let height, let minWidth, let maxWidth, let minHeight, let maxHeight):
            if let node = primaryContent() {
                let modifierToApply: SemanticModifier
                if (context == .horizontal || context == .inline),
                   maxWidth == Int.max,
                   children.contains(where: { switchStyledRow(in: $0) != nil }) {
                    modifierToApply = .frame(width: width, height: height, minWidth: minWidth, maxWidth: nil, minHeight: minHeight, maxHeight: maxHeight)
                } else {
                    modifierToApply = modifier
                }
                applyLayoutModifier(modifierToApply, to: node)
                return node
            }
            css = ""
        case .padding, .opacity, .offset:
            if let node = primaryContent() {
                applyLayoutModifier(modifier, to: node)
                return node
            }
            css = ""
        }
        guard let parent = omni_adw_frame_new(css, 0) else { return nil }
        applyLayoutModifier(modifier, to: parent)
        for child in children {
            if let built = build(child, context: context) {
                omni_adw_node_append(parent, built)
            }
        }
        return parent
    }

    private static func backgroundShapeCSSClass(from children: [SemanticNode]) -> String? {
        guard let background = children.first(where: { $0.id.hasSuffix(".background") }),
              let style = firstBackgroundShapeStyle(in: background)
        else {
            return nil
        }
        switch style {
        case .color(let color):
            return colorCSSClass(prefix: "omni-bg", color: color)
        case .gradient(let colors, let startX, let startY, let endX, let endY):
            return gradientCSSClass(
                colors: colors,
                startX: startX,
                startY: startY,
                endX: endX,
                endY: endY
            )
        }
    }

    private static func containsWebContent(_ nodes: [SemanticNode]) -> Bool {
        nodes.contains(where: containsWebContent)
    }

    private static func containsWebContent(_ node: SemanticNode) -> Bool {
        if case .webContent = node.kind { return true }
        return node.children.contains(where: containsWebContent)
    }

    private static func stripAdwaitaGlassDecoration(from node: SemanticNode) -> SemanticNode? {
        switch node.kind {
        case .modifier(.background("native/adwaita")):
            return node.children.first(where: { $0.id.hasSuffix(".content") })
                .flatMap(stripAdwaitaGlassDecoration)
        case .modifier(.shadow), .modifier(.opacity), .modifier(.clip), .modifier(.foreground),
             .modifier(.font), .modifier(.padding), .modifier(.accessibilityLabel),
             .modifier(.accessibilityIdentifier), .modifier(.accessibilityValue),
             .modifier(.accessibilityHint), .modifier(.help), .modifier(.noOp):
            return node.children.last.flatMap(stripAdwaitaGlassDecoration)
        default:
            return node
        }
    }

    private static func stripAdwaitaGlassDecorationForLabel(from node: SemanticNode) -> SemanticNode? {
        if case .disabledButton = node.kind {
            return node.children.last.flatMap(stripAdwaitaGlassDecorationForLabel)
        }
        if let stripped = stripAdwaitaGlassDecoration(from: node), stripped.id != node.id || "\(stripped.kind)" != "\(node.kind)" {
            return stripAdwaitaGlassDecorationForLabel(from: stripped)
        }
        return node
    }

    private static func disabledButtonLabel(_ label: String, children: [SemanticNode]) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !trimmed.hasPrefix("glass(") {
            return trimmed
        }
        for child in children {
            if let stripped = stripAdwaitaGlassDecorationForLabel(from: child) {
                let candidate = accessibleLabel(for: stripped)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty && candidate != "Action" && !candidate.hasPrefix("glass(") {
                    return candidate
                }
            }
        }
        return trimmed.isEmpty ? "Disabled" : trimmed
    }

    private enum BackgroundShapeStyle {
        case color(String)
        case gradient(colors: [String], startX: Double, startY: Double, endX: Double, endY: Double)
    }

    private static func firstBackgroundShapeStyle(in node: SemanticNode) -> BackgroundShapeStyle? {
        switch node.kind {
        case .drawingIsland(.shape(_, let fill, let stroke)):
            return (fill ?? stroke).map(BackgroundShapeStyle.color)
        case .drawingIsland(.gradient(let colors, let startX, let startY, let endX, let endY)):
            return .gradient(colors: colors, startX: startX, startY: startY, endX: endX, endY: endY)
        case .modifier(.opacity(let alpha)):
            guard let style = node.children.lazy.compactMap(firstBackgroundShapeStyle).first else { return nil }
            switch style {
            case .color(let color):
                return .color(colorString(color, multiplyingAlphaBy: alpha))
            case .gradient(let colors, let startX, let startY, let endX, let endY):
                return .gradient(
                    colors: colors.map { colorString($0, multiplyingAlphaBy: alpha) },
                    startX: startX,
                    startY: startY,
                    endX: endX,
                    endY: endY
                )
            }
        case .modifier(.background("native/adwaita")):
            return node.children.lazy.compactMap(firstBackgroundShapeStyle).first
        default:
            return node.children.lazy.compactMap(firstBackgroundShapeStyle).first
        }
    }

    private static func colorString(_ color: String, multiplyingAlphaBy alpha: Double) -> String {
        let parts = color.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let base = parts.first.map(String.init) ?? color
        let existingAlpha = parts.dropFirst().first.flatMap { Double($0) } ?? 1.0
        return "\(base)|\(max(0, min(1, existingAlpha * alpha)))"
    }

    private static func colorCSSClass(prefix: String, color: String) -> String {
        let normalized = color.lowercased()
        let parts = normalized.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let base = parts.first.map(String.init) ?? normalized
        let alpha = parts.dropFirst().first.flatMap { Double($0) } ?? 1.0
        if alpha <= 0.01 || base == "clear" {
            return "\(prefix)-clear"
        }
        if let cssColor = concreteCSSColor(base: base, alpha: alpha) {
            return dynamicColorCSSClass(prefix: prefix, base: base, alpha: alpha, cssColor: cssColor)
        }
        switch base {
        case "primary":
            return "\(prefix)-primary"
        case "orange":
            return alpha < 0.5 ? "\(prefix)-orange-muted" : "\(prefix)-orange"
        case "accentcolor", "tint":
            if alpha < 0.999, let cssColor = cssColorLiteral(color) {
                return dynamicColorCSSClass(prefix: prefix, base: base, alpha: alpha, cssColor: cssColor)
            }
            return "\(prefix)-accent"
        case "secondary":
            return "\(prefix)-secondary"
        case "tertiary":
            return "\(prefix)-tertiary"
        case "quaternary":
            return "\(prefix)-quaternary"
        case "white":
            return alpha < 0.5 ? "\(prefix)-white-muted" : "\(prefix)-white"
        case "black":
            return alpha < 0.5 ? "\(prefix)-black-muted" : "\(prefix)-black"
        case "gray", "grey":
            return "\(prefix)-gray"
        case "bar":
            return prefix == "omni-bg" ? "\(prefix)-material-bar" : "\(prefix)-native"
        case "background":
            return prefix == "omni-bg" ? "\(prefix)-material-background" : "\(prefix)-native"
        case "regularmaterial":
            return prefix == "omni-bg" ? "\(prefix)-material-regular" : "\(prefix)-native"
        case "thinmaterial":
            return prefix == "omni-bg" ? "\(prefix)-material-thin" : "\(prefix)-native"
        case "ultrathinmaterial":
            return prefix == "omni-bg" ? "\(prefix)-material-ultra-thin" : "\(prefix)-native"
        case "red", "yellow", "green", "mint", "teal", "cyan", "blue", "indigo", "purple", "pink", "brown":
            return alpha < 0.5 ? "\(prefix)-\(base)-muted" : "\(prefix)-\(base)"
        default:
            return "\(prefix)-native"
        }
    }

    private static func dynamicColorCSSClass(prefix: String, base: String, alpha: Double, cssColor: String) -> String {
        let className = "\(prefix)-dynamic-\(fnv1aHex("\(prefix)|\(base)|\(alpha)"))"
        let rule: String
        if prefix == "omni-fg" {
            rule = ".\(className), .\(className) label, .\(className) image { color: \(cssColor); }"
        } else {
            rule = ".\(className) { background: \(cssColor); background-color: \(cssColor); }"
        }
        rule.withCString { omni_adw_register_dynamic_css($0) }
        return className
    }

    private static func gradientCSSClass(colors: [String], startX: Double, startY: Double, endX: Double, endY: Double) -> String? {
        let cssStops = colors.compactMap(cssColorLiteral)
        guard cssStops.count >= 2 else {
            return colors.first.map { colorCSSClass(prefix: "omni-bg", color: $0) }
        }
        let className = "omni-bg-gradient-\(fnv1aHex("\(colors.joined(separator: ","))|\(startX)|\(startY)|\(endX)|\(endY)"))"
        let direction = gradientDirection(startX: startX, startY: startY, endX: endX, endY: endY)
        let gradient = "linear-gradient(\(direction), \(cssStops.joined(separator: ", ")))"
        let rule = ".\(className) { background: \(gradient); background-image: \(gradient); background-color: \(cssStops.first ?? "transparent"); }"
        rule.withCString { omni_adw_register_dynamic_css($0) }
        return className
    }

    private static func shadowCSSClass(color: String, radius: Int, x: Int, y: Int) -> String? {
        guard radius > 0 || x != 0 || y != 0,
              let cssColor = cssColorLiteral(color),
              cssColor != "transparent"
        else {
            return nil
        }
        let className = "omni-shadow-\(fnv1aHex("\(color)|\(radius)|\(x)|\(y)"))"
        let blur = max(1, radius)
        let rule = ".\(className), .\(className) label { text-shadow: \(x)px \(y)px \(blur)px \(cssColor); } .\(className) { box-shadow: \(x)px \(y)px \(blur)px \(cssColor); }"
        rule.withCString { omni_adw_register_dynamic_css($0) }
        return className
    }

    private static func crtScanlineOverlayCSSClass(from children: [SemanticNode]) -> String? {
        let fillColors = children.compactMap(scanlineFillColor)
        guard fillColors.count == children.count, fillColors.count >= 3 else { return nil }
        let color = fillColors[0]
        guard fillColors.allSatisfy({ $0 == color }),
              let cssColor = cssColorLiteral(color),
              cssColor != "transparent"
        else {
            return nil
        }
        let className = "omni-crt-scanlines-\(fnv1aHex(color))"
        let rule = ".\(className) { background-image: repeating-linear-gradient(to bottom, \(cssColor) 0px, \(cssColor) 1px, transparent 1px, transparent 3px); background-color: transparent; }"
        rule.withCString { omni_adw_register_dynamic_css($0) }
        return "omni-crt-overlay \(className)"
    }

    private static func crtScanlineOverlayRun(in children: [SemanticNode], startingAt start: Int) -> (css: String, count: Int)? {
        guard children.indices.contains(start) else { return nil }
        var index = start
        var run: [SemanticNode] = []
        while children.indices.contains(index), scanlineFillColor(in: children[index]) != nil {
            run.append(children[index])
            index += 1
        }
        guard let css = crtScanlineOverlayCSSClass(from: run) else { return nil }
        return (css, run.count)
    }

    private static func scanlineFillColor(in node: SemanticNode) -> String? {
        switch node.kind {
        case .drawingIsland(.shape(let name, let fill, _)):
            guard name == "path" || name == "rectangle" else { return nil }
            return fill
        case .modifier(.opacity(let alpha)):
            guard let color = node.children.lazy.compactMap(scanlineFillColor).first else { return nil }
            return colorString(color, multiplyingAlphaBy: alpha)
        case .modifier(let modifier) where modifierAllowsLayoutDescent(modifier):
            return node.children.lazy.compactMap(scanlineFillColor).first
        case .group, .stack, .zstack, .container:
            return node.children.count == 1 ? node.children.lazy.compactMap(scanlineFillColor).first : nil
        default:
            return nil
        }
    }

    private static func gradientDirection(startX: Double, startY: Double, endX: Double, endY: Double) -> String {
        let dx = endX - startX
        let dy = endY - startY
        if abs(dx) < 0.001 {
            return dy >= 0 ? "to bottom" : "to top"
        }
        if abs(dy) < 0.001 {
            return dx >= 0 ? "to right" : "to left"
        }
        if dx >= 0, dy >= 0 { return "to bottom right" }
        if dx < 0, dy >= 0 { return "to bottom left" }
        if dx >= 0, dy < 0 { return "to top right" }
        return "to top left"
    }

    private static func cssColorLiteral(_ color: String) -> String? {
        let normalized = color.lowercased()
        let parts = normalized.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let base = parts.first.map(String.init) ?? normalized
        let alpha = parts.dropFirst().first.flatMap { Double($0) } ?? 1.0
        if alpha <= 0.01 || base == "clear" { return "transparent" }
        if let cssColor = concreteCSSColor(base: base, alpha: alpha) {
            return cssColor
        }
        switch base {
        case "black":
            return rgbaCSS(red: 0, green: 0, blue: 0, alpha: alpha)
        case "white":
            return rgbaCSS(red: 1, green: 1, blue: 1, alpha: alpha)
        case "gray", "grey":
            return rgbaCSS(red: 142.0 / 255.0, green: 142.0 / 255.0, blue: 147.0 / 255.0, alpha: alpha)
        case "red":
            return rgbaCSS(red: 1, green: 69.0 / 255.0, blue: 58.0 / 255.0, alpha: alpha)
        case "orange":
            return rgbaCSS(red: 1, green: 149.0 / 255.0, blue: 0, alpha: alpha)
        case "yellow":
            return rgbaCSS(red: 191.0 / 255.0, green: 127.0 / 255.0, blue: 0, alpha: alpha)
        case "green":
            return rgbaCSS(red: 36.0 / 255.0, green: 138.0 / 255.0, blue: 61.0 / 255.0, alpha: alpha)
        case "mint":
            return rgbaCSS(red: 0, green: 166.0 / 255.0, blue: 153.0 / 255.0, alpha: alpha)
        case "teal":
            return rgbaCSS(red: 10.0 / 255.0, green: 127.0 / 255.0, blue: 143.0 / 255.0, alpha: alpha)
        case "cyan":
            return rgbaCSS(red: 0, green: 122.0 / 255.0, blue: 153.0 / 255.0, alpha: alpha)
        case "blue", "accentcolor", "tint":
            return rgbaCSS(red: 10.0 / 255.0, green: 132.0 / 255.0, blue: 1, alpha: alpha)
        case "indigo":
            return rgbaCSS(red: 94.0 / 255.0, green: 92.0 / 255.0, blue: 230.0 / 255.0, alpha: alpha)
        case "purple":
            return rgbaCSS(red: 175.0 / 255.0, green: 82.0 / 255.0, blue: 222.0 / 255.0, alpha: alpha)
        case "pink":
            return rgbaCSS(red: 1, green: 45.0 / 255.0, blue: 85.0 / 255.0, alpha: alpha)
        case "brown":
            return rgbaCSS(red: 142.0 / 255.0, green: 110.0 / 255.0, blue: 83.0 / 255.0, alpha: alpha)
        default:
            return nil
        }
    }

    private static func concreteCSSColor(base: String, alpha: Double) -> String? {
        if let components = rgbComponents(from: base) {
            return rgbaCSS(
                red: components.red,
                green: components.green,
                blue: components.blue,
                alpha: components.alpha * alpha
            )
        }
        if let components = hsbComponents(from: base) {
            let rgb = rgbFromHSB(hue: components.hue, saturation: components.saturation, brightness: components.brightness)
            return rgbaCSS(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
        }
        if let components = hexComponents(from: base) {
            return rgbaCSS(
                red: components.red,
                green: components.green,
                blue: components.blue,
                alpha: components.alpha * alpha
            )
        }
        return nil
    }

    private static func rgbComponents(from raw: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        guard let marker = raw.range(of: "rgba(") ?? raw.range(of: "rgb("),
              let end = raw[marker.upperBound...].firstIndex(of: ")")
        else { return nil }
        let body = raw[marker.upperBound..<end]
        let parts = body.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let red = Double(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
              let green = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
              let blue = Double(parts[2].trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        let componentAlpha = parts.count >= 4
            ? Double(parts[3].trimmingCharacters(in: .whitespacesAndNewlines)).map { normalizedAlphaComponent($0) } ?? 1.0
            : 1.0
        return (
            normalizedColorComponent(red),
            normalizedColorComponent(green),
            normalizedColorComponent(blue),
            componentAlpha
        )
    }

    private static func hsbComponents(from raw: String) -> (hue: Double, saturation: Double, brightness: Double)? {
        guard let marker = raw.range(of: "hsb("),
              let end = raw[marker.upperBound...].firstIndex(of: ")")
        else { return nil }
        let body = raw[marker.upperBound..<end]
        let values = body
            .split(separator: ",", omittingEmptySubsequences: false)
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count >= 3 else { return nil }
        return (values[0], values[1], values[2])
    }

    private static func hexComponents(from raw: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        guard raw.hasPrefix("#") else { return nil }
        let hex = String(raw.dropFirst())
        let expanded: String
        switch hex.count {
        case 3, 4:
            expanded = hex.map { "\($0)\($0)" }.joined()
        case 6, 8:
            expanded = hex
        default:
            return nil
        }
        guard let value = UInt64(expanded, radix: 16) else { return nil }
        if expanded.count == 8 {
            return (
                Double((value >> 24) & 0xff) / 255.0,
                Double((value >> 16) & 0xff) / 255.0,
                Double((value >> 8) & 0xff) / 255.0,
                Double(value & 0xff) / 255.0
            )
        }
        return (
            Double((value >> 16) & 0xff) / 255.0,
            Double((value >> 8) & 0xff) / 255.0,
            Double(value & 0xff) / 255.0,
            1.0
        )
    }

    private static func normalizedColorComponent(_ value: Double) -> Double {
        if value > 1.0 {
            return max(0, min(1, value / 255.0))
        }
        return max(0, min(1, value))
    }

    private static func normalizedAlphaComponent(_ value: Double) -> Double {
        if value > 1.0 {
            return max(0, min(1, value / 255.0))
        }
        return max(0, min(1, value))
    }

    private static func rgbFromHSB(hue: Double, saturation: Double, brightness: Double) -> (red: Double, green: Double, blue: Double) {
        let h = hue - floor(hue)
        let s = max(0, min(1, saturation))
        let v = max(0, min(1, brightness))
        if s <= 0 {
            return (v, v, v)
        }
        let sector = h * 6.0
        let i = floor(sector)
        let f = sector - i
        let p = v * (1.0 - s)
        let q = v * (1.0 - s * f)
        let t = v * (1.0 - s * (1.0 - f))
        switch Int(i) % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    private static func rgbaCSS(red: Double, green: Double, blue: Double, alpha: Double) -> String {
        let redByte = Int(round(max(0, min(1, red)) * 255.0))
        let greenByte = Int(round(max(0, min(1, green)) * 255.0))
        let blueByte = Int(round(max(0, min(1, blue)) * 255.0))
        let clampedAlpha = max(0, min(1, alpha))
        if clampedAlpha >= 0.9995 {
            return String(format: "#%02x%02x%02x", redByte, greenByte, blueByte)
        }
        return "rgba(\(redByte), \(greenByte), \(blueByte), \(String(format: "%.3f", clampedAlpha)))"
    }

    private static func fnv1aHex(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private static func visibleChildren(forOverlayChildren children: [SemanticNode]) -> [SemanticNode] {
        if let content = children.first(where: { $0.id.hasSuffix(".content") }) {
            return [content]
        }
        let nonDecorative = children.filter { !isDecorativeDrawing($0) }
        return nonDecorative.isEmpty ? children : nonDecorative
    }

    private static func isDecorativeDrawing(_ node: SemanticNode) -> Bool {
        switch node.kind {
        case .drawingIsland:
            return true
        case .modifier(.background), .modifier(.shadow), .modifier(.glass), .modifier(.crt), .modifier(.opacity), .modifier(.offset):
            return node.children.allSatisfy(isDecorativeDrawing)
        case .group, .zstack, .stack:
            return !node.children.isEmpty && node.children.allSatisfy(isDecorativeDrawing)
        default:
            return false
        }
    }

    private static func rendersComplexButtonContent(_ node: SemanticNode) -> Bool {
        guard node.children.count == 1, let child = node.children.first else { return false }
        return !isSimpleButtonLabel(child)
    }

    private static func rendersAsInlineButton(_ node: SemanticNode, context: BuildContext) -> Bool {
        guard rendersInlineButtonContent(node) else { return false }
        return context == .inline
    }

    private static func rendersInlineButtonContent(_ node: SemanticNode) -> Bool {
        guard node.children.count == 1, let child = node.children.first else { return false }
        return isSimpleButtonLabel(child)
    }

    private static func isSimpleButtonLabel(_ node: SemanticNode) -> Bool {
        switch node.kind {
        case .text, .image, .webContent:
            return true
        case .group, .stack, .zstack:
            return node.children.allSatisfy(isSimpleButtonLabel)
        case .modifier(.foreground), .modifier(.background), .modifier(.font), .modifier(.padding), .modifier(.opacity), .modifier(.frame), .modifier(.accessibilityLabel), .modifier(.accessibilityIdentifier), .modifier(.accessibilityValue), .modifier(.accessibilityHint), .modifier(.contextMenu), .modifier(.noOp):
            return node.children.allSatisfy(isSimpleButtonLabel)
        default:
            return false
        }
    }

    private static func foregroundCSSClass(in node: SemanticNode) -> String? {
        if case .modifier(.foreground(let color)) = node.kind {
            return colorCSSClass(prefix: "omni-fg", color: color)
        }
        for child in node.children {
            if let css = foregroundCSSClass(in: child) {
                return css
            }
        }
        return nil
    }

    private static func applyLayoutModifier(_ modifier: SemanticModifier, to node: OpaquePointer) {
        let cellWidth = 1
        let cellHeight = 1
        let marginUnit = 1
        switch modifier {
        case .frame(let width, let height, let minWidth, let maxWidth, let minHeight, let maxHeight):
            let resolvedWidth = width ?? (maxWidth == 0 ? 0 : nil)
            let resolvedHeight = height ?? (maxHeight == 0 ? 0 : nil)
            omni_adw_node_apply_layout(
                node,
                scaled(resolvedWidth, by: cellWidth),
                scaled(resolvedHeight, by: cellHeight),
                scaled(minWidth, by: cellWidth),
                scaled(minHeight, by: cellHeight),
                -1, -1, -1, -1,
                -1
            )
            if width != nil || height != nil {
                omni_adw_node_set_expand(
                    node,
                    width == nil ? -1 : 0,
                    height == nil ? -1 : 0
                )
            }
            if maxWidth != nil || maxHeight != nil {
                omni_adw_node_set_visible(node, maxWidth == 0 || maxHeight == 0 ? 0 : 1)
                omni_adw_node_set_expand(
                    node,
                    maxWidth == nil ? -1 : (maxWidth == 0 ? 0 : 1),
                    maxHeight == nil ? -1 : (maxHeight == 0 ? 0 : 1)
                )
            }
        case .padding(let top, let leading, let bottom, let trailing):
            omni_adw_node_apply_layout(
                node,
                -1, -1, -1, -1,
                Int32(max(0, top * marginUnit)),
                Int32(max(0, leading * marginUnit)),
                Int32(max(0, bottom * marginUnit)),
                Int32(max(0, trailing * marginUnit)),
                -1
            )
        case .opacity(let alpha):
            omni_adw_node_apply_layout(node, -1, -1, -1, -1, -1, -1, -1, -1, max(0, min(1, alpha)))
        case .offset(let x, let y):
            omni_adw_node_apply_layout(
                node,
                -1, -1, -1, -1,
                Int32(max(0, y * marginUnit)),
                Int32(max(0, x * marginUnit)),
                -1, -1,
                -1
            )
        default:
            break
        }
    }

    private static func scaled(_ value: Int?, by scale: Int) -> Int32 {
        guard let value else { return -1 }
        return Int32(max(0, value) * scale)
    }

    private static func semanticContainer(_ role: SemanticContainerRole, children: [SemanticNode], context: BuildContext) -> OpaquePointer? {
        if role == .form {
            guard let parent = omni_adw_form_new() else { return nil }
            for child in formRows(from: children) {
                if let built = buildSettingsRow(child, context: .settings) {
                    omni_adw_node_append(parent, built)
                }
            }
            return parent
        }

        if role == .list {
            if isEmptyListContent(children) {
                return omni_adw_box_new(1, 0)
            }
            if let simpleList = simpleListRows(from: children),
               context == .sidebar || simpleList.shouldUseCompactRenderer {
                var ids = simpleList.rows.map { Int32($0.actionID ?? 0) }
                let labels = simpleList.rows.map(\.label)
                var depths = simpleList.rows.map { Int32($0.depth) }
                var fontSizes = simpleList.rows.map { $0.fontSize ?? 0 }
                let fontWeights = simpleList.rows.map { $0.fontWeight ?? "" }
                var fontItalics = simpleList.rows.map { $0.fontItalic ? Int32(1) : Int32(0) }
                let cssClasses = simpleList.rows.map { $0.foregroundCSSClass ?? "" }
                let list = labels.withCStringArray { labelPointers in
                    fontWeights.withCStringArray { weightPointers in
                        cssClasses.withCStringArray { cssPointers in
                            ids.withUnsafeMutableBufferPointer { idBuffer in
                                depths.withUnsafeMutableBufferPointer { depthBuffer in
                                    fontSizes.withUnsafeMutableBufferPointer { fontSizeBuffer in
                                        fontItalics.withUnsafeMutableBufferPointer { fontItalicBuffer in
                                            if context == .sidebar {
                                                omni_adw_sidebar_list_new(labelPointers, idBuffer.baseAddress, depthBuffer.baseAddress, fontSizeBuffer.baseAddress, weightPointers, fontItalicBuffer.baseAddress, cssPointers, Int32(simpleList.rows.count))
                                            } else if simpleList.rows.count >= 128 {
                                                omni_adw_string_list_new(labelPointers, idBuffer.baseAddress, fontSizeBuffer.baseAddress, weightPointers, fontItalicBuffer.baseAddress, cssPointers, Int32(simpleList.rows.count))
                                            } else {
                                                omni_adw_plain_list_new(labelPointers, idBuffer.baseAddress, fontSizeBuffer.baseAddress, weightPointers, fontItalicBuffer.baseAddress, cssPointers, Int32(simpleList.rows.count))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                guard let list else { return nil }
                if let scroll = simpleList.scroll {
                    return wrapInScroll(list, axis: scroll.axis, offset: scroll.offset)
                }
                return wrapInScroll(list, axis: .vertical, offset: 0)
            }
            guard let parent = omni_adw_list_new() else { return nil }
            for child in children {
                if let built = build(child, context: context) {
                    omni_adw_node_append(parent, built)
                }
            }
            return wrapInScroll(parent, axis: .vertical, offset: 0)
        }

        if role == .navigationSplitView {
            return navigationSplitContainer(children: children)
        }

        let css: String
        let spacing: Int32
        switch role {
        case .form:
            css = "card"
            spacing = 8
        case .list:
            css = "boxed-list"
            spacing = 0
        case .navigationSplitView:
            css = "navigation-view"
            spacing = 8
        case .navigationStack:
            css = "navigation-view"
            spacing = 6
        case .lazyVStack:
            css = "view"
            spacing = 6
        }
        guard let parent = omni_adw_frame_new(css, spacing) else { return nil }
        for child in children {
            if let built = build(child, context: context) {
                omni_adw_node_append(parent, built)
            }
        }
        return parent
    }

    private static func buildSettingsRow(_ node: SemanticNode, context: BuildContext) -> OpaquePointer? {
        if let switchRow = switchStyledRow(in: node) {
            return omni_adw_switch_row_new(switchRow.title, switchRow.isOn ? 1 : 0, Int32(switchRow.actionID))
        }
        switch node.kind {
        case .toggle(let actionID, _, let isOn):
            return omni_adw_switch_row_new(accessibleLabel(for: node), isOn ? 1 : 0, Int32(actionID))
        case .disabledToggle(let label, let isOn):
            guard let row = omni_adw_switch_row_new(label, isOn ? 1 : 0, 0) else { return nil }
            omni_adw_node_set_sensitive(row, 0)
            return row
        case .textField(let actionID, let placeholder, let text, _, _, let isSecure):
            let title = placeholder.isEmpty ? "Text" : placeholder
            let input = isSecure
                ? omni_adw_secure_entry_new(placeholder, text, Int32(actionID))
                : omni_adw_entry_new(placeholder, text, Int32(actionID))
            return settingsRow(title: title, value: "", suffix: input, enabled: true)
        case .disabledTextField(let placeholder, let text, let isSecure):
            let title = placeholder.isEmpty ? "Text" : placeholder
            let input = isSecure
                ? omni_adw_secure_entry_new(placeholder, text, 0)
                : omni_adw_entry_new(placeholder, text, 0)
            return settingsRow(title: title, value: "", suffix: input, enabled: false)
        case .menu:
            return settingsRow(title: settingsTitle(for: node), value: "", suffix: build(node, context: context), enabled: true)
        case .disabledMenu(let title, let value):
            let suffix = omni_adw_button_new(value.isEmpty ? title : value, 0)
            return settingsRow(title: title.isEmpty ? "Menu" : title, value: "", suffix: suffix, enabled: false)
        default:
            return build(node, context: context)
        }
    }

    private struct SwitchStyledSettingsRow {
        var title: String
        var isOn: Bool
        var actionID: Int
    }

    private static func switchStyledRow(in node: SemanticNode) -> SwitchStyledSettingsRow? {
        switch node.kind {
        case .tapTarget(let actionID, _):
            guard let isOn = switchGlyphState(in: node) else { return nil }
            let title = strippedSwitchTitle(from: accessibleLabel(for: node))
            return SwitchStyledSettingsRow(
                title: title.isEmpty ? "Toggle" : title,
                isOn: isOn,
                actionID: actionID
            )
        case .modifier(let modifier):
            guard settingsRowModifierAllowsControlDescent(modifier),
                  node.children.count == 1,
                  let child = node.children.first else { return nil }
            return switchStyledRow(in: child)
        default:
            return nil
        }
    }

    private static func settingsRowModifierAllowsControlDescent(_ modifier: SemanticModifier) -> Bool {
        switch modifier {
        case .foreground, .background, .font, .padding, .opacity, .frame,
             .accessibilityLabel, .accessibilityIdentifier, .accessibilityValue,
             .accessibilityHint, .help, .noOp:
            return true
        case .offset, .clip, .shadow, .badge, .glass, .crt, .contextMenu, .dragSource:
            return false
        }
    }

    private static func switchGlyphState(in node: SemanticNode) -> Bool? {
        switch node.kind {
        case .text(let text):
            if text.contains("[━━●]") { return true }
            if text.contains("[○━━]") { return false }
            return nil
        default:
            for child in node.children {
                if let state = switchGlyphState(in: child) {
                    return state
                }
            }
            return nil
        }
    }

    private static func strippedSwitchTitle(from label: String) -> String {
        let title = label
            .replacingOccurrences(of: "[━━●]", with: "")
            .replacingOccurrences(of: "[○━━]", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if title.hasPrefix("> ") {
            return String(title.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title
    }

    private static func settingsRow(title: String, value: String, suffix: OpaquePointer?, enabled: Bool) -> OpaquePointer? {
        guard let row = omni_adw_action_row_new(title, value) else { return nil }
        if let suffix {
            omni_adw_node_append(row, suffix)
        }
        if !enabled {
            omni_adw_node_set_sensitive(row, 0)
        }
        return row
    }

    private static func settingsTitle(for node: SemanticNode) -> String {
        switch node.kind {
        case .menu(_, let title, _, _):
            return title.isEmpty ? accessibleLabel(for: node) : title
        default:
            return accessibleLabel(for: node)
        }
    }

    private static func wrapInScroll(_ child: OpaquePointer, axis: SemanticAxis, offset: Int) -> OpaquePointer? {
        guard let scrollNode = omni_adw_scroll_new(axis == .vertical ? 1 : 0, Double(offset)) else {
            return child
        }
        omni_adw_node_append(scrollNode, child)
        return scrollNode
    }

    private struct SimpleListRow {
        let label: String
        let actionID: Int?
        let depth: Int
        let fontSize: Double?
        let fontWeight: String?
        let fontItalic: Bool
        let foregroundCSSClass: String?
        let isPlainText: Bool
        let hasSymbolPrefix: Bool
    }

    private struct SimpleList {
        let rows: [SimpleListRow]
        let scroll: (axis: SemanticAxis, offset: Int)?

        var shouldUseCompactRenderer: Bool {
            if rows.count >= 128 { return true }
            if rows.allSatisfy(\.isPlainText) { return true }
            let plainTextRows = rows.filter(\.isPlainText).count
            if rows.count >= 8 && plainTextRows >= max(3, rows.count / 3) {
                return true
            }
            let symbolRows = rows.filter(\.hasSymbolPrefix).count
            return rows.count >= 8 && symbolRows >= max(3, rows.count / 2)
        }
    }

    private static func simpleListRows(from children: [SemanticNode]) -> SimpleList? {
        guard children.count == 1, let scroll = children.first, case .scroll(let axis, _, let offset) = scroll.kind else {
            guard let rows = simpleRows(in: children) else { return nil }
            return SimpleList(rows: rows, scroll: nil)
        }
        guard let rows = simpleRows(in: scroll.children) else { return nil }
        return SimpleList(rows: rows, scroll: (axis: axis, offset: offset))
    }

    private static func simpleRows(in nodes: [SemanticNode]) -> [SimpleListRow]? {
        var rows: [SimpleListRow] = []

        func contentChildren(of node: SemanticNode) -> [SemanticNode] {
            node.children.filter { child in
                switch child.kind {
                case .empty, .spacer, .divider, .drawingIsland:
                    return false
                default:
                    return true
                }
            }
        }

        func rawText(in node: SemanticNode) -> String {
            var parts: [String] = []
            func visit(_ current: SemanticNode) {
                if case .text(let text) = current.kind {
                    parts.append(text)
                }
                for child in current.children {
                    visit(child)
                }
            }
            visit(node)
            return parts.joined(separator: " ")
        }

        func firstImageSymbol(in node: SemanticNode) -> String? {
            if case .image(let imageName) = node.kind {
                return _terminalSymbolString(imageName)
            }
            for child in node.children {
                if let symbol = firstImageSymbol(in: child) {
                    return symbol
                }
            }
            return nil
        }

        func containsTextNode(_ node: SemanticNode) -> Bool {
            if case .text = node.kind {
                return true
            }
            return node.children.contains(where: containsTextNode)
        }

        func rowLabel(from node: SemanticNode) -> String {
            let raw = rawText(in: node)
            if !raw.isEmpty {
                if firstButtonActionID(in: node) == nil && firstImageSymbol(in: node) == nil {
                    return raw
                }
                if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return raw
                }
                let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedRaw.isEmpty {
                    return trimmedRaw
                }
            }
            let label = accessibleLabel(for: node).trimmingCharacters(in: .whitespacesAndNewlines)
            if label == "Action", containsTextNode(node) {
                return " "
            }
            return label == "Action" ? "" : label
        }

        func leadingWhitespaceDepth(in node: SemanticNode) -> Int {
            switch node.kind {
            case .text(let text):
                guard text.allSatisfy({ $0 == " " || $0 == "\t" }) else { return 0 }
                return max(0, text.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2)
            case .button, .tapTarget, .stack(axis: .horizontal, _), .modifier, .group:
                return node.children.map(leadingWhitespaceDepth(in:)).max() ?? 0
            default:
                return 0
            }
        }

        func firstButtonActionID(in node: SemanticNode) -> Int? {
            if case .button(let actionID, _) = node.kind {
                return actionID
            }
            if case .tapTarget(let actionID, _) = node.kind {
                return actionID
            }
            for child in node.children {
                if let actionID = firstButtonActionID(in: child) {
                    return actionID
                }
            }
            return nil
        }

        func rowFont(in node: SemanticNode) -> (size: Double?, weight: String?, italic: Bool) {
            var maxSize: Double?
            var selectedWeight: String?
            var selectedWeightRank = -1
            var italic = false

            func weightRank(_ weight: String?) -> Int {
                switch weight?.lowercased() {
                case "ultralight": return 0
                case "thin": return 1
                case "light": return 2
                case "regular": return 3
                case "medium": return 4
                case "semibold": return 5
                case "bold": return 6
                case "heavy": return 7
                case "black": return 8
                default: return -1
                }
            }

            func visit(_ current: SemanticNode) {
                if case .modifier(.font(let size, let weight, _, let isItalic)) = current.kind {
                    if let size, size > (maxSize ?? 0) {
                        maxSize = size
                    }
                    let rank = weightRank(weight)
                    if rank > selectedWeightRank {
                        selectedWeightRank = rank
                        selectedWeight = weight
                    }
                    italic = italic || isItalic
                }
                for child in current.children {
                    visit(child)
                }
            }

            visit(node)
            return (maxSize, selectedWeight, italic)
        }

        func isPlainTextRow(_ node: SemanticNode) -> Bool {
            switch node.kind {
            case .text:
                return true
            case .modifier(let modifier):
                guard modifierAllowsLayoutDescent(modifier) else { return false }
                return node.children.allSatisfy(isPlainTextRow)
            case .group, .stack(axis: .vertical, _), .container(.lazyVStack):
                return node.children.allSatisfy(isPlainTextRow)
            default:
                return false
            }
        }

        func appendRow(label: String, actionID: Int?, depth: Int, node: SemanticNode, inheritedForeground: String?) {
            let font = rowFont(in: node)
            let symbol = actionID != nil ? firstImageSymbol(in: node) : nil
            let displayLabel: String
            if let symbol, !label.hasPrefix(symbol) {
                displayLabel = "\(symbol)  \(label)"
            } else {
                displayLabel = label
            }
            rows.append(SimpleListRow(
                label: displayLabel,
                actionID: actionID,
                depth: depth,
                fontSize: font.size,
                fontWeight: font.weight,
                fontItalic: font.italic,
                foregroundCSSClass: foregroundCSSClass(in: node) ?? inheritedForeground,
                isPlainText: actionID == nil && isPlainTextRow(node),
                hasSymbolPrefix: symbol != nil
            ))
        }

        func containsMultiTapTarget(_ node: SemanticNode) -> Bool {
            if case .tapTarget(_, let tapCount) = node.kind, tapCount > 1 {
                return true
            }
            return node.children.contains(where: containsMultiTapTarget)
        }

        func appendRows(from node: SemanticNode, inheritedForeground: String? = nil) -> Bool {
            switch node.kind {
            case .scroll:
                for child in contentChildren(of: node) {
                    if !appendRows(from: child, inheritedForeground: inheritedForeground) { return false }
                }
                return true
            case .container(.list):
                return false
            case .stack(axis: .vertical, _), .group, .container(.lazyVStack):
                for child in node.children {
                    if !appendRows(from: child, inheritedForeground: inheritedForeground) { return false }
                }
                return true
            case .modifier:
                if case .modifier(.contextMenu) = node.kind {
                    return false
                }
                let nextForeground: String?
                if case .modifier(.foreground(let color)) = node.kind {
                    nextForeground = colorCSSClass(prefix: "omni-fg", color: color)
                } else {
                    nextForeground = foregroundCSSClass(in: node) ?? inheritedForeground
                }
                let children = contentChildren(of: node)
                guard !children.isEmpty else { return true }
                if case .modifier(.font) = node.kind, children.count == 1, let child = children.first {
                    switch child.kind {
                    case .text, .button, .tapTarget, .stack(axis: .horizontal, _), .zstack:
                        let label = rowLabel(from: node)
                        if label.isEmpty { return false }
                        appendRow(label: label, actionID: firstButtonActionID(in: node), depth: leadingWhitespaceDepth(in: node), node: node, inheritedForeground: nextForeground)
                        return true
                    default:
                        break
                    }
                }
                if children.count == 1, let child = children.first {
                    return appendRows(from: child, inheritedForeground: nextForeground)
                }
                for child in children {
                    if !appendRows(from: child, inheritedForeground: nextForeground) { return false }
                }
                return true
            case .divider, .empty, .spacer, .drawingIsland:
                return true
            case .text(let text):
                appendRow(label: text, actionID: nil, depth: 0, node: node, inheritedForeground: inheritedForeground)
                return true
            case .button(let actionID, _):
                let label = rowLabel(from: node)
                if label.isEmpty { return false }
                appendRow(label: label, actionID: actionID, depth: leadingWhitespaceDepth(in: node), node: node, inheritedForeground: inheritedForeground)
                return true
            case .tapTarget(let actionID, let tapCount):
                if tapCount > 1 { return false }
                let label = rowLabel(from: node)
                if label.isEmpty { return false }
                appendRow(label: label, actionID: actionID, depth: leadingWhitespaceDepth(in: node), node: node, inheritedForeground: inheritedForeground)
                return true
            case .stack(axis: .horizontal, _), .zstack:
                if containsMultiTapTarget(node) { return false }
                let label = rowLabel(from: node)
                if label.isEmpty { return false }
                appendRow(label: label, actionID: firstButtonActionID(in: node), depth: leadingWhitespaceDepth(in: node), node: node, inheritedForeground: inheritedForeground)
                return true
            default:
                return false
            }
        }

        for node in nodes {
            if !appendRows(from: node) { return nil }
        }
        return rows.isEmpty ? nil : rows
    }

    private static func isEmptyListContent(_ nodes: [SemanticNode]) -> Bool {
        nodes.allSatisfy(isEmptyListNode)
    }

    private static func isEmptyListNode(_ node: SemanticNode) -> Bool {
        switch node.kind {
        case .empty, .divider:
            return true
        case .group, .zstack, .stack, .scroll, .modifier:
            return node.children.allSatisfy(isEmptyListNode)
        case .container(.lazyVStack), .container(.list):
            return node.children.allSatisfy(isEmptyListNode)
        default:
            return false
        }
    }

    private static func formRows(from children: [SemanticNode]) -> [SemanticNode] {
        guard children.count == 1, let first = children.first else { return children }
        switch first.kind {
        case .stack(axis: .vertical, _), .group:
            return first.children
        case .modifier, .scroll:
            return formRows(from: first.children)
        default:
            return children
        }
    }

    private static func navigationSplitContainer(children: [SemanticNode]) -> OpaquePointer? {
        guard let parent = omni_adw_split_new() else { return nil }
        guard let columns = navigationSplitColumns(from: children) else {
            for child in children {
                if let built = build(child, context: .normal) {
                    omni_adw_node_append(parent, built)
                }
            }
            return parent
        }

        if let sidebar = build(columns.sidebar, context: .sidebar) {
            omni_adw_node_append(parent, sidebar)
        }
        if let detail = container(vertical: true, spacing: 6, children: columns.detail, context: .normal) {
            omni_adw_node_append(parent, detail)
        }
        return parent
    }

    private static func navigationSplitColumns(from children: [SemanticNode]) -> (sidebar: SemanticNode, detail: [SemanticNode])? {
        guard children.count == 1, let splitRoot = children.first else { return nil }
        guard case .stack(let axis, _) = splitRoot.kind, axis == .horizontal else { return nil }
        let meaningfulChildren = splitRoot.children.filter { child in
            if case .text("│") = child.kind {
                return false
            }
            return true
        }
        guard let sidebar = meaningfulChildren.first else { return nil }
        let detail = Array(meaningfulChildren.dropFirst())
        guard !detail.isEmpty else { return nil }
        return (sidebar, detail)
    }

    private static func metadataLabel(for node: SemanticNode) -> String {
        switch node.kind {
        case .text(let text):
            return text
        case .image(let text):
            return _terminalSymbolString(text)
        case .webContent(_, _, let url, let label, let description):
            return label ?? description ?? url
        case .button, .tapTarget, .toggle:
            return accessibleLabel(for: node)
        case .textField(_, let placeholder, let text, _, _, let isSecure):
            if isSecure {
                return text.isEmpty ? placeholder : String(repeating: "•", count: text.count)
            }
            return text.isEmpty ? placeholder : text
        case .textEditor(_, let text, _, _):
            return text.isEmpty ? "Text editor" : text
        case .menu(_, let title, let value, _):
            return value.isEmpty ? title : "\(title): \(value)"
        case .disabledButton(let label):
            return label
        case .disabledToggle(let label, _):
            return label
        case .disabledTextField(let placeholder, let text, let isSecure):
            if isSecure {
                return text.isEmpty ? placeholder : String(repeating: "•", count: text.count)
            }
            return text.isEmpty ? placeholder : text
        case .disabledMenu(let title, let value):
            return value.isEmpty ? title : "\(title): \(value)"
        case .progress(let label, let fraction):
            return progressLabel(label: label, fraction: fraction)
        case .slider(let label, let value, _, _, _, _, _, _):
            return label.isEmpty ? "Slider \(value)" : "\(label) \(value)"
        case .stepper(let label, let value, _, _):
            let prefix = label.isEmpty ? "Stepper" : label
            return value.map { "\(prefix) \($0)" } ?? prefix
        case .datePicker(let label, let value, _, _, _, _):
            let prefix = label.isEmpty ? "Date" : label
            return "\(prefix): \(value)"
        case .colorPicker(let label, let value, _, _):
            let prefix = label.isEmpty ? "Color" : label
            return "\(prefix): \(value)"
        case .labeledContent(let label, let value):
            return value.isEmpty ? label : "\(label): \(value)"
        case .disclosureGroup(let label, let isExpanded, _):
            return "\(label.isEmpty ? "Details" : label) \(isExpanded ? "expanded" : "collapsed")"
        case .groupBox(let label):
            return label.isEmpty ? "Group" : label
        case .contentUnavailable(let title, let description):
            return description.map { "\(title): \($0)" } ?? title
        case .section(let header, let footer):
            if !header.isEmpty { return header }
            if !footer.isEmpty { return footer }
            return "Section"
        case .drawingIsland(let kind):
            return "OmniUI \(kind)"
        case .container(let role):
            return role.rawValue
        case .modifier(let modifier):
            if case .accessibilityLabel(let label) = modifier {
                return label
            }
            if case .accessibilityIdentifier(let identifier) = modifier {
                return identifier
            }
            if let child = node.children.last {
                let childLabel = accessibleLabel(for: child).trimmingCharacters(in: .whitespacesAndNewlines)
                if !childLabel.isEmpty && childLabel != "Action" {
                    return childLabel
                }
            }
            return ""
        case .scroll(let axis, _, _):
            return axis == .vertical ? "vertical scroll view" : "horizontal scroll view"
        default:
            return accessibleLabel(for: node)
        }
    }

    private static func accessibleLabel(for node: SemanticNode) -> String {
        AdwaitaReconciliation.accessibleLabel(for: node)
    }

    private static func progressLabel(label: String, fraction: Double?) -> String {
        let prefix = label.isEmpty ? "Progress" : label
        guard let fraction else { return prefix }
        return "\(prefix) \(Int((max(0, min(1, fraction)) * 100).rounded()))%"
    }
}

private extension Array where Element == String {
    func withCStringArray<R>(_ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> R) -> R {
        let cStrings = map { strdup($0) }
        var pointers = cStrings.map { pointer -> UnsafePointer<CChar>? in
            guard let pointer else { return nil }
            return UnsafePointer(pointer)
        }
        defer {
            for pointer in cStrings {
                free(pointer)
            }
        }
        return pointers.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress)
        }
    }
}

@discardableResult
@MainActor
private func dispatchNativeEventToLocalMonitors(
    eventType: Int,
    x: Double,
    y: Double,
    clickCount: Int,
    modifiers: UInt32,
    codepoint: UInt32
) -> Bool {
#if os(Linux)
    let event = NSEvent()
    switch eventType {
    case 1:
        event.type = .leftMouseDown
    case 2:
        event.type = .leftMouseUp
    case 3:
        event.type = .rightMouseDown
    case 4:
        event.type = .rightMouseUp
    case 5:
        event.type = .mouseMoved
    case 6:
        event.type = .flagsChanged
    case 7:
        event.type = .keyDown
    case 8:
        event.type = .scrollWheel
    default:
        return false
    }
    if event.type == .scrollWheel {
        event.locationInWindow = NSApp.keyWindow?.mouseLocationOutsideOfEventStream ?? .zero
        event.scrollingDeltaX = x
        event.scrollingDeltaY = y
    } else {
        event.locationInWindow = NSPoint(x: x, y: y)
    }
    event.clickCount = clickCount
    event.modifierFlags = NSEvent._omniMacCompatibleModifierFlags(rawValue: Int(modifiers), eventType: event.type)
    if event.type == .keyDown, let scalar = UnicodeScalar(codepoint), scalar.value >= 32, scalar.value != 127 {
        event.charactersIgnoringModifiers = String(Character(scalar)).lowercased()
    }
    switch event.type {
    case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .mouseMoved:
        NSApp.keyWindow?._recordMouseLocation(event.locationInWindow)
    default:
        break
    }
    if NSEvent._deliverLocalMonitors(event) == nil {
        return true
    }
    if event.type == .rightMouseDown {
        return _omniPresentContextMenu(for: event)
    }
    if event.type == .scrollWheel {
        return _omniDispatchScrollWheel(for: event)
    }
    return false
#else
    _ = eventType
    _ = x
    _ = y
    _ = clickCount
    _ = modifiers
    _ = codepoint
    return false
#endif
}
