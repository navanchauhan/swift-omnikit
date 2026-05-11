import OmniUIAdwaitaRenderer
import OmniUICore
import Foundation
import Testing

@Test func adwaitaCoverageDocumentsBrowserViewSubset() {
    let exactRequired = [
        "App",
        "@State",
        "SwiftData @Query",
        "NavigationStack",
        "NavigationSplitView",
        "Form",
        "List",
        "ScrollViewReader",
        "Canvas",
        "Liquid Glass and CRT native-style approximations",
    ]

    for symbol in exactRequired {
        #expect(AdwaitaSemanticCoverage.supported.contains(symbol))
    }

    let documentedCoverage = AdwaitaSemanticCoverage.supported.joined(separator: " ")
    let requiredTerms = [
        "Scene", "WindowGroup", "Settings", "commands",
        "@Binding", "@Environment", "@AppStorage", "@FocusState", "@Namespace", "@Bindable",
        "modelContainer", "modelContext",
        "VStack", "HStack", "ZStack",
        "ScrollView", "LazyVStack", "GeometryReader",
        "Text", "Image", "Button", "Toggle", "TextField", "SecureField", "TextEditor", "Picker", "Menu",
        "Toolbar", "Sheet", "Alert",
        "Path", "Shape", "Gradient",
    ]
    for term in requiredTerms {
        #expect(documentedCoverage.contains(term))
    }
    #expect(!AdwaitaSemanticCoverage.approximations.isEmpty)
}

@Test func adwaitaRendererExposesNamedAppLauncher() throws {
    let source = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    #expect(source.contains("static func adwaitaMain"))
    #expect(source.contains("AdwaitaApp(appID: appID, title: title, size: size, Self.self).run()"))
}

@Test func packageDefinesNativeAdwaitaRendererTargetGraph() throws {
    let manifest = try readRepositoryFile("Package.swift")
    let omniUIFacade = try readRepositoryFile("Sources/OmniUI/OmniUI.swift")
    let header = try readRepositoryFile("Sources/CAdwaita/include/CAdwaita.h")
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let omniUITarget = try manifestTarget(named: "OmniUI", in: manifest)

    #expect(manifest.contains("name: \"CAdwaita\""))
    #expect(manifest.contains("path: \"Sources/CAdwaita\""))
    #expect(manifest.contains("publicHeadersPath: \"include\""))
    #expect(manifest.contains(".linkedLibrary(\"adwaita-1\""))
    #expect(manifest.contains(".linkedLibrary(\"gtk-4\""))
    #expect(manifest.contains("/usr/lib/aarch64-linux-gnu/glib-2.0/include"))
    #expect(manifest.contains("name: \"OmniUIAdwaitaRenderer\""))
    #expect(manifest.contains("dependencies: [\"OmniUICore\", \"CAdwaita\"]"))
    #expect(manifest.contains("name: \"OmniUIAdwaita\""))
    #expect(manifest.contains("dependencies: [\"OmniUICore\", \"OmniUIAdwaitaRenderer\", \"SwiftUIMacros\"]"))
    #expect(omniUITarget.contains("OmniUINotcursesRenderer"))
    #expect(!omniUITarget.contains("OmniUIAdwaitaRenderer"))
    #expect(!omniUIFacade.contains("OmniUIAdwaitaRenderer"))
    #expect(!omniUIFacade.contains("OMNIUI_RENDERER"))
    #expect(!omniUIFacade.contains("OMNIKIT_RENDERER"))
    #expect(header.contains("OmniAdwApp *omni_adw_app_new"))
    #expect(header.contains("OmniAdwNode *omni_adw_button_new"))
    #expect(header.contains("OmniAdwNode *omni_adw_drawing_new"))
    #expect(header.contains("omni_adw_app_share_url"))
    #expect(shim.contains("adw_application_new"))
    #expect(shim.contains("adw_application_window_new"))
    #expect(shim.contains("gtk_button_new_with_label"))
    #expect(shim.contains("gtk_drawing_area_new"))
    #expect(renderer.contains("import CAdwaita"))
    #expect(renderer.contains("omni_adw_app_new"))
    #expect(renderer.contains("omni_adw_app_set_root_focused"))
}

@Test func adwaitaRendererConsumesRendererNeutralSemanticLayer() throws {
    let semantic = try readRepositoryFile("Sources/OmniUICore/SemanticTree.swift")
    let runtime = try readRepositoryFile("Sources/OmniUICore/Runtime.swift")
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let supportDoc = try readRepositoryFile("docs/adwaita-renderer-support.md")

    #expect(semantic.contains("public struct SemanticSnapshot"))
    #expect(semantic.contains("public struct SemanticNode"))
    #expect(semantic.contains("public enum SemanticDiff"))
    #expect(semantic.contains("enum SemanticLowerer"))
    #expect(semantic.contains("case textField(actionID: Int"))
    #expect(semantic.contains("case container(SemanticContainerRole)"))
    #expect(semantic.contains("case modifier(SemanticModifier)"))
    #expect(runtime.contains("public func semanticSnapshot<V: View>(_ root: V, size: _Size) -> SemanticSnapshot"))
    #expect(runtime.contains("SemanticLowerer.lower(node)"))
    #expect(renderer.contains("runtime.semanticSnapshot(root(), size: renderSize)"))
    #expect(renderer.contains("let observationRenderLoop = Task { @MainActor [runtime, renderSize] in"))
    #expect(renderer.contains("if runtime.needsRender(size: renderSize)"))
    #expect(renderer.contains("observationRenderLoop.cancel()"))
    #expect(renderer.contains("AdwaitaPresentationExtractor.extract(from: snapshot.root)"))
    #expect(renderer.contains("SemanticDiff.changes(from: $0, to: displaySnapshot)"))
    #expect(renderer.contains("AdwaitaNodeBuilder.build(displaySnapshot.root)"))
    #expect(!renderer.contains("debugRender(root()"))
    #expect(!renderer.contains("RenderOp"))
    #expect(supportDoc.contains("lowers OmniUI's `_VNode` tree through `SemanticSnapshot` and `SemanticNode`"))
}

@Test func omniUIAdwaitaFacadeDefaultsAppMainToAdwaitaRenderer() throws {
    let manifest = try readRepositoryFile("Package.swift")
    let facade = try readRepositoryFile("Sources/OmniUIAdwaita/OmniUIAdwaita.swift")
    let smoke = try readRepositoryFile("Sources/OmniUIAdwaitaSmoke/main.swift")
    let swiftUISmoke = try readRepositoryFile("Sources/OmniUIAdwaitaSwiftUISmoke/main.swift")
    let supportDoc = try readRepositoryFile("docs/adwaita-renderer-support.md")
    let smokeRunner = try readRepositoryFile("scripts/run-omniui-adwaita-smoke-app.sh")
    let swiftUISmokeRunner = try readRepositoryFile("scripts/run-omniui-adwaita-swiftui-smoke-app.sh")

    #expect(manifest.contains("name: \"OmniUIAdwaita\""))
    #expect(manifest.contains("targets: [\"OmniUIAdwaita\"]"))
    #expect(manifest.contains("name: \"OmniUIAdwaitaSmoke\""))
    #expect(manifest.contains("name: \"OmniUIAdwaitaSwiftUISmoke\""))
    let smokeTarget = try manifestPackageTarget(named: "OmniUIAdwaitaSmoke", in: manifest)
    let swiftUISmokeTarget = try manifestPackageTarget(named: "OmniUIAdwaitaSwiftUISmoke", in: manifest)
    #expect(smokeTarget.contains("dependencies: [\"OmniUIAdwaita\"]"))
    #expect(!smokeTarget.contains("OmniSwiftUI"))
    #expect(!smokeTarget.contains("SwiftUI=OmniSwiftUI"))
    #expect(swiftUISmokeTarget.contains("dependencies: [\"OmniUIAdwaita\", \"OmniSwiftData\"]"))
    #expect(swiftUISmokeTarget.contains("\"SwiftUI=OmniUIAdwaita\""))
    #expect(swiftUISmokeTarget.contains("\"SwiftData=OmniSwiftData\""))
    #expect(facade.contains("@_exported import OmniUICore"))
    #expect(facade.contains("@_exported import OmniUIAdwaitaRenderer"))
    #expect(facade.contains("static func main() async throws"))
    #expect(facade.contains("String(describing: Self.self)"))
    #expect(facade.contains("try await Self.adwaitaMain(appID:"))
    #expect(smoke.contains("import OmniUIAdwaita"))
    #expect(swiftUISmoke.contains("import SwiftUI"))
    #expect(swiftUISmoke.contains("import SwiftData"))
    #expect(swiftUISmoke.contains("@Query private var records"))
    #expect(swiftUISmoke.contains("modelContext.insert"))
    #expect(swiftUISmoke.contains("ModelContainer(for: [AliasSmokeRecord.self], inMemory: true)"))
    #expect(swiftUISmoke.contains(".modelContainer(container)"))
    #expect(swiftUISmoke.contains("struct OmniUIAdwaitaSwiftUISmokeApp: App"))
    #expect(smoke.contains("@main"))
    #expect(smoke.contains("struct OmniUIAdwaitaSmokeApp: App"))
    #expect(supportDoc.contains("OmniUIAdwaitaSmoke"))
    #expect(supportDoc.contains("OmniUIAdwaitaSwiftUISmoke"))
    #expect(supportDoc.contains("SwiftUI=OmniUIAdwaita"))
    #expect(supportDoc.contains("SwiftData=OmniSwiftData"))
    #expect(smokeRunner.contains("xcrun swift build --product OmniUIAdwaitaSmoke"))
    #expect(smokeRunner.contains("CFBundleIdentifier"))
    #expect(smokeRunner.contains("dev.omnikit.OmniUIAdwaitaSmokeApp"))
    #expect(smokeRunner.contains("open \"$APP_DIR\""))
    #expect(swiftUISmokeRunner.contains("xcrun swift build --product OmniUIAdwaitaSwiftUISmoke"))
    #expect(swiftUISmokeRunner.contains("CFBundleIdentifier"))
    #expect(swiftUISmokeRunner.contains("dev.omnikit.OmniUIAdwaitaSwiftUISmokeApp"))
    #expect(swiftUISmokeRunner.contains("open \"$APP_DIR\""))
}

