import Foundation

public struct RenderOp: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case glyph(x: Int, y: Int, egc: String, fg: Color?, bg: Color?)
        case textRun(x: Int, y: Int, text: String, fg: Color?, bg: Color?)
        case fillRect(rect: _Rect, color: Color)
        case shape(rect: _Rect, shape: _ShapeNode)
    }

    public var zIndex: Int
    public var kind: Kind

    public init(zIndex: Int = 0, kind: Kind) {
        self.zIndex = zIndex
        self.kind = kind
    }
}

public struct RenderSnapshot: Sendable {
    public let size: _Size
    public let ops: [RenderOp]
    public let focusedRect: _Rect?
    public let shapeRegions: [(_Rect, _ShapeNode)]

    let hitRegions: [(_Rect, _ActionID)]
    let scrollRegions: [_ScrollRegion]
    let runtime: _UIRuntime

    public func click(x: Int, y: Int) {
        let p = _Point(x: x, y: y)
        guard let (_, id) = hitRegions.last(where: { $0.0.contains(p) }) else { return }
        runtime._invokeAction(id)
    }

    public func scroll(x: Int, y: Int, deltaY: Int) {
        let p = _Point(x: x, y: y)
        guard let r = scrollRegions.last(where: { $0.rect.contains(p) }) else { return }
        runtime._scroll(path: r.path, deltaY: deltaY, maxOffset: r.maxOffsetY)
    }

    public func type(_ s: String) {
        for scalar in s.unicodeScalars {
            runtime._handleKey(.char(scalar.value))
        }
    }

    public func backspace() {
        runtime._handleKey(.backspace)
    }
}

enum _RenderLayout {
    struct Result {
        var ops: [RenderOp]
        var hitRegions: [(_Rect, _ActionID)]
        var scrollRegions: [_ScrollRegion]
        var shapeRegions: [(_Rect, _ShapeNode)]
    }

    private struct _Style {
        var fg: Color?
        var bg: Color?
    }

    private struct _Ctx {
        let size: _Size
        var clip: _Rect?
        var style: _Style
        var z: Int

        mutating func withClip<T>(_ r: _Rect, _ body: (inout _Ctx) -> T) -> T {
            let prev = clip
            clip = r
            defer { clip = prev }
            return body(&self)
        }
    }

    static func layout(node: _VNode, size: _Size) -> Result {
        var ops: [RenderOp] = []
        var hits: [(_Rect, _ActionID)] = []
        var scrolls: [_ScrollRegion] = []
        var shapes: [(_Rect, _ShapeNode)] = []
        var ctx = _Ctx(size: size, clip: _Rect(origin: _Point(x: 0, y: 0), size: size), style: _Style(fg: nil, bg: nil), z: 0)
        _ = draw(
            node: node,
            origin: _Point(x: 0, y: 0),
            maxSize: size,
            ctx: &ctx,
            ops: &ops,
            hitRegions: &hits,
            scrollRegions: &scrolls,
            shapeRegions: &shapes
        )
        // Stable-ish order: zIndex, then kind rank, then y/x.
        func rank(_ k: RenderOp.Kind) -> Int {
            switch k {
            case .fillRect: return 0
            case .shape: return 1
            case .glyph, .textRun: return 2
            }
        }
        func key(_ op: RenderOp) -> (Int, Int, Int, Int) {
            switch op.kind {
            case .glyph(let x, let y, _, _, _):
                return (op.zIndex, rank(op.kind), y, x)
            case .textRun(let x, let y, _, _, _):
                return (op.zIndex, rank(op.kind), y, x)
            case .fillRect(let r, _):
                return (op.zIndex, rank(op.kind), r.origin.y, r.origin.x)
            case .shape(let r, _):
                return (op.zIndex, rank(op.kind), r.origin.y, r.origin.x)
            }
        }
        ops.sort { key($0) < key($1) }

        // Coalesce adjacent glyphs into text runs to reduce op count and make renderers faster.
        var coalesced: [RenderOp] = []
        coalesced.reserveCapacity(ops.count)
        var i = 0
        while i < ops.count {
            let op = ops[i]
            guard case .glyph(let x0, let y0, let egc0, let fg0, let bg0) = op.kind else {
                coalesced.append(op)
                i += 1
                continue
            }

            var text = egc0
            var x = x0
            var j = i + 1
            while j < ops.count {
                let next = ops[j]
                if next.zIndex != op.zIndex { break }
                guard case .glyph(let nx, let ny, let negc, let nfg, let nbg) = next.kind else { break }
                if ny != y0 { break }
                if nx != x + 1 { break }
                if nfg != fg0 || nbg != bg0 { break }
                // Only coalesce 1-cell glyphs (layout enforces this via sanitization).
                if negc.count != 1 { break }
                text.append(contentsOf: negc)
                x = nx
                j += 1
            }
            if text.count >= 2 {
                coalesced.append(RenderOp(zIndex: op.zIndex, kind: .textRun(x: x0, y: y0, text: text, fg: fg0, bg: bg0)))
                i = j
            } else {
                coalesced.append(op)
                i += 1
            }
        }

        return Result(ops: coalesced, hitRegions: hits, scrollRegions: scrolls, shapeRegions: shapes)
    }

