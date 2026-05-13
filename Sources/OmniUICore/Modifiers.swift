import Foundation

public extension View {
    func font(_ font: Font?) -> some View {
        environment(\.font, font)
    }
    func foregroundStyle(_ color: Color) -> some View { _Style(content: AnyView(self), fg: color, bg: nil) }
    func foregroundColor(_ color: Color) -> some View { _Style(content: AnyView(self), fg: color, bg: nil) }
    func fontWeight(_ weight: Font.Weight?) -> some View {
        switch weight {
        case .bold, .heavy, .black, .semibold, .medium:
            return AnyView(_TextStyleModifier(content: AnyView(self), style: .bold))
        case .light, .thin, .ultraLight:
            return AnyView(_Style(content: AnyView(self), fg: .secondary, bg: nil))
        case .regular, .none:
            return AnyView(self)
        }
    }
    func bold() -> some View { _TextStyleModifier(content: AnyView(self), style: .bold) }
    func italic() -> some View { _TextStyleModifier(content: AnyView(self), style: .italic) }
    func underline() -> some View { _TextStyleModifier(content: AnyView(self), style: .underline) }
    func strikethrough() -> some View { _TextStyleModifier(content: AnyView(self), style: .struck) }
    func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        environment(\.multilineTextAlignment, alignment)
    }
    func lineLimit(_ limit: Int?) -> some View {
        environment(\.lineLimit, limit)
    }
    func monospacedDigit() -> some View {
        environment(\.monospacedDigits, true)
    }
    func textSelection(_ selection: TextSelection) -> some View {
        environment(\.textSelectionEnabled, selection == .enabled)
    }
    func accentColor(_ color: Color?) -> some View {
        tint(color)
    }

    func tint(_ color: Color?) -> some View {
        if let color {
            return AnyView(environment(\.tint, color))
        }
        return AnyView(environment(\.tint, nil))
    }
    func cornerRadius(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius))
    }
    func shadow(color: Color, radius: CGFloat) -> some View {
        shadow(color: color, radius: radius, x: 0, y: 0)
    }
    func shadow(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        _Shadow(content: AnyView(self), color: color, radius: radius, x: x, y: y)
    }
    func opacity(_ value: CGFloat) -> some View {
        _OpacityModifier(content: AnyView(self), opacity: value)
    }
    func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        _OffsetModifier(content: AnyView(self), x: x, y: y)
    }
    func transition(_ t: AnyTransition) -> some View {
        _TransitionModifier(content: AnyView(self), transition: t)
    }
    func ignoresSafeArea() -> some View { _IgnoresSafeAreaModifier(content: AnyView(self)) }
    func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View {
        _ = style
        let kind: _ShapeKind = {
            if let rr = shape as? RoundedRectangle {
                return .roundedRectangle(cornerRadius: Int(rr.cornerRadius.rounded()))
            }
            if shape is Rectangle { return .rectangle }
            if shape is Circle { return .circle }
            if shape is Ellipse { return .ellipse }
            if shape is Capsule { return .capsule }
            if shape is Path { return .path }
            return .rectangle
        }()
        return _Clip(content: AnyView(self), kind: kind)
    }
    func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View {
        _ = eoFill
        let kind: _ShapeKind = {
            if shape is Rectangle { return .rectangle }
            if shape is RoundedRectangle { return .roundedRectangle(cornerRadius: 0) }
            if shape is Capsule { return .capsule }
            if shape is Circle { return .circle }
            if shape is Ellipse { return .ellipse }
            return .rectangle
        }()
        return _ContentShapeRect(content: AnyView(self), kind: kind)
    }
    func mask<M: View>(_ mask: M) -> some View {
        _MaskModifier(content: AnyView(self), mask: AnyView(mask))
    }
    func labelsHidden() -> some View {
        _LabelsHidden(content: AnyView(self), hidden: true)
    }
    func accessibilityLabel(_ label: String) -> some View {
        _AccessibilityLabelModifier(content: AnyView(self), label: label)
    }
    func accessibilityLabel(_ label: Text) -> some View {
        _AccessibilityLabelModifier(content: AnyView(self), label: label.content)
    }
    func accessibilityLabel(_ label: String, isEnabled: Bool) -> some View {
        isEnabled ? AnyView(_AccessibilityLabelModifier(content: AnyView(self), label: label)) : AnyView(self)
    }
    func accessibilityLabel(_ label: Text, isEnabled: Bool) -> some View {
        accessibilityLabel(label.content, isEnabled: isEnabled)
    }
    func accessibilityIdentifier(_ identifier: String) -> some View {
        _AccessibilityIdentifierModifier(content: AnyView(self), identifier: identifier)
    }
    func accessibilityIdentifier(_ identifier: String, isEnabled: Bool) -> some View {
        isEnabled ? AnyView(_AccessibilityIdentifierModifier(content: AnyView(self), identifier: identifier)) : AnyView(self)
    }
    func accessibilityHidden(_ hidden: Bool) -> some View {
        _ = hidden
        return _Passthrough(self)
    }
    func accessibilityElement(children: AccessibilityChildBehavior) -> some View {
        _ = children
        return _Passthrough(self)
    }

    // Liquid Glass: bounded native/terminal approximation carried as semantic metadata.
    func glassEffect() -> some View { _GlassEffectModifier(content: AnyView(self), style: .regular, shape: nil) }
    func glassEffect(_ style: GlassEffect) -> some View { _GlassEffectModifier(content: AnyView(self), style: style, shape: nil) }
    func glassEffect(_ style: GlassEffect, in shape: GlassEffectShape) -> some View {
        _GlassEffectModifier(content: AnyView(self), style: style, shape: shape)
    }
    func glassEffect(in shape: GlassEffectShape) -> some View {
        _GlassEffectModifier(content: AnyView(self), style: .regular, shape: shape)
    }
    func crtEffect(_ style: CRTEffect = .terminal) -> some View {
        _CRTEffectModifier(content: AnyView(self), style: style)
    }

    func background<B: View>(_ background: B) -> some View { _Background(content: AnyView(self), background: AnyView(background)) }
    func background<B: View>(@ViewBuilder _ background: () -> B) -> some View {
        _Background(content: AnyView(self), background: AnyView(background()))
    }
    func background(_ color: Color) -> some View { _Style(content: AnyView(self), fg: nil, bg: color) }
    func background<S: Shape>(_ color: Color, in shape: S, fillStyle: FillStyle = FillStyle()) -> some View {
        background {
            shape.fill(color, style: fillStyle)
        }
    }
    func background(_ material: Material) -> some View {
        // Terminal-friendly approximation.
        switch material.raw {
        case Material.bar.raw:
            return AnyView(background(Color.gray.opacity(0.2)))
        case Material.background.raw:
            return AnyView(background(Color.gray.opacity(0.1)))
        case Material.ultraThinMaterial.raw:
            return AnyView(background(Color.gray.opacity(0.15)))
        case Material.regularMaterial.raw:
            return AnyView(background(Color.gray.opacity(0.25)))
        default:
            return AnyView(background(Color.gray.opacity(0.2)))
        }
    }
    func background<S: Shape>(_ material: Material, in shape: S, fillStyle: FillStyle = FillStyle()) -> some View {
        background {
            shape.fill(material, style: fillStyle)
        }
    }
    func overlay<O: View>(_ overlay: O) -> some View { _Overlay(content: AnyView(self), overlay: AnyView(overlay)) }
    func overlay<O: View>(@ViewBuilder _ overlay: () -> O) -> some View {
        _Overlay(content: AnyView(self), overlay: AnyView(overlay()))
    }

    // MARK: SwiftUI API Surface (stubs/passthrough)
    func navigationTitle(_ title: String) -> some View {
        environment(\.navigationTitle, title)
    }
    func navigationTransition(_ transition: NavigationTransition) -> some View {
        _NavigationTransitionModifier(content: AnyView(self), transition: transition)
    }
    func contentTransition(_ transition: ContentTransition) -> some View {
        _ContentTransitionModifier(content: AnyView(self), transition: transition)
    }
    func navigationTitle(_ title: Text) -> some View {
        environment(\.navigationTitle, title.content)
    }
    func navigationBarTitleDisplayMode(_ mode: _NavigationTitleDisplayModeKind = .automatic) -> some View {
        environment(\.navigationTitleDisplayMode, mode)
    }

    func onTapGesture(perform action: @escaping () -> Void) -> some View {
        _TapGesture(content: AnyView(self), count: 1, action: action, actionScopePath: _UIRuntime._currentPath ?? [])
    }

    func onTapGesture(count: Int, perform action: @escaping () -> Void) -> some View {
        _TapGesture(content: AnyView(self), count: count, action: action, actionScopePath: _UIRuntime._currentPath ?? [])
    }

    func allowsHitTesting(_ enabled: Bool) -> some View {
        _AllowsHitTesting(content: AnyView(self), enabled: enabled)
    }

    @ViewBuilder
    func preferredColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            environment(\.colorScheme, scheme)
        } else {
            self
        }
    }

    func listStyle<S: ListStyle>(_ style: S) -> some View {
        let kind: _ListStyleKind
        switch style {
        case is SidebarListStyle:
            kind = .sidebar
        case is PlainListStyle:
            kind = .plain
        default:
            kind = .automatic
        }
        return environment(\.listStyleKind, kind)
    }
    func formStyle<S: FormStyle>(_ style: S) -> some View {
        let kind: _FormStyleKind
        switch style {
        case is GroupedFormStyle:
            kind = .grouped
        default:
            kind = .automatic
        }
        return environment(\.formStyleKind, kind)
    }
    func pickerStyle<S: PickerStyle>(_ style: S) -> some View {
        let kind: _PickerStyleKind
        switch style {
        case is SegmentedPickerStyle:
            kind = .segmented
        case is MenuPickerStyle:
            kind = .menu
        default:
            kind = .automatic
        }
        return environment(\.pickerStyleKind, kind)
    }
    func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        let kind: _ButtonStyleKind
        switch style {
        case is PlainButtonStyle:
            kind = .plain
        case is BorderedProminentButtonStyle:
            kind = .borderedProminent
        case is PrimaryFillButtonStyle:
            kind = .primaryFill
        case is BorderedButtonStyle:
            kind = .bordered
        default:
            // Custom ButtonStyle: store type-erased style in environment
            return AnyView(
                environment(\._customButtonStyle, _AnyButtonStyle(style))
                    .environment(\.buttonStyleKind, .automatic)
            )
        }
        return AnyView(
            environment(\._customButtonStyle, nil)
                .environment(\.buttonStyleKind, kind)
        )
    }
    func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View {
        let kind: _TextFieldStyleKind
        switch style {
        case is PlainTextFieldStyle:
            kind = .plain
        case is RoundedBorderTextFieldStyle:
            kind = .roundedBorder
        default:
            kind = .automatic
        }
        return environment(\.textFieldStyleKind, kind)
    }
    func datePickerStyle<S: DatePickerStyle>(_ style: S) -> some View {
        let kind: _DatePickerStyleKind
        switch style {
        case is CompactDatePickerStyle:
            kind = .compact
        case is GraphicalDatePickerStyle:
            kind = .graphical
        case is FieldDatePickerStyle:
            kind = .field
        case is StepperFieldDatePickerStyle:
            kind = .stepperField
        default:
            kind = .automatic
        }
        return environment(\.datePickerStyleKind, kind)
    }
    func gaugeStyle<S: GaugeStyle>(_ style: S) -> some View {
        let kind: _GaugeStyleKind = {
            if style is DefaultGaugeStyle { return .default }
            let name = String(describing: type(of: style))
            if name.contains("LinearCapacity") { return .linearCapacity }
            if name.contains("AccessoryLinear") { return .accessoryLinear }
            if name.contains("AccessoryCircular") { return .accessoryCircular }
            return .automatic
        }()
        return environment(\.gaugeStyleKind, kind)
    }
    func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
        let kind: _ToggleStyleKind = style is SwitchToggleStyle ? .switch : .automatic
        return environment(\.toggleStyleKind, kind)
    }
    func labelStyle<S: LabelStyle>(_ style: S) -> some View {
        let kind: _LabelStyleKind = style is IconOnlyLabelStyle ? .iconOnly : .automatic
        return environment(\.labelStyleKind, kind)
    }
    func navigationViewStyle<S: NavigationViewStyle>(_ style: S) -> some View {
        let kind: _NavigationViewStyleKind
        switch style {
        case is ColumnNavigationViewStyle:
            kind = .column
        case is DoubleColumnNavigationViewStyle:
            kind = .doubleColumn
        case is DefaultNavigationViewStyle:
            kind = .default
        default:
            kind = .automatic
        }
        return environment(\.navigationViewStyleKind, kind)
    }
    func scrollContentBackground(_ visibility: Visibility) -> some View {
        environment(\.scrollContentBackgroundVisibility, visibility)
    }
    func listRowSeparator(_ visibility: Visibility) -> some View {
        environment(\.listRowSeparatorVisibility, visibility)
    }
    func listRowBackground<B: View>(_ background: B?) -> some View {
        if let background {
            return AnyView(environment(\.listRowBackground, _ListRowBackgroundValue(AnyView(background))))
        }
        return AnyView(environment(\.listRowBackground, nil))
    }
    func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        _ToolbarModifier(content: AnyView(self), toolbar: AnyView(content()))
    }
    func toolbar<Content: ToolbarContent>(@ToolbarContentBuilder content: () -> Content) -> some View {
        _ToolbarModifier(content: AnyView(self), toolbar: content()._toolbarView())
    }
    func toolbar(removing placements: ToolbarPlacement...) -> some View {
        let existing = (_UIRuntime._currentEnvironment ?? EnvironmentValues()).toolbarRemovedPlacements
        return environment(\.toolbarRemovedPlacements, existing.union(placements))
    }
    func toolbar(_ any: Any = ()) -> some View {
        if let visibility = any as? Visibility {
            return AnyView(environment(\.toolbarVisibility, visibility))
        }
        if let color = any as? Color {
            var next = (_UIRuntime._currentEnvironment ?? EnvironmentValues()).toolbarBackgroundStyle
            next.color = color
            next.material = nil
            return AnyView(environment(\.toolbarBackgroundStyle, next))
        }
        if let material = any as? Material {
            var next = (_UIRuntime._currentEnvironment ?? EnvironmentValues()).toolbarBackgroundStyle
            next.material = material
            next.color = nil
            return AnyView(environment(\.toolbarBackgroundStyle, next))
        }
        return AnyView(self)
    }
    func toolbarBackground(_ any: Any = (), for bars: ToolbarPlacement...) -> some View {
        _ = bars // stored for compile parity; toolbar-region targeting requires ToolbarItemPlacement redesign
        let current = (_UIRuntime._currentEnvironment ?? EnvironmentValues()).toolbarBackgroundStyle
        var next = current
        if let visibility = any as? Visibility {
            next.visibility = visibility
        } else if let color = any as? Color {
            next.color = color
            next.material = nil
        } else if let material = any as? Material {
            next.material = material
            next.color = nil
        }
        return environment(\.toolbarBackgroundStyle, next)
    }
    func controlSize(_ size: ControlSize) -> some View {
        environment(\.controlSize, size)
    }
    func modelContainer(_ any: Any) -> some View {
        if let container = any as? ModelContainer {
            return AnyView(modelContainer(container))
        }
        return AnyView(self)
    }
    func modelContainer(_ container: ModelContainer) -> some View {
        _ModelContainerProvider(content: AnyView(self), container: container)
    }
    func modelContainer(for modelTypes: [Any.Type], inMemory: Bool = false) -> some View {
        _ModelContainerBuilder(content: AnyView(self), modelTypes: modelTypes, inMemory: inMemory)
    }

    func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> some View {
        _KeyboardShortcutBinder(content: AnyView(self), shortcut: KeyboardShortcut(key, modifiers: modifiers))
    }
    func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
        _KeyboardShortcutBinder(content: AnyView(self), shortcut: shortcut)
    }
    func onKeyPress(_ key: KeyEquivalent, action: @escaping () -> KeyPress.Result) -> some View {
        _OnKeyPressBinder(content: AnyView(self), key: key, action: { action() == .handled }, actionScopePath: _UIRuntime._currentPath ?? [])
    }
    func help(_ text: String) -> some View {
        _HelpModifier(content: AnyView(self), text: text)
    }
    func onExitCommand(perform action: @escaping () -> Void) -> some View {
        _OnExitCommandBinder(content: AnyView(self), action: action, actionScopePath: _UIRuntime._currentPath ?? [])
    }

    func sheet<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        _Sheet(content: AnyView(self), isPresented: isPresented, onDismiss: nil, sheet: AnyView(content()))
    }
    func sheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)?, @ViewBuilder content: () -> Content) -> some View {
        _Sheet(content: AnyView(self), isPresented: isPresented, onDismiss: onDismiss, sheet: AnyView(content()))
    }
    func sheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        _ItemPresentationOverlay(content: AnyView(self), item: item, onDismiss: onDismiss, title: "Sheet", showsScrim: true, presented: { AnyView(content($0)) })
    }
    func fullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: () -> Content) -> some View {
        _PresentationOverlay(content: AnyView(self), isPresented: isPresented, onDismiss: onDismiss, title: "Full Screen", showsScrim: true, presented: AnyView(content()))
    }
    func popover<Content: View>(isPresented: Binding<Bool>, attachmentAnchor: Any = (), arrowEdge: Edge = .top, @ViewBuilder content: () -> Content) -> some View {
        _ = attachmentAnchor
        return _PresentationOverlay(content: AnyView(self), isPresented: isPresented, onDismiss: nil, title: "Popover", showsScrim: false, presented: AnyView(content()), arrowEdge: arrowEdge)
    }
    func popover<Item: Identifiable, Content: View>(item: Binding<Item?>, attachmentAnchor: Any = (), arrowEdge: Edge = .top, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        _ = attachmentAnchor
        return _ItemPresentationOverlay(content: AnyView(self), item: item, onDismiss: nil, title: "Popover", showsScrim: false, presented: { AnyView(content($0)) })
    }
    func confirmationDialog<Actions: View>(_ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: () -> Actions) -> some View {
        _ConfirmationDialog(content: AnyView(self), title: title, isPresented: isPresented, titleVisibility: titleVisibility, actions: AnyView(actions()), message: nil)
    }
    func confirmationDialog<Actions: View, Message: View>(_ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: () -> Actions, @ViewBuilder message: () -> Message) -> some View {
        _ConfirmationDialog(content: AnyView(self), title: title, isPresented: isPresented, titleVisibility: titleVisibility, actions: AnyView(actions()), message: AnyView(message()))
    }
    func confirmationDialog<Data, Actions: View>(_ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: Data, @ViewBuilder actions: (Data) -> Actions) -> some View {
        _ConfirmationDialog(content: AnyView(self), title: title, isPresented: isPresented, titleVisibility: titleVisibility, actions: AnyView(actions(data)), message: nil)
    }
    func confirmationDialog<Data, Actions: View, Message: View>(_ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: Data, @ViewBuilder actions: (Data) -> Actions, @ViewBuilder message: (Data) -> Message) -> some View {
        _ConfirmationDialog(content: AnyView(self), title: title, isPresented: isPresented, titleVisibility: titleVisibility, actions: AnyView(actions(data)), message: AnyView(message(data)))
    }
    func navigationDestination<Value: Hashable, Destination: View>(for value: Value.Type, @ViewBuilder destination: @escaping (Value) -> Destination) -> some View {
        _NavigationDestinationResolver(content: AnyView(self), valueType: value, destination: { AnyView(destination($0)) })
    }
    func navigationDestination<Destination: View>(isPresented: Binding<Bool>, @ViewBuilder destination: () -> Destination) -> some View {
        _NavigationDestinationBool(content: AnyView(self), isPresented: isPresented, destination: AnyView(destination()), ownerKeyOverride: nil)
    }
    func navigationDestination<Item: Identifiable, Destination: View>(item: Binding<Item?>, @ViewBuilder destination: @escaping (Item) -> Destination) -> some View {
        _NavigationDestinationItem(content: AnyView(self), item: item, destination: { AnyView(destination($0)) })
    }
    func alert<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        _Alert(content: AnyView(self), isPresented: isPresented, alert: AnyView(content()))
    }

    func alert(isPresented: Binding<Bool>, content: @escaping () -> Alert) -> some View {
        _AlertFromType(content: AnyView(self), isPresented: isPresented, makeAlert: content)
    }

    func alert<Actions: View, Message: View>(_ title: String, isPresented: Binding<Bool>, @ViewBuilder actions: () -> Actions, @ViewBuilder message: () -> Message) -> some View {
        _Alert(
            content: AnyView(self),
            isPresented: isPresented,
            alert: AnyView(VStack(alignment: .leading, spacing: 12) {
                Text(title)
                message()
                actions()
            })
        )
    }

    func focused(_ isFocused: Binding<Bool>) -> some View {
        _FocusBoolBinder(content: AnyView(self), get: { isFocused.wrappedValue }, set: { isFocused.wrappedValue = $0 })
    }

    func focused(_ isFocused: Bool) -> some View {
        _FocusBoolValueBinder(content: AnyView(self), isFocused: isFocused)
    }

    func focused(_ isFocused: FocusState<Bool>.Binding) -> some View {
        _FocusBoolBinder(content: AnyView(self), get: { isFocused.wrappedValue }, set: { isFocused.wrappedValue = $0 })
    }

    func focusedSceneValue<Value>(_ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value?) -> some View {
        _FocusedSceneValueModifier(content: AnyView(self), keyPath: keyPath, value: value)
    }

    func id<ID: Hashable>(_ id: ID) -> some View {
        _Identified(content: AnyView(self), id: AnyHashable(id), readerScopePath: _UIRuntime._currentScrollReaderScopePath)
    }

    func onDelete(perform action: @escaping (IndexSet) -> Void) -> some View {
        _OnDelete(content: AnyView(self), action: action, actionScopePath: _UIRuntime._currentPath ?? [])
    }

    func onChange<V: Equatable>(of value: V, perform action: @escaping (_ newValue: V) -> Void) -> some View {
        AnyView(_OnChange(content: AnyView(self), value: value, action: { _, newValue in action(newValue) }))
    }

    func onChange<V: Equatable>(of value: V, perform action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some View {
        AnyView(_OnChange(content: AnyView(self), value: value, action: action))
    }

    func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping () -> Void) -> some View {
        AnyView(_OnChangeSimple(content: AnyView(self), value: value, initial: initial, action: action))
    }

    func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some View {
        AnyView(_OnChangeWithInitial(content: AnyView(self), value: value, initial: initial, action: action))
    }

    func task(priority: TaskPriority? = nil, _ action: @escaping () async -> Void) -> some View {
        _TaskBinder(content: AnyView(self), priority: priority, action: action)
    }

    func onSubmit(_ action: @escaping () -> Void) -> some View {
        _OnSubmitBinder(content: AnyView(self), action: action, actionScopePath: _UIRuntime._currentPath ?? [])
    }
    func submitLabel(_ label: SubmitLabel) -> some View {
        environment(\.submitLabel, label)
    }

    func keyboardType(_ type: UIKeyboardType) -> some View {
        environment(\.textInputKeyboardType, type)
    }
    func textInputAutocapitalization(_ style: TextInputAutocapitalization?) -> some View {
        environment(\.textInputAutocapitalization, style)
    }
    func textContentType(_ type: UITextContentType?) -> some View {
        environment(\.textContentType, type)
    }
    func disableAutocorrection(_ disable: Bool? = true) -> some View {
        environment(\.autocorrectionDisabled, disable)
    }
    func autocorrectionDisabled(_ disabled: Bool = true) -> some View {
        disableAutocorrection(disabled)
    }

    func searchable(text: Binding<String>) -> some View {
        _SearchableModifier(content: AnyView(self), text: text)
    }
    func refreshable(action: @escaping () async -> Void) -> some View {
        _RefreshableModifier(content: AnyView(self), action: action, actionScopePath: _UIRuntime._currentPath ?? [])
    }

    func disabled(_ disabled: Bool) -> some View {
        _DisabledModifier(content: AnyView(self), disabled: disabled)
    }

    func hidden() -> some View {
        _Hidden(content: AnyView(self))
    }

    func quickLookPreview(_ url: Binding<URL?>) -> some View {
        _QuickLookPreviewModifier(content: AnyView(self), url: url)
    }

    func onHover(perform action: @escaping (Bool) -> Void) -> some View {
        _HoverModifier(content: AnyView(self), action: action, actionScopePath: _UIRuntime._currentPath ?? [])
    }

    func contextMenu<MenuItems: View>(@ViewBuilder menuItems: () -> MenuItems) -> some View {
        _ = menuItems()
        return _Passthrough(self)
    }

    func contextMenu<MenuItems: View, Preview: View>(
        @ViewBuilder menuItems: () -> MenuItems,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        _ = menuItems()
        _ = preview()
        return _Passthrough(self)
    }

    func frame(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        _Frame(
            content: AnyView(self),
            width: width,
            height: height,
            minWidth: nil,
            maxWidth: nil,
            minHeight: nil,
            maxHeight: nil
        )
    }

    func frame(
        minWidth: CGFloat? = nil,
        idealWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        idealHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        _Frame(
            content: AnyView(self),
            width: idealWidth,
            height: idealHeight,
            minWidth: minWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
    }

    func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        // Negative padding is used in some upstream SwiftUI views for fine visual tuning.
        // OmniUI's box model doesn't support negative extents safely, so clamp to zero.
        let amt = max(0, Int(length ?? 1))
        let t = edges.contains(.top) || edges == .all || edges.contains(.vertical)
        let b = edges.contains(.bottom) || edges == .all || edges.contains(.vertical)
        let l = edges.contains(.leading) || edges == .all || edges.contains(.horizontal)
        let r = edges.contains(.trailing) || edges == .all || edges.contains(.horizontal)
        return AnyView(_EdgePadding(
            content: AnyView(self),
            top: t ? amt : 0,
            leading: l ? amt : 0,
            bottom: b ? amt : 0,
            trailing: r ? amt : 0
        ))
    }

    func padding(_ length: CGFloat) -> some View {
        padding(.all, length)
    }

    func clipped(antialiased: Bool = false) -> some View {
        _ = antialiased
        return clipShape(Rectangle())
    }

    // MARK: Parity modifiers

    func fixedSize() -> some View {
        _FixedSizeModifier(content: AnyView(self), horizontal: true, vertical: true)
    }

    func fixedSize(horizontal: Bool, vertical: Bool) -> some View {
        _FixedSizeModifier(content: AnyView(self), horizontal: horizontal, vertical: vertical)
    }

    func layoutPriority(_ value: Double) -> some View {
        _LayoutPriorityModifier(content: AnyView(self), priority: value)
    }

    func aspectRatio(_ ratio: CGFloat? = nil, contentMode: ContentMode) -> some View {
        let mode: _ContentMode = contentMode == .fit ? .fit : .fill
        return _AspectRatioModifier(content: AnyView(self), ratio: ratio, contentMode: mode)
    }

    func alignmentGuide(_ alignment: HorizontalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
        _AlignmentGuideModifier(content: AnyView(self), alignmentID: .horizontal(alignment), computeValue: computeValue)
    }

    func alignmentGuide(_ alignment: VerticalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
        _AlignmentGuideModifier(content: AnyView(self), alignmentID: .vertical(alignment), computeValue: computeValue)
    }

    func preference<K: PreferenceKey>(key: K.Type, value: K.Value) -> some View {
        _PreferenceModifier<K>(content: AnyView(self), value: value)
    }

    func onPreferenceChange<K: PreferenceKey>(_ key: K.Type, perform action: @escaping (K.Value) -> Void) -> some View where K.Value: Equatable {
        _OnPreferenceChangeModifier<K>(content: AnyView(self), action: action)
    }

    func anchorPreference<K: PreferenceKey>(key: K.Type, value: _AnchorSource, transform: @escaping (Anchor<CGRect>) -> K.Value) -> some View {
        _AnchorPreferenceModifier<K>(content: AnyView(self), transform: transform)
    }

    func swipeActions<T: View>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true, @ViewBuilder content: () -> T) -> some View {
        _SwipeActionsModifier(content: AnyView(self), edge: edge, actions: AnyView(content()))
    }

    func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
        _RotationEffectModifier(content: AnyView(self), angle: angle)
    }

    func onAppear(perform action: @escaping () -> Void) -> some View {
        _OnAppear(content: AnyView(self), action: action)
    }

    func onDisappear(perform action: @escaping () -> Void) -> some View {
        _OnDisappear(content: AnyView(self), action: action)
    }

    func safeAreaInset<Content: View>(edge: Edge, alignment: Alignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) -> some View {
        _SafeAreaInset(base: AnyView(self), edge: edge, alignment: alignment, spacing: Int(spacing ?? 0), inset: AnyView(content()))
    }

    func presentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        environment(\.presentationDetents, detents)
    }

    func presentationDragIndicator(_ visibility: Visibility) -> some View {
        environment(\.presentationDragIndicatorVisibility, visibility)
    }

    func navigationSplitViewColumnWidth(min: CGFloat? = nil, ideal: CGFloat, max maxWidth: CGFloat? = nil) -> some View {
        let fallback = ideal > 0 ? ideal : (min ?? maxWidth ?? 0)
        let columns = Swift.max(1, Int(fallback.rounded()))
        return frame(width: CGFloat(columns))
    }

    func scaleEffect(_ scale: CGFloat, anchor: UnitPoint = .center) -> some View {
        _ = anchor
        // Tiered terminal approximation of scale
        if scale < 0.5 {
            return AnyView(opacity(0))
        } else if scale < 1.0 {
            return AnyView(foregroundStyle(.secondary))
        } else if scale <= 1.0 {
            return AnyView(self)
        } else if scale <= 1.5 {
            return AnyView(bold())
        } else {
            return AnyView(bold().textCase(.uppercase))
        }
    }

    func scaleEffect(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> some View {
        _ = anchor
        return scaleEffect(max(x, y))
    }

    func previewDisplayName(_ name: String) -> some View {
        _PreviewDisplayNameModifier(content: AnyView(self), name: name)
    }

    // MARK: - .blur() (TUI approximation: heavy blur → shade chars, light blur → dim opacity)
    func blur(radius: CGFloat, opaque: Bool = false) -> some View {
        _ = opaque
        return _BlurModifier(content: AnyView(self), radius: radius)
    }

    // MARK: - .textCase()
    func textCase(_ textCase: Text.Case?) -> some View {
        if let tc = textCase {
            return AnyView(_TextCaseModifier(content: AnyView(self), textCase: tc))
        }
        return AnyView(environment(\.textCase, textCase))
    }

    // MARK: - .truncationMode()
    func truncationMode(_ mode: Text.TruncationMode) -> some View {
        environment(\.truncationMode, mode)
    }

    // MARK: - .badge()
    func badge(_ count: Int) -> some View {
        _BadgeModifier(content: AnyView(self), badge: count > 0 ? "\(count)" : nil)
    }

    func badge(_ label: Text?) -> some View {
        _BadgeModifier(content: AnyView(self), badge: label?.content)
    }

    func badge(_ label: String?) -> some View {
        _BadgeModifier(content: AnyView(self), badge: label)
    }

    // MARK: - .task(id:)
    func task<T: Equatable & Hashable>(id: T, priority: TaskPriority? = nil, _ action: @escaping () async -> Void) -> some View {
        _TaskIdBinder(content: AnyView(self), id: AnyHashable(id), priority: priority, action: action)
    }

    // MARK: - .interactiveDismissDisabled() (compile parity only)
    func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View {
        environment(\.interactiveDismissDisabled, isDisabled)
    }

    // MARK: - .focusSection()
    func focusSection() -> some View {
        _FocusSectionModifier(content: AnyView(self))
    }
}