@Test func adwaitaRendererUsesSceneDefaultSizeForNativeWindow() throws {
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")
    let header = try readRepositoryFile("Sources/CAdwaita/include/CAdwaita.h")

    #expect(renderer.contains("_scenePreferredSize(scene)"))
    #expect(renderer.contains("nativeWindowSize(for: size)"))
    #expect(renderer.contains("semanticRenderSize(for: size)"))
    #expect(renderer.contains("runtime.semanticSnapshot(root(), size: renderSize)"))
    #expect(renderer.contains("omni_adw_app_set_default_size"))
    #expect(shim.contains("default_width"))
    #expect(shim.contains("default_height"))
    #expect(shim.contains("gtk_window_set_default_size(GTK_WINDOW(app->window), app->default_width, app->default_height)"))
    #expect(header.contains("omni_adw_app_set_default_size"))
}

@Test func adwaitaSceneInitializerInstallsNativeSettingsAndCommandsChrome() throws {
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let core = try readRepositoryFile("Sources/OmniUICore/AppScene.swift")
    let header = try readRepositoryFile("Sources/CAdwaita/include/CAdwaita.h")
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")
    let source = try readRepositoryFile("Sources/KitchenSinkAdwaita/main.swift")

    #expect(renderer.contains("let sceneSettings = _sceneSettingsView(scene)"))
    #expect(renderer.contains("let sceneCommands = _sceneCommandsView(scene)"))
    #expect(renderer.contains("omni_adw_app_set_settings(cApp, node)"))
    #expect(renderer.contains("omni_adw_app_set_commands(cApp, node)"))
    #expect(renderer.contains("runtime.setDefaultOpenURLAction"))
    #expect(renderer.contains("runtime.setDefaultShareURLAction"))
    #expect(renderer.contains("omni_adw_app_share_url(appHandle, value)"))
    #expect(!renderer.contains("root.safeAreaInset(edge: .bottom) { commands }"))
    #expect(header.contains("omni_adw_app_set_settings"))
    #expect(header.contains("omni_adw_app_set_commands"))
    #expect(shim.contains("gtk_menu_button_set_icon_name(GTK_MENU_BUTTON(app->command_button), \"open-menu-symbolic\")"))
    #expect(shim.contains("gtk_widget_set_visible(app->command_button, FALSE)"))
    #expect(!shim.contains("gtk_button_new_with_label(\"Settings\")"))
    #expect(shim.contains("app->settings_window = gtk_window_new()"))
    #expect(shim.contains("gtk_window_set_decorated(GTK_WINDOW(app->settings_window), TRUE)"))
    #expect(shim.contains("g_signal_connect(app->settings_window, \"close-request\""))
    #expect(shim.contains("gtk_window_set_child(GTK_WINDOW(app->settings_window), app->settings_content)"))
    #expect(shim.contains("static gboolean on_settings_close_request"))
    #expect(shim.contains("gtk_widget_set_visible(GTK_WIDGET(window), FALSE)"))
    #expect(shim.contains("keyval == GDK_KEY_comma"))
    #expect(shim.contains("install_application_actions(app)"))
    #expect(shim.contains("\"app.preferences\""))
    #expect(shim.contains("\"app.about\""))
    #expect(shim.contains("adw_about_dialog_new()"))
    #expect(core.contains("public func _sceneCommandsView<S: Scene>(_ scene: S) -> AnyView?"))
    #expect(core.contains("public func _sceneSettingsView<S: Scene>(_ scene: S) -> AnyView?"))
    #expect(source.contains("CommandGroup(after: .appInfo)"))
    #expect(source.contains("SidebarCommands()"))
    #expect(source.contains("Settings {"))
}

@Test func kitchenSinkAdwaitaSourceExercisesBrowserViewSubsetAndSmokeControls() throws {
    let source = try readRepositoryFile("Sources/KitchenSinkAdwaita/main.swift")
    let runner = try readRepositoryFile("scripts/run-kitchensink-adwaita-app.sh")
    let supportDoc = try readRepositoryFile("docs/adwaita-renderer-support.md")
    let requiredTerms = [
        "import OmniUIAdwaita",
        "WindowGroup", "Settings", ".commands",
        "@State", "@Binding", "@AppStorage", "@FocusState", "@Namespace", "@Environment", "@Query", "@Bindable",
        "modelContainer", "modelContext",
        "NavigationSplitView", "NavigationStack", "ScrollViewReader", "ScrollView", "LazyVStack",
        "Form", "List", "GeometryReader", "Canvas", "Path", "RoundedRectangle", "LinearGradient",
        "TextField", "TextEditor", "SecureField", "ProgressView", "Slider", "Stepper", "DatePicker", "Picker", "Toggle", "Button",
        ".toolbar", ".sheet", ".alert", ".glassEffect()",
        "Input smoke:", "Type !", "Backspace",
        "Notes smoke:", "Append note", "Reset notes",
        "Picker smoke:", "Set Mint", "Set Vanilla",
        "SwiftData records:", "Add record", "Delete record",
        "Common controls:", "Level +", "Step +", "Stepper:",
        "Disabled action", "Disabled toggle", "Disabled name", ".disabled(true)",
    ]

    for term in requiredTerms {
        #expect(source.contains(term))
    }
    #expect(runner.contains("xcrun swift build --product KitchenSinkAdwaita"))
    #expect(runner.contains("CFBundleIdentifier"))
    #expect(runner.contains("dev.omnikit.KitchenSinkAdwaita"))
    #expect(runner.contains("open \"$APP_DIR\""))
    #expect(supportDoc.contains("scripts/run-kitchensink-adwaita-app.sh"))
    #expect(supportDoc.contains("KitchenSinkAdwaita"))
}

@Test func kitchenSinkAndSmokeCoverStateWrapperSurface() throws {
    let source = try readRepositoryFile("Sources/KitchenSinkAdwaita/main.swift")
    let smoke = try readRepositoryFile("Sources/OmniUIAdwaitaSmoke/main.swift")
    let swiftUISmoke = try readRepositoryFile("Sources/OmniUIAdwaitaSwiftUISmoke/main.swift")
    let supportDoc = try readRepositoryFile("docs/adwaita-renderer-support.md")

    let kitchenSinkTerms = [
        "@State private var count",
        "@Binding var count",
        "@Environment(\\.demoEnvironmentLabel)",
        "@Environment(\\.modelContext)",
        "@AppStorage(\"kitchensink-adwaita-note\")",
        "@FocusState private var nameFocused",
        "@Namespace private var namespace",
        "@Bindable var model",
        "BindingCounter(count: $count)",
        "EnvironmentBadge()",
        "NamespaceBadge(namespace: namespace)",
        "BindableModelPanel(model: bindableModel)",
    ]
    for term in kitchenSinkTerms {
        #expect(source.contains(term))
    }

    #expect(smoke.contains("@State private var count"))
    #expect(smoke.contains("@FocusState private var focused"))
    #expect(swiftUISmoke.contains("@State private var count"))
    #expect(swiftUISmoke.contains("@FocusState private var focused"))
    #expect(swiftUISmoke.contains("@Environment(\\.modelContext)"))
    #expect(supportDoc.contains("`@State`, `@Binding`, `@Environment`, `@AppStorage`, `@FocusState`, `@Namespace`, and `@Bindable`"))
    #expect(supportDoc.contains("stay owned by OmniUICore's runtime and are re-read on each semantic render"))
    #expect(supportDoc.contains("Toolbar items preserve leading, trailing, principal, and bottom-bar placement"))
    #expect(supportDoc.contains("ForEach(..., id:)` elements use stable ID-derived runtime path components"))
}

