/// Extremely small "renderer" used for snapshot testing and interactive simulation.
///
/// This is intentionally simplistic (monospace terminal grid) but provides:
/// - deterministic plaintext output
/// - hit testing for `Button`
enum _DebugLayout {
    struct Overlay {
        var zIndex: Int
        var draw: (_ canvas: inout [[String]], _ hitRegions: inout [(_Rect, _ActionID)]) -> Void
    }

    struct Result {
        var lines: [String]
        var hitRegions: [(_Rect, _ActionID)]
    }

    static func layout(node: _VNode, in rect: _Rect) -> Result {
        var canvas = Array(repeating: Array(repeating: " ", count: rect.size.width), count: rect.size.height)
        var hits: [(_Rect, _ActionID)] = []
        var overlays: [Overlay] = []
        _ = draw(node: node, origin: rect.origin, maxSize: rect.size, canvas: &canvas, hitRegions: &hits, overlays: &overlays)

        // Draw overlays last so they appear "above" later siblings in stacks.
        for o in overlays.sorted(by: { $0.zIndex < $1.zIndex }) {
            o.draw(&canvas, &hits)
        }

        let lines = canvas.map { $0.joined() }
        return Result(lines: lines, hitRegions: hits)
    }

    @discardableResult
    private static func draw(
        node: _VNode,
        origin: _Point,
        maxSize: _Size,
        canvas: inout [[String]],
        hitRegions: inout [(_Rect, _ActionID)],
        overlays: inout [Overlay]
    ) -> _Size {
        guard maxSize.width > 0, maxSize.height > 0 else { return _Size(width: 0, height: 0) }

        switch node {
        case .empty:
            return _Size(width: 0, height: 0)

        case .group(let nodes):
            var used = _Size(width: 0, height: 0)
            for n in nodes {
                // Groups are drawn on top of each other; callers should flatten for layout.
                let s = draw(node: n, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, overlays: &overlays)
                used.width = max(used.width, s.width)
                used.height = max(used.height, s.height)
            }
            return used

        case .text(let s):
            let clipped = String(s.prefix(maxSize.width))
            for (i, ch) in clipped.enumerated() {
                put(String(ch), at: _Point(x: origin.x + i, y: origin.y), canvas: &canvas)
            }
            return _Size(width: min(s.count, maxSize.width), height: 1)

        case .image(let name):
            let s = "<\(name)>"
            let clipped = String(s.prefix(maxSize.width))
            for (i, ch) in clipped.enumerated() {
                put(String(ch), at: _Point(x: origin.x + i, y: origin.y), canvas: &canvas)
            }
            return _Size(width: min(s.count, maxSize.width), height: 1)

        case .spacer:
            return _Size(width: 0, height: 0)

        case .padding(let amount, let child):
            let inner = _Rect(
                origin: _Point(x: origin.x + amount, y: origin.y + amount),
                size: _Size(width: max(0, maxSize.width - amount * 2), height: max(0, maxSize.height - amount * 2))
            )
            let s = draw(node: child, origin: inner.origin, maxSize: inner.size, canvas: &canvas, hitRegions: &hitRegions, overlays: &overlays)
            return _Size(width: min(maxSize.width, s.width + amount * 2), height: min(maxSize.height, s.height + amount * 2))

        case .stack(let axis, let spacing, let children):
            var cursor = origin
            var used = _Size(width: 0, height: 0)
            for (idx, child) in children.enumerated() {
                let remaining: _Size
                switch axis {
                case .vertical:
                    remaining = _Size(width: maxSize.width, height: maxSize.height - (cursor.y - origin.y))
                case .horizontal:
                    remaining = _Size(width: maxSize.width - (cursor.x - origin.x), height: maxSize.height)
                }
                let s = draw(node: child, origin: cursor, maxSize: remaining, canvas: &canvas, hitRegions: &hitRegions, overlays: &overlays)
                switch axis {
                case .vertical:
                    cursor.y += s.height
                    if idx != children.count - 1 { cursor.y += spacing }
                    used.width = max(used.width, s.width)
                    used.height = cursor.y - origin.y
                case .horizontal:
                    cursor.x += s.width
                    if idx != children.count - 1 { cursor.x += spacing }
                    used.width = cursor.x - origin.x
                    used.height = max(used.height, s.height)
                }
                if cursor.x >= origin.x + maxSize.width || cursor.y >= origin.y + maxSize.height { break }
            }
            used.width = min(used.width, maxSize.width)
            used.height = min(used.height, maxSize.height)
            return used

        case .button(let id, let isFocused, let label):
            // Render as [ label ]
            let x0 = isFocused ? origin.x + 1 : origin.x
            if isFocused {
                put(">", at: origin, canvas: &canvas)
            }
            put("[", at: _Point(x: x0, y: origin.y), canvas: &canvas)
            let labelOrigin = _Point(x: x0 + 2, y: origin.y)
            let labelMax = _Size(width: max(0, maxSize.width - (isFocused ? 5 : 4)), height: 1)
            let labelSize = draw(node: label, origin: labelOrigin, maxSize: labelMax, canvas: &canvas, hitRegions: &hitRegions, overlays: &overlays)
            put("]", at: _Point(x: x0 + 1 + labelSize.width + 2, y: origin.y), canvas: &canvas)
            let buttonWidth = min(maxSize.width, (isFocused ? 1 : 0) + 4 + labelSize.width)
            let rect = _Rect(origin: origin, size: _Size(width: buttonWidth, height: 1))
            hitRegions.append((rect, id))
            return _Size(width: buttonWidth, height: 1)

        case .toggle(let id, let isFocused, let isOn, let label):
            // Render as [x] label / [ ] label
            let box = isOn ? "[x] " : "[ ] "
            let x0 = isFocused ? origin.x + 1 : origin.x
            if isFocused {
                put(">", at: origin, canvas: &canvas)
            }
            for (i, ch) in box.enumerated() {
                put(String(ch), at: _Point(x: x0 + i, y: origin.y), canvas: &canvas)
            }
            let labelOrigin = _Point(x: x0 + box.count, y: origin.y)
            let labelMax = _Size(width: max(0, maxSize.width - box.count - (isFocused ? 1 : 0)), height: 1)
            let labelSize = draw(node: label, origin: labelOrigin, maxSize: labelMax, canvas: &canvas, hitRegions: &hitRegions, overlays: &overlays)
            let width = min(maxSize.width, (isFocused ? 1 : 0) + box.count + labelSize.width)
            let rect = _Rect(origin: origin, size: _Size(width: width, height: 1))
            hitRegions.append((rect, id))
            return _Size(width: width, height: 1)

        case .textField(let id, let placeholder, let text, let isFocused):
            let display = text.isEmpty ? placeholder : text
            let prefix = isFocused ? "> " : "  "
            let s = prefix + "[" + display + "]"
            let clipped = String(s.prefix(maxSize.width))
            for (i, ch) in clipped.enumerated() {
                put(String(ch), at: _Point(x: origin.x + i, y: origin.y), canvas: &canvas)
            }
            let rect = _Rect(origin: origin, size: _Size(width: min(maxSize.width, clipped.count), height: 1))
            hitRegions.append((rect, id))
            return _Size(width: min(maxSize.width, clipped.count), height: 1)

        case .menu(let id, let isFocused, let isExpanded, let title, let value, let items):
            // Header like:  >[ Flavor: Chocolate v ]
            let v = isExpanded ? "^" : "v"
            let headText = "\(title): \(value) \(v)"
            let x0 = isFocused ? origin.x + 1 : origin.x
            if isFocused {
                put(">", at: origin, canvas: &canvas)
            }
            put("[", at: _Point(x: x0, y: origin.y), canvas: &canvas)
            let inner = " " + headText + " "
            let innerClipped = String(inner.prefix(max(0, maxSize.width - (isFocused ? 3 : 2))))
            for (i, ch) in innerClipped.enumerated() {
                put(String(ch), at: _Point(x: x0 + 1 + i, y: origin.y), canvas: &canvas)
            }
            let closeX = min(origin.x + maxSize.width - 1, x0 + 1 + innerClipped.count)
            put("]", at: _Point(x: closeX, y: origin.y), canvas: &canvas)
            let headWidth = min(maxSize.width, (isFocused ? 1 : 0) + 2 + innerClipped.count)
            hitRegions.append((_Rect(origin: origin, size: _Size(width: headWidth, height: 1)), id))

            if !isExpanded || items.isEmpty || maxSize.height < 3 {
                return _Size(width: headWidth, height: 1)
            }

            // Dropdown is an overlay (z-layer), so it doesn't affect layout height.
            // This matches typical UI pickers: the list appears above later content instead of pushing it down.
            let overlayX0 = x0
            let overlayOrigin = _Point(x: overlayX0, y: origin.y + 1)
            let overlayMax = _Size(
                width: max(0, maxSize.width - (overlayX0 - origin.x)),
                height: max(0, maxSize.height - 1)
            )

            let overlayItems = items
            overlays.append(Overlay(zIndex: 1000, draw: { canvas, hitRegions in
                guard overlayMax.width > 0, overlayMax.height > 0 else { return }

                // Dropdown box (simple ASCII).
                let maxLabel = overlayItems.map { $0.label.count }.max() ?? 0
                let boxInnerWidth = min(max(8, maxLabel + 4), max(0, overlayMax.width - 2))
                let boxWidth = boxInnerWidth + 2

                // Top border
                let topY = overlayOrigin.y
                let maxY = overlayOrigin.y + overlayMax.height
                if topY < maxY {
                    put("+", at: _Point(x: overlayOrigin.x, y: topY), canvas: &canvas)
                    for i in 0..<boxInnerWidth { put("-", at: _Point(x: overlayOrigin.x + 1 + i, y: topY), canvas: &canvas) }
                    put("+", at: _Point(x: overlayOrigin.x + boxInnerWidth + 1, y: topY), canvas: &canvas)
                }

                var usedHeight = 1
                for item in overlayItems {
                    let y = overlayOrigin.y + usedHeight
                    if y >= maxY - 1 { break }

                    put("|", at: _Point(x: overlayOrigin.x, y: y), canvas: &canvas)
                    for i in 0..<boxInnerWidth { put(" ", at: _Point(x: overlayOrigin.x + 1 + i, y: y), canvas: &canvas) }
                    put("|", at: _Point(x: overlayOrigin.x + boxInnerWidth + 1, y: y), canvas: &canvas)

                    // Selection + focus markers inside the box.
                    let sel = item.isSelected ? "*" : " "
                    let foc = item.isFocused ? ">" : " "
                    let prefix = "\(foc)\(sel) "
                    for (i, ch) in prefix.enumerated() {
                        put(String(ch), at: _Point(x: overlayOrigin.x + 1 + i, y: y), canvas: &canvas)
                    }
                    let labelClipped = String(item.label.prefix(max(0, boxInnerWidth - prefix.count)))
                    for (i, ch) in labelClipped.enumerated() {
                        put(String(ch), at: _Point(x: overlayOrigin.x + 1 + prefix.count + i, y: y), canvas: &canvas)
                    }

                    let optRect = _Rect(origin: _Point(x: overlayOrigin.x, y: y), size: _Size(width: boxWidth, height: 1))
                    hitRegions.append((optRect, item.id))

                    usedHeight += 1
                }

                // Bottom border
                let bottomY = overlayOrigin.y + usedHeight
                if bottomY < maxY {
                    put("+", at: _Point(x: overlayOrigin.x, y: bottomY), canvas: &canvas)
                    for i in 0..<boxInnerWidth { put("-", at: _Point(x: overlayOrigin.x + 1 + i, y: bottomY), canvas: &canvas) }
                    put("+", at: _Point(x: overlayOrigin.x + boxInnerWidth + 1, y: bottomY), canvas: &canvas)
                }
            }))

            return _Size(width: headWidth, height: 1)

        }
    }

    private static func put(_ s: String, at p: _Point, canvas: inout [[String]]) {
        guard p.y >= 0, p.y < canvas.count else { return }
        guard p.x >= 0, p.x < canvas[p.y].count else { return }
        canvas[p.y][p.x] = s
    }
}