private struct _Hidden: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // Still build the subtree so it can register actions/shortcuts, but don't render it.
        _ = ctx.buildChild(content)
        return .empty
    }
}

private struct _FocusedSceneValueModifier<Value>: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let keyPath: WritableKeyPath<FocusedValues, Value?>
    let value: Value?

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        var next = FocusedValues._current
        next[keyPath: keyPath] = value
        FocusedValues._current = next
        return ctx.buildChild(content)
    }
}

public enum SubmitLabel: Hashable, Sendable {
    case done
    case go
    case search
    case send
    case next
    case `return`
}

private struct _Sheet: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let sheet: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let env = _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment
        if isPresented.wrappedValue {
            let dismissDisabled = env.interactiveDismissDisabled
            let dismiss: () -> Void = dismissDisabled ? {} : {
                if isPresented.wrappedValue {
                    isPresented.wrappedValue = false
                    onDismiss?()
                }
            }
            let detents = env.presentationDetents
            let renderSize = _UIRuntime._currentRenderSize ?? _Size(width: 80, height: 24)
            let dialogWidth = max(
                36,
                min(detents.isEmpty ? 56 : 72, max(36, renderSize.width - 8))
            )
            let dialogMaxHeight: Int = {
                if detents.contains(.large) {
                    return max(12, renderSize.height - 4)
                }
                if detents.contains(.medium) {
                    return max(10, renderSize.height / 2)
                }
                return max(8, renderSize.height - 6)
            }()
            ctx.runtime._registerOverlay(
                view: AnyView(
                    _ModalOverlayCard(
                        scrim: Color.black.opacity(0.45),
                        maxWidth: dialogWidth,
                        maxHeight: dialogMaxHeight
                    ) {
                        _presentationChrome(title: "", dismiss: dismiss, env: env) {
                            sheet
                        }
                    }
                ),
                dismiss: dismiss
            )
        }
        return ctx.buildChild(content)
    }
}