@Test func cAdwaitaShimInstallsSemanticStylingForNativeRenderer() throws {
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")
    let requiredTerms = [
        "omni_install_css_once",
        ".card",
        ".adw-dialog",
        ".boxed-list",
        ".navigation-view",
        ".accent",
        ".omni-drawing-island",
        "omni_accessible_label",
        "omni_accessible_description",
        "omni_accessible_role_description",
        "omni_accessible_list_position",
        "gtk_accessible_update_property",
        "GTK_ACCESSIBLE_PROPERTY_LABEL",
        "GTK_ACCESSIBLE_PROPERTY_DESCRIPTION",
        "GTK_ACCESSIBLE_PROPERTY_PLACEHOLDER",
        "GTK_ACCESSIBLE_RELATION_POS_IN_SET",
        "GTK_ACCESSIBLE_STATE_SELECTED",
        "apply_initial_scroll_offset",
        "gtk_scrolled_window_get_vadjustment",
        "gtk_scrolled_window_get_hadjustment",
        "gtk_adjustment_set_value",
        "omni_adw_node_apply_layout",
        "omni_adw_list_new",
        "omni_adw_form_new",
        "omni_adw_split_new",
        "gtk_list_box_new",
        "gtk_list_box_row_new",
        "gtk_box_new(GTK_ORIENTATION_VERTICAL, 8)",
        "adw_overlay_split_view_new",
        "adw_overlay_split_view_set_sidebar_position",
        "adw_overlay_split_view_set_show_sidebar",
        "sidebar_show_sidebar",
        "adw_overlay_split_view_set_sidebar",
        "adw_overlay_split_view_set_content",
        "ADW_IS_OVERLAY_SPLIT_VIEW(parent->widget)",
        "adw-sidebar-symbolic",
        "on_sidebar_toggle_toggled",
        "sync_sidebar_toggle",
        "gtk_widget_set_size_request",
        "gtk_widget_set_margin_top",
        "gtk_widget_set_opacity",
        "omni_adw_node_set_sensitive",
        "omni_adw_progress_new",
        "gtk_progress_bar_new",
        "gtk_progress_bar_set_fraction",
        "omni_adw_scale_new",
        "gtk_scale_new_with_range",
        "on_scale_value_changed",
        "gtk_range_set_value",
        "omni_adw_spin_new",
        "gtk_spin_button_new_with_range",
        "on_spin_value_changed",
        "gtk_spin_button_set_value",
        "omni_adw_date_new",
        "gtk_calendar_new",
        "omni-set-action-id",
        "on_calendar_date_notify",
        "omni_calendar_set_date",
        "gtk_calendar_set_year",
        "omni_apply_color_scheme_from_environment",
        "OMNIUI_ADWAITA_COLOR_SCHEME",
        "OMNIUI_COLOR_SCHEME",
        "ADW_COLOR_SCHEME_FORCE_DARK",
        "ADW_COLOR_SCHEME_FORCE_LIGHT",
        "omni_adw_app_set_header_entry",
        "ensure_header_title_widget",
        "sync_header_entry",
        "omni-header-entry",
        "header_new_tab_button",
        "gtk_button_set_icon_name(GTK_BUTTON(app->header_new_tab_button), \"adw-tab-new-symbolic\")",
        "omni_adw_secure_entry_new",
        "gtk_entry_set_visibility",
        "gtk_entry_set_invisible_char",
        "gtk_widget_set_vexpand(node->widget, FALSE)",
        "gtk_widget_set_valign(node->widget, GTK_ALIGN_CENTER)",
        "GDK_KEY_Return",
        "GDK_KEY_Escape",
        "gtk_css_provider_load_from_string",
        "gtk_style_context_add_provider_for_display",
    ]

    for term in requiredTerms {
        #expect(shim.contains(term))
    }
}

@Test func adwaitaCommonControlsMapToNativeGtkConstructors() throws {
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let header = try readRepositoryFile("Sources/CAdwaita/include/CAdwaita.h")
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")
    let source = try readRepositoryFile("Sources/KitchenSinkAdwaita/main.swift")
    let supportDoc = try readRepositoryFile("docs/adwaita-renderer-support.md")

    let controls = [
        ("Text", "case .text(let text), .image(let text):", "omni_adw_text_new", "gtk_label_new"),
        ("Button", "case .button(let actionID, _):", "omni_adw_button_new", "gtk_button_new_with_label"),
        ("Toggle", "case .toggle(let actionID, _, let isOn):", "omni_adw_toggle_new", "gtk_check_button_new_with_label"),
        ("TextField", "case .textField(let actionID, let placeholder, let text, _, _, let isSecure):", "omni_adw_entry_new", "gtk_entry_new"),
        ("SecureField", "omni_adw_secure_entry_new", "omni_adw_secure_entry_new", "gtk_entry_set_visibility"),
        ("TextEditor", "case .textEditor(let actionID, let text, _, _):", "omni_adw_text_view_new", "gtk_text_view_new"),
        ("ProgressView", "case .progress(let label, let fraction):", "omni_adw_progress_new", "gtk_progress_bar_new"),
        ("Slider", "case .slider(let label, let value", "omni_adw_scale_new", "gtk_scale_new_with_range"),
        ("Stepper", "case .stepper(let label, let value", "omni_adw_spin_new", "gtk_spin_button_new_with_range"),
        ("DatePicker", "case .datePicker(let label, let value", "omni_adw_date_new", "gtk_calendar_new"),
        ("Picker", "case .menu(let actionID, let title, let value, let isExpanded):", "omni_adw_dropdown_new", "gtk_menu_button_new"),
    ]

    for (control, rendererTerm, headerTerm, shimTerm) in controls {
        #expect(source.contains(control))
        #expect(renderer.contains(rendererTerm))
        #expect(header.contains(headerTerm))
        #expect(shim.contains(shimTerm))
    }

    #expect(source.contains("Disabled action"))
    #expect(renderer.contains("omni_adw_node_set_sensitive(built, 0)"))
    #expect(shim.contains("gtk_widget_set_sensitive(node->widget, sensitive != 0)"))
    #expect(supportDoc.contains("## Native Widgets"))
}