    private static func draw(
        node: _VNode,
        origin: _Point,
        maxSize: _Size,
        ctx: inout _Ctx,
        ops: inout [RenderOp],
        hitRegions: inout [(_Rect, _ActionID)],
        scrollRegions: inout [_ScrollRegion],
        shapeRegions: inout [(_Rect, _ShapeNode)]
    ) -> _Size {
        guard maxSize.width > 0, maxSize.height > 0 else { return _Size(width: 0, height: 0) }

        func inClip(_ p: _Point) -> Bool {
            guard let c = ctx.clip else { return true }
            return c.contains(p)
        }

        func emitGlyph(_ s: String, at p: _Point) {
            guard p.x >= 0, p.y >= 0, p.x < ctx.size.width, p.y < ctx.size.height else { return }
            guard inClip(p) else { return }
            let egc = _sanitizeCell(s)
            ops.append(RenderOp(zIndex: ctx.z, kind: .glyph(x: p.x, y: p.y, egc: egc, fg: ctx.style.fg, bg: ctx.style.bg)))
        }

        func emitText(_ text: String, at p: _Point) {
            var x = p.x
            for ch in text {
                if x >= origin.x + maxSize.width { break }
                emitGlyph(String(ch), at: _Point(x: x, y: p.y))
                x += 1
            }
        }

        func emitFillRect(_ r: _Rect, _ color: Color) {
            ops.append(RenderOp(zIndex: ctx.z, kind: .fillRect(rect: r, color: color)))
        }

        switch node {
        case .empty:
            return _Size(width: 0, height: 0)

        case .style(let fg, let bg, let child):
            let prev = ctx.style
            ctx.style = _Style(fg: fg ?? prev.fg, bg: bg ?? prev.bg)
            defer { ctx.style = prev }
            if let bg = ctx.style.bg {
                emitFillRect(_Rect(origin: origin, size: maxSize), bg)
            }
            return draw(node: child, origin: origin, maxSize: maxSize, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)

        case .background(let child, let background):
            let sz = measure(child, maxSize)
            _ = draw(node: background, origin: origin, maxSize: sz, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
            _ = draw(node: child, origin: origin, maxSize: sz, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
            return sz

        case .overlay(let child, let overlay):
            let sz = draw(node: child, origin: origin, maxSize: maxSize, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
            let prevZ = ctx.z
            ctx.z = prevZ + 1000
            _ = draw(node: overlay, origin: origin, maxSize: sz, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
            ctx.z = prevZ
            return sz

        case .frame(let width, let height, let minWidth, let maxWidth, let minHeight, let maxHeight, let child):
            func clamp(_ v: Int?, _ minV: Int?, _ maxV: Int?) -> Int? {
                guard let v else { return nil }
                var out = v
                if let minV { out = max(minV, out) }
                if let maxV, maxV != Int.max { out = min(maxV, out) }
                return out
            }
            let cw = clamp(width, minWidth, maxWidth)
            let ch = clamp(height, minHeight, maxHeight)
            let targetW: Int = {
                if let cw, cw != Int.max { return min(cw, maxSize.width) }
                if let maxWidth, maxWidth == Int.max { return maxSize.width }
                return maxSize.width
            }()
            let targetH: Int = {
                if let ch, ch != Int.max { return min(ch, maxSize.height) }
                if let maxHeight, maxHeight == Int.max { return maxSize.height }
                return maxSize.height
            }()
            let innerMax = _Size(width: targetW, height: targetH)
            let s = draw(node: child, origin: origin, maxSize: innerMax, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
            let outW = max(minWidth ?? 0, min(s.width, maxSize.width))
            let outH = max(minHeight ?? 0, min(s.height, maxSize.height))
            return _Size(width: outW, height: outH)

        case .edgePadding(let top, let leading, let bottom, let trailing, let child):
            let inner = _Rect(
                origin: _Point(x: origin.x + leading, y: origin.y + top),
                size: _Size(width: max(0, maxSize.width - leading - trailing), height: max(0, maxSize.height - top - bottom))
            )
            let s = draw(node: child, origin: inner.origin, maxSize: inner.size, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
            return _Size(width: min(maxSize.width, s.width + leading + trailing), height: min(maxSize.height, s.height + top + bottom))

        case .tagged(_, let label):
            return draw(node: label, origin: origin, maxSize: maxSize, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)

        case .group(let nodes):
            var used = _Size(width: 0, height: 0)
            for n in nodes {
                let s = draw(node: n, origin: origin, maxSize: maxSize, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
                used.width = max(used.width, s.width)
                used.height = max(used.height, s.height)
            }
            return used

        case .zstack(let children):
            var used = _Size(width: 0, height: 0)
            for n in children {
                let s = draw(node: n, origin: origin, maxSize: maxSize, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
                used.width = max(used.width, s.width)
                used.height = max(used.height, s.height)
            }
            return used

        case .text(let s):
            emitText(s, at: origin)
            return _Size(width: min(s.count, maxSize.width), height: 1)

        case .image(let name):
            let s = _imageString(name)
            emitText(s, at: origin)
            return _Size(width: min(s.count, maxSize.width), height: 1)

        case .shape(let shape):
            // Intrinsic placeholder size unless constrained by a frame.
            let w = min(maxSize.width, 11)
            let h = min(maxSize.height, 5)
            let r = _Rect(origin: origin, size: _Size(width: w, height: h))
            ops.append(RenderOp(zIndex: ctx.z, kind: .shape(rect: r, shape: shape)))
            shapeRegions.append((r, shape))
            return _Size(width: w, height: h)

        case .spacer:
            return _Size(width: 0, height: 0)

        case .stack(let axis, let spacing, let children):
            var cursor = origin
            var used = _Size(width: 0, height: 0)

            let spacerCount = children.reduce(0) { acc, n in
                if case .spacer = n { return acc + 1 }
                return acc
            }
            var fixedPrimary = 0
            var measured: [_Size] = []
            measured.reserveCapacity(children.count)
            for c in children {
                if case .spacer = c {
                    measured.append(_Size(width: 0, height: 0))
                } else {
                    let s = measure(c, maxSize)
                    measured.append(s)
                    switch axis {
                    case .horizontal: fixedPrimary += s.width
                    case .vertical: fixedPrimary += s.height
                    }
                }
            }
            let spacingTotal = max(0, (children.count - 1) * spacing)
            let availablePrimary: Int = (axis == .horizontal) ? maxSize.width : maxSize.height
            let leftover = max(0, availablePrimary - fixedPrimary - spacingTotal)
            let spacerPrimary = spacerCount > 0 ? (leftover / spacerCount) : 0

            for (idx, child) in children.enumerated() {
                let remaining: _Size = (axis == .vertical)
                    ? _Size(width: maxSize.width, height: maxSize.height - (cursor.y - origin.y))
                    : _Size(width: maxSize.width - (cursor.x - origin.x), height: maxSize.height)

                let s: _Size
                if case .spacer = child {
                    s = (axis == .horizontal)
                        ? _Size(width: min(remaining.width, spacerPrimary), height: 0)
                        : _Size(width: 0, height: min(remaining.height, spacerPrimary))
                } else {
                    s = draw(node: child, origin: cursor, maxSize: remaining, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
                }

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
            let x0 = isFocused ? origin.x + 1 : origin.x
            if isFocused { emitGlyph(">", at: origin) }
            emitGlyph("[", at: _Point(x: x0, y: origin.y))
            let labelOrigin = _Point(x: x0 + 2, y: origin.y)
            let labelMax = _Size(width: max(0, maxSize.width - (isFocused ? 5 : 4)), height: 1)
            let labelSize = draw(node: label, origin: labelOrigin, maxSize: labelMax, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
            emitGlyph("]", at: _Point(x: x0 + 1 + labelSize.width + 2, y: origin.y))
            let buttonWidth = min(maxSize.width, (isFocused ? 1 : 0) + 4 + labelSize.width)
            let rect = _Rect(origin: origin, size: _Size(width: buttonWidth, height: 1))
            hitRegions.append((rect, id))
            return _Size(width: buttonWidth, height: 1)

        case .toggle(let id, let isFocused, let isOn, let label):
            let box = isOn ? "[x] " : "[ ] "
            let x0 = isFocused ? origin.x + 1 : origin.x
            if isFocused { emitGlyph(">", at: origin) }
            emitText(box, at: _Point(x: x0, y: origin.y))
            let labelOrigin = _Point(x: x0 + box.count, y: origin.y)
            let labelMax = _Size(width: max(0, maxSize.width - box.count - (isFocused ? 1 : 0)), height: 1)
            let labelSize = draw(node: label, origin: labelOrigin, maxSize: labelMax, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
            let width = min(maxSize.width, (isFocused ? 1 : 0) + box.count + labelSize.width)
            let rect = _Rect(origin: origin, size: _Size(width: width, height: 1))
            hitRegions.append((rect, id))
            return _Size(width: width, height: 1)

        case .textField(let id, let placeholder, let text, let cursor, let isFocused):
            let display = text.isEmpty ? placeholder : text
            let prefix = isFocused ? "> " : "  "
            let cpos = max(0, min(cursor, display.unicodeScalars.count))
            let withCursor: String = {
                guard isFocused else { return display }
                var scalars = Array(display.unicodeScalars)
                scalars.insert("|", at: cpos)
                return String(String.UnicodeScalarView(scalars))
            }()
            let s = prefix + "[" + withCursor + "]"
            emitText(String(s.prefix(maxSize.width)), at: origin)
            let rect = _Rect(origin: origin, size: _Size(width: min(maxSize.width, s.count), height: 1))
            hitRegions.append((rect, id))
            return _Size(width: min(maxSize.width, s.count), height: 1)

        case .scrollView(let id, let path, let isFocused, let axis, let offset, let content):
            // Measure content height in a bounded way (same approach as DebugLayout).
            let measureMax = _Size(width: maxSize.width, height: 2048)
            let contentSize = measure(content, measureMax)

            let viewportHeight: Int = (axis == .vertical) ? min(maxSize.height, max(1, contentSize.height)) : min(maxSize.height, 1)
            let viewportSize = _Size(width: maxSize.width, height: viewportHeight)

            let rect = _Rect(origin: origin, size: viewportSize)
            hitRegions.append((rect, id))

            let maxOffsetY: Int = (axis == .vertical) ? max(0, contentSize.height - viewportHeight) : 0
            scrollRegions.append(_ScrollRegion(rect: rect, path: path, maxOffsetY: maxOffsetY))

            if isFocused { emitGlyph(">", at: origin) }

            let yOff = (axis == .vertical) ? min(max(0, offset), maxOffsetY) : 0

            // Clip and translate.
            let childOrigin = _Point(x: origin.x, y: origin.y - yOff)
            _ = ctx.withClip(rect) { c in
                draw(node: content, origin: childOrigin, maxSize: _Size(width: viewportSize.width, height: viewportSize.height + yOff), ctx: &c, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
            }

            return viewportSize

        case .menu(let id, let isFocused, let isExpanded, let title, let value, let items):
            // Same rendering as DebugLayout, but typed.
            let v = isExpanded ? "^" : "v"
            let headText = "\(title): \(value) \(v)"
            let x0 = isFocused ? origin.x + 1 : origin.x
            if isFocused { emitGlyph(">", at: origin) }
            emitGlyph("[", at: _Point(x: x0, y: origin.y))
            let inner = " " + headText + " "
            let innerClipped = String(inner.prefix(max(0, maxSize.width - (isFocused ? 3 : 2))))
            emitText(innerClipped, at: _Point(x: x0 + 1, y: origin.y))
            let closeX = min(origin.x + maxSize.width - 1, x0 + 1 + innerClipped.count)
            emitGlyph("]", at: _Point(x: closeX, y: origin.y))
            let headWidth = min(maxSize.width, (isFocused ? 1 : 0) + 2 + innerClipped.count)
            hitRegions.append((_Rect(origin: origin, size: _Size(width: headWidth, height: 1)), id))

            if !isExpanded || items.isEmpty || maxSize.height < 3 {
                return _Size(width: headWidth, height: 1)
            }

            // Dropdown overlay above later content.
            let overlayOrigin = _Point(x: x0, y: origin.y + 1)
            let maxLabel = items.map { $0.label.count }.max() ?? 0
            let boxInnerWidth = min(max(8, maxLabel + 4), max(0, maxSize.width - 2))
            let boxWidth = boxInnerWidth + 2

            let prevZ = ctx.z
            ctx.z = prevZ + 1000
            // Top border
            emitGlyph("+", at: overlayOrigin)
            for i in 0..<boxInnerWidth { emitGlyph("-", at: _Point(x: overlayOrigin.x + 1 + i, y: overlayOrigin.y)) }
            emitGlyph("+", at: _Point(x: overlayOrigin.x + boxInnerWidth + 1, y: overlayOrigin.y))

            var usedHeight = 1
            for (i, item) in items.enumerated() {
                let y = overlayOrigin.y + 1 + i
                if y >= origin.y + maxSize.height - 1 { break }
                emitGlyph("|", at: _Point(x: overlayOrigin.x, y: y))
                for x in 0..<boxInnerWidth { emitGlyph(" ", at: _Point(x: overlayOrigin.x + 1 + x, y: y)) }
                emitGlyph("|", at: _Point(x: overlayOrigin.x + boxInnerWidth + 1, y: y))

                let sel = item.isSelected ? "*" : " "
                let foc = item.isFocused ? ">" : " "
                let prefix = "\(foc)\(sel) "
                emitText(prefix, at: _Point(x: overlayOrigin.x + 1, y: y))
                let labelClipped = String(item.label.prefix(max(0, boxInnerWidth - prefix.count)))
                emitText(labelClipped, at: _Point(x: overlayOrigin.x + 1 + prefix.count, y: y))

                let optRect = _Rect(origin: _Point(x: overlayOrigin.x, y: y), size: _Size(width: boxWidth, height: 1))
                hitRegions.append((optRect, item.id))
                usedHeight += 1
            }

            let bottomY = overlayOrigin.y + usedHeight
            if bottomY < origin.y + maxSize.height {
                emitGlyph("+", at: _Point(x: overlayOrigin.x, y: bottomY))
                for i in 0..<boxInnerWidth { emitGlyph("-", at: _Point(x: overlayOrigin.x + 1 + i, y: bottomY)) }
                emitGlyph("+", at: _Point(x: overlayOrigin.x + boxInnerWidth + 1, y: bottomY))
            }
            ctx.z = prevZ

            return _Size(width: headWidth, height: 1)
        }
    }

    private static func measure(_ node: _VNode, _ maxSize: _Size) -> _Size {
        guard maxSize.width > 0, maxSize.height > 0 else { return _Size(width: 0, height: 0) }
        switch node {
        case .empty:
            return _Size(width: 0, height: 0)
        case .style(_, _, let child):
            return measure(child, maxSize)
        case .background(let child, _):
            return measure(child, maxSize)
        case .overlay(let child, _):
            return measure(child, maxSize)
        case .tagged(_, let label):
            return measure(label, maxSize)
        case .frame(_, _, let minWidth, let maxWidth, let minHeight, let maxHeight, let child):
            let s = measure(child, maxSize)
            let w = max(minWidth ?? 0, min(maxSize.width, maxWidth == Int.max ? maxSize.width : min(s.width, maxWidth ?? s.width)))
            let h = max(minHeight ?? 0, min(maxSize.height, maxHeight == Int.max ? maxSize.height : min(s.height, maxHeight ?? s.height)))
            return _Size(width: w, height: h)
        case .edgePadding(let top, let leading, let bottom, let trailing, let child):
            let inner = _Size(width: max(0, maxSize.width - leading - trailing), height: max(0, maxSize.height - top - bottom))
            let s = measure(child, inner)
            return _Size(width: min(maxSize.width, s.width + leading + trailing), height: min(maxSize.height, s.height + top + bottom))
        case .group(let nodes):
            var u = _Size(width: 0, height: 0)
            for n in nodes {
                let s = measure(n, maxSize)
                u.width = max(u.width, s.width)
                u.height = max(u.height, s.height)
            }
            return u
        case .zstack(let children):
            var u = _Size(width: 0, height: 0)
            for n in children {
                let s = measure(n, maxSize)
                u.width = max(u.width, s.width)
                u.height = max(u.height, s.height)
            }
            return u
        case .text(let s):
            return _Size(width: min(s.count, maxSize.width), height: 1)
        case .image(let name):
            let s = _imageString(name)
            return _Size(width: min(s.count, maxSize.width), height: 1)
        case .shape:
            return _Size(width: min(maxSize.width, 11), height: min(maxSize.height, 5))
        case .spacer:
            return _Size(width: 0, height: 0)
        case .stack(let axis, let spacing, let children):
            switch axis {
            case .horizontal:
                var w = 0
                var h = 0
                let count = children.count
                for (i, c) in children.enumerated() {
                    let s = measure(c, maxSize)
                    w += s.width
                    h = max(h, s.height)
                    if i != count - 1 { w += spacing }
                }
                return _Size(width: min(w, maxSize.width), height: min(h, maxSize.height))
            case .vertical:
                var w = 0
                var h = 0
                let count = children.count
                for (i, c) in children.enumerated() {
                    let s = measure(c, maxSize)
                    h += s.height
                    w = max(w, s.width)
                    if i != count - 1 { h += spacing }
                }
                return _Size(width: min(w, maxSize.width), height: min(h, maxSize.height))
            }
        case .button(_, let isFocused, let label):
            let xPad = isFocused ? 1 : 0
            let labelMax = _Size(width: max(0, maxSize.width - (isFocused ? 5 : 4)), height: 1)
            let l = measure(label, labelMax)
            return _Size(width: min(maxSize.width, xPad + 4 + l.width), height: 1)
        case .toggle(_, let isFocused, _, let label):
            let xPad = isFocused ? 1 : 0
            let boxCount = 4
            let labelMax = _Size(width: max(0, maxSize.width - boxCount - xPad), height: 1)
            let l = measure(label, labelMax)
            return _Size(width: min(maxSize.width, xPad + boxCount + l.width), height: 1)
        case .textField(_, let placeholder, let text, _, _):
            let display = text.isEmpty ? placeholder : text
            let prefixCount = 2
            let s = prefixCount + 2 + display.count
            return _Size(width: min(maxSize.width, s), height: 1)
        case .scrollView:
            return _Size(width: maxSize.width, height: maxSize.height)
        case .menu(_, let isFocused, _, let title, let value, _):
            let headText = "\(title): \(value) v"
            let inner = " " + headText + " "
            let w = (isFocused ? 1 : 0) + 2 + min(inner.count, max(0, maxSize.width - (isFocused ? 3 : 2)))
            return _Size(width: min(w, maxSize.width), height: 1)
        }
    }
}

private func _sanitizeCell(_ s: String) -> String {
    // Prevent embedding terminal control sequences (ESC, C0 controls).
    // Layout expects a single printable grapheme; anything else is replaced.
    guard s.count == 1, let scalar = s.unicodeScalars.first else { return "?" }
    let v = scalar.value
    if v == 0x1B { return "?" } // ESC
    if v < 0x20 || v == 0x7F { return "?" }
    return s
}

private func _imageString(_ name: String) -> String {
    switch name {
    case "sparkles": return "✨"
    case "chevron.down": return "▾"
    case "chevron.up": return "▴"
    case "checkmark": return "✓"
    case "xmark": return "✕"
    case "plus": return "+"
    case "minus": return "−"
    case "arrow.up": return "↑"
    case "arrow.down": return "↓"
    case "arrow.left": return "←"
    case "arrow.right": return "→"
    default:
        return "■"
    }
}
