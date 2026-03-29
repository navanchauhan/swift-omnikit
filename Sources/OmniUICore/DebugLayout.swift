/// Extremely small "renderer" used for snapshot testing and interactive simulation.
///
/// This is intentionally simplistic (monospace terminal grid) but provides:
/// - deterministic plaintext output
/// - hit testing for `Button`
enum _DebugLayout {
    struct _CanvasCell {
        var ch: String
        var fg: Color?
        var bg: Color?
    }

    struct Overlay {
        var zIndex: Int
        var draw: (_ canvas: inout [[_CanvasCell]], _ hitRegions: inout [(_Rect, _ActionID)], _ hoverRegions: inout [(_Rect, _HoverID)], _ scrollRegions: inout [_ScrollRegion]) -> Void
    }

    struct Result {
        var lines: [String]
        var cells: [String]
        var styledCells: [StyledCell]
        var hitRegions: [(_Rect, _ActionID)]
        var hoverRegions: [(_Rect, _HoverID)]
        var scrollRegions: [_ScrollRegion]
        var scrollTargets: [_ScrollTarget]
        var shapeRegions: [(_Rect, _ShapeNode)]
    }

    private struct _DebugScrollContext {
        let path: [Int]
        let contentOriginY: Int
        let viewportHeight: Int
        let maxOffsetY: Int
    }

    static func layout(node: _VNode, in rect: _Rect, renderShapeGlyphs: Bool = true) -> Result {
        var canvas = Array(
            repeating: Array(repeating: _CanvasCell(ch: " ", fg: nil, bg: nil), count: rect.size.width),
            count: rect.size.height
        )
        var hits: [(_Rect, _ActionID)] = []
        var hovers: [(_Rect, _HoverID)] = []
        var scrolls: [_ScrollRegion] = []
        var shapes: [(_Rect, _ShapeNode)] = []
        var overlays: [Overlay] = []
        _ = draw(
            node: node,
            origin: rect.origin,
            maxSize: rect.size,
            canvas: &canvas,
            hitRegions: &hits,
            hoverRegions: &hovers,
            scrollRegions: &scrolls,
            shapeRegions: &shapes,
            renderShapeGlyphs: renderShapeGlyphs,
            overlays: &overlays,
            style: (fg: nil, bg: nil)
        )

        // Draw overlays last so they appear "above" later siblings in stacks.
        for o in overlays.sorted(by: { $0.zIndex < $1.zIndex }) {
            o.draw(&canvas, &hits, &hovers, &scrolls)
        }

        let lines = canvas.map { $0.map(\.ch).joined() }
        let cells = canvas.flatMap { $0.map(\.ch) }
        let styledCells = canvas.flatMap { row in row.map { StyledCell(egc: $0.ch, fg: $0.fg, bg: $0.bg) } }
        var scrollTargets: [_ScrollTarget] = []
        _ = collectScrollTargets(node: node, origin: rect.origin, maxSize: rect.size, targets: &scrollTargets)
        return Result(
            lines: lines,
            cells: cells,
            styledCells: styledCells,
            hitRegions: hits,
            hoverRegions: hovers,
            scrollRegions: scrolls,
            scrollTargets: scrollTargets,
            shapeRegions: shapes
        )
    }

    private static func imageString(_ name: String) -> String {
        _terminalSymbolString(name)
    }