@Test func adwaitaRendererHasLargeListAndTextFastPaths() throws {
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let header = try readRepositoryFile("Sources/CAdwaita/include/CAdwaita.h")
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")
    let source = try readRepositoryFile("Sources/KitchenSinkAdwaita/main.swift")
    let hugeSmokeScript = try readRepositoryFile("scripts/run-adwaita-huge-smoke.sh")

    #expect(header.contains("omni_adw_string_list_new"))
    #expect(header.contains("omni_adw_plain_list_new"))
    #expect(renderer.contains("simpleListRows(from: children)"))
    #expect(renderer.contains("isEmptyListContent(children)"))
    #expect(renderer.contains("if let simpleList = simpleListRows(from: children)"))
    #expect(renderer.contains("if let scroll = simpleList.scroll"))
    #expect(renderer.contains("return wrapInScroll(list, axis: scroll.axis, offset: scroll.offset)"))
    #expect(renderer.contains("return wrapInScroll(list, axis: .vertical, offset: 0)"))
    #expect(renderer.contains("return wrapInScroll(parent, axis: .vertical, offset: 0)"))
    #expect(renderer.contains("private static func wrapInScroll"))
    #expect(renderer.contains("omni_adw_node_append(scrollNode, child)"))
    #expect(renderer.contains("func firstButtonActionID(in node: SemanticNode) -> Int?"))
    #expect(renderer.contains("let rows: [(label: String, actionID: Int?, depth: Int)]"))
    #expect(renderer.contains("leadingWhitespaceDepth(in node: SemanticNode)"))
    #expect(renderer.contains("rows.append((label: label, actionID: firstButtonActionID(in: node), depth: leadingWhitespaceDepth(in: node)))"))
    #expect(renderer.contains("omni_adw_plain_list_new"))
    #expect(renderer.contains("private enum BuildContext: Equatable"))
    #expect(renderer.contains("case sidebar"))
    #expect(renderer.contains("if case .spacer = child.kind"))
    #expect(renderer.contains("built = omni_adw_box_new(vertical ? 1 : 0, 0)"))
    #expect(renderer.contains("navigationSplitContainer(children: children)"))
    #expect(renderer.contains("omni_adw_sidebar_list_new(labelPointers, idBuffer.baseAddress, depthBuffer.baseAddress"))
    #expect(renderer.contains("simpleList.rows.count >= 128"))
    #expect(renderer.contains("case .container(.list):"))
    #expect(renderer.contains("omni_adw_string_list_new"))
    #expect(header.contains("omni_adw_sidebar_list_new"))
    #expect(shim.contains("gtk_string_list_append"))
    #expect(shim.contains("gtk_list_view_new"))
    #expect(shim.contains("gtk_list_view_set_single_click_activate"))
    #expect(shim.contains("gtk_list_item_set_accessible_label"))
    #expect(shim.contains("on_virtual_list_button_clicked"))
    #expect(shim.contains("omni-list-row-button"))
    #expect(shim.contains("omni-sidebar-row-button"))
    #expect(shim.contains("on_sidebar_list_setup"))
    #expect(shim.contains("on_sidebar_list_bind"))
    #expect(shim.contains("if (count >= 128)"))
    #expect(shim.contains("data->depths = calloc"))
    #expect(shim.contains("data->labels = calloc"))
    #expect(shim.contains("data->collapsed = calloc"))
    #expect(shim.contains("sidebar_rebuild_visible_indices"))
    #expect(shim.contains("on_sidebar_disclosure_clicked"))
    #expect(shim.contains("omni-sidebar-disclosure-button"))
    #expect(shim.contains("g_signal_connect(factory, \"bind\", G_CALLBACK(on_sidebar_list_bind), data)"))
    #expect(shim.contains("gtk_label_set_wrap(GTK_LABEL(label), FALSE)"))
    #expect(shim.contains("omni_adw_plain_list_new"))
    #expect(shim.contains("omni_adw_sidebar_list_new"))
    #expect(shim.contains("omni-sidebar-list"))
    #expect(shim.contains(".omni-plain-list row:hover { background: transparent; }"))
    #expect(shim.contains(".omni-sidebar-list row:hover { background: transparent; }"))
    #expect(shim.contains("gtk_list_box_set_selection_mode(GTK_LIST_BOX(node->widget), GTK_SELECTION_SINGLE)"))
    #expect(shim.contains("install_row_click_controller(label)"))
    #expect(shim.contains("GTK_IS_LIST_BOX(widget)"))
    #expect(shim.contains("on_plain_list_row_activated"))
    #expect(shim.contains("on_plain_list_row_pressed"))
    #expect(shim.contains("on_plain_list_row_released"))
    #expect(shim.contains("omni_click_is_stationary(gesture, x, y)"))
    #expect(!shim.contains("schedule_scrolled_window_adjustment_restores(app->content)"))
    #expect(shim.contains("GTK_IS_LIST_BOX_ROW(row_widget)"))
    #expect(shim.contains("action_id > 0 && GTK_IS_LIST_BOX_ROW(action_widget)"))
    #expect(shim.contains("gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED)"))
    #expect(shim.contains("first_widget_action_id"))
    #expect(shim.contains("first_widget_accessible_label"))
    #expect(shim.contains("on_string_list_activate"))
    #expect(shim.contains("gtk_scrolled_window_set_propagate_natural_height(GTK_SCROLLED_WINDOW(node->widget), FALSE)"))
    #expect(shim.contains("gtk_scrolled_window_set_propagate_natural_width(GTK_SCROLLED_WINDOW(node->widget), FALSE)"))
    #expect(shim.contains("strlen(value) > 16384"))
    #expect(shim.contains("gtk_text_view_set_editable(GTK_TEXT_VIEW(node->widget), FALSE)"))
    #expect(source.contains("OMNIUI_ADWAITA_HUGE_SMOKE"))
    #expect(source.contains("0..<5_000"))
    #expect(hugeSmokeScript.contains("List(0..<5_000"))
    #expect(hugeSmokeScript.contains("String(repeating: \"Gopher text payload. \", count: 8_000)"))
    #expect(hugeSmokeScript.contains("OMNIUI_ADWAITA_DUMP_SEMANTIC=1"))
    #expect(hugeSmokeScript.contains("gopher://example/4999"))
}

@Test func adwaitaRendererPreservesDialogOverlayStyling() throws {
    let semantic = try readRepositoryFile("Sources/OmniUICore/SemanticTree.swift")
    let modifiers = try readRepositoryFile("Sources/OmniUICore/Modifiers.swift")
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let header = try readRepositoryFile("Sources/CAdwaita/include/CAdwaita.h")
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")

    #expect(semantic.contains(".background(\"adw-dialog\")"))
    #expect(modifiers.contains("_ModalOverlayCard("))
    #expect(modifiers.contains("scrim: Color.black.opacity(0.45)"))
    #expect(renderer.contains("AdwaitaPresentationExtractor.extract(from: snapshot.root)"))
    #expect(renderer.contains("syncNativePresentation(presentation.modal, app: cApp)"))
    #expect(renderer.contains("stripPresentation(from: root"))
    #expect(header.contains("omni_adw_app_present_modal"))
    #expect(header.contains("omni_adw_app_dismiss_modal"))
    #expect(shim.contains("AdwDialog *base_dialog = adw_alert_dialog_new"))
    #expect(shim.contains("adw_alert_dialog_add_response(dialog"))
    #expect(shim.contains("adw_dialog_present(base_dialog, app->window)"))
    #expect(shim.contains("static void on_alert_response"))
    #expect(shim.contains("static void present_sheet_dialog"))
    #expect(shim.contains("AdwDialog *dialog = adw_alert_dialog_new(heading, NULL)"))
    #expect(shim.contains("effective_close_action_id"))
    #expect(shim.contains("modal_cancel_action_id"))
    #expect(shim.contains("adw_dialog_set_can_close(dialog, effective_close_action_id > 0)"))
    #expect(shim.contains("adw_alert_dialog_set_prefer_wide_layout(alert, TRUE)"))
    #expect(shim.contains("omni-sheet-surface"))
    #expect(shim.contains("gtk_box_append(GTK_BOX(surface), modal->widget)"))
    #expect(shim.contains("adw_alert_dialog_set_extra_child(alert, surface)"))
    #expect(shim.contains("omni-sheet-content-widget"))
    #expect(shim.contains("g_signal_connect(dialog, \"close-attempt\", G_CALLBACK(on_sheet_close_attempt), app)"))
    #expect(shim.contains("g_signal_connect(dialog, \"closed\", G_CALLBACK(on_sheet_closed), app)"))
    #expect(shim.contains("static void on_window_click_pressed"))
    #expect(shim.contains("static void on_window_click_released"))
    #expect(!shim.contains("static void on_sheet_click_pressed"))
    #expect(!shim.contains("static void on_sheet_click_released"))
    #expect(!shim.contains("gtk_widget_pick(GTK_WIDGET(dialog), x, y, GTK_PICK_DEFAULT)"))
    #expect(!shim.contains("G_CALLBACK(on_sheet_click_released)"))
    #expect(shim.contains("adw_dialog_close(dialog)"))
    #expect(shim.contains("static int modal_close_action_id"))
    #expect(shim.contains("static int modal_cancel_action_id"))
    #expect(shim.contains("strcmp(label, \"Close\") == 0"))
    #expect(shim.contains("find_first_entry_widget(modal->widget)"))
    #expect(shim.contains("if (app->modal_dialog)"))
    #expect(shim.contains("gtk_widget_grab_focus(sheet_entry)"))
    #expect(shim.contains("omni_macos_accessibility_add_widget(GTK_WIDGET(app->modal_dialog)"))
    #expect(shim.contains("omni_macos_accessibility_add_widget(app->window, app->window"))
    #expect(shim.range(of: "omni_macos_accessibility_add_widget(GTK_WIDGET(app->modal_dialog)")!.lowerBound < shim.range(of: "omni_macos_accessibility_add_widget(app->window, app->window", range: shim.range(of: "static void omni_macos_accessibility_sync")!.lowerBound..<shim.endIndex)!.lowerBound)
    #expect(shim.contains("setAccessibilityValue:"))
    #expect(shim.contains("accessibilityValue"))
    #expect(shim.contains("omni_macos_accessibility_value_key"))
    #expect(shim.contains("GTK_IS_ENTRY(widget) || GTK_IS_TEXT_VIEW(widget) || (value && value[0])"))
    #expect(shim.contains("gtk_editable_set_text(GTK_EDITABLE(widget), text)"))
    #expect(shim.contains("adw_dialog_force_close(app->modal_dialog)"))
    #expect(shim.contains("gtk_button_get_label(GTK_BUTTON(widget))"))
    #expect(shim.contains("gtk_label_get_text(GTK_LABEL(widget))"))
    #expect(!shim.contains("app->modal_window = gtk_window_new()"))
    #expect(!shim.contains("gtk_window_set_child(GTK_WINDOW(app->modal_window)"))
    #expect(renderer.contains("case .background(\"adw-dialog\")"))
    #expect(renderer.contains("modal = nativeDialogContent(from: node)"))
    #expect(renderer.contains("private static func nativeDialogContent"))
    #expect(renderer.contains("guard case .modifier(.background(\"adw-dialog\")) = node.kind else"))
    #expect(renderer.contains("node.children.first(where: { $0.id.hasSuffix(\".content\") }) ?? node"))
    #expect(renderer.contains("css = \"card adw-dialog\""))
    #expect(shim.contains(".adw-dialog"))
    #expect(shim.contains("adw_alert_dialog_set_extra_child(alert, surface)"))
    #expect(shim.contains("background-color: #303036"))
    #expect(!shim.contains("gtk_frame_set_child(GTK_FRAME(surface), modal->widget)"))
    #expect(shim.contains("adw_dialog_set_presentation_mode(dialog, ADW_DIALOG_FLOATING)"))
    #expect(shim.contains("gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED)"))
}