private struct _ModalOverlayCard<Content: View>: View, _PrimitiveView {
    typealias Body = Never

    let scrim: Color?
    let maxWidth: Int
    let maxHeight: Int?
    let content: Content

    init(
        scrim: Color?,
        maxWidth: Int,
        maxHeight: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.scrim = scrim
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .modalOverlay(
            scrim: scrim,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            child: ctx.buildChild(content)
        )
    }
}

private func _presentationOverlaySizing(
    env: EnvironmentValues,
    renderSize: _Size,
    preferredWidth: Int? = nil
) -> (maxWidth: Int, maxHeight: Int) {
    let detents = env.presentationDetents
    let width = max(
        36,
        min(preferredWidth ?? (detents.isEmpty ? 56 : 72), max(36, renderSize.width - 8))
    )
    let height: Int = {
        if detents.contains(.large) {
            return max(12, renderSize.height - 4)
        }
        if detents.contains(.medium) {
            return max(10, renderSize.height / 2)
        }
        return max(8, renderSize.height - 6)
    }()
    return (maxWidth: width, maxHeight: height)
}


private struct _PresentationOverlay: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let title: String
    let showsScrim: Bool
    let presented: AnyView
    var arrowEdge: Edge? = nil

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let env = _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment
        if isPresented.wrappedValue {
            let dismiss = {
                if isPresented.wrappedValue {
                    isPresented.wrappedValue = false
                    onDismiss?()
                }
            }
            if showsScrim, arrowEdge == nil {
                let renderSize = _UIRuntime._currentRenderSize ?? _Size(width: 80, height: 24)
                let sizing = _presentationOverlaySizing(env: env, renderSize: renderSize)
                ctx.runtime._registerOverlay(
                    view: AnyView(
                        _ModalOverlayCard(
                            scrim: Color.black.opacity(0.45),
                            maxWidth: sizing.maxWidth,
                            maxHeight: sizing.maxHeight
                        ) {
                            _presentationChrome(title: title, dismiss: dismiss, env: env) {
                                presented
                            }
                        }
                    ),
                    dismiss: dismiss
                )
            } else {
                let chrome = _presentationChrome(title: title, dismiss: dismiss, env: env) {
                    presented
                }
                let aligned: AnyView
                if let edge = arrowEdge {
                    switch edge {
                    case .top:
                        aligned = AnyView(VStack(spacing: 0) { Spacer(); chrome })
                    case .bottom:
                        aligned = AnyView(VStack(spacing: 0) { chrome; Spacer() })
                    case .leading:
                        aligned = AnyView(HStack(spacing: 0) { Spacer(); chrome })
                    case .trailing:
                        aligned = AnyView(HStack(spacing: 0) { chrome; Spacer() })
                    }
                } else {
                    aligned = AnyView(chrome)
                }
                ctx.runtime._registerOverlay(view: AnyView(
                    ZStack {
                        if showsScrim {
                            Color.gray.opacity(0.35)
                        }
                        aligned
                    }
                ), dismiss: dismiss)
            }
        }
        return ctx.buildChild(content)
    }
}

