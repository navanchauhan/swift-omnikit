import Foundation

public struct RenderOp: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case glyph(x: Int, y: Int, egc: String, fg: Color?, bg: Color?)
        case textRun(x: Int, y: Int, text: String, fg: Color?, bg: Color?)
        case fillRect(rect: _Rect, color: Color)
        case pushClip(rect: _Rect)
        case popClip
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
        var style: _Style
        var z: Int
    }

    static func layout(node: _VNode, size: _Size) -> Result {
        var ops: [RenderOp] = []
        var hits: [(_Rect, _ActionID)] = []
        var scrolls: [_ScrollRegion] = []
        var shapes: [(_Rect, _ShapeNode)] = []
        var ctx = _Ctx(size: size, style: _Style(fg: nil, bg: nil), z: 0)
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

        // Coalesce adjacent glyphs into text runs to reduce op count, without reordering.
        var out: [RenderOp] = []
        out.reserveCapacity(ops.count)
        var i = 0
        while i < ops.count {
            let op = ops[i]
            guard case .glyph(let x0, let y0, let egc0, let fg0, let bg0) = op.kind else {
                out.append(op)
                i += 1
                continue
            }
            if egc0.count != 1 {
                out.append(op)
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
                if negc.count != 1 { break }
                text.append(contentsOf: negc)
                x = nx
                j += 1
            }
            if text.count >= 2 {
                out.append(RenderOp(zIndex: op.zIndex, kind: .textRun(x: x0, y: y0, text: text, fg: fg0, bg: bg0)))
                i = j
            } else {
                out.append(op)
                i += 1
            }
        }

        return Result(ops: out, hitRegions: hits, scrollRegions: scrolls, shapeRegions: shapes)
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

        func emitGlyph(_ s: String, at p: _Point) {
            guard p.x >= 0, p.y >= 0, p.x < ctx.size.width, p.y < ctx.size.height else { return }
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

        case .contentShapeRect(let child):
            // Rendering is unaffected; this node only influences hit-testing.
            return draw(node: child, origin: origin, maxSize: maxSize, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)

        case .clip(_, let child):
            let sz = measure(child, maxSize)
            let rect = _Rect(origin: origin, size: sz)
            ops.append(RenderOp(zIndex: ctx.z, kind: .pushClip(rect: rect)))
            _ = draw(node: child, origin: origin, maxSize: sz, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
            ops.append(RenderOp(zIndex: ctx.z, kind: .popClip))
            return sz

        case .shadow(let child, let color, let radius, let x, let y):
            // Simple, terminal-friendly shadow/glow: draw the glyphs behind the child at a few offsets.
            guard color.alpha > 0, (radius > 0 || x != 0 || y != 0) else {
                return draw(node: child, origin: origin, maxSize: maxSize, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
            }

            let shadowZ = ctx.z - 1
            let r = min(3, max(0, radius))
            var offsets: [(dx: Int, dy: Int)] = []
            offsets.reserveCapacity((2 * r + 1) * (2 * r + 1))
            if r > 0 {
                for dy in -r...r {
                    for dx in -r...r {
                        if dx == 0 && dy == 0 { continue }
                        if abs(dx) + abs(dy) > r { continue }
                        offsets.append((dx: x + dx, dy: y + dy))
                    }
                }
            } else if x != 0 || y != 0 {
                offsets.append((dx: x, dy: y))
            }

            if !offsets.isEmpty {
                // Render shadow glyphs without hit regions / scroll regions etc.
                var shadowOps: [RenderOp] = []
                shadowOps.reserveCapacity(64)
                var dummyHits: [(_Rect, _ActionID)] = []
                var dummyScrolls: [_ScrollRegion] = []
                var dummyShapes: [(_Rect, _ShapeNode)] = []

                for o in offsets {
                    var shadowCtx = ctx
                    shadowCtx.z = shadowZ
                    _ = draw(
                        node: child,
                        origin: _Point(x: origin.x + o.dx, y: origin.y + o.dy),
                        maxSize: maxSize,
                        ctx: &shadowCtx,
                        ops: &shadowOps,
                        hitRegions: &dummyHits,
                        scrollRegions: &dummyScrolls,
                        shapeRegions: &dummyShapes
                    )
                }

                // Keep only glyph/text ops and override their colors so shadows don't clobber BG fills.
                for op in shadowOps {
                    switch op.kind {
                    case .glyph(let x, let y, let egc, _, _):
                        ops.append(RenderOp(zIndex: shadowZ, kind: .glyph(x: x, y: y, egc: egc, fg: color, bg: nil)))
                    case .textRun(let x, let y, let text, _, _):
                        ops.append(RenderOp(zIndex: shadowZ, kind: .textRun(x: x, y: y, text: text, fg: color, bg: nil)))
                    default:
                        break
                    }
                }
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

            func isFlexibleCandidate(_ node: _VNode) -> Bool {
                switch node {
                case .spacer:
                    return true
                case .scrollView(_, _, _, let scrollAxis, _, _):
                    return scrollAxis == axis
                case .style(_, _, let child):
                    return isFlexibleCandidate(child)
                case .contentShapeRect(let child):
                    return isFlexibleCandidate(child)
                case .clip(_, let child):
                    return isFlexibleCandidate(child)
                case .shadow(let child, _, _, _, _):
                    return isFlexibleCandidate(child)
                case .background(let child, _):
                    return isFlexibleCandidate(child)
                case .overlay(let child, _):
                    return isFlexibleCandidate(child)
                case .tagged(_, let label):
                    return isFlexibleCandidate(label)
                case .edgePadding(_, _, _, _, let child):
                    return isFlexibleCandidate(child)
                case .group(let nodes):
                    return nodes.contains(where: isFlexibleCandidate)
                case .zstack(let nodes):
                    return nodes.contains(where: isFlexibleCandidate)
                case .stack(let childAxis, _, let nodes):
                    guard childAxis == axis else { return false }
                    return nodes.contains(where: isFlexibleCandidate)
                default:
                    return false
                }
            }

            var fixedPrimary = 0
            var measured: [_Size] = []
            var flexible: [Bool] = []
            measured.reserveCapacity(children.count)
            flexible.reserveCapacity(children.count)

            let availablePrimary: Int = (axis == .horizontal) ? maxSize.width : maxSize.height
            for c in children {
                let s = measure(c, maxSize)
                measured.append(s)
                let primary = (axis == .horizontal) ? s.width : s.height

                // Treat explicit flexible nodes (Spacer/ScrollView) as fill-space participants.
                // Also treat "greedy" children as flexible when siblings are present so trailing
                // fixed controls (e.g. toolbars under lists) remain visible.
                let isFlexible = isFlexibleCandidate(c)
                    || (children.count > 1 && primary >= availablePrimary)
                flexible.append(isFlexible)

                if !isFlexible {
                    fixedPrimary += primary
                }
            }
            let spacingTotal = max(0, (children.count - 1) * spacing)
            let leftover = max(0, availablePrimary - fixedPrimary - spacingTotal)
            let flexibleCount = flexible.reduce(0) { $0 + ($1 ? 1 : 0) }
            let flexiblePrimary = flexibleCount > 0 ? (leftover / flexibleCount) : 0
            let flexibleRemainder = flexibleCount > 0 ? (leftover % flexibleCount) : 0
            var seenFlexible = 0

            for (idx, child) in children.enumerated() {
                let remaining: _Size = (axis == .vertical)
                    ? _Size(width: maxSize.width, height: maxSize.height - (cursor.y - origin.y))
                    : _Size(width: maxSize.width - (cursor.x - origin.x), height: maxSize.height)

                let s: _Size
                if flexible[idx] {
                    var allocated = flexiblePrimary
                    if seenFlexible < flexibleRemainder { allocated += 1 }
                    seenFlexible += 1

                    let proposed: _Size = (axis == .horizontal)
                        ? _Size(width: min(remaining.width, allocated), height: remaining.height)
                        : _Size(width: remaining.width, height: min(remaining.height, allocated))

                    if case .spacer = child {
                        s = (axis == .horizontal)
                            ? _Size(width: proposed.width, height: 0)
                            : _Size(width: 0, height: proposed.height)
                    } else {
                        s = draw(
                            node: child,
                            origin: cursor,
                            maxSize: proposed,
                            ctx: &ctx,
                            ops: &ops,
                            hitRegions: &hitRegions,
                            scrollRegions: &scrollRegions,
                            shapeRegions: &shapeRegions
                        )
                    }
                } else {
                    s = draw(
                        node: child,
                        origin: cursor,
                        maxSize: remaining,
                        ctx: &ctx,
                        ops: &ops,
                        hitRegions: &hitRegions,
                        scrollRegions: &scrollRegions,
                        shapeRegions: &shapeRegions
                    )
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
            let wantsFullHitRect = hasContentShapeRect(label)
            let x0 = isFocused ? origin.x + 1 : origin.x
            if isFocused { emitGlyph(">", at: origin) }
            emitGlyph("[", at: _Point(x: x0, y: origin.y))
            let labelOrigin = _Point(x: x0 + 2, y: origin.y)
            let labelMax = _Size(width: max(0, maxSize.width - (isFocused ? 5 : 4)), height: 1)
            let labelSize = draw(node: label, origin: labelOrigin, maxSize: labelMax, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
            emitGlyph("]", at: _Point(x: x0 + 1 + labelSize.width + 2, y: origin.y))
            let buttonWidth = min(maxSize.width, (isFocused ? 1 : 0) + 4 + labelSize.width)
            let hitWidth = wantsFullHitRect ? maxSize.width : buttonWidth
            let rect = _Rect(origin: origin, size: _Size(width: min(maxSize.width, hitWidth), height: 1))
            hitRegions.append((rect, id))
            return _Size(width: buttonWidth, height: 1)

        case .tapTarget(let id, let child):
            let wantsFullHitRect = hasContentShapeRect(child)
            let s = draw(node: child, origin: origin, maxSize: maxSize, ctx: &ctx, ops: &ops, hitRegions: &hitRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions)
            let w = min(maxSize.width, max(1, s.width))
            let h = min(maxSize.height, max(1, s.height))
            let hitWidth = wantsFullHitRect ? maxSize.width : w
            let rect = _Rect(origin: origin, size: _Size(width: min(maxSize.width, hitWidth), height: h))
            hitRegions.append((rect, id))
            return s

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

            // Scroll views should fill the space their parent allocates.
            let viewportHeight: Int = (axis == .vertical) ? maxSize.height : min(maxSize.height, 1)
            let viewportSize = _Size(width: maxSize.width, height: viewportHeight)

            let rect = _Rect(origin: origin, size: viewportSize)
            hitRegions.append((rect, id))

            let maxOffsetY: Int = (axis == .vertical) ? max(0, contentSize.height - viewportHeight) : 0
            scrollRegions.append(_ScrollRegion(rect: rect, path: path, maxOffsetY: maxOffsetY))

            if isFocused { emitGlyph(">", at: origin) }

            let yOff = (axis == .vertical) ? min(max(0, offset), maxOffsetY) : 0

            // Clip and translate (renderer-enforced via ops).
            ops.append(RenderOp(zIndex: ctx.z, kind: .pushClip(rect: rect)))
            let childOrigin = _Point(x: origin.x, y: origin.y - yOff)
            _ = draw(
                node: content,
                origin: childOrigin,
                maxSize: _Size(width: viewportSize.width, height: viewportSize.height + yOff),
                ctx: &ctx,
                ops: &ops,
                hitRegions: &hitRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions
            )
            ops.append(RenderOp(zIndex: ctx.z, kind: .popClip))

            return viewportSize

        case .menu(let id, let isFocused, let isExpanded, let title, let value, let items):
            // Same rendering as DebugLayout, but typed.
            let v = isExpanded ? "^" : "v"
            let headText = title.isEmpty ? "\(value) \(v)" : "\(title): \(value) \(v)"
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

        case .divider:
            let line = String(repeating: "─", count: max(0, maxSize.width))
            emitText(line, at: origin)
            return _Size(width: maxSize.width, height: 1)
        }
    }

    private static func hasContentShapeRect(_ node: _VNode) -> Bool {
        switch node {
        case .contentShapeRect:
            return true
        case .style(_, _, let child):
            return hasContentShapeRect(child)
        case .background(let child, let bg):
            return hasContentShapeRect(child) || hasContentShapeRect(bg)
        case .overlay(let child, let ov):
            return hasContentShapeRect(child) || hasContentShapeRect(ov)
        case .frame(_, _, _, _, _, _, let child):
            return hasContentShapeRect(child)
        case .edgePadding(_, _, _, _, let child):
            return hasContentShapeRect(child)
        case .tagged(_, let label):
            return hasContentShapeRect(label)
        case .shadow(let child, _, _, _, _):
            return hasContentShapeRect(child)
        case .clip(_, let child):
            return hasContentShapeRect(child)
        case .group(let nodes):
            return nodes.contains(where: hasContentShapeRect)
        case .stack(_, _, let children):
            return children.contains(where: hasContentShapeRect)
        case .zstack(let children):
            return children.contains(where: hasContentShapeRect)
        default:
            return false
        }
    }

    private static func measure(_ node: _VNode, _ maxSize: _Size) -> _Size {
        guard maxSize.width > 0, maxSize.height > 0 else { return _Size(width: 0, height: 0) }
        switch node {
        case .empty:
            return _Size(width: 0, height: 0)
        case .style(_, _, let child):
            return measure(child, maxSize)
        case .contentShapeRect(let child):
            return measure(child, maxSize)
        case .clip(_, let child):
            return measure(child, maxSize)
        case .shadow(let child, _, _, _, _):
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
        case .tapTarget(_, let child):
            return measure(child, maxSize)
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
            let headText = title.isEmpty ? "\(value) v" : "\(title): \(value) v"
            let inner = " " + headText + " "
            let w = (isFocused ? 1 : 0) + 2 + min(inner.count, max(0, maxSize.width - (isFocused ? 3 : 2)))
            return _Size(width: min(w, maxSize.width), height: 1)
        case .divider:
            return _Size(width: maxSize.width, height: 1)
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