@Test func adwaitaRendererHasTabsToolbarAndTypographyPolish() throws {
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")

    #expect(shim.contains("header_tab_strip"))
    #expect(shim.contains("header_selected_tab"))
    #expect(shim.contains("tab_count"))
    #expect(shim.contains("update_header_tab_strip"))
    #expect(shim.contains("gtk_widget_set_visible(app->header_tab_strip, FALSE)"))
    #expect(shim.contains("on_new_tab_clicked"))
    #expect(shim.contains("omni-selected-tab"))
    #expect(shim.contains("omni-inactive-tab"))
    #expect(shim.contains("omni-icon-button"))
    #expect(shim.contains("gtk_widget_set_size_request(node->widget, 38, 34)"))
    #expect(shim.contains("adw-sidebar-symbolic"))
    #expect(shim.contains("omni-sidebar-toggle"))
    #expect(shim.contains("gtk_widget_set_size_request(app->header_sidebar_button, 36, 34)"))
    #expect(shim.contains("app->sidebar_show_sidebar = TRUE"))
    #expect(shim.contains("app->sidebar_show_sidebar = show_sidebar"))
    #expect(shim.contains("adw_overlay_split_view_set_show_sidebar(ADW_OVERLAY_SPLIT_VIEW(widget), app->sidebar_show_sidebar)"))
    #expect(shim.contains("omni_symbolic_icon_name_for_label"))
    #expect(shim.contains("user-home-symbolic"))
    #expect(shim.contains("go-previous-symbolic"))
    #expect(shim.contains("go-next-symbolic"))
    #expect(shim.contains("bookmark-new-symbolic"))
    #expect(shim.contains("open-menu-symbolic"))
    #expect(shim.contains("adw-external-link-symbolic"))
    #expect(shim.contains("adw-tab-new-symbolic"))
    #expect(shim.contains("gtk_menu_button_set_icon_name(GTK_MENU_BUTTON(app->command_button), \"open-menu-symbolic\")"))
    #expect(shim.contains("omni-go-button"))
    #expect(shim.contains("gtk_widget_set_size_request(node->widget, 46, 34)"))
    #expect(shim.contains("omni-monospace-text"))
    #expect(shim.contains("SFMono-Regular"))
    #expect(shim.contains("font-size: 13px"))
}

@Test func adwaitaDocumentsLiquidGlassAndCRTApproximationPath() throws {
    let source = try readRepositoryFile("Sources/KitchenSinkAdwaita/main.swift")
    let modifiers = try readRepositoryFile("Sources/OmniUICore/Modifiers.swift")
    let semantic = try readRepositoryFile("Sources/OmniUICore/SemanticTree.swift")
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")
    let supportDoc = try readRepositoryFile("docs/adwaita-renderer-support.md")

    #expect(source.contains(".glassEffect()"))
    #expect(source.contains(".crtEffect(.scanline)"))
    #expect(source.contains("CRT modifiers are native no-op approximations"))
    #expect(modifiers.contains("private struct _GlassEffectModifier"))
    #expect(modifiers.contains("private struct _CRTEffectModifier"))
    #expect(modifiers.contains("return .glass(style: style.rawValue"))
    #expect(modifiers.contains(".crt(style: style.rawValue"))
    #expect(semantic.contains("case .glass(let style, let shape, let child):"))
    #expect(semantic.contains("case .crt(let style, let child):"))
    #expect(semantic.contains("kind: .modifier(.glass(descriptor))"))
    #expect(semantic.contains("kind: .modifier(.crt(style))"))
    #expect(renderer.contains("case .foreground, .background, .shadow, .glass, .crt, .clip, .accessibilityLabel, .noOp:"))
    #expect(renderer.contains("return primaryContent()"))
    #expect(renderer.contains("visibleChildren(forOverlayChildren:"))
    #expect(renderer.contains("isDecorativeDrawing"))
    #expect(shim.contains(".card {"))
    #expect(shim.contains(".crt { }"))
    #expect(supportDoc.contains("Liquid Glass and CRT effect modifiers are semantic metadata in the Adwaita backend"))
    #expect(supportDoc.contains("decorative Canvas, Path, shape, and gradient overlays"))
}

@Test func adwaitaMapsDrawingSurfacePrimitivesToNativeDrawingIslands() throws {
    let source = try readRepositoryFile("Sources/KitchenSinkAdwaita/main.swift")
    let drawing = try readRepositoryFile("Sources/OmniUICore/Drawing.swift")
    let semantic = try readRepositoryFile("Sources/OmniUICore/SemanticTree.swift")
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")
    let supportDoc = try readRepositoryFile("docs/adwaita-renderer-support.md")

    #expect(source.contains("Canvas { context, size in"))
    #expect(source.contains("context.fill(Path(rect), with: .color(.teal))"))
    #expect(source.contains("RoundedRectangle(cornerRadius: 8)"))
    #expect(source.contains("LinearGradient(colors: [.blue, .green]"))
    #expect(drawing.contains("commands.append(.fillShape(node))"))
    #expect(drawing.contains("return nodes.isEmpty ? .empty : .group(nodes)"))
    #expect(semantic.contains("case .shape(let shape):"))
    #expect(semantic.contains("kind: .drawingIsland(.shape(shape.kind.semanticName))"))
    #expect(semantic.contains("case .gradient:"))
    #expect(semantic.contains("kind: .drawingIsland(.gradient)"))
    #expect(renderer.contains("case .drawingIsland(let kind):"))
    #expect(renderer.contains("omni_adw_drawing_new(\"OmniUI \\(kind)"))
    #expect(shim.contains("gtk_drawing_area_new()"))
    #expect(shim.contains("gtk_widget_add_css_class(node->widget, \"omni-drawing-island\")"))
    #expect(shim.contains("gtk_widget_set_tooltip_text(node->widget"))
    #expect(supportDoc.contains("Drawing islands carry tooltips/metadata"))
}

@Test func cAdwaitaShimLetsGtkOwnScrollStateAndOnlyAppliesExplicitInitialOffsets() throws {
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let header = try readRepositoryFile("Sources/CAdwaita/include/CAdwaita.h")

    let setRootRange = try #require(shim.range(of: "void omni_adw_app_set_root_focused"))
    let setRootEnd = try #require(shim.range(of: "typedef struct {", range: setRootRange.upperBound..<shim.endIndex))
    let setRootBody = String(shim[setRootRange.lowerBound..<setRootEnd.lowerBound])

    #expect(setRootBody.contains("adw_application_window_set_content"))
    #expect(!setRootBody.contains("collect_scroll_offsets"))
    #expect(!setRootBody.contains("restore_scroll_offsets"))
    #expect(!setRootBody.contains("schedule_scroll_offset_restore"))
    #expect(!shim.contains("scroll_offsets"))
    #expect(!shim.contains("collect_scroll_offsets"))
    #expect(!shim.contains("restore_scroll_offsets"))
    #expect(!shim.contains("schedule_scroll_offset_restore"))
    #expect(!shim.contains("g_timeout_add"))
    #expect(shim.contains("gtk_widget_set_name(node->widget, copy)"))
    #expect(shim.contains("omni_semantic_scroll_to_pixels"))
    #expect(shim.contains("offset * 28.0"))
    #expect(shim.contains("if (offset > 0.0)"))
    #expect(shim.contains("g_object_set_data(G_OBJECT(node->widget), \"omni-scroll-vertical\""))
    #expect(shim.contains("apply_initial_scroll_offset(GTK_SCROLLED_WINDOW(parent->widget))"))
    #expect(shim.contains("g_idle_add(restore_adjustment_value, request);"))
    #expect(shim.contains("case 10:"))
    #expect(shim.contains("GTK_IS_SCROLLED_WINDOW(widget)"))
    #expect(shim.contains("schedule_adjustment_restore(adjustment, pixels);"))
    #expect(renderer.contains("omni_adw_scroll_new(axis == .vertical ? 1 : 0, Double(offset))"))
    #expect(renderer.contains("case scroll = 10"))
    #expect(renderer.contains("case .scroll(_, _, let offset):"))
    #expect(header.contains("omni_adw_scroll_new(int32_t vertical, double offset)"))
}