private struct _ItemPresentationOverlay<Item: Identifiable>: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let item: Binding<Item?>
    let onDismiss: (() -> Void)?
    let title: String
    let showsScrim: Bool
    let presented: (Item) -> AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let env = _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment
        if let current = item.wrappedValue {
            let dismiss = {
                if item.wrappedValue != nil {
                    item.wrappedValue = nil
                    onDismiss?()
                }
            }
            if showsScrim {
                let renderSize = _UIRuntime._currentRenderSize ?? _Size(width: 80, height: 24)
                let sizing = _presentationOverlaySizing(env: env, renderSize: renderSize)
                let displayTitle = title == "Sheet" ? "" : title
                ctx.runtime._registerOverlay(
                    view: AnyView(
                        _ModalOverlayCard(
                            scrim: Color.black.opacity(0.45),
                            maxWidth: sizing.maxWidth,
                            maxHeight: sizing.maxHeight
                        ) {
                            _presentationChrome(title: displayTitle, dismiss: dismiss, env: env) {
                                presented(current)
                            }
                        }
                    ),
                    dismiss: dismiss
                )
            } else {
                ctx.runtime._registerOverlay(view: AnyView(
                    ZStack {
                        if showsScrim {
                            Color.gray.opacity(0.35)
                        }
                        _presentationChrome(title: title, dismiss: dismiss, env: env) {
                            presented(current)
                        }
                    }
                ), dismiss: dismiss)
            }
        }
        return ctx.buildChild(content)
    }
}

private struct _ConfirmationDialog: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let title: String
    let isPresented: Binding<Bool>
    let titleVisibility: Visibility
    let actions: AnyView
    let message: AnyView?

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let env = _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment
        if isPresented.wrappedValue {
            let runtime = ctx.runtime
            let captureID = runtime._beginMenuCapture()
            _UIRuntime.$_currentMenuCaptureID.withValue(captureID) {
                var actionsCtx = _BuildContext(runtime: runtime, path: ctx.path + [91_000], nextChildIndex: 0)
                _ = _BuildContext.withRuntime(runtime, path: actionsCtx.path) {
                    OmniUICore._makeNode(actions, &actionsCtx)
                }
            }
            let captured = runtime._endMenuCapture(captureID)
            let dismiss = {
                if isPresented.wrappedValue {
                    isPresented.wrappedValue = false
                }
            }
            let shouldShowTitle = titleVisibility != .hidden && !title.isEmpty
            let messageView = message ?? AnyView(EmptyView())
            let renderSize = _UIRuntime._currentRenderSize ?? _Size(width: 80, height: 24)
            let sizing = _presentationOverlaySizing(env: env, renderSize: renderSize, preferredWidth: 48)
            let messageRows = message == nil ? 0 : 2
            let actionRows = captured.isEmpty ? 1 : max(1, captured.count * 2 - 1)
            let chromeRows = 4
            let desiredHeight = chromeRows + messageRows + actionRows
            let maxHeight = min(max(8, desiredHeight), max(8, renderSize.height - 1))
            ctx.runtime._registerOverlay(
                view: AnyView(
                    _ModalOverlayCard(
                        scrim: Color.black.opacity(0.45),
                        maxWidth: sizing.maxWidth,
                        maxHeight: maxHeight
                    ) {
                        _presentationChrome(title: shouldShowTitle ? title : "", dismiss: dismiss, env: env) {
                            VStack(spacing: 1) {
                                messageView
                                if captured.isEmpty {
                                    Button("OK") { dismiss() }
                                } else {
                                    ForEach(0..<captured.count, id: \.self) { idx in
                                        let entry = captured[idx]
                                        Button(entry.label) {
                                            dismiss()
                                            runtime._invokeCapturedMenuItem(entry)
                                        }
                                    }
                                }
                            }
                        }
                    }
                ),
                dismiss: dismiss
            )
        }
        return ctx.buildChild(content)
    }
}


