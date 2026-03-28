// Terminal-friendly ColorPicker with HSL slider rendering for SwiftUI compatibility.

public struct ColorPicker: View, _PrimitiveView {
    public typealias Body = Never

    let title: String
    let selection: Binding<Color>
    let supportsOpacity: Bool
    let actionScopePath: [Int]

    public init(_ titleKey: String, selection: Binding<Color>, supportsOpacity: Bool = true) {
        self.title = titleKey
        self.selection = selection
        self.supportsOpacity = supportsOpacity
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _ = supportsOpacity

        let currentColor = selection.wrappedValue
        let hex = _colorToHex(currentColor)
        let labelText = _UIRuntime._labelsHidden ? hex : "\(title): \(hex)"

        guard _UIRuntime._hitTestingEnabled else {
            return .text(labelText)
        }

        let runtime = ctx.runtime
        let controlPath = ctx.path

        // Three HSL bar controls: H, S, L
        let hsl = _colorToHSL(currentColor)
        let barWidth = 6

        // H bar
        let hPath = controlPath + [0]
        let hFocused = runtime._isFocused(path: hPath)
        let hID = runtime._registerAction({
            runtime._setFocus(path: hPath)
            let newH = (hsl.h + 1.0 / Double(barWidth)).truncatingRemainder(dividingBy: 1.0)
            selection.wrappedValue = _hslToColor(h: newH, s: hsl.s, l: hsl.l)
        }, path: actionScopePath)
        runtime._registerFocusable(path: hPath, activate: hID)
        let hBar = _renderBar(label: "H", value: hsl.h, width: barWidth, focused: hFocused)

        // S bar
        let sPath = controlPath + [1]
        let sFocused = runtime._isFocused(path: sPath)
        let sID = runtime._registerAction({
            runtime._setFocus(path: sPath)
            let newS = min(1.0, hsl.s + 1.0 / Double(barWidth))
            selection.wrappedValue = _hslToColor(h: hsl.h, s: newS, l: hsl.l)
        }, path: actionScopePath)
        runtime._registerFocusable(path: sPath, activate: sID)
        let sBar = _renderBar(label: "S", value: hsl.s, width: barWidth, focused: sFocused)

        // L bar
        let lPath = controlPath + [2]
        let lFocused = runtime._isFocused(path: lPath)
        let lID = runtime._registerAction({
            runtime._setFocus(path: lPath)
            let newL = min(1.0, hsl.l + 1.0 / Double(barWidth))
            selection.wrappedValue = _hslToColor(h: hsl.h, s: hsl.s, l: newL)
        }, path: actionScopePath)
        runtime._registerFocusable(path: lPath, activate: lID)
        let lBar = _renderBar(label: "L", value: hsl.l, width: barWidth, focused: lFocused)

        // Preview swatch
        let swatchNode = _VNode.style(fg: nil, bg: currentColor, child: .text("  \(hex)  "))

        let titleNode = _VNode.text(title)
        return .stack(axis: .vertical, spacing: 0, children: [
            titleNode,
            .stack(axis: .horizontal, spacing: 1, children: [
                .tapTarget(id: hID, child: hBar),
                .tapTarget(id: sID, child: sBar),
                .tapTarget(id: lID, child: lBar),
            ]),
            swatchNode,
        ])
    }

    private func _renderBar(label: String, value: Double, width: Int, focused: Bool) -> _VNode {
        let filled = max(0, min(width, Int((value * Double(width)).rounded())))
        let filledStr = String(repeating: "▓", count: filled)
        let emptyStr = String(repeating: "░", count: width - filled)
        let prefix = focused ? ">\(label):" : " \(label):"
        return .text("\(prefix)\(filledStr)\(emptyStr)")
    }

    // -- Color conversion helpers --

    private static let _namedColors: [(String, Double, Double, Double)] = [
        ("red", 0.0, 1.0, 0.5),
        ("orange", 30.0/360, 1.0, 0.5),
        ("yellow", 60.0/360, 1.0, 0.5),
        ("green", 120.0/360, 1.0, 0.5),
        ("mint", 160.0/360, 0.7, 0.6),
        ("teal", 180.0/360, 0.7, 0.5),
        ("cyan", 195.0/360, 1.0, 0.5),
        ("blue", 240.0/360, 1.0, 0.5),
        ("indigo", 275.0/360, 0.5, 0.5),
        ("purple", 285.0/360, 0.8, 0.5),
        ("pink", 330.0/360, 1.0, 0.7),
        ("brown", 30.0/360, 0.6, 0.4),
        ("white", 0.0, 0.0, 1.0),
        ("black", 0.0, 0.0, 0.0),
        ("gray", 0.0, 0.0, 0.5),
    ]

    private func _colorToHSL(_ color: Color) -> (h: Double, s: Double, l: Double) {
        // Try named color lookup
        let name = color.name
        if let entry = ColorPicker._namedColors.first(where: { $0.0 == name }) {
            return (entry.1, entry.2, entry.3)
        }
        // Try parsing rgb() format
        if name.hasPrefix("rgb("), let rgb = _parseRGB(name) {
            return _rgbToHSL(r: rgb.0, g: rgb.1, b: rgb.2)
        }
        return (0.0, 0.0, 0.5) // fallback: gray
    }

    private func _parseRGB(_ s: String) -> (Double, Double, Double)? {
        let inner = s.dropFirst(4).dropLast(1) // strip "rgb(" and ")"
        let parts = inner.split(separator: ",")
        guard parts.count == 3,
              let r = Double(parts[0]),
              let g = Double(parts[1]),
              let b = Double(parts[2]) else { return nil }
        return (r, g, b)
    }

    private func _rgbToHSL(r: Double, g: Double, b: Double) -> (h: Double, s: Double, l: Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let l = (maxC + minC) / 2.0
        guard maxC != minC else { return (0, 0, l) }
        let d = maxC - minC
        let s = l > 0.5 ? d / (2.0 - maxC - minC) : d / (maxC + minC)
        var h: Double = 0
        if maxC == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if maxC == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h /= 6.0
        return (h, s, l)
    }

    private func _colorToHex(_ color: Color) -> String {
        if let rgb = _resolveColorToRGB(color) {
            return String(format: "#%02X%02X%02X", rgb.r, rgb.g, rgb.b)
        }
        return color.name
    }
}

private func _hslToColor(h: Double, s: Double, l: Double) -> Color {
    let (r, g, b) = _hslToRGB(h: h, s: s, l: l)
    return Color(red: r, green: g, blue: b)
}

private func _hslToRGB(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
    guard s > 0 else { return (l, l, l) }
    let q = l < 0.5 ? l * (1 + s) : l + s - l * s
    let p = 2 * l - q
    func hue2rgb(_ t0: Double) -> Double {
        var t = t0
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0/6 { return p + (q - p) * 6 * t }
        if t < 1.0/2 { return q }
        if t < 2.0/3 { return p + (q - p) * (2.0/3 - t) * 6 }
        return p
    }
    return (hue2rgb(h + 1.0/3), hue2rgb(h), hue2rgb(h - 1.0/3))
}