@Test func cAdwaitaShimExportsGtkWidgetsToMacOSAccessibility() throws {
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")

    #expect(shim.contains("#include <objc/message.h>"))
    #expect(shim.contains("NSAccessibilityElement"))
    #expect(shim.contains("objc_allocateClassPair(baseClass, \"OmniAdwaitaAccessibilityElement\", 0)"))
    #expect(shim.contains("accessibilityPerformPress"))
    #expect(shim.contains("app->callback(actionID, app->context);"))
    #expect(shim.contains("accessibilityElementWithRole:frame:label:parent:"))
    #expect(shim.contains("gtk_widget_compute_bounds(widget, root, &bounds)"))
    #expect(shim.contains("if (!gtk_widget_get_visible(widget)) return;"))
    #expect(shim.contains("if (gtk_widget_get_mapped(widget) && omni_macos_accessibility_should_export(widget))"))
    #expect(shim.contains("setAccessibilityChildren:"))
    #expect(shim.contains("setAccessibilityChildrenInNavigationOrder:"))
    #expect(shim.contains("omni_macos_accessibility_schedule(app);"))
    #expect(shim.contains("omni_macos_accessibility_schedule_after_scroll"))
    #expect(shim.contains("g_timeout_source_new(120)"))
    #expect(shim.contains("omni_macos_accessibility_has_exported_action_ancestor"))
    #expect(shim.contains("omni_macos_accessibility_sync_idle"))
    #expect(shim.contains("on_scroll_adjustment_value_changed"))
    #expect(shim.contains("g_signal_connect(vadjustment, \"value-changed\", G_CALLBACK(on_scroll_adjustment_value_changed), app)"))
    #expect(shim.contains("if (GTK_IS_ENTRY(widget)) return \"AXTextField\";"))
    #expect(shim.contains("if (GTK_IS_BUTTON(widget) || GTK_IS_MENU_BUTTON(widget)) return \"AXButton\";"))
    #expect(shim.contains("if (GTK_IS_LIST_BOX_ROW(widget) && GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), \"omni-action-id\")) > 0) return \"AXButton\";"))
    #expect(shim.contains("if (GTK_IS_LIST_VIEW(widget) || GTK_IS_LIST_BOX(widget)) return \"AXList\";"))
}

@Test func cAdwaitaShimCanReplaceNamedSemanticSubtrees() throws {
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let header = try readRepositoryFile("Sources/CAdwaita/include/CAdwaita.h")

    #expect(header.contains("omni_adw_app_replace_node"))
    #expect(shim.contains("int32_t omni_adw_app_replace_node"))
    #expect(shim.contains("find_widget_for_name(app->content, name)"))
    #expect(shim.contains("if (app->body_slot)"))
    #expect(shim.contains("gtk_box_append(GTK_BOX(app->body_slot), app->content)"))
    #expect(shim.contains("gtk_box_insert_child_after"))
    #expect(shim.contains("gtk_list_box_row_set_child"))
    #expect(shim.contains("gtk_paned_set_start_child"))
    #expect(shim.contains("gtk_scrolled_window_set_child"))
    #expect(!shim.contains("schedule_scroll_offset_restore(app->content, app->scroll_offsets);"))
    #expect(renderer.contains("applyStructuralReplacement"))
    #expect(renderer.contains("omni_adw_app_replace_node(app, replacement.id, node"))
}

@Test func adwaitaRerenderAttemptsLeafThenStructuralThenRootReplacement() throws {
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")

    guard
        let diffRange = renderer.range(of: "SemanticDiff.changes(from: $0, to: displaySnapshot)"),
        let noOpRange = renderer.range(of: "if changes.isEmpty, callbackBox.previousSnapshot != nil", range: diffRange.lowerBound..<renderer.endIndex),
        let leafRange = renderer.range(of: "AdwaitaNodeBuilder.applyLeafUpdates", range: noOpRange.lowerBound..<renderer.endIndex),
        let structuralRange = renderer.range(of: "AdwaitaNodeBuilder.applyStructuralReplacement", range: leafRange.lowerBound..<renderer.endIndex),
        let buildRange = renderer.range(of: "AdwaitaNodeBuilder.build(displaySnapshot.root)", range: structuralRange.lowerBound..<renderer.endIndex),
        let rootRange = renderer.range(of: "omni_adw_app_set_root_focused", range: buildRange.lowerBound..<renderer.endIndex)
    else {
        #expect(Bool(false), "Adwaita rerender reconciliation sequence was not found")
        return
    }

    #expect(diffRange.lowerBound < leafRange.lowerBound)
    #expect(diffRange.lowerBound < noOpRange.lowerBound)
    #expect(noOpRange.lowerBound < leafRange.lowerBound)
    #expect(leafRange.lowerBound < structuralRange.lowerBound)
    #expect(structuralRange.lowerBound < buildRange.lowerBound)
    #expect(buildRange.lowerBound < rootRange.lowerBound)
    #expect(renderer.contains("callbackBox.previousSnapshot = displaySnapshot"))
    #expect(renderer.contains("callbackBox.lastChanges = changes"))
}

@Test func adwaitaNativeTextInputAvoidsRedundantFocusRerenders() throws {
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")
    let primitives = try readRepositoryFile("Sources/OmniUICore/Primitives.swift")

    #expect(renderer.contains("changed = box.runtime.focusByRawActionID(rawID)"))
    #expect(renderer.contains("box.rerender()"))
    #expect(shim.contains("action_id > 0 && app->focused_action_id != action_id"))
    #expect(shim.contains("if (app->focus_callback) app->focus_callback(action_id, app->context);"))
    #expect(shim.contains("handle_entry_readline_key"))
    #expect(shim.contains("GDK_KEY_e"))
    #expect(shim.contains("GDK_KEY_k"))
    #expect(shim.contains("controller_native_text_widget(controller)"))
    #expect(shim.contains("app_focused_native_text_widget"))
    #expect(shim.contains("app_modal_native_text_widget(app)"))
    #expect(shim.contains("find_widget_for_action(app->window, app->focused_action_id)"))
    #expect(primitives.contains("runtime._registerTextEditor(path: controlPath"))
    #expect(primitives.contains("value == 10 || value == 13"))
    #expect(primitives.contains("value == 13 ? UnicodeScalar(10)! : scalar"))
}

@Test func adwaitaRendererMapsCommonLayoutModifiersToNativeGtkProperties() throws {
    let source = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let requiredTerms = [
        "applyLayoutModifier",
        "omni_adw_node_apply_layout",
        "case .frame",
        "case .padding",
        "case .opacity",
        "case .offset",
        "cellWidth",
        "cellHeight",
        "marginUnit",
    ]

    for term in requiredTerms {
        #expect(source.contains(term))
    }
}

@Test func adwaitaRendererBridgesStyleInputAndAccessibilityModifiers() throws {
    let renderer = try readRepositoryFile("Sources/OmniUIAdwaitaRenderer/AdwaitaRenderer.swift")
    let semantic = try readRepositoryFile("Sources/OmniUICore/SemanticTree.swift")
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")
    let supportDoc = try readRepositoryFile("docs/adwaita-renderer-support.md")

    let semanticTerms = [
        "case foreground(String)",
        "case background(String)",
        "case frame(width: Int?, height: Int?, minWidth: Int?, maxWidth: Int?, minHeight: Int?, maxHeight: Int?)",
        "case padding(top: Int, leading: Int, bottom: Int, trailing: Int)",
        "case opacity(Double)",
        "case offset(x: Int, y: Int)",
        "case badge(String)",
        "case accessibilityLabel(String)",
        "case accessibilityIdentifier(String)",
    ]
    for term in semanticTerms {
        #expect(semantic.contains(term))
    }

    let rendererTerms = [
        "case .foreground, .background, .shadow, .glass, .crt, .clip, .accessibilityLabel, .noOp:",
        "return primaryContent()",
        "case .badge:",
        "css = \"accent\"",
        "case .accessibilityIdentifier:",
        "AdwaitaHeaderEntry.extract",
        "omni_adw_app_set_header_entry",
        "metadataID = identifier",
        "case .frame, .padding, .opacity, .offset:",
        "applyLayoutModifier(modifier, to: parent)",
        "case .accessibilityLabel(let label)",
        "AdwaitaReconciliation.accessibleLabel(for: node)",
    ]
    for term in rendererTerms {
        #expect(renderer.contains(term))
    }

    let shimTerms = [
        "omni_adw_node_apply_layout",
        "gtk_widget_set_size_request",
        "gtk_widget_set_margin_top",
        "gtk_widget_set_margin_start",
        "gtk_widget_set_opacity",
        "gtk_widget_set_name(node->widget, copy)",
        "gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_LABEL",
        "gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_DESCRIPTION",
        "gtk_accessible_update_relation(",
        "GDK_KEY_Return",
        "GDK_KEY_Escape",
    ]
    for term in shimTerms {
        #expect(shim.contains(term))
    }

    #expect(supportDoc.contains("Common layout modifiers such as frame, padding, opacity, and positive offset map to native GTK"))
    #expect(supportDoc.contains("Accessibility labels and identifiers are preserved in the semantic tree"))
    #expect(supportDoc.contains("Native Return and Escape key presses invoke OmniUI"))
}