private struct _NavigationDestinationResolver<Value: Hashable>: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let valueType: Value.Type
    let destination: (Value) -> AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        if let stackPath = ctx.runtime._nearestNavStackRoot(from: ctx.path) {
            ctx.runtime._registerNavDestinationResolver(stackPath: stackPath, valueType: valueType, destination: destination)
        }
        return ctx.buildChild(content)
    }
}

private struct _NavigationDestinationBool: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let isPresented: Binding<Bool>
    let destination: AnyView
    let ownerKeyOverride: String?

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        guard let stackPath = ctx.runtime._nearestNavStackRoot(from: ctx.path) else {
            return ctx.buildChild(content)
        }
        let ownerKey = ownerKeyOverride ?? ctx.runtime._viewPathKey(path: ctx.path)
        let isActive = ctx.runtime._navContainsOwner(stackPath: stackPath, ownerKey: ownerKey)

        if isPresented.wrappedValue {
            if !isActive {
                ctx.runtime._navPush(
                    stackPath: stackPath,
                    view: destination,
                    ownerKey: ownerKey,
                    onPop: {
                        if isPresented.wrappedValue {
                            isPresented.wrappedValue = false
                        }
                    }
                )
            }
        } else if isActive {
            ctx.runtime._navRemoveOwned(stackPath: stackPath, ownerKey: ownerKey)
        }
        return ctx.buildChild(content)
    }
}

private struct _NavigationDestinationItem<Item: Identifiable>: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let item: Binding<Item?>
    let destination: (Item) -> AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { presented in
                if !presented {
                    item.wrappedValue = nil
                }
            }
        )
        let ownerKey = ctx.runtime._viewPathKey(path: ctx.path)
        let target = item.wrappedValue.map(destination) ?? AnyView(EmptyView())
        return ctx.buildChild(
            _NavigationDestinationBool(content: content, isPresented: isPresented, destination: target, ownerKeyOverride: ownerKey)
        )
    }
}

private struct _Alert: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let isPresented: Binding<Bool>
    let alert: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        if isPresented.wrappedValue {
            let dismiss = {
                if isPresented.wrappedValue {
                    isPresented.wrappedValue = false
                }
            }
            let renderSize = _UIRuntime._currentRenderSize ?? _Size(width: 80, height: 24)
            let sizing = _presentationOverlaySizing(
                env: _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment,
                renderSize: renderSize,
                preferredWidth: 48
            )
            ctx.runtime._registerOverlay(view: AnyView(
                _ModalOverlayCard(
                    scrim: Color.black.opacity(0.45),
                    maxWidth: sizing.maxWidth,
                    maxHeight: min(max(6, sizing.maxHeight), max(6, renderSize.height - 2))
                ) {
                    VStack(spacing: 1) {
                        alert
                        HStack(spacing: 1) {
                            Spacer()
                            Button("OK") { dismiss() }
                        }
                    }
                    .padding(1)
                }
            ), dismiss: dismiss)
        }
        return ctx.buildChild(content)
    }
}

public struct Alert {
    public struct Button {
        enum Kind {
            case `default`
            case cancel
            case destructive
        }

        let kind: Kind
        let label: Text
        let action: (() -> Void)?

        private init(kind: Kind, label: Text, action: (() -> Void)?) {
            self.kind = kind
            self.label = label
            self.action = action
        }

        public static func `default`(_ label: Text, action: (() -> Void)? = nil) -> Button {
            Button(kind: .default, label: label, action: action)
        }

        public static func cancel(_ label: Text, action: (() -> Void)? = nil) -> Button {
            Button(kind: .cancel, label: label, action: action)
        }

        public static func destructive(_ label: Text, action: (() -> Void)? = nil) -> Button {
            Button(kind: .destructive, label: label, action: action)
        }
    }

    public let title: Text
    public let message: Text?
    public let dismissButton: Button?

    public init(title: Text, message: Text? = nil, dismissButton: Button? = nil) {
        self.title = title
        self.message = message
        self.dismissButton = dismissButton
    }
}

private struct _AlertFromType: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let isPresented: Binding<Bool>
    let makeAlert: () -> Alert

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        if isPresented.wrappedValue {
            let alert = makeAlert()

            let dismiss = {
                if isPresented.wrappedValue {
                    isPresented.wrappedValue = false
                }
            }

            let button = alert.dismissButton ?? .default(Text("OK"), action: nil)
            let messageView: AnyView = alert.message.map(AnyView.init) ?? AnyView(EmptyView())
            let renderSize = _UIRuntime._currentRenderSize ?? _Size(width: 80, height: 24)
            let sizing = _presentationOverlaySizing(
                env: _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment,
                renderSize: renderSize,
                preferredWidth: 48
            )
            ctx.runtime._registerOverlay(view: AnyView(
                _ModalOverlayCard(
                    scrim: Color.black.opacity(0.45),
                    maxWidth: sizing.maxWidth,
                    maxHeight: min(max(6, sizing.maxHeight), max(6, renderSize.height - 2))
                ) {
                    VStack(spacing: 1) {
                        VStack(spacing: 1) {
                            alert.title
                            messageView
                        }
                        HStack(spacing: 1) {
                            Spacer()
                            Button(button.label.content) {
                                dismiss()
                                button.action?()
                            }
                        }
                    }
                    .padding(1)
                }
            ), dismiss: dismiss)
        }
        return ctx.buildChild(content)
    }
}

private func _presentationChrome<Content: View>(title: String, dismiss: @escaping () -> Void, env: EnvironmentValues, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 1) {
            if !title.isEmpty {
                Text(title)
                    .bold()
            }
            Spacer()
            Button("Close") { dismiss() }
        }
        Divider()
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    .padding(1)
    .background(_presentationBackgroundColor(env: env))
}

private func _presentationBackgroundColor(env: EnvironmentValues) -> Color {
    // Use a distinct panel background so modals stand out over the scrim.
    if env.presentationDetents.contains(.large) {
        return Color(red: 0.16, green: 0.18, blue: 0.23)
    }
    if env.presentationDetents.contains(.medium) {
        return Color(red: 0.15, green: 0.17, blue: 0.21)
    }
    return Color(red: 0.13, green: 0.15, blue: 0.19)
}

private struct _TapGesture: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let count: Int
    let action: () -> Void
    let actionScopePath: [Int]

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _ = count // multi-tap not modeled; retained for call-site compatibility.
        guard _UIRuntime._hitTestingEnabled else {
            return ctx.buildChild(content)
        }

        let runtime = ctx.runtime
        let controlPath = ctx.path
        let id = runtime._registerAction({
            runtime._setFocus(path: controlPath)
            action()
        }, path: actionScopePath)
        runtime._registerFocusable(path: controlPath, activate: id)
        return .tapTarget(id: id, child: ctx.buildChild(content))
    }
}

private struct _AllowsHitTesting: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let enabled: Bool

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _UIRuntime.$_hitTestingEnabled.withValue(enabled) {
            ctx.buildChild(content)
        }
    }
}

private struct _SafeAreaInset: View, _PrimitiveView {
    typealias Body = Never

    let base: AnyView
    let edge: Edge
    let alignment: Alignment
    let spacing: Int
    let inset: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // alignment is stored for API completeness but not yet visually effective
        // (layout primitives ignore alignment parameter)
        switch edge {
        case .top:
            return ctx.buildChild(VStack(spacing: spacing) { inset; base })
        case .bottom:
            return ctx.buildChild(VStack(spacing: spacing) { base; inset })
        case .leading:
            return ctx.buildChild(HStack(spacing: spacing) { inset; base })
        case .trailing:
            return ctx.buildChild(HStack(spacing: spacing) { base; inset })
        }
    }
}

private struct _ToolbarModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let toolbar: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let baseNode = ctx.buildChild(content)
        let toolbarNode = ctx.buildChild(toolbar)
        var items = _collectToolbarItems(from: toolbarNode)
        let env = _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment

        if env.toolbarRemovedPlacements.contains(.sidebarToggle) {
            items.leading.removeAll()
        }

        if items.principal.isEmpty, let title = env.navigationTitle, !title.isEmpty {
            let titleNode: _VNode = env.navigationTitleDisplayMode == .large
                ? .textStyled(style: .bold, child: .text(title))
                : .text(title)
            items.principal.append(titleNode)
        }

        guard env.toolbarVisibility != .hidden, !items.isEmpty else { return baseNode }

        var root: [_VNode] = []
        if let top = _toolbarTopBar(items: items, env: env) {
            root.append(top)
        }
        root.append(baseNode)
        if let bottom = _toolbarBottomBar(items: items, env: env) {
            root.append(bottom)
        }
        return .stack(axis: .vertical, spacing: 0, children: root)
    }
}

private func _toolbarTopBar(items: _ToolbarLayoutItems, env: EnvironmentValues) -> _VNode? {
    if items.leading.isEmpty && items.principal.isEmpty && items.trailing.isEmpty {
        return nil
    }

    var row: [_VNode] = []
    if !items.leading.isEmpty {
        row.append(.stack(axis: .horizontal, spacing: 1, children: items.leading))
    }
    if !items.principal.isEmpty {
        if !row.isEmpty { row.append(.spacer) }
        row.append(.stack(axis: .horizontal, spacing: 1, children: items.principal))
        row.append(.spacer)
    } else if !items.leading.isEmpty && !items.trailing.isEmpty {
        row.append(.spacer)
    }
    if !items.trailing.isEmpty {
        row.append(.stack(axis: .horizontal, spacing: 1, children: items.trailing))
    }

    let bar = _VNode.stack(axis: .vertical, spacing: 0, children: [
        .stack(axis: .horizontal, spacing: 1, children: row),
        .divider,
    ])
    return _applyToolbarBackground(to: bar, env: env)
}

private func _toolbarBottomBar(items: _ToolbarLayoutItems, env: EnvironmentValues) -> _VNode? {
    guard !items.bottom.isEmpty else { return nil }
    let bar = _VNode.stack(axis: .vertical, spacing: 0, children: [
        .divider,
        .stack(axis: .horizontal, spacing: 1, children: items.bottom),
    ])
    return _applyToolbarBackground(to: bar, env: env)
}