    private static func hasContentShapeRect(_ node: _VNode) -> Bool {
        switch node {
        case .contentShapeRect:
            return true
        case .style(_, _, let child):
            return hasContentShapeRect(child)
        case .offset(_, _, let child):
            return hasContentShapeRect(child)
        case .opacity(_, let child):
            return hasContentShapeRect(child)
        case .background(let child, let bg):
            return hasContentShapeRect(child) || hasContentShapeRect(bg)
        case .overlay(let child, let ov):
            return hasContentShapeRect(child) || hasContentShapeRect(ov)
        case .modalOverlay(_, _, _, let child):
            return hasContentShapeRect(child)
        case .frame(_, _, _, _, _, _, let child):
            return hasContentShapeRect(child)
        case .edgePadding(_, _, _, _, let child):
            return hasContentShapeRect(child)
        case .identified(_, _, let child):
            return hasContentShapeRect(child)
        case .onDelete(_, _, let child):
            return hasContentShapeRect(child)
        case .tagged(_, let label):
            return hasContentShapeRect(label)
        case .shadow(let child, _, _, _, _):
            return hasContentShapeRect(child)
        case .hover(_, let child):
            return hasContentShapeRect(child)
        case .clip(_, let child):
            return hasContentShapeRect(child)
        case .gestureTarget(_, let child):
            return hasContentShapeRect(child)
        case .fixedSize(_, _, let child):
            return hasContentShapeRect(child)
        case .layoutPriority(_, let child):
            return hasContentShapeRect(child)
        case .alignmentGuide(_, _, let child):
            return hasContentShapeRect(child)
        case .preferenceNode(_, let child):
            return hasContentShapeRect(child)
        case .rotationEffect(_, let child):
            return hasContentShapeRect(child)
        case .aspectRatio(_, _, let child):
            return hasContentShapeRect(child)
        case .swipeActions(_, _, _, let child):
            return hasContentShapeRect(child)
        case .textCase(_, let child): return hasContentShapeRect(child)
        case .blur(_, let child): return hasContentShapeRect(child)
        case .badge(_, let child): return hasContentShapeRect(child)
        case .anchorPreference(_, _, _, let child): return hasContentShapeRect(child)
        case .geometryReaderProxy(_, let child): return hasContentShapeRect(child)
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

    private static func measureNode(_ node: _VNode, _ maxSize: _Size) -> _Size {
        guard maxSize.width > 0, maxSize.height > 0 else { return _Size(width: 0, height: 0) }
        switch node {
        case .empty:
            return _Size(width: 0, height: 0)
        case .textStyled(_, let child),
             .style(_, _, let child),
             .offset(_, _, let child),
             .opacity(_, let child),
             .contentShapeRect(_, let child),
             .clip(_, let child),
             .shadow(let child, _, _, _, _),
             .background(let child, _),
             .overlay(let child, _),
             .elevated(_, let child),
             .identified(_, _, let child),
             .onDelete(_, _, let child),
             .gestureTarget(_, let child),
             .hover(_, let child),
             .fixedSize(_, _, let child),
             .layoutPriority(_, let child),
             .alignmentGuide(_, _, let child),
             .preferenceNode(_, let child),
             .rotationEffect(_, let child),
             .aspectRatio(_, _, let child),
             .swipeActions(_, _, _, let child),
             .textCase(_, let child),
             .blur(_, let child),
             .badge(_, let child),
             .anchorPreference(_, _, _, let child),
             .geometryReaderProxy(_, let child):
            return measureNode(child, maxSize)
        case .modalOverlay:
            return maxSize
        case .tagged(_, let label):
            return measureNode(label, maxSize)
        case .frame(_, _, let minWidth, let maxWidth, let minHeight, let maxHeight, let child):
            let childSize = measureNode(child, maxSize)
            let width = max(minWidth ?? 0, min(maxSize.width, maxWidth == Int.max ? maxSize.width : min(childSize.width, maxWidth ?? childSize.width)))
            let height = max(minHeight ?? 0, min(maxSize.height, maxHeight == Int.max ? maxSize.height : min(childSize.height, maxHeight ?? childSize.height)))
            return _Size(width: width, height: height)
        case .edgePadding(let top, let leading, let bottom, let trailing, let child):
            let inner = _Size(width: max(0, maxSize.width - leading - trailing), height: max(0, maxSize.height - top - bottom))
            let childSize = measureNode(child, inner)
            return _Size(
                width: min(maxSize.width, childSize.width + leading + trailing),
                height: min(maxSize.height, childSize.height + top + bottom)
            )
        case .group(let nodes), .zstack(let nodes):
            var size = _Size(width: 0, height: 0)
            for child in nodes {
                let childSize = measureNode(child, maxSize)
                size.width = max(size.width, childSize.width)
                size.height = max(size.height, childSize.height)
            }
            return size
        case .stack(let axis, let spacing, let children):
            switch axis {
            case .horizontal:
                var width = 0
                var height = 0
                for (index, child) in children.enumerated() {
                    let childSize = measureNode(child, maxSize)
                    width += childSize.width
                    height = max(height, childSize.height)
                    if index != children.count - 1 { width += spacing }
                }
                return _Size(width: min(width, maxSize.width), height: min(height, maxSize.height))
            case .vertical:
                var width = 0
                var height = 0
                for (index, child) in children.enumerated() {
                    let childSize = measureNode(child, maxSize)
                    width = max(width, childSize.width)
                    height += childSize.height
                    if index != children.count - 1 { height += spacing }
                }
                return _Size(width: min(width, maxSize.width), height: min(height, maxSize.height))
            }
        case .text(let text):
            return _Size(width: min(text.count, maxSize.width), height: 1)
        case .styledText(let segments):
            let width = segments.reduce(0) { $0 + $1.content.count }
            return _Size(width: min(width, maxSize.width), height: 1)
        case .image(let name):
            return _Size(width: min(imageString(name).count, maxSize.width), height: 1)
        case .gradient:
            return maxSize
        case .shape:
            return _Size(width: min(maxSize.width, max(10, maxSize.width)), height: min(maxSize.height, 4))
        case .spacer:
            return _Size(width: 0, height: 0)
        case .button(_, let isFocused, let label):
            let labelSize = measureNode(label, _Size(width: max(0, maxSize.width - (isFocused ? 5 : 4)), height: 1))
            return _Size(width: min(maxSize.width, (isFocused ? 1 : 0) + 4 + labelSize.width), height: 1)
        case .tapTarget(_, let child):
            return measureNode(child, maxSize)
        case .toggle(_, let isFocused, _, let label):
            let labelSize = measureNode(label, _Size(width: max(0, maxSize.width - (isFocused ? 5 : 4)), height: 1))
            return _Size(width: min(maxSize.width, (isFocused ? 1 : 0) + 4 + labelSize.width), height: 1)
        case .textField(_, let placeholder, let text, _, _, let style):
            let display = text.isEmpty ? placeholder : text
            let width = 2 + (style == .plain ? 0 : 2) + display.count
            return _Size(width: min(maxSize.width, width), height: 1)
        case .scrollView(_, _, _, _, _, let content):
            let contentSize = measureNode(content, _Size(width: maxSize.width, height: 2048))
            return _Size(width: min(maxSize.width, contentSize.width), height: min(maxSize.height, contentSize.height))
        case .menu(_, let isFocused, _, let title, let value, _):
            let headText = title.isEmpty ? "\(value) v" : "\(title): \(value) v"
            let inner = " " + headText + " "
            let width = (isFocused ? 1 : 0) + 2 + min(inner.count, max(0, maxSize.width - (isFocused ? 3 : 2)))
            return _Size(width: min(width, maxSize.width), height: 1)
        case .divider:
            return _Size(width: maxSize.width, height: 1)
        case .viewThatFits(_, let children):
            return children.first.map { measureNode($0, maxSize) } ?? _Size(width: 0, height: 0)
        case .truncatedText(let text, _):
            return _Size(width: min(text.count, maxSize.width), height: 1)
        }
    }

    private static func collectScrollTargets(
        node: _VNode,
        origin: _Point,
        maxSize: _Size,
        scrollContext: [_DebugScrollContext] = [],
        targets: inout [_ScrollTarget]
    ) -> _Size {
        guard maxSize.width > 0, maxSize.height > 0 else { return _Size(width: 0, height: 0) }

        func isFlexibleCandidate(_ node: _VNode, axis: _Axis) -> Bool {
            switch node {
            case .spacer:
                return true
            case .shape:
                return true
            case .textField:
                return true
            case .frame(_, _, _, let maxWidth, _, _, let child):
                if maxWidth == Int.max { return true }
                return isFlexibleCandidate(child, axis: axis)
            case .scrollView(_, _, _, let scrollAxis, _, _):
                return scrollAxis == axis
            case .style(_, _, let child),
                 .textStyled(_, let child),
                 .offset(_, _, let child),
                 .opacity(_, let child),
                 .contentShapeRect(_, let child),
                 .clip(_, let child),
                 .shadow(let child, _, _, _, _),
                 .hover(_, let child),
                 .elevated(_, let child),
                 .identified(_, _, let child),
                 .onDelete(_, _, let child),
                 .gestureTarget(_, let child),
                 .fixedSize(_, _, let child),
                 .layoutPriority(_, let child),
                 .alignmentGuide(_, _, let child),
                 .preferenceNode(_, let child),
                 .rotationEffect(_, let child),
                 .aspectRatio(_, _, let child),
                 .swipeActions(_, _, _, let child),
                 .textCase(_, let child),
                 .blur(_, let child),
                 .badge(_, let child),
                 .anchorPreference(_, _, _, let child),
                 .geometryReaderProxy(_, let child):
                return isFlexibleCandidate(child, axis: axis)
            case .background(let child, let background):
                return isFlexibleCandidate(child, axis: axis) || isFlexibleCandidate(background, axis: axis)
            case .overlay(let child, let overlay):
                return isFlexibleCandidate(child, axis: axis) || isFlexibleCandidate(overlay, axis: axis)
            case .modalOverlay(_, _, _, let child):
                return isFlexibleCandidate(child, axis: axis)
            case .tagged(_, let label):
                return isFlexibleCandidate(label, axis: axis)
            case .edgePadding(_, _, _, _, let child):
                return isFlexibleCandidate(child, axis: axis)
            case .group(let nodes), .zstack(let nodes):
                return nodes.contains { isFlexibleCandidate($0, axis: axis) }
            case .stack(let childAxis, _, let nodes):
                guard childAxis == axis else { return false }
                return nodes.contains { isFlexibleCandidate($0, axis: axis) }
            default:
                return false
            }
        }

        switch node {
        case .empty:
            return _Size(width: 0, height: 0)
        case .style(_, _, let child),
             .textStyled(_, let child),
             .offset(_, _, let child),
             .opacity(_, let child),
             .contentShapeRect(_, let child),
             .clip(_, let child),
             .shadow(let child, _, _, _, _),
             .hover(_, let child),
             .elevated(_, let child),
             .onDelete(_, _, let child),
             .gestureTarget(_, let child),
             .fixedSize(_, _, let child),
             .layoutPriority(_, let child),
             .alignmentGuide(_, _, let child),
             .preferenceNode(_, let child),
             .rotationEffect(_, let child),
             .aspectRatio(_, _, let child),
             .swipeActions(_, _, _, let child),
             .textCase(_, let child),
             .blur(_, let child),
             .badge(_, let child),
             .anchorPreference(_, _, _, let child),
             .geometryReaderProxy(_, let child):
            return collectScrollTargets(
                node: child,
                origin: origin,
                maxSize: maxSize,
                scrollContext: scrollContext,
                targets: &targets
            )
        case .background(let child, let background):
            _ = collectScrollTargets(
                node: background,
                origin: origin,
                maxSize: maxSize,
                scrollContext: scrollContext,
                targets: &targets
            )
            return collectScrollTargets(
                node: child,
                origin: origin,
                maxSize: maxSize,
                scrollContext: scrollContext,
                targets: &targets
            )
        case .overlay(let child, let overlay):
            let base = collectScrollTargets(
                node: child,
                origin: origin,
                maxSize: maxSize,
                scrollContext: scrollContext,
                targets: &targets
            )
            _ = collectScrollTargets(
                node: overlay,
                origin: origin,
                maxSize: base,
                scrollContext: scrollContext,
                targets: &targets
            )
            return base
        case .modalOverlay(_, let maxWidth, let maxHeight, let child):
            let panelWidth = min(maxSize.width, max(1, maxWidth))
            let panelMaxHeight = min(maxSize.height, max(1, maxHeight ?? maxSize.height))
            let panelProposal = _Size(width: panelWidth, height: panelMaxHeight)
            let measured = measureNode(child, panelProposal)
            let panelSize = _Size(width: panelWidth, height: max(1, min(panelProposal.height, measured.height)))
            let panelOrigin = _Point(
                x: origin.x + max(0, (maxSize.width - panelSize.width) / 2),
                y: origin.y + max(0, (maxSize.height - panelSize.height) / 2)
            )
            _ = collectScrollTargets(
                node: child,
                origin: panelOrigin,
                maxSize: panelSize,
                scrollContext: scrollContext,
                targets: &targets
            )
            return maxSize
        case .identified(let id, let readerScopePath, let child):
            let size = collectScrollTargets(
                node: child,
                origin: origin,
                maxSize: maxSize,
                scrollContext: scrollContext,
                targets: &targets
            )
            if let owner = scrollContext.last {
                let targetMinY = max(0, origin.y - owner.contentOriginY)
                targets.append(
                    _ScrollTarget(
                        id: id,
                        readerScopePath: readerScopePath,
                        scrollPath: owner.path,
                        minY: targetMinY,
                        height: max(1, size.height),
                        viewportHeight: owner.viewportHeight,
                        maxOffsetY: owner.maxOffsetY
                    )
                )
            }
            return size
        case .tagged(_, let label):
            return collectScrollTargets(
                node: label,
                origin: origin,
                maxSize: maxSize,
                scrollContext: scrollContext,
                targets: &targets
            )
        case .frame(_, _, let minWidth, let maxWidth, let minHeight, let maxHeight, let child):
            let targetW: Int = {
                if let maxWidth, maxWidth == Int.max { return maxSize.width }
                return maxSize.width
            }()
            let targetH: Int = {
                if let maxHeight, maxHeight == Int.max { return maxSize.height }
                return maxSize.height
            }()
            let innerMax = _Size(width: targetW, height: targetH)
            let childSize = collectScrollTargets(
                node: child,
                origin: origin,
                maxSize: innerMax,
                scrollContext: scrollContext,
                targets: &targets
            )
            let width = max(minWidth ?? 0, min(maxSize.width, maxWidth == Int.max ? maxSize.width : min(childSize.width, maxWidth ?? childSize.width)))
            let height = max(minHeight ?? 0, min(maxSize.height, maxHeight == Int.max ? maxSize.height : min(childSize.height, maxHeight ?? childSize.height)))
            return _Size(width: width, height: height)
        case .edgePadding(let top, let leading, let bottom, let trailing, let child):
            let inner = _Rect(
                origin: _Point(x: origin.x + leading, y: origin.y + top),
                size: _Size(
                    width: max(0, maxSize.width - leading - trailing),
                    height: max(0, maxSize.height - top - bottom)
                )
            )
            let size = collectScrollTargets(
                node: child,
                origin: inner.origin,
                maxSize: inner.size,
                scrollContext: scrollContext,
                targets: &targets
            )
            return _Size(
                width: min(maxSize.width, size.width + leading + trailing),
                height: min(maxSize.height, size.height + top + bottom)
            )
        case .group(let nodes), .zstack(let nodes):
            var used = _Size(width: 0, height: 0)
            for child in nodes {
                let size = collectScrollTargets(
                    node: child,
                    origin: origin,
                    maxSize: maxSize,
                    scrollContext: scrollContext,
                    targets: &targets
                )
                used.width = max(used.width, size.width)
                used.height = max(used.height, size.height)
            }
            return used
        case .stack(let axis, let spacing, let children):
            var cursor = origin
            var used = _Size(width: 0, height: 0)
            let availablePrimary = axis == .horizontal ? maxSize.width : maxSize.height

            var fixedPrimary = 0
            var measured: [_Size] = []
            var flexible: [Bool] = []
            measured.reserveCapacity(children.count)
            flexible.reserveCapacity(children.count)

            for child in children {
                let size = measureNode(child, maxSize)
                measured.append(size)
                let primary = axis == .horizontal ? size.width : size.height
                let childIsFlexible = isFlexibleCandidate(child, axis: axis)
                    || (children.count > 1 && primary >= availablePrimary)
                flexible.append(childIsFlexible)
                if !childIsFlexible {
                    fixedPrimary += primary
                }
            }

            let spacingTotal = max(0, (children.count - 1) * spacing)
            let leftover = max(0, availablePrimary - fixedPrimary - spacingTotal)
            let flexibleCount = flexible.reduce(0) { $0 + ($1 ? 1 : 0) }
            var flexAllocations = [Int](repeating: 0, count: children.count)
            if flexibleCount > 0 {
                let equalShare = leftover / flexibleCount
                var surplus = leftover % flexibleCount
                var greedyIndices: [Int] = []
                for idx in 0..<children.count where flexible[idx] {
                    let measuredPrimary = axis == .horizontal ? measured[idx].width : measured[idx].height
                    if case .spacer = children[idx] {
                        flexAllocations[idx] = equalShare
                        greedyIndices.append(idx)
                    } else if measuredPrimary < equalShare {
                        flexAllocations[idx] = measuredPrimary
                        surplus += (equalShare - measuredPrimary)
                    } else {
                        flexAllocations[idx] = equalShare
                        greedyIndices.append(idx)
                    }
                }
                if !greedyIndices.isEmpty {
                    let extra = surplus / greedyIndices.count
                    let extraRem = surplus % greedyIndices.count
                    for (index, greedyIndex) in greedyIndices.enumerated() {
                        flexAllocations[greedyIndex] += extra + (index < extraRem ? 1 : 0)
                    }
                }
            }

            for (idx, child) in children.enumerated() {
                let remaining = axis == .vertical
                    ? _Size(width: maxSize.width, height: maxSize.height - (cursor.y - origin.y))
                    : _Size(width: maxSize.width - (cursor.x - origin.x), height: maxSize.height)
                guard remaining.width > 0, remaining.height > 0 else { break }

                let size: _Size
                if flexible[idx] {
                    let allocated = flexAllocations[idx]
                    let proposed = axis == .horizontal
                        ? _Size(width: min(remaining.width, allocated), height: remaining.height)
                        : _Size(width: remaining.width, height: min(remaining.height, allocated))
                    if case .spacer = child {
                        size = axis == .horizontal
                            ? _Size(width: proposed.width, height: 0)
                            : _Size(width: 0, height: proposed.height)
                    } else {
                        size = collectScrollTargets(
                            node: child,
                            origin: cursor,
                            maxSize: proposed,
                            scrollContext: scrollContext,
                            targets: &targets
                        )
                    }
                } else {
                    let measuredChild = measureNode(child, remaining)
                    let constrained = axis == .vertical
                        ? _Size(width: remaining.width, height: min(remaining.height, measuredChild.height))
                        : _Size(width: min(remaining.width, measuredChild.width), height: remaining.height)
                    size = collectScrollTargets(
                        node: child,
                        origin: cursor,
                        maxSize: constrained,
                        scrollContext: scrollContext,
                        targets: &targets
                    )
                }

                switch axis {
                case .vertical:
                    cursor.y += size.height
                    if idx != children.count - 1 { cursor.y += spacing }
                    used.width = max(used.width, size.width)
                    used.height = cursor.y - origin.y
                case .horizontal:
                    cursor.x += size.width
                    if idx != children.count - 1 { cursor.x += spacing }
                    used.width = cursor.x - origin.x
                    used.height = max(used.height, size.height)
                }
            }

            used.width = min(used.width, maxSize.width)
            used.height = min(used.height, maxSize.height)
            return used
        case .scrollView(_, let path, _, let axis, let offset, let content):
            let measureMax: _Size = axis == .horizontal
                ? _Size(width: 4096, height: maxSize.height)
                : _Size(width: maxSize.width, height: 2048)
            let contentSize = measureNode(content, measureMax)
            let viewportHeight = axis == .vertical ? maxSize.height : min(maxSize.height, contentSize.height)
            let viewportWidth = maxSize.width
            let maxOffsetY = axis == .vertical ? max(0, contentSize.height - viewportHeight) : 0
            let maxOffsetX = axis == .horizontal ? max(0, contentSize.width - viewportWidth) : 0
            let yOff = axis == .vertical ? min(max(0, offset), maxOffsetY) : 0
            let xOff = axis == .horizontal ? min(max(0, offset), maxOffsetX) : 0
            let childOrigin = _Point(x: origin.x - xOff, y: origin.y - yOff)
            var nextScrollContext = scrollContext
            nextScrollContext.append(
                _DebugScrollContext(
                    path: path,
                    contentOriginY: childOrigin.y,
                    viewportHeight: viewportHeight,
                    maxOffsetY: maxOffsetY
                )
            )
            _ = collectScrollTargets(
                node: content,
                origin: childOrigin,
                maxSize: _Size(
                    width: max(viewportWidth + xOff, contentSize.width),
                    height: max(viewportHeight + yOff, contentSize.height)
                ),
                scrollContext: nextScrollContext,
                targets: &targets
            )
            return _Size(width: viewportWidth, height: viewportHeight)
        default:
            return measureNode(node, maxSize)
        }
    }

    @discardableResult
    private static func draw(
        node: _VNode,
        origin: _Point,
        maxSize: _Size,
        canvas: inout [[_CanvasCell]],
        hitRegions: inout [(_Rect, _ActionID)],
        hoverRegions: inout [(_Rect, _HoverID)],
        scrollRegions: inout [_ScrollRegion],
        shapeRegions: inout [(_Rect, _ShapeNode)],
        renderShapeGlyphs: Bool,
        overlays: inout [Overlay],
        style: (fg: Color?, bg: Color?) = (nil, nil)
    ) -> _Size {
        guard maxSize.width > 0, maxSize.height > 0 else { return _Size(width: 0, height: 0) }

        switch node {
        case .empty:
            return _Size(width: 0, height: 0)

        case .textStyled(_, let child):
            // Text styles don't affect the debug layout — just recurse.
            return draw(
                node: child, origin: origin, maxSize: maxSize,
                canvas: &canvas, hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions, shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays, style: style
            )

        case .style(_, _, let child):
            // Merge local style into the inherited style.
            // We model bg as a simple rect fill across the current available area.
            // This is not SwiftUI-perfect, but it enables `.background(Color)` for TUI.
            let fg = {
                if case .style(let fg, _, _) = node { return fg }
                return nil
            }()
            let bg = {
                if case .style(_, let bg, _) = node { return bg }
                return nil
            }()
            let merged: (fg: Color?, bg: Color?) = (fg: fg ?? style.fg, bg: bg ?? style.bg)

            if let bg = merged.bg {
                let x0 = max(0, origin.x)
                let y0 = max(0, origin.y)
                let x1 = min(canvas.first?.count ?? 0, origin.x + maxSize.width)
                let y1 = min(canvas.count, origin.y + maxSize.height)
                if x1 > x0, y1 > y0 {
                    for y in y0..<y1 {
                        for x in x0..<x1 {
                            canvas[y][x].bg = bg
                        }
                    }
                }
            }

            return draw(
                node: child,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: merged
            )

        case .gradient(let gradient):
            let first = gradient.colors.first ?? .secondary
            let last = gradient.colors.last ?? first
            let horizontal: Bool = {
                switch gradient.kind {
                case .linear(let startPoint, let endPoint):
                    return abs(endPoint.x - startPoint.x) >= abs(endPoint.y - startPoint.y)
                case .radial:
                    return false
                }
            }()
            if horizontal {
                for x in 0..<maxSize.width {
                    let color = x < maxSize.width / 2 ? first : last
                    for y in 0..<maxSize.height {
                        let px = origin.x + x
                        let py = origin.y + y
                        guard py >= 0, py < canvas.count, px >= 0, px < (canvas.first?.count ?? 0) else { continue }
                        canvas[py][px].bg = color
                    }
                }
            } else {
                for y in 0..<maxSize.height {
                    let color = y < maxSize.height / 2 ? first : last
                    for x in 0..<maxSize.width {
                        let px = origin.x + x
                        let py = origin.y + y
                        guard py >= 0, py < canvas.count, px >= 0, px < (canvas.first?.count ?? 0) else { continue }
                        canvas[py][px].bg = color
                    }
                }
            }
            return maxSize

        case .offset(let x, let y, let child):
            return draw(
                node: child,
                origin: _Point(x: origin.x + x, y: origin.y + y),
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )

        case .opacity(_, let child):
            return draw(
                node: child,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )

        case .hover(let id, let child):
            let s = draw(
                node: child,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )
            let rect = _Rect(origin: origin, size: _Size(width: min(maxSize.width, max(1, s.width)), height: min(maxSize.height, max(1, s.height))))
            hoverRegions.append((rect, id))
            return s

        case .contentShapeRect(_, let child):
            // Rendering is unaffected; this node only influences hit-testing.
            return draw(
                node: child,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )

        case .clip(_, let child):
            // Debug renderer doesn't implement non-rectangular clipping; treat as a passthrough.
            return draw(
                node: child,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )

        case .shadow(let child, _, _, _, _):
            // Debug renderer: ignore shadow, but keep the child.
            return draw(
                node: child,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )

        case .background(let child, let background):
            _ = draw(
                node: background,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )
            return draw(
                node: child,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )

        case .overlay(let child, let overlay):
            let base = draw(
                node: child,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )
            _ = draw(
                node: overlay,
                origin: origin,
                maxSize: base,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )
            return base

        case .elevated(_, let child):
            return draw(
                node: child,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )

        case .modalOverlay(let scrim, let maxWidth, let maxHeight, let child):
            if let scrim {
                let x0 = max(0, origin.x)
                let y0 = max(0, origin.y)
                let x1 = min(canvas.first?.count ?? 0, origin.x + maxSize.width)
                let y1 = min(canvas.count, origin.y + maxSize.height)
                if x1 > x0, y1 > y0 {
                    for y in y0..<y1 {
                        for x in x0..<x1 {
                            canvas[y][x].bg = scrim
                        }
                    }
                }
            }
            let panelWidth = min(maxSize.width, max(1, maxWidth))
            let panelMaxHeight = min(maxSize.height, max(1, maxHeight ?? maxSize.height))
            let panelProposal = _Size(width: panelWidth, height: panelMaxHeight)
            let measured = measureNode(child, panelProposal)
            let panelSize = _Size(width: panelWidth, height: max(1, min(panelProposal.height, measured.height)))
            let panelOrigin = _Point(
                x: origin.x + max(0, (maxSize.width - panelSize.width) / 2),
                y: origin.y + max(0, (maxSize.height - panelSize.height) / 2)
            )
            _ = draw(
                node: child,
                origin: panelOrigin,
                maxSize: panelSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )
            return maxSize

        case .identified(_, _, let child):
            return draw(
                node: child,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )

        case .onDelete(_, _, let child):
            return draw(
                node: child,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )

        case .tagged(_, let label):
            return draw(
                node: label,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )

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
            let s = draw(
                node: child,
                origin: origin,
                maxSize: innerMax,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )
            // Enforce min sizes if specified.
            let outW = max(minWidth ?? 0, min(s.width, maxSize.width))
            let outH = max(minHeight ?? 0, min(s.height, maxSize.height))
            return _Size(width: outW, height: outH)

        case .edgePadding(let top, let leading, let bottom, let trailing, let child):
            let inner = _Rect(
                origin: _Point(x: origin.x + leading, y: origin.y + top),
                size: _Size(
                    width: max(0, maxSize.width - leading - trailing),
                    height: max(0, maxSize.height - top - bottom)
                )
            )
            let s = draw(
                node: child,
                origin: inner.origin,
                maxSize: inner.size,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )
            return _Size(
                width: min(maxSize.width, s.width + leading + trailing),
                height: min(maxSize.height, s.height + top + bottom)
            )

        case .group(let nodes):
            var used = _Size(width: 0, height: 0)
            for n in nodes {
                // Groups are drawn on top of each other; callers should flatten for layout.
                let s = draw(
                    node: n,
                    origin: origin,
                    maxSize: maxSize,
                    canvas: &canvas,
                    hitRegions: &hitRegions,
                    hoverRegions: &hoverRegions,
                    scrollRegions: &scrollRegions,
                    shapeRegions: &shapeRegions,
                    renderShapeGlyphs: renderShapeGlyphs,
                    overlays: &overlays,
                    style: style
                )
                used.width = max(used.width, s.width)
                used.height = max(used.height, s.height)
            }
            return used

        case .zstack(let children):
            var used = _Size(width: 0, height: 0)
            for n in children {
                let s = draw(
                    node: n,
                    origin: origin,
                    maxSize: maxSize,
                    canvas: &canvas,
                    hitRegions: &hitRegions,
                    hoverRegions: &hoverRegions,
                    scrollRegions: &scrollRegions,
                    shapeRegions: &shapeRegions,
                    renderShapeGlyphs: renderShapeGlyphs,
                    overlays: &overlays,
                    style: style
                )
                used.width = max(used.width, s.width)
                used.height = max(used.height, s.height)
            }
            return used

        case .text(let s):
            let clipped = String(s.prefix(maxSize.width))
            for (i, ch) in clipped.enumerated() {
                put(String(ch), at: _Point(x: origin.x + i, y: origin.y), canvas: &canvas, style: style)
            }
            return _Size(width: min(s.count, maxSize.width), height: 1)

        case .image(let name):
            let s = _DebugLayout.imageString(name)
            let clipped = String(s.prefix(maxSize.width))
            for (i, ch) in clipped.enumerated() {
                put(String(ch), at: _Point(x: origin.x + i, y: origin.y), canvas: &canvas, style: style)
            }
            return _Size(width: min(s.count, maxSize.width), height: 1)

        case .divider:
            if maxSize.width > 0 {
                for i in 0..<maxSize.width {
                    put("─", at: _Point(x: origin.x + i, y: origin.y), canvas: &canvas, style: style)
                }
            }
            return _Size(width: maxSize.width, height: 1)

        case .shape(let shape):
            // Shapes fill their proposed region. Only fall back to small intrinsic
            // size if the proposal is absurdly large (unconstrained).
            let w: Int
            let h: Int
            if maxSize.width <= 200 && maxSize.height <= 100 {
                w = maxSize.width
                h = maxSize.height
            } else {
                w = min(maxSize.width, 20)
                h = min(maxSize.height, 5)
            }
            guard w > 0, h > 0 else { return _Size(width: 0, height: 0) }

            func putLine(_ y: Int, _ s: String) {
                let clipped = String(s.prefix(w))
                for (i, ch) in clipped.enumerated() {
                    put(String(ch), at: _Point(x: origin.x + i, y: origin.y + y), canvas: &canvas)
                }
            }

            // Fill token, styled by renderers. If the shape is stroke-only, avoid emitting
            // the fill token so the placeholder matches the semantic style.
            let fill = (shape.fillStyle == nil) ? " " : "·"
            let innerW = max(0, w - 2)

            // Record a semantic region for renderers that can do true shape/path drawing.
            // This allows the notcurses renderer to use sprixels (or braille) rather than
            // relying on the placeholder glyph art below.
            shapeRegions.append((_Rect(origin: origin, size: _Size(width: w, height: h)), shape))

            if !renderShapeGlyphs {
                return _Size(width: w, height: h)
            }

            switch shape.kind {
            case .rectangle:
                if h >= 2 {
                    putLine(0, "┌" + String(repeating: "─", count: innerW) + "┐")
                    if h > 2 {
                        for y in 1..<(h - 1) {
                            putLine(y, "│" + String(repeating: fill, count: innerW) + "│")
                        }
                        putLine(h - 1, "└" + String(repeating: "─", count: innerW) + "┘")
                    } else {
                        putLine(1, "└" + String(repeating: "─", count: innerW) + "┘")
                    }
                } else {
                    putLine(0, String(repeating: fill, count: w))
                }
            case .roundedRectangle:
                if h >= 2 {
                    putLine(0, "╭" + String(repeating: "─", count: innerW) + "╮")
                    if h > 2 {
                        for y in 1..<(h - 1) {
                            putLine(y, "│" + String(repeating: fill, count: innerW) + "│")
                        }
                        putLine(h - 1, "╰" + String(repeating: "─", count: innerW) + "╯")
                    } else {
                        putLine(1, "╰" + String(repeating: "─", count: innerW) + "╯")
                    }
                } else {
                    putLine(0, "╭" + String(repeating: "─", count: innerW) + "╮")
                }
            case .circle:
                if h >= 5 && w >= 7 {
                    putLine(0, "  ╭" + String(repeating: "─", count: max(0, w - 6)) + "╮  ")
                    putLine(1, " ╭" + String(repeating: fill, count: max(0, w - 4)) + "╮ ")
                    putLine(2, " │" + String(repeating: fill, count: max(0, w - 4)) + "│ ")
                    putLine(3, " ╰" + String(repeating: fill, count: max(0, w - 4)) + "╯ ")
                    putLine(4, "  ╰" + String(repeating: "─", count: max(0, w - 6)) + "╯  ")
                } else {
                    putLine(0, "◯")
                }
            case .ellipse:
                if h >= 5 && w >= 9 {
                    putLine(0, "  ╭" + String(repeating: "─", count: max(0, w - 6)) + "╮  ")
                    putLine(1, "╭" + String(repeating: fill, count: max(0, w - 2)) + "╮")
                    putLine(2, "│" + String(repeating: fill, count: max(0, w - 2)) + "│")
                    putLine(3, "╰" + String(repeating: fill, count: max(0, w - 2)) + "╯")
                    putLine(4, "  ╰" + String(repeating: "─", count: max(0, w - 6)) + "╯  ")
                } else {
                    putLine(0, "⬭")
                }
            case .capsule:
                if h >= 3 && w >= 7 {
                    putLine(0, "╭" + String(repeating: "─", count: innerW) + "╮")
                    for y in 1..<(h - 1) {
                        putLine(y, "│" + String(repeating: fill, count: innerW) + "│")
                    }
                    putLine(h - 1, "╰" + String(repeating: "─", count: innerW) + "╯")
                } else {
                    putLine(0, "Capsule")
                }
            case .path:
                if h >= 3 && w >= 7 {
                    // Simple "mountain" polyline.
                    putLine(0, "      ╱╲     ")
                    if h > 2 {
                        putLine(1, "    ╱" + String(repeating: fill, count: max(0, w - 8)) + "╲   ")
                    }
                    if h > 3 {
                        putLine(2, "  ╱" + String(repeating: fill, count: max(0, w - 6)) + "╲  ")
                    }
                    if h > 4 {
                        putLine(3, "╱" + String(repeating: fill, count: max(0, w - 2)) + "╲")
                        putLine(4, String(repeating: "─", count: w))
                    }
                } else {
                    putLine(0, "Path")
                }
            }

            return _Size(width: w, height: h)

        case .spacer:
            return _Size(width: 0, height: 0)

        // `padding` is modeled as `.edgePadding` now.

        case .stack(let axis, let spacing, let children):
            // 2-pass layout to make `Spacer()` work (allocate remaining space across spacers).
            // This is simplistic but good enough for terminal/grid renderers.
	            func measure(_ node: _VNode, _ maxSize: _Size) -> _Size {
	                guard maxSize.width > 0, maxSize.height > 0 else { return _Size(width: 0, height: 0) }
	                switch node {
	                case .empty:
	                    return _Size(width: 0, height: 0)
	                case .textStyled(_, let child):
	                    return measure(child, maxSize)
	                case .style(_, _, let child):
	                    return measure(child, maxSize)
	                case .offset(_, _, let child):
	                    return measure(child, maxSize)
	                case .opacity(_, let child):
	                    return measure(child, maxSize)
	                case .contentShapeRect(_, let child):
	                    return measure(child, maxSize)
	                case .clip(_, let child):
	                    return measure(child, maxSize)
	                case .shadow(let child, _, _, _, _):
	                    return measure(child, maxSize)
	                case .background(let child, _):
	                    return measure(child, maxSize)
	                case .overlay(let child, _):
	                    return measure(child, maxSize)
	                case .elevated(_, let child):
	                    return measure(child, maxSize)
	                case .modalOverlay:
	                    return maxSize
	                case .identified(_, _, let child):
	                    return measure(child, maxSize)
	                case .onDelete(_, _, let child):
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
                case .text(let s):
                    return _Size(width: min(s.count, maxSize.width), height: 1)
                case .image(let name):
                    let s = _DebugLayout.imageString(name)
                    return _Size(width: min(s.count, maxSize.width), height: 1)
                case .gradient:
                    return maxSize
                case .shape:
                    let sw = min(maxSize.width, max(10, maxSize.width))
                    let sh = min(maxSize.height, 4)
                    return _Size(width: sw, height: sh)
                case .spacer:
                    return _Size(width: 0, height: 0)
                // `padding` is modeled as `.edgePadding` now.
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
                case .zstack(let children):
                    var u = _Size(width: 0, height: 0)
                    for n in children {
                        let s = measure(n, maxSize)
                        u.width = max(u.width, s.width)
                        u.height = max(u.height, s.height)
                    }
                    return u
                case .divider:
                    return _Size(width: maxSize.width, height: 1)
                case .button(_, let isFocused, let label):
                    // Render as [ label ] with optional focus marker.
                    let xPad = isFocused ? 1 : 0
                    let labelMax = _Size(width: max(0, maxSize.width - (isFocused ? 5 : 4)), height: 1)
                    let l = measure(label, labelMax)
                    return _Size(width: min(maxSize.width, xPad + 4 + l.width), height: 1)
                case .tapTarget(_, let child):
                    return measure(child, maxSize)
                case .gestureTarget(_, let child):
                    return measure(child, maxSize)
                case .hover(_, let child):
                    return measure(child, maxSize)
                case .toggle(_, let isFocused, _, let label):
                    let xPad = isFocused ? 1 : 0
                    let boxCount = 4
                    let labelMax = _Size(width: max(0, maxSize.width - boxCount - xPad), height: 1)
                    let l = measure(label, labelMax)
                    return _Size(width: min(maxSize.width, xPad + boxCount + l.width), height: 1)
                case .textField(_, let placeholder, let text, _, _, let style):
                    let display = text.isEmpty ? placeholder : text
                    let prefixCount = 2
                    let s = prefixCount + 2 + display.count
                    return _Size(width: min(maxSize.width, s), height: 1)
                case .scrollView(_, _, _, let axis, _, let content):
                    let contentMax = _Size(width: maxSize.width, height: 2048)
                    let cs = measure(content, contentMax)
                    let w = min(maxSize.width, cs.width)
                    let h = (axis == .vertical) ? min(maxSize.height, cs.height) : min(maxSize.height, cs.height)
                    return _Size(width: w, height: h)
                case .menu(_, let isFocused, _, let title, let value, _):
                    let headText = title.isEmpty ? "\(value) v" : "\(title): \(value) v"
                    let inner = " " + headText + " "
                    let w = (isFocused ? 1 : 0) + 2 + min(inner.count, max(0, maxSize.width - (isFocused ? 3 : 2)))
                    return _Size(width: min(w, maxSize.width), height: 1)
                case .styledText(let segments):
                    let total = segments.reduce(0) { $0 + $1.content.count }
                    return _Size(width: min(total, maxSize.width), height: 1)
                case .viewThatFits(_, let children):
                    if let first = children.first { return measure(first, maxSize) }
                    return _Size(width: 0, height: 0)
                case .fixedSize(_, _, let child):
                    return measure(child, maxSize)
                case .layoutPriority(_, let child):
                    return measure(child, maxSize)
                case .aspectRatio(_, _, let child):
                    return measure(child, maxSize)
                case .alignmentGuide(_, _, let child):
                    return measure(child, maxSize)
                case .preferenceNode(_, let child):
                    return measure(child, maxSize)
                case .swipeActions(_, _, _, let child):
                    return measure(child, maxSize)
                case .rotationEffect(_, let child):
                    return measure(child, maxSize)
                case .truncatedText(let text, _):
                    let total = text.count
                    return _Size(width: min(total, maxSize.width), height: 1)
                case .textCase(_, let child): return measure(child, maxSize)
                case .blur(_, let child): return measure(child, maxSize)
                case .badge(let badgeText, let child):
                    let childSize = measure(child, maxSize)
                    return _Size(width: max(childSize.width + badgeText.count + 1, maxSize.width), height: max(1, childSize.height))
                case .anchorPreference(_, _, _, let child): return measure(child, maxSize)
                case .geometryReaderProxy(let buildSize, _):
                    return _Size(width: min(buildSize.width, maxSize.width), height: min(buildSize.height, maxSize.height))
                }
            }

            var cursor = origin
            var used = _Size(width: 0, height: 0)

            func isFlexibleCandidate(_ node: _VNode) -> Bool {
                switch node {
                case .spacer:
                    return true
                case .shape:
                    return true
                case .textField:
                    return true
                case .frame(_, _, _, let maxWidth, _, _, let child):
                    if maxWidth == Int.max { return true }
                    return isFlexibleCandidate(child)
                case .scrollView(_, _, _, let scrollAxis, _, _):
                    return scrollAxis == axis
                case .style(_, _, let child):
                    return isFlexibleCandidate(child)
                case .hover(_, let child):
                    return isFlexibleCandidate(child)
                case .offset(_, _, let child):
                    return isFlexibleCandidate(child)
                case .opacity(_, let child):
                    return isFlexibleCandidate(child)
                case .contentShapeRect(_, let child):
                    return isFlexibleCandidate(child)
                case .clip(_, let child):
                    return isFlexibleCandidate(child)
                case .shadow(let child, _, _, _, _):
                    return isFlexibleCandidate(child)
                case .background(let child, _):
                    return isFlexibleCandidate(child)
                case .overlay(let child, _):
                    return isFlexibleCandidate(child)
                case .elevated(_, let child):
                    return isFlexibleCandidate(child)
                case .modalOverlay(_, _, _, let child):
                    return isFlexibleCandidate(child)
                case .identified(_, _, let child):
                    return isFlexibleCandidate(child)
                case .onDelete(_, _, let child):
                    return isFlexibleCandidate(child)
                case .tagged(_, let label):
                    return isFlexibleCandidate(label)
                case .edgePadding(_, _, _, _, let child):
                    return isFlexibleCandidate(child)
                case .gestureTarget(_, let child):
                    return isFlexibleCandidate(child)
                case .fixedSize(_, _, let child):
                    return isFlexibleCandidate(child)
                case .layoutPriority(_, let child):
                    return isFlexibleCandidate(child)
                case .alignmentGuide(_, _, let child):
                    return isFlexibleCandidate(child)
                case .preferenceNode(_, let child):
                    return isFlexibleCandidate(child)
                case .rotationEffect(_, let child):
                    return isFlexibleCandidate(child)
                case .aspectRatio(_, _, let child):
                    return isFlexibleCandidate(child)
                case .swipeActions(_, _, _, let child):
                    return isFlexibleCandidate(child)
                case .textCase(_, let child): return isFlexibleCandidate(child)
                case .blur(_, let child): return isFlexibleCandidate(child)
                case .badge(_, let child): return isFlexibleCandidate(child)
                case .anchorPreference(_, _, _, let child): return isFlexibleCandidate(child)
                case .geometryReaderProxy(_, let child): return isFlexibleCandidate(child)
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

            let availablePrimary: Int
            switch axis {
            case .horizontal: availablePrimary = maxSize.width
            case .vertical: availablePrimary = maxSize.height
            }
            for c in children {
                let s = measure(c, maxSize)
                measured.append(s)
                let primary: Int
                switch axis {
                case .horizontal: primary = s.width
                case .vertical: primary = s.height
                }

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

            // Two-pass flex allocation: cap each flexible child by its measured
            // content size, redistribute surplus to truly greedy children (Spacers).
            var flexAllocations = [Int](repeating: 0, count: children.count)
            if flexibleCount > 0 {
                let equalShare = leftover / flexibleCount
                var surplus = leftover % flexibleCount
                var greedyIndices: [Int] = []
                for idx in 0..<children.count where flexible[idx] {
                    let measuredPrimary: Int
                    switch axis {
                    case .horizontal: measuredPrimary = measured[idx].width
                    case .vertical: measuredPrimary = measured[idx].height
                    }
                    if case .spacer = children[idx] {
                        flexAllocations[idx] = equalShare
                        greedyIndices.append(idx)
                    } else if measuredPrimary < equalShare {
                        flexAllocations[idx] = measuredPrimary
                        surplus += (equalShare - measuredPrimary)
                    } else {
                        flexAllocations[idx] = equalShare
                        greedyIndices.append(idx)
                    }
                }
                if !greedyIndices.isEmpty {
                    let extra = surplus / greedyIndices.count
                    let extraRem = surplus % greedyIndices.count
                    for (i, idx) in greedyIndices.enumerated() {
                        flexAllocations[idx] += extra + (i < extraRem ? 1 : 0)
                    }
                }
            }

            for (idx, child) in children.enumerated() {
                let remaining: _Size
                switch axis {
                case .vertical:
                    remaining = _Size(width: maxSize.width, height: maxSize.height - (cursor.y - origin.y))
                case .horizontal:
                    remaining = _Size(width: maxSize.width - (cursor.x - origin.x), height: maxSize.height)
                }
                let s: _Size
                if flexible[idx] {
                    let allocated = flexAllocations[idx]

                    let proposed: _Size
                    switch axis {
                    case .horizontal:
                        proposed = _Size(width: min(remaining.width, allocated), height: remaining.height)
                    case .vertical:
                        proposed = _Size(width: remaining.width, height: min(remaining.height, allocated))
                    }

                    if case .spacer = child {
                        switch axis {
                        case .horizontal:
                            s = _Size(width: proposed.width, height: 0)
                        case .vertical:
                            s = _Size(width: 0, height: proposed.height)
                        }
                    } else {
                        s = draw(
                            node: child,
                            origin: cursor,
                            maxSize: proposed,
                            canvas: &canvas,
                            hitRegions: &hitRegions,
                            hoverRegions: &hoverRegions,
                            scrollRegions: &scrollRegions,
                            shapeRegions: &shapeRegions,
                            renderShapeGlyphs: renderShapeGlyphs,
                            overlays: &overlays,
                            style: style
                        )
                    }
                } else {
                    // Constrain non-flex children to their measured primary-axis size
                    // to prevent them from consuming all remaining space.
                    let m = measure(child, remaining)
                    let constrained: _Size
                    switch axis {
                    case .vertical:
                        constrained = _Size(width: remaining.width, height: min(remaining.height, m.height))
                    case .horizontal:
                        constrained = _Size(width: min(remaining.width, m.width), height: remaining.height)
                    }
                    s = draw(
                        node: child,
                        origin: cursor,
                        maxSize: constrained,
                        canvas: &canvas,
                        hitRegions: &hitRegions,
                        hoverRegions: &hoverRegions,
                        scrollRegions: &scrollRegions,
                        shapeRegions: &shapeRegions,
                        renderShapeGlyphs: renderShapeGlyphs,
                        overlays: &overlays,
                        style: style
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
            // Render as [ label ]
            let wantsFullHitRect = hasContentShapeRect(label)
            let x0 = isFocused ? origin.x + 1 : origin.x
            if isFocused {
                put(">", at: origin, canvas: &canvas)
            }
            put("[", at: _Point(x: x0, y: origin.y), canvas: &canvas)
            let labelOrigin = _Point(x: x0 + 2, y: origin.y)
            let labelMax = _Size(width: max(0, maxSize.width - (isFocused ? 5 : 4)), height: 1)
            let labelSize = draw(
                node: label,
                origin: labelOrigin,
                maxSize: labelMax,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )
            put("]", at: _Point(x: x0 + 1 + labelSize.width + 2, y: origin.y), canvas: &canvas)
            let buttonWidth = min(maxSize.width, (isFocused ? 1 : 0) + 4 + labelSize.width)
            let hitWidth = wantsFullHitRect ? maxSize.width : buttonWidth
            let rect = _Rect(origin: origin, size: _Size(width: min(maxSize.width, hitWidth), height: 1))
            hitRegions.append((rect, id))
            return _Size(width: buttonWidth, height: 1)

        case .tapTarget(let id, let child):
            let wantsFullHitRect = hasContentShapeRect(child)
            let s = draw(
                node: child,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )
            let w = min(maxSize.width, max(1, s.width))
            let h = min(maxSize.height, max(1, s.height))
            let hitWidth = wantsFullHitRect ? maxSize.width : w
            let rect = _Rect(origin: origin, size: _Size(width: min(maxSize.width, hitWidth), height: h))
            hitRegions.append((rect, id))
            return s

        case .gestureTarget(let gid, let gchild):
            let s = draw(
                node: gchild,
                origin: origin,
                maxSize: maxSize,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )
            let w = min(maxSize.width, max(1, s.width))
            let h = min(maxSize.height, max(1, s.height))
            let rect = _Rect(origin: origin, size: _Size(width: w, height: h))
            hitRegions.append((rect, gid))
            return s

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
            let labelSize = draw(
                node: label,
                origin: labelOrigin,
                maxSize: labelMax,
                canvas: &canvas,
                hitRegions: &hitRegions,
                hoverRegions: &hoverRegions,
                scrollRegions: &scrollRegions,
                shapeRegions: &shapeRegions,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &overlays,
                style: style
            )
            let width = min(maxSize.width, (isFocused ? 1 : 0) + box.count + labelSize.width)
            let rect = _Rect(origin: origin, size: _Size(width: width, height: 1))
            hitRegions.append((rect, id))
            return _Size(width: width, height: 1)

        case .textField(let id, let placeholder, let text, let cursor, let isFocused, let style):
            let display = text.isEmpty ? placeholder : text
            let prefix = isFocused ? "> " : "  "
            let cpos = max(0, min(cursor, display.unicodeScalars.count))
            let withCursor: String = {
                guard isFocused else { return display }
                var scalars = Array(display.unicodeScalars)
                scalars.insert("|", at: cpos)
                return String(String.UnicodeScalarView(scalars))
            }()
            let s: String = {
                switch style {
                case .plain:
                    return prefix + withCursor
                case .automatic, .roundedBorder:
                    return prefix + "[" + withCursor + "]"
                }
            }()
            let clipped = String(s.prefix(maxSize.width))
            for (i, ch) in clipped.enumerated() {
                put(String(ch), at: _Point(x: origin.x + i, y: origin.y), canvas: &canvas)
            }
            let rect = _Rect(origin: origin, size: _Size(width: min(maxSize.width, clipped.count), height: 1))
            hitRegions.append((rect, id))
            return _Size(width: min(maxSize.width, clipped.count), height: 1)

        case .scrollView(let id, let path, let isFocused, let axis, let offset, let content):
            // ScrollView is a clipping container; content is drawn translated by offset.
            // We also register a scroll region so mouse wheel events can be routed.
            // Compute max scroll in Y for now (vertical only); horizontal scroll is a no-op.
            // Limit measurement height to avoid pathological allocations/work.
            let measureMax = _Size(width: maxSize.width, height: 2048)
            let contentSize = {
                // Reuse the stack-local measure helper by calling into a small inline implementation.
                func m(_ node: _VNode, _ maxSize: _Size) -> _Size {
                    guard maxSize.width > 0, maxSize.height > 0 else { return _Size(width: 0, height: 0) }
	                    switch node {
	                    case .empty: return _Size(width: 0, height: 0)
	                    case .textStyled(_, let child):
	                        return m(child, maxSize)
	                    case .style(_, _, let child):
	                        return m(child, maxSize)
	                    case .hover(_, let child):
	                        return m(child, maxSize)
	                    case .offset(_, _, let child):
	                        return m(child, maxSize)
	                    case .opacity(_, let child):
	                        return m(child, maxSize)
	                    case .contentShapeRect(_, let child):
	                        return m(child, maxSize)
	                    case .clip(_, let child):
	                        return m(child, maxSize)
	                    case .shadow(let child, _, _, _, _):
	                        return m(child, maxSize)
	                    case .background(let child, _):
	                        return m(child, maxSize)
	                    case .overlay(let child, _):
	                        return m(child, maxSize)
	                    case .elevated(_, let child):
	                        return m(child, maxSize)
	                    case .modalOverlay:
	                        return maxSize
	                    case .identified(_, _, let child):
	                        return m(child, maxSize)
	                    case .onDelete(_, _, let child):
	                        return m(child, maxSize)
	                    case .tagged(_, let label):
	                        return m(label, maxSize)
	                    case .gradient:
	                        return maxSize
	                    case .frame(_, _, let minWidth, let maxWidth, let minHeight, let maxHeight, let child):
	                        let s = m(child, maxSize)
	                        let w = max(minWidth ?? 0, min(maxSize.width, maxWidth == Int.max ? maxSize.width : min(s.width, maxWidth ?? s.width)))
	                        let h = max(minHeight ?? 0, min(maxSize.height, maxHeight == Int.max ? maxSize.height : min(s.height, maxHeight ?? s.height)))
	                        return _Size(width: w, height: h)
	                    case .edgePadding(let top, let leading, let bottom, let trailing, let child):
	                        let inner = _Size(width: max(0, maxSize.width - leading - trailing), height: max(0, maxSize.height - top - bottom))
	                        let s = m(child, inner)
	                        return _Size(width: min(maxSize.width, s.width + leading + trailing), height: min(maxSize.height, s.height + top + bottom))
	                    case .group(let nodes):
	                        var u = _Size(width: 0, height: 0)
	                        for n in nodes {
	                            let s = m(n, maxSize)
                            u.width = max(u.width, s.width)
                            u.height = max(u.height, s.height)
                        }
                        return u
                    case .zstack(let children):
                        var u = _Size(width: 0, height: 0)
                        for n in children {
                            let s = m(n, maxSize)
                            u.width = max(u.width, s.width)
                            u.height = max(u.height, s.height)
                        }
                        return u
                    case .divider:
                        return _Size(width: maxSize.width, height: 1)
                    case .text(let s): return _Size(width: min(s.count, maxSize.width), height: 1)
                    case .image(let name):
                        let s = _DebugLayout.imageString(name)
                        return _Size(width: min(s.count, maxSize.width), height: 1)
                    case .shape:
                        return _Size(width: min(maxSize.width, 11), height: min(maxSize.height, 8))
                    case .spacer: return _Size(width: 0, height: 0)
                    // `padding` is modeled as `.edgePadding` now.
                    case .stack(let axis, let spacing, let children):
                        switch axis {
                        case .horizontal:
                            var w = 0
                            var h = 0
                            let count = children.count
                            for (i, c) in children.enumerated() {
                                let s = m(c, maxSize)
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
                                let s = m(c, maxSize)
                                h += s.height
                                w = max(w, s.width)
                                if i != count - 1 { h += spacing }
                            }
                            return _Size(width: min(w, maxSize.width), height: min(h, maxSize.height))
                        }
                    case .button(_, let isFocused, let label):
                        let xPad = isFocused ? 1 : 0
                        let labelMax = _Size(width: max(0, maxSize.width - (isFocused ? 5 : 4)), height: 1)
                        let l = m(label, labelMax)
                        return _Size(width: min(maxSize.width, xPad + 4 + l.width), height: 1)
                    case .tapTarget(_, let child):
                        return m(child, maxSize)
                    case .gestureTarget(_, let child):
                        return m(child, maxSize)
                    case .toggle(_, let isFocused, _, let label):
                        let xPad = isFocused ? 1 : 0
                        let boxCount = 4
                        let labelMax = _Size(width: max(0, maxSize.width - boxCount - xPad), height: 1)
                        let l = m(label, labelMax)
                        return _Size(width: min(maxSize.width, xPad + boxCount + l.width), height: 1)
                    case .textField(_, let placeholder, let text, _, _, let style):
                        let display = text.isEmpty ? placeholder : text
                        let prefixCount = 2
                        let s = prefixCount + 2 + display.count
                        return _Size(width: min(maxSize.width, s), height: 1)
                    case .scrollView(_, _, _, let axis, _, let innerContent):
                        let cMax = _Size(width: maxSize.width, height: 2048)
                        let cs = m(innerContent, cMax)
                        let w = min(maxSize.width, cs.width)
                        let h = (axis == .vertical) ? min(maxSize.height, cs.height) : min(maxSize.height, cs.height)
                        return _Size(width: w, height: h)
                    case .menu(_, let isFocused, _, let title, let value, _):
                        let headText = title.isEmpty ? "\(value) v" : "\(title): \(value) v"
                        let inner = " " + headText + " "
                        let w = (isFocused ? 1 : 0) + 2 + min(inner.count, max(0, maxSize.width - (isFocused ? 3 : 2)))
                        return _Size(width: min(w, maxSize.width), height: 1)
                    case .styledText(let segments):
                        let total = segments.reduce(0) { $0 + $1.content.count }
                        return _Size(width: min(total, maxSize.width), height: 1)
                    case .viewThatFits(_, let children):
                        if let first = children.first { return m(first, maxSize) }
                        return _Size(width: 0, height: 0)
                    case .fixedSize(_, _, let child): return m(child, maxSize)
                    case .layoutPriority(_, let child): return m(child, maxSize)
                    case .aspectRatio(_, _, let child): return m(child, maxSize)
                    case .alignmentGuide(_, _, let child): return m(child, maxSize)
                    case .preferenceNode(_, let child): return m(child, maxSize)
                    case .swipeActions(_, _, _, let child): return m(child, maxSize)
                    case .rotationEffect(_, let child): return m(child, maxSize)
                    case .truncatedText(let text, _): return _Size(width: text.count, height: 1)
                    case .textCase(_, let child): return m(child, maxSize)
                    case .blur(_, let child): return m(child, maxSize)
                    case .badge(_, let child): return m(child, maxSize)
                    case .anchorPreference(_, _, _, let child): return m(child, maxSize)
                    case .geometryReaderProxy(let bs, _): return _Size(width: min(bs.width, maxSize.width), height: min(bs.height, maxSize.height))
                    }
                }
                return m(content, measureMax)
            }()

            let viewportHeight: Int
            switch axis {
            case .vertical:
                viewportHeight = maxSize.height
            case .horizontal:
                viewportHeight = min(maxSize.height, 1)
            }
            let viewportSize = _Size(width: maxSize.width, height: viewportHeight)

            let rect = _Rect(origin: origin, size: viewportSize)
            hitRegions.append((rect, id))

            let maxOffsetY: Int
            let maxOffsetX: Int
            switch axis {
            case .vertical:
                maxOffsetY = max(0, contentSize.height - viewportHeight)
                maxOffsetX = 0
            case .horizontal:
                maxOffsetY = 0
                maxOffsetX = max(0, contentSize.width - viewportSize.width)
            }
            scrollRegions.append(_ScrollRegion(rect: rect, path: path, maxOffsetY: maxOffsetY, maxOffsetX: maxOffsetX, axis: axis))

            // Basic focus marker: draw a leading ">" on the first line if focused.
            if isFocused {
                put(">", at: origin, canvas: &canvas)
            }

            let yOff: Int
            let xOff: Int
            switch axis {
            case .vertical:
                yOff = min(max(0, offset), maxOffsetY)
                xOff = 0
            case .horizontal:
                yOff = 0
                xOff = min(max(0, offset), maxOffsetX)
            }

            // Clip content to the scroll view's rect by drawing into an offscreen buffer first.
            let bufferWidth = max(viewportSize.width, viewportSize.width + xOff)
            let bufferHeight = max(viewportSize.height, viewportSize.height + yOff)
            var sub = Array(
                repeating: Array(repeating: _CanvasCell(ch: " ", fg: nil, bg: nil), count: bufferWidth),
                count: bufferHeight
            )
            var subHits: [(_Rect, _ActionID)] = []
            var subHovers: [(_Rect, _HoverID)] = []
            var subScrolls: [_ScrollRegion] = []
            var subOverlays: [Overlay] = []
            var subShapes: [(_Rect, _ShapeNode)] = []
            _ = draw(
                node: content,
                origin: _Point(x: -xOff, y: -yOff),
                maxSize: _Size(width: max(viewportSize.width + xOff, contentSize.width), height: max(viewportSize.height + yOff, contentSize.height)),
                canvas: &sub,
                hitRegions: &subHits,
                hoverRegions: &subHovers,
                scrollRegions: &subScrolls,
                shapeRegions: &subShapes,
                renderShapeGlyphs: renderShapeGlyphs,
                overlays: &subOverlays,
                style: style
            )

            // Apply overlays (e.g. Picker dropdown) within the scroll view, then clip via composition.
            for o in subOverlays.sorted(by: { $0.zIndex < $1.zIndex }) {
                o.draw(&sub, &subHits, &subHovers, &subScrolls)
            }

            // Composite subcanvas into the main canvas and translate hit regions.
            for y in 0..<viewportSize.height {
                let dy = origin.y + y
                guard dy >= 0, dy < canvas.count else { continue }
                for x in 0..<viewportSize.width {
                    let dx = origin.x + x
                    guard dx >= 0, dx < canvas[dy].count else { continue }
                    let s = sub[y][x].ch
                    if s != " " {
                        canvas[dy][dx].ch = s
                    }
                }
            }

            // Scrollbar (vertical only), drawn over the last column.
            if axis == .vertical, maxOffsetY > 0, viewportSize.width > 0 {
                let sbX = origin.x + viewportSize.width - 1
                let trackH = viewportSize.height
                if trackH > 0 {
                    let total = maxOffsetY + viewportSize.height
                    let thumbH = max(1, (viewportSize.height * viewportSize.height) / max(1, total))
                    let travel = max(1, viewportSize.height - thumbH)
                    let thumbY0 = origin.y + (yOff * travel) / max(1, maxOffsetY)
                    let thumbY1 = min(origin.y + trackH - 1, thumbY0 + thumbH - 1)

                    for yy in 0..<trackH {
                        let y = origin.y + yy
                        guard y >= 0, y < canvas.count else { continue }
                        let ch = (y >= thumbY0 && y <= thumbY1) ? "█" : "│"
                        put(ch, at: _Point(x: sbX, y: y), canvas: &canvas)
                    }
                }
            }

            for (r, a) in subHits {
                let tr = _Rect(origin: _Point(x: r.origin.x + origin.x, y: r.origin.y + origin.y), size: r.size)
                hitRegions.append((tr, a))
            }
            for sr in subScrolls {
                let tr = _Rect(origin: _Point(x: sr.rect.origin.x + origin.x, y: sr.rect.origin.y + origin.y), size: sr.rect.size)
                scrollRegions.append(_ScrollRegion(rect: tr, path: sr.path, maxOffsetY: sr.maxOffsetY))
            }
            for (r, s) in subShapes {
                let tr = _Rect(origin: _Point(x: r.origin.x + origin.x, y: r.origin.y + origin.y), size: r.size)
                shapeRegions.append((tr, s))
            }

            // Note: overlays inside scroll views currently escape the clip (good enough for now).
            return viewportSize

        case .menu(let id, let isFocused, let isExpanded, let title, let value, let items):
            // Header like:  >[ Flavor: Chocolate v ]
            let v = isExpanded ? "^" : "v"
            let headText = title.isEmpty ? "\(value) \(v)" : "\(title): \(value) \(v)"
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
            overlays.append(Overlay(zIndex: 1000, draw: { canvas, hitRegions, _, _ in
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

        // Parity additions
        case .styledText(let segments):
            var x = origin.x
            for seg in segments {
                for ch in seg.content {
                    if x >= origin.x + maxSize.width { break }
                    put(String(ch), at: _Point(x: x, y: origin.y), canvas: &canvas, style: (fg: seg.fg ?? style.fg, bg: style.bg))
                    x += 1
                }
            }
            let total = segments.reduce(0) { $0 + $1.content.count }
            return _Size(width: min(total, maxSize.width), height: 1)

        case .viewThatFits(let axes, let children):
            func m(_ node: _VNode, _ ms: _Size) -> _Size {
                // Simple intrinsic measure for fit-testing
                switch node {
                case .text(let s): return _Size(width: s.count, height: 1)
                case .styledText(let segs): return _Size(width: segs.reduce(0) { $0 + $1.content.count }, height: 1)
                case .stack(let a, let sp, let ch):
                    var w = 0; var h = 0
                    for (i, c) in ch.enumerated() {
                        let s = m(c, ms)
                        if a == .horizontal { w += s.width; h = max(h, s.height); if i < ch.count - 1 { w += sp } }
                        else { h += s.height; w = max(w, s.width); if i < ch.count - 1 { h += sp } }
                    }
                    return _Size(width: w, height: h)
                default: return _Size(width: ms.width, height: 1)
                }
            }
            for child in children {
                let intrinsic = m(child, maxSize)
                let fitsH = !axes.contains(.horizontal) || intrinsic.width <= maxSize.width
                let fitsV = !axes.contains(.vertical) || intrinsic.height <= maxSize.height
                if fitsH && fitsV {
                    return draw(node: child, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)
                }
            }
            if let last = children.last {
                return draw(node: last, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)
            }
            return _Size(width: 0, height: 0)

        case .fixedSize(_, _, let child):
            return draw(node: child, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)

        case .layoutPriority(_, let child):
            return draw(node: child, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)

        case .aspectRatio(_, _, let child):
            return draw(node: child, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)

        case .alignmentGuide(_, _, let child):
            return draw(node: child, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)

        case .preferenceNode(_, let child):
            return draw(node: child, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)

        case .swipeActions(_, let revealed, let actions, let child):
            if revealed, let first = actions.first {
                return draw(node: first, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)
            }
            return draw(node: child, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)

        case .rotationEffect(_, let child):
            return draw(node: child, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)

        case .truncatedText(let text, let mode):
            let available = maxSize.width
            if text.count <= available {
                for (i, ch) in text.enumerated() {
                    let pt = _Point(x: origin.x + i, y: origin.y)
                    if pt.x < origin.x + maxSize.width {
                        put(String(ch), at: pt, canvas: &canvas, style: style)
                    }
                }
                return _Size(width: text.count, height: 1)
            }
            let ellipsis: Character = "\u{2026}"
            let truncated: String
            switch mode {
            case .head:
                truncated = String(ellipsis) + String(text.suffix(available - 1))
            case .middle:
                let half = (available - 1) / 2
                let remainder = available - 1 - half
                truncated = String(text.prefix(half)) + String(ellipsis) + String(text.suffix(remainder))
            case .tail:
                truncated = String(text.prefix(available - 1)) + String(ellipsis)
            }
            for (i, ch) in truncated.enumerated() {
                let pt = _Point(x: origin.x + i, y: origin.y)
                if pt.x < origin.x + maxSize.width {
                    put(String(ch), at: pt, canvas: &canvas, style: style)
                }
            }
            return _Size(width: min(truncated.count, available), height: 1)

        case .textCase(let tc, let child):
            // Save canvas state, draw child, then transform text in-place
            let childSize = draw(node: child, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)
            // Transform drawn characters in the affected region
            for y in origin.y ..< (origin.y + childSize.height) {
                guard y < canvas.count else { break }
                for x in origin.x ..< (origin.x + childSize.width) {
                    guard x < canvas[y].count else { break }
                    let ch = canvas[y][x].ch
                    canvas[y][x].ch = tc == .uppercase ? ch.uppercased() : ch.lowercased()
                }
            }
            return childSize

        case .blur(let radius, let child):
            let childSize = draw(node: child, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)
            if radius > 2 {
                let shade = "\u{2591}"
                for y in origin.y ..< (origin.y + childSize.height) {
                    guard y < canvas.count else { break }
                    for x in origin.x ..< (origin.x + childSize.width) {
                        guard x < canvas[y].count else { break }
                        if canvas[y][x].ch != " " {
                            canvas[y][x].ch = shade
                        }
                    }
                }
            }
            return childSize

        case .badge(let badgeText, let child):
            let childSize = draw(node: child, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)
            let badgeStr = " \(badgeText)"
            let badgeX = origin.x + maxSize.width - badgeStr.count
            if badgeX > origin.x + childSize.width {
                let badgeStyle = (fg: Color.red as Color?, bg: style.bg)
                for (i, ch) in badgeStr.enumerated() {
                    let pt = _Point(x: badgeX + i, y: origin.y)
                    put(String(ch), at: pt, canvas: &canvas, style: badgeStyle)
                }
            }
            return _Size(width: maxSize.width, height: max(1, childSize.height))

        case .anchorPreference(_, _, _, let child):
            return draw(node: child, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)

        case .geometryReaderProxy(_, let child):
            return draw(node: child, origin: origin, maxSize: maxSize, canvas: &canvas, hitRegions: &hitRegions, hoverRegions: &hoverRegions, scrollRegions: &scrollRegions, shapeRegions: &shapeRegions, renderShapeGlyphs: renderShapeGlyphs, overlays: &overlays, style: style)

        }
    }

    private static func put(_ s: String, at p: _Point, canvas: inout [[_CanvasCell]], style: (fg: Color?, bg: Color?)? = nil) {
        guard p.y >= 0, p.y < canvas.count else { return }
        guard p.x >= 0, p.x < canvas[p.y].count else { return }
        canvas[p.y][p.x].ch = _sanitizeCell(s)
        if let style {
            if let fg = style.fg { canvas[p.y][p.x].fg = fg }
            if let bg = style.bg { canvas[p.y][p.x].bg = bg }
        }
    }

    private static func _sanitizeCell(_ s: String) -> String {
        // Prevent embedding terminal control sequences (ESC, C0 controls).
        // Layout expects a single printable grapheme; anything else is replaced.
        guard s.count == 1, let scalar = s.unicodeScalars.first else { return "?" }
        let v = scalar.value
        if v == 0x1B { return "?" } // ESC
        if v < 0x20 || v == 0x7F { return "?" }
        return s
    }
}