@Test func iGopherAdwaitaParityFixesStayCovered() throws {
    let shim = try readRepositoryFile("Sources/CAdwaita/shim.c")
    let omniToolbar = try readRepositoryFile("Sources/OmniUI/LinuxCompatibilityViews.swift")
    let adwaitaToolbar = try readRepositoryFile("Sources/OmniUIAdwaita/LinuxCompatibilityViews.swift")

    let rootInstallStart = try #require(shim.range(of: "void omni_adw_app_set_root_focused"))
    let rootInstallEnd = try #require(shim.range(of: "wire_actions(app->content, app);", range: rootInstallStart.lowerBound..<shim.endIndex))
    let rootInstall = String(shim[rootInstallStart.lowerBound..<rootInstallEnd.upperBound])
    #expect(rootInstall.contains("gtk_widget_set_margin_top(app->content, 0);"))
    #expect(rootInstall.contains("gtk_widget_set_margin_bottom(app->content, 0);"))
    #expect(rootInstall.contains("gtk_widget_set_margin_start(app->content, 0);"))
    #expect(rootInstall.contains("gtk_widget_set_margin_end(app->content, 0);"))

    let rootReplacementStart = try #require(shim.range(of: "if (target == app->content)"))
    let rootReplacementEnd = try #require(shim.range(of: "if (app->window)", range: rootReplacementStart.lowerBound..<shim.endIndex))
    let rootReplacement = String(shim[rootReplacementStart.lowerBound..<rootReplacementEnd.lowerBound])
    #expect(rootReplacement.contains("gtk_widget_set_margin_top(app->content, 0);"))
    #expect(rootReplacement.contains("gtk_widget_set_margin_bottom(app->content, 0);"))
    #expect(rootReplacement.contains("gtk_widget_set_margin_start(app->content, 0);"))
    #expect(rootReplacement.contains("gtk_widget_set_margin_end(app->content, 0);"))

    #expect(shim.contains(".navigation-view { padding: 0; border-radius: 0; background: @window_bg_color; }"))
    #expect(shim.contains(".omni-plain-list row { min-height: 24px; padding: 0 0; background: transparent; border-bottom: 1px solid alpha(@borders, 0.16); }"))
    #expect(shim.contains("sidebar_collapsed_items"))
    #expect(shim.contains("sidebar_apply_saved_collapse_state(widget, app);"))
    #expect(shim.contains("g_hash_table_replace(app->sidebar_collapsed_items"))
    #expect(shim.contains("omni-menu-expanded"))
    #expect(shim.contains("g_signal_emit_by_name(widget, \"clicked\")"))
    #expect(shim.contains("gtk_menu_button_popup(GTK_MENU_BUTTON(widget))"))
    #expect(!shim.contains("on_sheet_click_released"))
    #expect(omniToolbar.contains(".frame(minWidth: 560)"))
    #expect(adwaitaToolbar.contains(".frame(minWidth: 560)"))
}

@Test func adwaitaReconciliationPlansSupportedLeafUpdates() {
    let previous = SemanticNode(id: "root", kind: .stack(axis: .vertical, spacing: 0), children: [
        SemanticNode(id: "title", kind: .text("Old")),
        SemanticNode(id: "enabled", kind: .toggle(actionID: 7, isFocused: false, isOn: false), children: [
            SemanticNode(id: "enabled.label", kind: .text("Enabled"))
        ]),
        SemanticNode(id: "name", kind: .textField(actionID: 8, placeholder: "Name", text: "Omni", cursor: 4, isFocused: false, isSecure: false)),
    ])
    let next = SemanticNode(id: "root", kind: .stack(axis: .vertical, spacing: 0), children: [
        SemanticNode(id: "title", kind: .text("New")),
        SemanticNode(id: "enabled", kind: .toggle(actionID: 7, isFocused: false, isOn: true), children: [
            SemanticNode(id: "enabled.label", kind: .text("Enabled"))
        ]),
        SemanticNode(id: "name", kind: .textField(actionID: 8, placeholder: "Name", text: "Omni GTK", cursor: 8, isFocused: false, isSecure: false)),
    ])
    let changes = SemanticDiff.changes(from: previous, to: next)

    let updates = AdwaitaReconciliation.leafUpdates(changes: changes, root: next)

    #expect(updates == [
        AdwaitaNativeLeafUpdate(id: "enabled", kind: .toggle, text: "Enabled", active: true),
        AdwaitaNativeLeafUpdate(id: "name", kind: .textField, text: "Omni GTK"),
        AdwaitaNativeLeafUpdate(id: "title", kind: .text, text: "New"),
    ])
}

@Test func adwaitaReconciliationPlansLocalizedStructuralSubtreeReplacement() {
    let previous = SemanticNode(id: "root", kind: .stack(axis: .vertical, spacing: 0), children: [
        SemanticNode(id: "root.section", kind: .stack(axis: .vertical, spacing: 0), children: [
            SemanticNode(id: "root.section.a", kind: .text("A")),
        ]),
    ])
    let next = SemanticNode(id: "root", kind: .stack(axis: .vertical, spacing: 0), children: [
        SemanticNode(id: "root.section", kind: .stack(axis: .vertical, spacing: 0), children: [
            SemanticNode(id: "root.section.a", kind: .text("A")),
            SemanticNode(id: "root.section.b", kind: .button(actionID: 1, isFocused: false), children: [
                SemanticNode(id: "root.section.b.label", kind: .text("B"))
            ]),
        ]),
    ])
    let changes = SemanticDiff.changes(from: previous, to: next)

    #expect(AdwaitaReconciliation.leafUpdates(changes: changes, root: next) == nil)
    #expect(AdwaitaReconciliation.subtreeReplacement(changes: changes, previous: previous, next: next) == AdwaitaNativeSubtreeReplacement(id: "root.section", node: next.children[0]))
}

@Test func adwaitaReconciliationPlansLocalizedChildReorderReplacement() {
    let previous = SemanticNode(id: "root", kind: .stack(axis: .vertical, spacing: 0), children: [
        SemanticNode(id: "root.section", kind: .stack(axis: .vertical, spacing: 0), children: [
            SemanticNode(id: "root.section.a", kind: .text("A")),
            SemanticNode(id: "root.section.b", kind: .text("B")),
        ]),
    ])
    let next = SemanticNode(id: "root", kind: .stack(axis: .vertical, spacing: 0), children: [
        SemanticNode(id: "root.section", kind: .stack(axis: .vertical, spacing: 0), children: [
            SemanticNode(id: "root.section.b", kind: .text("B")),
            SemanticNode(id: "root.section.a", kind: .text("A")),
        ]),
    ])
    let changes = SemanticDiff.changes(from: previous, to: next)

    #expect(changes == [SemanticChange(id: "root.section", kind: .childrenReordered)])
    #expect(AdwaitaReconciliation.leafUpdates(changes: changes, root: next) == nil)
    #expect(AdwaitaReconciliation.subtreeReplacement(changes: changes, previous: previous, next: next) == AdwaitaNativeSubtreeReplacement(id: "root.section", node: next.children[0]))
}