private func _applyToolbarBackground(to node: _VNode, env: EnvironmentValues) -> _VNode {
    let style = env.toolbarBackgroundStyle
    guard style.visibility != .hidden else { return node }
    if let color = style.color {
        return .background(child: node, background: .style(fg: nil, bg: color, child: .empty))
    }
    if let material = style.material {
        let backgroundColor: Color
        switch material.raw {
        case Material.bar.raw:
            backgroundColor = Color.gray.opacity(0.18)
        case Material.background.raw:
            backgroundColor = Color.gray.opacity(0.10)
        case Material.ultraThinMaterial.raw:
            backgroundColor = Color.gray.opacity(0.14)
        default:
            backgroundColor = Color.gray.opacity(0.22)
        }
        return .background(child: node, background: .style(fg: nil, bg: backgroundColor, child: .empty))
    }
    if style.visibility == .visible {
        return .background(child: node, background: .style(fg: nil, bg: Color.gray.opacity(0.10), child: .empty))
    }
    return node
}

private struct _Frame: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let width: CGFloat?
    let height: CGFloat?
    let minWidth: CGFloat?
    let maxWidth: CGFloat?
    let minHeight: CGFloat?
    let maxHeight: CGFloat?

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        func toInt(_ v: CGFloat?) -> Int? {
            guard let v else { return nil }
            if v.isInfinite || v >= CGFloat(Int.max) { return Int.max }
            return max(0, Int(v.rounded()))
        }
        // Update _currentRenderSize for children (F20: GeometryReader container size)
        let currentRS = _UIRuntime._currentRenderSize ?? _Size(width: 0, height: 0)
        let fixedWidth = toInt(width)
        let fixedHeight = toInt(height)
        let resolvedMaxWidth = toInt(maxWidth)
        let resolvedMaxHeight = toInt(maxHeight)
        let resolvedW = fixedWidth ?? (resolvedMaxWidth == Int.max ? currentRS.width : (resolvedMaxWidth ?? currentRS.width))
        let resolvedH = fixedHeight ?? (resolvedMaxHeight == Int.max ? currentRS.height : (resolvedMaxHeight ?? currentRS.height))
        let childRenderSize = _Size(width: resolvedW, height: resolvedH)
        let child = _UIRuntime.$_currentRenderSize.withValue(childRenderSize) {
            ctx.buildChild(content)
        }
        return .frame(
            width: fixedWidth,
            height: fixedHeight,
            minWidth: toInt(minWidth),
            maxWidth: resolvedMaxWidth,
            minHeight: toInt(minHeight),
            maxHeight: resolvedMaxHeight,
            child: child
        )
    }
}

private struct _EdgePadding: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let top: Int
    let leading: Int
    let bottom: Int
    let trailing: Int

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .edgePadding(top: top, leading: leading, bottom: bottom, trailing: trailing, child: ctx.buildChild(content))
    }
}

private struct _FocusBoolBinder: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let get: () -> Bool
    let set: (Bool) -> Void

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let captureID = runtime._beginFocusCapture()
        let node = _UIRuntime.$_currentFocusCaptureID.withValue(captureID) {
            ctx.buildChild(content)
        }
        guard let focusPath = runtime._endFocusCapture(captureID) else {
            return node
        }

        runtime._registerFocusBoolBinding(path: focusPath, set: set)

        let wantsFocus = get()
        let isFocused = runtime._isFocused(path: focusPath)
        if wantsFocus && !isFocused {
            runtime._setFocus(path: focusPath)
        } else if !wantsFocus && isFocused {
            runtime._setFocus(path: nil)
        }

        return node
    }
}

private struct _FocusBoolValueBinder: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let isFocused: Bool

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let captureID = runtime._beginFocusCapture()
        let node = _UIRuntime.$_currentFocusCaptureID.withValue(captureID) {
            ctx.buildChild(content)
        }
        guard let focusPath = runtime._endFocusCapture(captureID) else {
            return node
        }

        let currentlyFocused = runtime._isFocused(path: focusPath)
        if isFocused && !currentlyFocused {
            runtime._setFocus(path: focusPath)
        } else if !isFocused && currentlyFocused {
            runtime._setFocus(path: nil)
        }

        return node
    }
}

private struct _OnSubmitBinder: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let action: () -> Void
    let actionScopePath: [Int]

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let captureID = runtime._beginFocusCapture()
        let node = _UIRuntime.$_currentFocusCaptureID.withValue(captureID) {
            ctx.buildChild(content)
        }
        if let focusPath = runtime._endFocusCapture(captureID) {
            runtime._registerSubmitHandler(controlPath: focusPath, actionScopePath: actionScopePath, action: action)
        }
        return node
    }
}

private struct _Style: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let fg: Color?
    let bg: Color?

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .style(fg: fg, bg: bg, child: ctx.buildChild(content))
    }
}

private struct _TextStyleModifier: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let style: TextStyle

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .textStyled(style: style, child: ctx.buildChild(content))
    }
}

private struct _Shadow: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .shadow(
            child: ctx.buildChild(content),
            color: color,
            radius: max(0, Int(radius.rounded())),
            x: Int(x.rounded()),
            y: Int(y.rounded())
        )
    }
}

private struct _Clip: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let kind: _ShapeKind

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .clip(kind: kind, child: ctx.buildChild(content))
    }
}

private struct _ContentShapeRect: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let kind: _ShapeKind

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .contentShapeRect(kind: kind, child: ctx.buildChild(content))
    }
}

private struct _Background: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let background: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .background(child: ctx.buildChild(content), background: ctx.buildChild(background))
    }
}

private struct _Overlay: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let overlay: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .overlay(child: ctx.buildChild(content), overlay: ctx.buildChild(overlay))
    }
}

private struct _LabelsHidden: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let hidden: Bool

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _UIRuntime.$_labelsHidden.withValue(hidden) {
            ctx.buildChild(content)
        }
    }
}

private struct _AccessibilityLabelModifier: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let label: String

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .tagged(value: AnyHashable(_AccessibilityLabel(value: label)), label: ctx.buildChild(content))
    }
}

private struct _AccessibilityIdentifierModifier: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let identifier: String

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .tagged(value: AnyHashable(_AccessibilityIdentifier(value: identifier)), label: ctx.buildChild(content))
    }
}

private struct _KeyboardShortcutBinder: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let shortcut: KeyboardShortcut

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let captureID = runtime._beginFocusCapture()
        let node = _UIRuntime.$_currentFocusCaptureID.withValue(captureID) {
            ctx.buildChild(content)
        }
        if let focusPath = runtime._endFocusCapture(captureID) {
            runtime._registerKeyboardShortcut(shortcut, forFocusablePath: focusPath)
        }
        return node
    }
}

private struct _OnKeyPressBinder: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let key: KeyEquivalent
    let action: () -> Bool
    let actionScopePath: [Int]

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let captureID = runtime._beginFocusCapture()
        let node = _UIRuntime.$_currentFocusCaptureID.withValue(captureID) {
            ctx.buildChild(content)
        }
        let targetPath = runtime._endFocusCapture(captureID) ?? ctx.path
        runtime._registerKeyPress(key, forFocusablePath: targetPath, actionPath: actionScopePath, action: action)
        return node
    }
}

// MARK: Keyboard shortcuts

public struct KeyboardShortcut: Hashable, Sendable {
    public var key: KeyEquivalent
    public var modifiers: EventModifiers
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let cancelAction = KeyboardShortcut(.escape)
    public static let defaultAction = KeyboardShortcut(.return)
}

public struct KeyEquivalent: Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { self.rawValue = value }

    public static let escape: KeyEquivalent = "\u{001B}"
    public static let `return`: KeyEquivalent = "\n"
    public static let upArrow: KeyEquivalent = "\u{F700}"
    public static let downArrow: KeyEquivalent = "\u{F701}"
    public static let leftArrow: KeyEquivalent = "\u{F702}"
    public static let rightArrow: KeyEquivalent = "\u{F703}"
    public static let home: KeyEquivalent = "\u{F729}"
    public static let end: KeyEquivalent = "\u{F72B}"
}

public enum KeyPress {
    public enum Phases {
        public enum ArrayLiteralElement {}
        public enum Element {}
        public enum RawValue {}
    }

    public enum Result {
        case handled
        case ignored
    }
}

public struct EventModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = EventModifiers(rawValue: 1 << 0)
    public static let shift = EventModifiers(rawValue: 1 << 1)
    public static let option = EventModifiers(rawValue: 1 << 2)
    public static let control = EventModifiers(rawValue: 1 << 3)
}

// MARK: Tagged options (Picker)
public extension View {
    func tag<V: Hashable>(_ value: V) -> some View {
        _Tag(content: AnyView(self), value: AnyHashable(value))
    }
}

private struct _Tag: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let value: AnyHashable

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .tagged(value: value, label: ctx.buildChild(content))
    }
}

private struct _Identified: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let id: AnyHashable
    let readerScopePath: [Int]?

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .identified(id: id, readerScopePath: readerScopePath, child: ctx.buildChild(content))
    }
}

private struct _OnDelete: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let action: (IndexSet) -> Void
    let actionScopePath: [Int]

    @Environment(\.editMode) private var editMode

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let child = ctx.buildChild(content)
        let wrapped = _VNode.onDelete(actionScopePath: actionScopePath, action: action, child: child)
        guard editMode?.wrappedValue.isEditing == true else {
            return wrapped
        }
        return _attachDeleteControls(node: wrapped, runtime: ctx.runtime)
    }

    private func _attachDeleteControls(node: _VNode, runtime: _UIRuntime) -> _VNode {
        let rows = _collectDeleteRows(node)
        guard !rows.isEmpty else { return node }

        var entries: [_VNode] = []
        entries.reserveCapacity(rows.count)

        for (index, row) in rows.enumerated() {
            let deletePath = (_UIRuntime._currentPath ?? []) + [70_000 + index]
            let deleteID = runtime._registerAction({
                action(IndexSet(integer: index))
            }, path: actionScopePath)
            runtime._registerFocusable(path: deletePath, activate: deleteID)

            let deleteButton = _VNode.button(
                id: deleteID,
                isFocused: runtime._isFocused(path: deletePath),
                label: .text("Del")
            )

            entries.append(.stack(axis: .horizontal, spacing: 1, children: [deleteButton, row]))
        }

        return .group(entries)
    }

    private func _collectDeleteRows(_ node: _VNode) -> [_VNode] {
        switch node {
        case .empty:
            return []
        case .group(let children):
            return children.flatMap(_collectDeleteRows)
        case .onDelete(_, _, let child):
            return _collectDeleteRows(child)
        default:
            return [node]
        }
    }
}