@Test func adwaitaReconciliationDeclinesAmbiguousStructuralChanges() {
    let previous = SemanticNode(id: "root", kind: .stack(axis: .vertical, spacing: 0), children: [
        SemanticNode(id: "root.left", kind: .stack(axis: .vertical, spacing: 0)),
        SemanticNode(id: "root.right", kind: .stack(axis: .vertical, spacing: 0)),
    ])
    let next = SemanticNode(id: "root", kind: .stack(axis: .vertical, spacing: 0), children: [
        SemanticNode(id: "root.left", kind: .stack(axis: .vertical, spacing: 0), children: [
            SemanticNode(id: "root.left.item", kind: .text("Left")),
        ]),
        SemanticNode(id: "root.right", kind: .stack(axis: .vertical, spacing: 0), children: [
            SemanticNode(id: "root.right.item", kind: .text("Right")),
        ]),
    ])
    let changes = SemanticDiff.changes(from: previous, to: next)

    #expect(AdwaitaReconciliation.subtreeReplacement(changes: changes, previous: previous, next: next) == nil)
}

@Test func adwaitaReconciliationUsesAccessibilityLabelForNativeActions() {
    let previous = SemanticNode(id: "button", kind: .button(actionID: 9, isFocused: false), children: [
        SemanticNode(id: "button.accessibility", kind: .modifier(.accessibilityLabel("Accessible button")), children: [
            SemanticNode(id: "button.label", kind: .text("Visual"))
        ])
    ])
    let next = SemanticNode(id: "button", kind: .button(actionID: 9, isFocused: true), children: [
        SemanticNode(id: "button.accessibility", kind: .modifier(.accessibilityLabel("Accessible button")), children: [
            SemanticNode(id: "button.label", kind: .text("Visual"))
        ])
    ])

    let updates = AdwaitaReconciliation.leafUpdates(
        changes: SemanticDiff.changes(from: previous, to: next),
        root: next
    )

    #expect(updates == [
        AdwaitaNativeLeafUpdate(id: "button", kind: .button, text: "Accessible button")
    ])
}

@Test func adwaitaReconciliationDeclinesIdentifierOnlyWrapperChanges() {
    let previous = SemanticNode(id: "target", kind: .text("Target"))
    let next = SemanticNode(id: "target.wrapper", kind: .modifier(.accessibilityIdentifier("native-target")), children: [
        SemanticNode(id: "target", kind: .text("Target"))
    ])

    #expect(
        AdwaitaReconciliation.leafUpdates(
            changes: SemanticDiff.changes(from: previous, to: next),
            root: next
        ) == nil
    )
}

@Test func adwaitaReconciliationPlansTextEditorLeafUpdates() {
    let previous = SemanticNode(id: "editor", kind: .textEditor(actionID: 11, text: "Old", cursor: 3, isFocused: false))
    let next = SemanticNode(id: "editor", kind: .textEditor(actionID: 11, text: "Old\nNew", cursor: 7, isFocused: false))

    let updates = AdwaitaReconciliation.leafUpdates(
        changes: SemanticDiff.changes(from: previous, to: next),
        root: next
    )

    #expect(updates == [
        AdwaitaNativeLeafUpdate(id: "editor", kind: .textEditor, text: "Old\nNew")
    ])
}

@Test func adwaitaReconciliationPlansSecureFieldLeafUpdatesAsNativeTextInput() {
    let previous = SemanticNode(id: "secret", kind: .textField(actionID: 12, placeholder: "Secret", text: "old", cursor: 3, isFocused: false, isSecure: true))
    let next = SemanticNode(id: "secret", kind: .textField(actionID: 12, placeholder: "Secret", text: "new secret", cursor: 10, isFocused: false, isSecure: true))

    let updates = AdwaitaReconciliation.leafUpdates(
        changes: SemanticDiff.changes(from: previous, to: next),
        root: next
    )

    #expect(updates == [
        AdwaitaNativeLeafUpdate(id: "secret", kind: .textField, text: "new secret")
    ])
}

@Test func adwaitaReconciliationPlansDropdownLeafUpdatesForPickerMenus() {
    let previous = SemanticNode(id: "picker", kind: .menu(actionID: 20, title: "Flavor", value: "Vanilla", isExpanded: false), children: [
        SemanticNode(id: "picker.vanilla", kind: .button(actionID: 21, isFocused: false), children: [
            SemanticNode(id: "picker.vanilla.label", kind: .text("Vanilla"))
        ]),
        SemanticNode(id: "picker.mint", kind: .button(actionID: 22, isFocused: false), children: [
            SemanticNode(id: "picker.mint.label", kind: .text("Mint"))
        ]),
    ])
    let next = SemanticNode(id: "picker", kind: .menu(actionID: 20, title: "Flavor", value: "Mint", isExpanded: false), children: previous.children)

    let updates = AdwaitaReconciliation.leafUpdates(
        changes: SemanticDiff.changes(from: previous, to: next),
        root: next
    )

    #expect(updates == [
        AdwaitaNativeLeafUpdate(id: "picker", kind: .dropdown, text: "Mint")
    ])
}

@Test func adwaitaReconciliationPlansProgressLeafUpdates() {
    let previous = SemanticNode(id: "progress", kind: .progress(label: "Load", fraction: 0.4))
    let next = SemanticNode(id: "progress", kind: .progress(label: "Load", fraction: 0.7))

    let updates = AdwaitaReconciliation.leafUpdates(
        changes: SemanticDiff.changes(from: previous, to: next),
        root: next
    )

    #expect(updates == [
        AdwaitaNativeLeafUpdate(id: "progress", kind: .progress, text: "0.7\nLoad 70%")
    ])
}

@Test func adwaitaReconciliationPlansSliderLeafUpdates() {
    let previous = SemanticNode(id: "slider", kind: .slider(label: "Level", value: 0.4, lowerBound: 0, upperBound: 1, step: 0.1, decrementActionID: 1, incrementActionID: 2))
    let next = SemanticNode(id: "slider", kind: .slider(label: "Level", value: 0.6, lowerBound: 0, upperBound: 1, step: 0.1, decrementActionID: 1, incrementActionID: 2))

    let updates = AdwaitaReconciliation.leafUpdates(
        changes: SemanticDiff.changes(from: previous, to: next),
        root: next
    )

    #expect(updates == [
        AdwaitaNativeLeafUpdate(id: "slider", kind: .slider, text: "0.6\nLevel")
    ])
}

@Test func adwaitaReconciliationPlansStepperLeafUpdates() {
    let previous = SemanticNode(id: "stepper", kind: .stepper(label: "Stepper: 2", value: 2, decrementActionID: 1, incrementActionID: 2))
    let next = SemanticNode(id: "stepper", kind: .stepper(label: "Stepper: 3", value: 3, decrementActionID: 1, incrementActionID: 2))

    let updates = AdwaitaReconciliation.leafUpdates(
        changes: SemanticDiff.changes(from: previous, to: next),
        root: next
    )

    #expect(updates == [
        AdwaitaNativeLeafUpdate(id: "stepper", kind: .stepper, text: "3.0\nStepper: 3")
    ])
}

@Test func adwaitaReconciliationPlansDatePickerLeafUpdates() {
    let previous = SemanticNode(id: "date", kind: .datePicker(label: "Due", value: "Dec 31, 2023", timestamp: 1_704_067_200, setActionID: 3, decrementActionID: 1, incrementActionID: 2))
    let next = SemanticNode(id: "date", kind: .datePicker(label: "Due", value: "Jan 1, 2024", timestamp: 1_704_153_600, setActionID: 3, decrementActionID: 1, incrementActionID: 2))

    let updates = AdwaitaReconciliation.leafUpdates(
        changes: SemanticDiff.changes(from: previous, to: next),
        root: next
    )

    #expect(updates == [
        AdwaitaNativeLeafUpdate(id: "date", kind: .datePicker, text: "1704153600.0\nJan 1, 2024\nDue")
    ])
}

private func readRepositoryFile(_ relativePath: String) throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fileURL = repositoryRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: fileURL, encoding: .utf8)
}

private func manifestPackageTarget(named targetName: String, in manifest: String) throws -> String {
    let marker = ".executableTarget(\n            name: \"\(targetName)\""
    guard let start = manifest.range(of: marker) else {
        throw NSError(
            domain: "AdwaitaCoverageTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing executable target \(targetName)"]
        )
    }

    let remaining = start.upperBound..<manifest.endIndex
    let end = manifest.range(of: "\n        .", range: remaining)?.lowerBound ?? manifest.endIndex
    return String(manifest[start.lowerBound..<end])
}

private func manifestTarget(named targetName: String, in manifest: String) throws -> String {
    let marker = ".target(\n            name: \"\(targetName)\""
    guard let start = manifest.range(of: marker) else {
        throw NSError(
            domain: "AdwaitaCoverageTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing target \(targetName)"]
        )
    }

    let remaining = start.upperBound..<manifest.endIndex
    let end = manifest.range(of: "\n        .", range: remaining)?.lowerBound ?? manifest.endIndex
    return String(manifest[start.lowerBound..<end])
}