private struct _ModelContainerProvider: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let container: ModelContainer

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let current = _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment
        var next = current
        next.modelContext = container.mainContext
        return _UIRuntime.$_currentEnvironment.withValue(next) {
            ctx.buildChild(content)
        }
    }
}

private struct _ModelContainerBuilder: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let modelTypes: [Any.Type]
    let inMemory: Bool

    @State private var container: ModelContainer? = nil

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        if container == nil {
            container = try? ModelContainer(for: modelTypes, inMemory: inMemory)
        }
        guard let container else {
            return ctx.buildChild(content)
        }

        let current = _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment
        var next = current
        next.modelContext = container.mainContext
        return _UIRuntime.$_currentEnvironment.withValue(next) {
            ctx.buildChild(content)
        }
    }
}

/// Transition modifier: applies terminal-appropriate enter/exit effects.
///
/// In a real GPU renderer these would animate over many frames. In a terminal we approximate:
/// - `.opacity` — renders the view with reduced opacity (secondary color hint) on appear.
/// - `.slide` — offsets the view by -1 from the leading edge (appears to slide in).
/// - `.scale` — wraps the view in a scale-effect hint (rendered as secondary on first tick).
/// - `.identity` — no visual effect (passthrough).
/// - `.asymmetric(insertion:removal:)` — uses the insertion transition on appear.
/// - `.move(edge:)` — offsets the view by one cell from the given edge.
private struct _TransitionModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let transition: AnyTransition

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let raw = transition.rawValue.lowercased()
        let base = ctx.buildChild(content)

        // Identity — no effect
        if raw == "identity" {
            return base
        }

        // Asymmetric — use the insertion transition for the appear pass.
        // Parse "asymmetric(insertion:X,removal:Y)" and apply X.
        if raw.hasPrefix("asymmetric(") {
            if let insertionStart = raw.range(of: "insertion:"),
               let commaRange = raw.range(of: ",removal:") {
                let insertionRaw = String(raw[insertionStart.upperBound..<commaRange.lowerBound])
                return _applyTransitionEffect(insertionRaw, to: base)
            }
            return base
        }

        return _applyTransitionEffect(raw, to: base)
    }

    private func _applyTransitionEffect(_ raw: String, to base: _VNode) -> _VNode {
        if raw.contains("move(") {
            if raw.contains("top") {
                return .offset(x: 0, y: -1, child: base)
            }
            if raw.contains("bottom") {
                return .offset(x: 0, y: 1, child: base)
            }
            if raw.contains("leading") {
                return .offset(x: -1, y: 0, child: base)
            }
            if raw.contains("trailing") {
                return .offset(x: 1, y: 0, child: base)
            }
        }
        if raw.contains("opacity") {
            // Terminal approximation: reduced opacity on appear tick.
            // When an animation is active, use the animation progress for opacity.
            if let runtime = _UIRuntime._current, runtime._hasActiveAnimations {
                let progress = runtime._animationProgress
                return .opacity(CGFloat(progress), child: base)
            }
            return .opacity(0.85, child: base)
        }
        if raw.contains("slide") {
            // Terminal approximation: offset from the leading edge.
            // When an animation is active, progressively reduce the offset.
            if let runtime = _UIRuntime._current, runtime._hasActiveAnimations {
                let progress = runtime._animationProgress
                let offset = Int(round((1.0 - progress) * -2.0))
                return .offset(x: offset, y: 0, child: base)
            }
            return .offset(x: -1, y: 0, child: base)
        }
        if raw.contains("scale") {
            // Terminal approximation: show with secondary styling on first tick,
            // then normal. In terminal we can't truly scale text.
            if let runtime = _UIRuntime._current, runtime._hasActiveAnimations {
                let progress = runtime._animationProgress
                if progress < 0.5 {
                    return .style(fg: .secondary, bg: nil, child: base)
                }
            }
            return base
        }
        return base
    }
}

private struct _IgnoresSafeAreaModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.buildChild(content)
    }
}

private struct _GlassEffectModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let style: GlassEffect
    let shape: GlassEffectShape?

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let child = ctx.buildChild(content)
        let clipped: _VNode = {
            guard let shape else { return child }
            if shape.rawValue.contains("capsule") {
                return .clip(kind: .capsule, child: child)
            }
            if shape.rawValue.contains("cornerRadius"),
               let radiusStart = shape.rawValue.firstIndex(of: ":"),
               let radiusEnd = shape.rawValue.firstIndex(of: ")"),
               let radius = Int(shape.rawValue[shape.rawValue.index(after: radiusStart)..<radiusEnd]) {
                return .clip(kind: .roundedRectangle(cornerRadius: radius), child: child)
            }
            return .clip(kind: .rectangle, child: child)
        }()
        // Vary background opacity by glass style
        let isInteractive = style.rawValue.contains("interactive")
        let bgOpacity = isInteractive ? 0.24 : 0.16
        let shadowOpacity = isInteractive ? 0.12 : 0.08
        let approximated = _VNode.background(
            child: .shadow(child: clipped, color: .white.opacity(shadowOpacity), radius: 1, x: 0, y: 0),
            background: ctx.buildChild(Color.gray.opacity(bgOpacity))
        )
        return .glass(style: style.rawValue, shape: shape?.rawValue, child: approximated)
    }
}

private struct _CRTEffectModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let style: CRTEffect

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .crt(style: style.rawValue, child: ctx.buildChild(content))
    }
}

private struct _NavigationTransitionModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let transition: NavigationTransition

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _ = transition
        return ctx.buildChild(content)
    }
}

private struct _ContentTransitionModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let transition: ContentTransition

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _ = transition
        return ctx.buildChild(content)
    }
}

private struct _HoverModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let action: (Bool) -> Void
    let actionScopePath: [Int]

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let id = ctx.runtime._registerHoverHandler(actionScopePath: ctx.path, action: action)
        return .hover(id: id, child: ctx.buildChild(content))
    }
}

private struct _PreviewDisplayNameModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let name: String

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        guard !name.isEmpty else { return ctx.buildChild(content) }
        return ctx.buildChild(
            VStack(alignment: .leading, spacing: 0) {
                Text(name).foregroundStyle(.secondary)
                content
            }
        )
    }
}

private struct _OpacityModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let opacity: CGFloat

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .opacity(opacity, child: ctx.buildChild(content))
    }
}

private struct _OffsetModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let x: CGFloat
    let y: CGFloat

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .offset(x: Int(x.rounded()), y: Int(y.rounded()), child: ctx.buildChild(content))
    }
}

private struct _MaskModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let mask: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let child = ctx.buildChild(content)
        let maskNode = ctx.buildChild(mask)
        let kind: _ShapeKind = {
            guard case .shape(let shape) = maskNode else { return .rectangle }
            return shape.kind
        }()
        return .clip(kind: kind, child: child)
    }
}

private struct _DisabledModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let disabled: Bool

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let current = _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment
        var next = current
        next.isEnabled = current.isEnabled && !disabled
        return _UIRuntime.$_currentEnvironment.withValue(next) {
            _UIRuntime.$_hitTestingEnabled.withValue(_UIRuntime._hitTestingEnabled && !disabled) {
                let node = ctx.buildChild(content)
                if disabled {
                    return _VNode.style(fg: .secondary, bg: nil, child: node)
                }
                return node
            }
        }
    }
}

private struct _SearchableModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let text: Binding<String>

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.buildChild(
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 1) {
                    Image(systemName: "magnifyingglass")
                    TextField("Search", text: text)
                        .submitLabel(.search)
                }
                content
            }
        )
    }
}

private struct _RefreshableModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let action: () async -> Void
    let actionScopePath: [Int]

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let actionPath = actionScopePath
        let refreshAction = action
        return ctx.buildChild(
            VStack(alignment: .leading, spacing: 1) {
                Button("Refresh") {
                    runtime._launchAsyncAction(path: actionPath, action: refreshAction)
                }
                .keyboardShortcut("r", modifiers: .control)
                content
            }
        )
    }
}

private struct _HelpModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let text: String

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _ = text
        return ctx.buildChild(content)
    }
}

private struct _OnExitCommandBinder: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let action: () -> Void
    let actionScopePath: [Int]

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.runtime._registerExitCommand(actionScopePath: actionScopePath, action: action)
        return ctx.buildChild(content)
    }
}

private struct _QuickLookPreviewModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let url: Binding<URL?>

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        if let currentURL = url.wrappedValue {
            let dismiss = {
                if url.wrappedValue != nil {
                    url.wrappedValue = nil
                }
            }

            // Extract file metadata
            let filename = currentURL.lastPathComponent
            let icon = _quickLookIcon(for: currentURL.pathExtension)
            var metadataLines: [String] = ["\(icon) \(filename)"]

            // Try to get file size
            if currentURL.isFileURL {
                let fm = FileManager.default
                if let attrs = try? fm.attributesOfItem(atPath: currentURL.path),
                   let size = attrs[.size] as? UInt64 {
                    metadataLines.append("Size: \(_formatFileSize(size))")
                }
            }

            // For text files, read first 10 lines (bounded to 4KB)
            let textExtensions: Set<String> = ["txt", "md", "swift", "json", "yaml", "yml", "xml", "html", "css", "js", "ts", "py", "rb", "go", "rs", "c", "h", "cpp", "java"]
            var previewLines: [String] = []
            if textExtensions.contains(currentURL.pathExtension.lowercased()), currentURL.isFileURL {
                // Bounded synchronous read: 4KB max
                if let fh = FileHandle(forReadingAtPath: currentURL.path) {
                    let data = fh.readData(ofLength: 4096)
                    fh.closeFile()
                    if let text = String(data: data, encoding: .utf8) {
                        previewLines = Array(text.components(separatedBy: .newlines).prefix(10))
                    }
                }
            }

            ctx.runtime._registerOverlay(view: AnyView(
                ZStack {
                    Color.gray.opacity(0.25)
                    VStack(spacing: 1) {
                        Text("Quick Look")
                            .bold()
                        ForEach(Array(metadataLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                        }
                        if !previewLines.isEmpty {
                            Text("───")
                                .foregroundStyle(.secondary)
                            ForEach(Array(previewLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                            }
                        }
                        Button("Close") {
                            dismiss()
                        }
                    }
                    .padding(1)
                }
            ), dismiss: dismiss)
        }
        return ctx.buildChild(content)
    }
}

private func _quickLookIcon(for ext: String) -> String {
    switch ext.lowercased() {
    case "txt", "md", "rtf": return "📄"
    case "swift", "py", "js", "ts", "go", "rs", "c", "cpp", "h", "java", "rb": return "📝"
    case "json", "yaml", "yml", "xml", "html", "css": return "📋"
    case "png", "jpg", "jpeg", "gif", "bmp", "tiff", "svg": return "🖼"
    case "pdf": return "📕"
    case "zip", "tar", "gz", "bz2": return "📦"
    default: return "📎"
    }
}

private func _formatFileSize(_ bytes: UInt64) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
    return "\(bytes / (1024 * 1024)) MB"
}

// MARK: - _AnimationModifier (wires .animation(_:value:) to runtime)

public struct _AnimationModifier<Value: Equatable>: View, _PrimitiveView {
    public typealias Body = Never

    let content: AnyView
    let animation: _AnyAnimation?
    let value: Value

    public init(content: AnyView, animation: _AnyAnimation?, value: Value) {
        self.content = content
        self.animation = animation
        self.value = value
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        if let anim = animation {
            let previous: Value? = ctx.runtime._replaceModifierValue(
                prefix: "animation",
                path: ctx.path,
                value: value
            )
            if let previous, previous != value {
                ctx.runtime._registerAnimation(curve: anim.curve, duration: anim.duration)
            }
        }
        return ctx.buildChild(content)
    }
}

// MARK: - _PhaseAnimatorPrimitive (cycles through phases with runtime-managed state)

public struct _PhaseAnimatorPrimitive: View, _PrimitiveView {
    public typealias Body = Never

    let phases: [Any]
    let content: (Any) -> AnyView
    let intervalSeconds: Double

    public init(phases: [Any], content: @escaping (Any) -> AnyView, intervalSeconds: Double) {
        self.phases = phases
        self.content = content
        self.intervalSeconds = intervalSeconds
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        guard !phases.isEmpty else { return .empty }

        // Keep this deterministic for native renderers. The previous timer-backed
        // implementation mutated runtime state from an async task and could race
        // GTK's render pass. Apps still get the first phase layout without churn.
        return ctx.buildChild(content(phases[0]))
    }
}

/// Type-erased animation info passed from SwiftUI module to OmniUICore.
public struct _AnyAnimation: Hashable, Sendable {
    public let curve: AnimationCurve
    public let duration: Double
    public init(curve: AnimationCurve, duration: Double) {
        self.curve = curve
        self.duration = duration
    }
}

public struct _Passthrough: View, _PrimitiveView {
    public typealias Body = Never

    // Type-erase immediately to avoid exponential generic growth in large `body` expressions.
    let content: AnyView

    public init<V: View>(_ content: V) { self.content = AnyView(content) }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.buildChild(content)
    }
}

public struct _OnAppear: View, _PrimitiveView {
    public typealias Body = Never

    let content: AnyView
    let action: () -> Void

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let node = ctx.buildChild(content)
        ctx.runtime._registerOnAppear(path: ctx.path, action: action)
        return node
    }
}

public struct _OnDisappear: View, _PrimitiveView {
    public typealias Body = Never

    let content: AnyView
    let action: () -> Void

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.runtime._registerOnDisappear(path: ctx.path, action: action)
        return ctx.buildChild(content)
    }
}

public struct _OnChange<V: Equatable>: View, _PrimitiveView {
    public typealias Body = Never

    let content: AnyView
    let value: V
    let action: (_ oldValue: V, _ newValue: V) -> Void

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let change = ctx.runtime._consumeOnChange(path: ctx.path, value: value, initial: false)
        if change.shouldFire {
            action(change.oldValue, value)
        }
        return ctx.buildChild(content)
    }
}

public struct _OnChangeSimple<V: Equatable>: View, _PrimitiveView {
    public typealias Body = Never

    let content: AnyView
    let value: V
    let initial: Bool
    let action: () -> Void

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let change = ctx.runtime._consumeOnChange(path: ctx.path, value: value, initial: initial)
        if change.shouldFire {
            action()
        }
        return ctx.buildChild(content)
    }
}

public struct _OnChangeWithInitial<V: Equatable>: View, _PrimitiveView {
    public typealias Body = Never

    let content: AnyView
    let value: V
    let initial: Bool
    let action: (_ oldValue: V, _ newValue: V) -> Void

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let change = ctx.runtime._consumeOnChange(path: ctx.path, value: value, initial: initial)
        if change.shouldFire {
            action(change.oldValue, value)
        }
        return ctx.buildChild(content)
    }
}

private struct _TaskBinder: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let priority: TaskPriority?
    let action: () async -> Void

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.runtime._registerTask(path: ctx.path, priority: priority, action: action)
        return ctx.buildChild(content)
    }
}

// MARK: - _BadgeModifier

private struct _BadgeModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let badge: String?

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let childNode = ctx.buildChild(content)
        guard let badge = badge, !badge.isEmpty else { return childNode }
        return .badge(text: badge, child: childNode)
    }
}

// MARK: - _TaskIdBinder (task with id-based cancellation/restart)

private struct _TaskIdBinder: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let id: AnyHashable
    let priority: TaskPriority?
    let action: () async -> Void

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.runtime._registerTaskWithId(path: ctx.path, id: id, priority: priority, action: action)
        return ctx.buildChild(content)
    }
}

// MARK: - _FocusSectionModifier

private struct _FocusSectionModifier: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.runtime._beginFocusSection(path: ctx.path)
        let node = ctx.buildChild(content)
        ctx.runtime._endFocusSection()
        return node
    }
}

// MARK: - Parity Modifier Structs

private struct _FixedSizeModifier: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let horizontal: Bool
    let vertical: Bool

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .fixedSize(horizontal: horizontal, vertical: vertical, child: ctx.buildChild(content))
    }
}

private struct _LayoutPriorityModifier: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let priority: Double

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .layoutPriority(priority, child: ctx.buildChild(content))
    }
}

private struct _AspectRatioModifier: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let ratio: CGFloat?
    let contentMode: _ContentMode

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .aspectRatio(ratio, contentMode: contentMode, child: ctx.buildChild(content))
    }
}

private struct _AlignmentGuideModifier: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let alignmentID: _AlignmentID
    let computeValue: (ViewDimensions) -> CGFloat

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let child = ctx.buildChild(content)
        let rs = _UIRuntime._currentRenderSize ?? _Size(width: 0, height: 0)
        let dims = ViewDimensions(width: CGFloat(rs.width), height: CGFloat(rs.height))
        let customValue = computeValue(dims)
        let defaultValue: CGFloat
        switch alignmentID {
        case .horizontal(let h): defaultValue = dims[h]
        case .vertical(let v): defaultValue = dims[v]
        }
        let offset = Int(defaultValue - customValue)
        return .alignmentGuide(alignment: alignmentID, offset: offset, child: child)
    }
}

private struct _PreferenceModifier<K: PreferenceKey>: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let value: K.Value

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let keyID = ObjectIdentifier(K.self)
        let child = ctx.buildChild(content)
        return .preferenceNode(kind: .set(
            keyID: keyID,
            value: value,
            reduce: { existing, nextValue in
                guard var typedExisting = existing as? K.Value else { return }
                K.reduce(value: &typedExisting, nextValue: { nextValue() as! K.Value })
                existing = typedExisting
            }
        ), child: child)
    }
}

private struct _OnPreferenceChangeModifier<K: PreferenceKey>: View, _PrimitiveView where K.Value: Equatable {
    typealias Body = Never
    let content: AnyView
    let action: (K.Value) -> Void

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let keyID = ObjectIdentifier(K.self)
        let child = ctx.buildChild(content)
        ctx.runtime._registerPreferenceCallback(keyID: keyID) { value in
            if let typed = value as? K.Value {
                self.action(typed)
            }
        }
        return .preferenceNode(kind: .onChange(keyID: keyID, callback: { value in
            if let typed = value as? K.Value {
                self.action(typed)
            }
        }), child: child)
    }
}

private struct _SwipeActionsModifier: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let edge: HorizontalEdge
    let actions: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let child = ctx.buildChild(content)
        let actionNode = ctx.buildChild(actions)
        return .swipeActions(edge: edge, revealed: false, actions: [actionNode], child: child)
    }
}

private struct _AnchorPreferenceModifier<K: PreferenceKey>: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let transform: (Anchor<CGRect>) -> K.Value

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let keyID = ObjectIdentifier(K.self)
        let child = ctx.buildChild(content)
        return .anchorPreference(
            keyID: keyID,
            transform: { rect in
                let anchor = Anchor<CGRect>(value: rect.cgRect)
                return self.transform(anchor)
            },
            reduce: { existing, nextValue in
                guard var typedExisting = existing as? K.Value else { return }
                K.reduce(value: &typedExisting, nextValue: { nextValue() as! K.Value })
                existing = typedExisting
            },
            child: child
        )
    }
}

private struct _BlurModifier: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let radius: CGFloat

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .blur(radius: radius, child: ctx.buildChild(content))
    }
}

private struct _TextCaseModifier: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let textCase: Text.Case

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let child = _UIRuntime.$_currentEnvironment.withValue(
            { var e = _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment; e.textCase = textCase; return e }()
        ) {
            ctx.buildChild(content)
        }
        return .textCase(textCase, child: child)
    }
}

private struct _RotationEffectModifier: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let angle: Angle

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .rotationEffect(angle: angle.degrees, child: ctx.buildChild(content))
    }
}
