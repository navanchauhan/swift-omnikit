import OmniUICore

#if os(Linux)
import Glibc
#else
import Darwin
#endif

public enum OmniUITerminalRendererError: Error {
    case notATerminal
}

/// ANSI/VT-based renderer with a differential cell cache.
///
/// This is intentionally minimal: it renders OmniUICore's `DebugSnapshot` grid and provides
/// basic keyboard + mouse (SGR) input without depending on notcurses.
public struct TerminalApp<V: View> {
    let root: () -> V

    public init(root: @escaping () -> V) {
        self.root = root
    }

    @MainActor
    public func run() async throws {
        let runtime = _UIRuntime()

        guard isatty(STDIN_FILENO) != 0, isatty(STDOUT_FILENO) != 0 else {
            throw OmniUITerminalRendererError.notATerminal
        }

        var term = try _TerminalSession()
        defer { term.restore() }

        var prev: [_Cell]? = nil

        while !Task.isCancelled {
            let size = _terminalSize()
            let snapshot = runtime.render(root(), size: size)

            let baseFG = _RGB(r: 0xD8, g: 0xDB, b: 0xE2)
            let baseBG = _RGB(r: 0x0B, g: 0x10, b: 0x20)
            let focusFG = _RGB(r: 0xFF, g: 0xFF, b: 0xFF)
            let focusBG = _RGB(r: 0x1D, g: 0x4E, b: 0xD8)
            let accentFG = _RGB(r: 0x34, g: 0xD3, b: 0x99)
            let borderFG = _RGB(r: 0xF2, g: 0xF4, b: 0xF8)

            var curr = Array(repeating: _Cell(ch: " ", fg: baseFG, bg: baseBG), count: size.width * size.height)
            // Rasterize typed ops into a cell buffer.
            func setCell(_ x: Int, _ y: Int, _ egc: String, _ fg: _RGB?, _ bg: _RGB?) {
                guard x >= 0, y >= 0, x < size.width, y < size.height else { return }
                let idx = y * size.width + x
                var c = curr[idx]
                c.ch = egc
                if let fg { c.fg = fg }
                if let bg { c.bg = bg }
                curr[idx] = c
            }

            for op in snapshot.ops {
                switch op.kind {
                case .glyph(let x, let y, let egc, let fg, let bg):
                    let mapped = egc.first ?? " "
                    let rfg = _resolveColor(fg)
                    let rbg = _resolveColor(bg)
                    var outFG = rfg ?? baseFG
                    let outBG = rbg ?? baseBG
                    if mapped == "*" { outFG = accentFG }
                    if _isBorderGlyph(mapped) { outFG = borderFG }
                    setCell(x, y, egc, outFG, outBG)
                case .textRun(let x, let y, let text, let fg, let bg):
                    let rfg = _resolveColor(fg)
                    let rbg = _resolveColor(bg)
                    let outFG = rfg ?? baseFG
                    let outBG = rbg ?? baseBG
                    // Per-run specials aren't ideal, but this keeps legacy "border glyph" tinting working.
                    // We apply it per-character.
                    var xx = x
                    for ch in text {
                        let mapped = ch
                        var fg2 = outFG
                        if mapped == "*" { fg2 = accentFG }
                        if _isBorderGlyph(mapped) { fg2 = borderFG }
                        setCell(xx, y, String(ch), fg2, outBG)
                        xx += 1
                        if xx >= size.width { break }
                    }
                case .fillRect(let rect, let color):
                    guard let c = _resolveColor(color) else { continue }
                    let x0 = max(0, rect.origin.x)
                    let y0 = max(0, rect.origin.y)
                    let x1 = min(size.width, rect.origin.x + rect.size.width)
                    let y1 = min(size.height, rect.origin.y + rect.size.height)
                    if x1 <= x0 || y1 <= y0 { continue }
                    for yy in y0..<y1 {
                        for xx in x0..<x1 {
                            setCell(xx, yy, " ", nil, c)
                        }
                    }
                case .shape:
                    break
                }
            }

            // Render shapes via braille into the cell grid (portable fallback).
            let shapeRegions: [(_Rect, _ShapeNode)] = snapshot.ops.compactMap { op in
                if case .shape(let r, let s) = op.kind { return (r, s) }
                return nil
            }
            if !shapeRegions.isEmpty {
                _renderBrailleShapes(
                    termSize: size,
                    shapes: shapeRegions,
                    curr: &curr,
                    baseBG: baseBG,
                    fillBG: _RGB(r: 0x12, g: 0x1B, b: 0x33),
                    strokeFG: borderFG
                )
            }

            // Focus highlight overlays everything else.
            if let fr = snapshot.focusedRect {
                let x0 = max(0, fr.origin.x)
                let y0 = max(0, fr.origin.y)
                let x1 = min(size.width, fr.origin.x + fr.size.width)
                let y1 = min(size.height, fr.origin.y + fr.size.height)
                if x1 > x0, y1 > y0 {
                    for yy in y0..<y1 {
                        for xx in x0..<x1 {
                            let idx = yy * size.width + xx
                            curr[idx].fg = focusFG
                            curr[idx].bg = focusBG
                        }
                    }
                }
            }

            let changed: [(Int, _Cell)]
            if let prev {
                changed = curr.enumerated().compactMap { i, c in prev[i] == c ? nil : (i, c) }
            } else {
                term.write("\u{001B}[2J\u{001B}[H") // clear + home
                changed = curr.enumerated().map { ($0.offset, $0.element) }
            }

            var penFG: _RGB? = nil
            var penBG: _RGB? = nil
            var penX = 0
            var penY = 0
            for (idx, cell) in changed {
                let y = idx / size.width
                let x = idx % size.width
                if x != penX || y != penY {
                    term.write(_move(row: y + 1, col: x + 1))
                    penX = x
                    penY = y
                }
                if penFG != cell.fg {
                    term.write(_fg(cell.fg))
                    penFG = cell.fg
                }
                if penBG != cell.bg {
                    term.write(_bg(cell.bg))
                    penBG = cell.bg
                }
                term.write(cell.ch)
                penX += 1
            }

            prev = curr

            // Drain input.
            while let ev = term.pollEvent() {
                switch ev {
                case .quit:
                    return
                case .esc:
                    if runtime.hasExpandedPicker() {
                        runtime.collapseExpandedPicker()
                    } else {
                        return
                    }
                case .tab(let shift):
                    if shift {
                        if runtime.hasExpandedPicker() { runtime.focusPrevWithinExpandedPicker() }
                        else { runtime.focusPrev() }
                    } else {
                        if runtime.hasExpandedPicker() { runtime.focusNextWithinExpandedPicker() }
                        else { runtime.focusNext() }
                    }
                case .up:
                    if runtime.hasExpandedPicker() { runtime.focusPrevWithinExpandedPicker() }
                    else { runtime.focusPrev() }
                case .down:
                    if runtime.hasExpandedPicker() { runtime.focusNextWithinExpandedPicker() }
                    else { runtime.focusNext() }
                case .enter:
                    runtime.activateFocused()
                case .backspace:
                    if runtime.isTextEditingFocused() {
                        runtime._handleKey(.backspace)
                    } else if runtime.canPopNavigation() {
                        runtime.popNavigation()
                    }
                case .delete:
                    if runtime.isTextEditingFocused() {
                        runtime._handleKey(.delete)
                    }
                case .left:
                    if runtime.isTextEditingFocused() { runtime._handleKey(.left) }
                case .right:
                    if runtime.isTextEditingFocused() { runtime._handleKey(.right) }
                case .home:
                    if runtime.isTextEditingFocused() { runtime._handleKey(.home) }
                case .end:
                    if runtime.isTextEditingFocused() { runtime._handleKey(.end) }
                case .char(let u):
                    if runtime.isTextEditingFocused() || u != 32 {
                        runtime._handleKey(.char(u))
                    } else {
                        runtime.activateFocused()
                    }
                case .mouse(let x, let y, let kind):
                    switch kind {
                    case .leftDown:
                        snapshot.click(x: x, y: y)
                    case .wheelUp:
                        snapshot.scroll(x: x, y: y, deltaY: -1)
                    case .wheelDown:
                        snapshot.scroll(x: x, y: y, deltaY: 1)
                    }
                }
            }

            try await Task.sleep(nanoseconds: 16_000_000)
        }
    }
}

private struct _TerminalSession {
    private var orig = termios()
    private var nonblockingWasSet = false
    private var input = _InputParser()

    init() throws {
        // Save tty mode.
        if tcgetattr(STDIN_FILENO, &orig) != 0 {
            throw OmniUITerminalRendererError.notATerminal
        }

        var raw = orig
        // Raw-ish mode, but keep ISIG so Ctrl+C still works.
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL | INLCR)
        raw.c_oflag &= ~tcflag_t(OPOST)
        _setCC(&raw, VMIN, 0)
        _setCC(&raw, VTIME, 0)

        _ = tcsetattr(STDIN_FILENO, TCSANOW, &raw)

        // Nonblocking stdin.
        let flags = fcntl(STDIN_FILENO, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
            nonblockingWasSet = true
        }

        // Enter alt screen, clear, hide cursor. Enable SGR mouse reporting + bracketed paste.
        write("\u{001B}[?1049h\u{001B}[2J\u{001B}[H\u{001B}[?25l\u{001B}[?1000h\u{001B}[?1006h\u{001B}[?2004h")
    }

    func restore() {
        // Disable bracketed paste + mouse, show cursor, reset attrs, leave alt screen.
        write("\u{001B}[?2004l\u{001B}[?1000l\u{001B}[?1006l\u{001B}[0m\u{001B}[?25h\u{001B}[?1049l")
        var o = orig
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &o)
        if nonblockingWasSet {
            let flags = fcntl(STDIN_FILENO, F_GETFL, 0)
            if flags >= 0 {
                _ = fcntl(STDIN_FILENO, F_SETFL, flags & ~O_NONBLOCK)
            }
        }
    }

    func write(_ s: String) {
        s.withCString { _ = _sysWrite(STDOUT_FILENO, $0, strlen($0)) }
    }

    mutating func pollEvent() -> _Event? {
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = _sysRead(STDIN_FILENO, &buf, buf.count)
            if n > 0 {
                input.push(buf[0..<n])
            } else {
                break
            }
        }
        return input.next()
    }
}

private func _resolveColor(_ c: Color?) -> _RGB? {
    guard let c, c.alpha > 0 else { return nil }
    // Very small palette; good enough for iGopherBrowser-style `.primary/.secondary` and basic colors.
    switch c.name {
    case "primary":
        return _RGB(r: 0xD8, g: 0xDB, b: 0xE2)
    case "secondary":
        return _RGB(r: 0xA5, g: 0xAC, b: 0xB8)
    case "tertiary":
        return _RGB(r: 0x7D, g: 0x86, b: 0x96)
    case "white":
        return _RGB(r: 0xFF, g: 0xFF, b: 0xFF)
    case "gray":
        return _RGB(r: 0x99, g: 0xA1, b: 0xAE)
    case "yellow":
        return _RGB(r: 0xFA, g: 0xD3, b: 0x5D)
    case "accentColor":
        return _RGB(r: 0x34, g: 0xD3, b: 0x99)
    case "black":
        return _RGB(r: 0x00, g: 0x00, b: 0x00)
    default:
        return nil
    }
}

private func _renderBrailleShapes(
    termSize: _Size,
    shapes: [(_Rect, _ShapeNode)],
    curr: inout [_Cell],
    baseBG: _RGB,
    fillBG: _RGB,
    strokeFG: _RGB
) {
    func setCell(_ x: Int, _ y: Int, _ ch: String, _ fg: _RGB, _ bg: _RGB) {
        guard x >= 0, y >= 0, x < termSize.width, y < termSize.height else { return }
        let idx = y * termSize.width + x
        if curr[idx].ch != " " { return }
        curr[idx] = _Cell(ch: ch, fg: fg, bg: bg)
    }

    func dotBit(_ sx: Int, _ sy: Int) -> UInt8 {
        switch (sx, sy) {
        case (0, 0): return 0x01
        case (0, 1): return 0x02
        case (0, 2): return 0x04
        case (1, 0): return 0x08
        case (1, 1): return 0x10
        case (1, 2): return 0x20
        case (0, 3): return 0x40
        case (1, 3): return 0x80
        default: return 0
        }
    }

    func insideRoundedRect(x: Double, y: Double, w: Double, h: Double, rx: Double, ry: Double) -> Bool {
        let crx = min(rx, w / 2.0)
        let cry = min(ry, h / 2.0)
        if (x >= crx && x <= w - crx) { return true }
        if (y >= cry && y <= h - cry) { return true }
        let cx = (x < crx) ? crx : (w - crx)
        let cy = (y < cry) ? cry : (h - cry)
        let dx = (x - cx) / max(1e-6, crx)
        let dy = (y - cy) / max(1e-6, cry)
        return (dx * dx + dy * dy) <= 1.0
    }

    func strokePathMask(elements: [Path.Element], subW: Int, subH: Int) -> ([Bool], [(Int, Int, Int, Int)]) {
        var subStroke = Array(repeating: false, count: subW * subH)
        func setStroke(_ sx: Int, _ sy: Int) {
            guard sx >= 0, sy >= 0, sx < subW, sy < subH else { return }
            subStroke[sy * subW + sx] = true
        }

        // Bounds
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        func consider(_ p: CGPoint) {
            minX = min(minX, Double(p.x))
            minY = min(minY, Double(p.y))
            maxX = max(maxX, Double(p.x))
            maxY = max(maxY, Double(p.y))
        }

        for e in elements {
            switch e {
            case .move(let p), .line(let p):
                consider(p)
            case .quadCurve(let p, let c):
                consider(p); consider(c)
            case .curve(let p, let c1, let c2):
                consider(p); consider(c1); consider(c2)
            case .rect(let r):
                consider(r.origin)
                consider(CGPoint(x: r.origin.x + r.size.width, y: r.origin.y + r.size.height))
            case .ellipse(let r):
                consider(r.origin)
                consider(CGPoint(x: r.origin.x + r.size.width, y: r.origin.y + r.size.height))
            case .closeSubpath:
                break
            }
        }

        if !minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite {
            return (subStroke, [])
        }
        let rangeX = max(1e-6, maxX - minX)
        let rangeY = max(1e-6, maxY - minY)

        func map(_ p: CGPoint) -> (Int, Int) {
            let nx = (Double(p.x) - minX) / rangeX
            let ny = (Double(p.y) - minY) / rangeY
            let x = Int(nx * Double(max(1, subW - 1)))
            let y = Int(ny * Double(max(1, subH - 1)))
            return (x, y)
        }

        func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
            var x0 = x0, y0 = y0
            let dx = abs(x1 - x0)
            let sx = x0 < x1 ? 1 : -1
            let dy = -abs(y1 - y0)
            let sy = y0 < y1 ? 1 : -1
            var err = dx + dy
            while true {
                setStroke(x0, y0)
                if x0 == x1 && y0 == y1 { break }
                let e2 = 2 * err
                if e2 >= dy { err += dy; x0 += sx }
                if e2 <= dx { err += dx; y0 += sy }
            }
        }

        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
            CGPoint(x: CGFloat(Double(a.x) + (Double(b.x) - Double(a.x)) * t), y: CGFloat(Double(a.y) + (Double(b.y) - Double(a.y)) * t))
        }

        func cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, _ t: Double) -> CGPoint {
            let u = 1.0 - t
            let tt = t * t
            let uu = u * u
            let uuu = uu * u
            let ttt = tt * t
            let x =
                uuu * Double(p0.x) +
                3.0 * uu * t * Double(c1.x) +
                3.0 * u * tt * Double(c2.x) +
                ttt * Double(p3.x)
            let y =
                uuu * Double(p0.y) +
                3.0 * uu * t * Double(c1.y) +
                3.0 * u * tt * Double(c2.y) +
                ttt * Double(p3.y)
            return CGPoint(x: CGFloat(x), y: CGFloat(y))
        }

        var segments: [(Int, Int, Int, Int)] = []
        segments.reserveCapacity(max(16, elements.count * 3))

        var curr: (Int, Int)? = nil
        var start: (Int, Int)? = nil
        var currSrc: CGPoint? = nil
        var startSrc: CGPoint? = nil

        for e in elements {
            switch e {
            case .move(let p):
                let mp = map(p)
                curr = mp
                start = mp
                currSrc = p
                startSrc = p
            case .line(let p):
                let mp = map(p)
                if let c = curr {
                    line(c.0, c.1, mp.0, mp.1)
                    segments.append((c.0, c.1, mp.0, mp.1))
                }
                curr = mp
                currSrc = p
            case .rect(let r):
                let p0 = map(r.origin)
                let p1 = map(CGPoint(x: r.origin.x + r.size.width, y: r.origin.y + r.size.height))
                let ax0 = min(p0.0, p1.0), ay0 = min(p0.1, p1.1)
                let ax1 = max(p0.0, p1.0), ay1 = max(p0.1, p1.1)
                let edges = [(ax0, ay0, ax1, ay0), (ax1, ay0, ax1, ay1), (ax1, ay1, ax0, ay1), (ax0, ay1, ax0, ay0)]
                for e in edges { line(e.0, e.1, e.2, e.3); segments.append(e) }
            case .ellipse(let r):
                let p0 = map(r.origin)
                let p1 = map(CGPoint(x: r.origin.x + r.size.width, y: r.origin.y + r.size.height))
                let ax0 = min(p0.0, p1.0), ay0 = min(p0.1, p1.1)
                let ax1 = max(p0.0, p1.0), ay1 = max(p0.1, p1.1)
                let cx = Double(ax0 + ax1) / 2.0
                let cy = Double(ay0 + ay1) / 2.0
                let rx = max(1.0, Double(ax1 - ax0) / 2.0)
                let ry = max(1.0, Double(ay1 - ay0) / 2.0)
                var prev: (Int, Int)? = nil
                let steps = 64
                for i in 0...steps {
                    let t = Double(i) * (2.0 * Double.pi) / Double(steps)
                    let x = Int(cx + cos(t) * rx)
                    let y = Int(cy + sin(t) * ry)
                    if let p = prev {
                        line(p.0, p.1, x, y)
                        segments.append((p.0, p.1, x, y))
                    }
                    prev = (x, y)
                }
            case .quadCurve(let p, let c):
                guard let s0 = currSrc else {
                    currSrc = p
                    curr = map(p)
                    break
                }
                let steps = 24
                var prevP = s0
                for i in 1...steps {
                    let tt = Double(i) / Double(steps)
                    let a = lerp(s0, c, tt)
                    let b = lerp(c, p, tt)
                    let q = lerp(a, b, tt)
                    let m0 = map(prevP)
                    let m1 = map(q)
                    line(m0.0, m0.1, m1.0, m1.1)
                    segments.append((m0.0, m0.1, m1.0, m1.1))
                    prevP = q
                }
                currSrc = p
                curr = map(p)
            case .curve(let p, let c1, let c2):
                guard let s0 = currSrc else {
                    currSrc = p
                    curr = map(p)
                    break
                }
                let steps = 32
                var prevP = s0
                for i in 1...steps {
                    let tt = Double(i) / Double(steps)
                    let q = cubic(s0, c1, c2, p, tt)
                    let m0 = map(prevP)
                    let m1 = map(q)
                    line(m0.0, m0.1, m1.0, m1.1)
                    segments.append((m0.0, m0.1, m1.0, m1.1))
                    prevP = q
                }
                currSrc = p
                curr = map(p)
            case .closeSubpath:
                if let c = curr, let s = start {
                    line(c.0, c.1, s.0, s.1)
                    segments.append((c.0, c.1, s.0, s.1))
                }
                curr = start
                currSrc = startSrc
            }
        }

        return (subStroke, segments)
    }

    for (r, s) in shapes {
        let x0 = max(0, r.origin.x)
        let y0 = max(0, r.origin.y)
        let x1 = min(termSize.width, r.origin.x + r.size.width)
        let y1 = min(termSize.height, r.origin.y + r.size.height)
        guard x1 > x0, y1 > y0 else { continue }

        let regionW = x1 - x0
        let regionH = y1 - y0
        let subW = regionW * 2
        let subH = regionH * 4
        if subW <= 0 || subH <= 0 { continue }

        let fillEnabled = (s.fillStyle != nil)
        let eoFill = s.fillStyle?.isEOFilled ?? false

        func insideFilledShape(_ sx: Int, _ sy: Int) -> Bool {
            let x = Double(sx) + 0.5
            let y = Double(sy) + 0.5
            let w = Double(subW)
            let h = Double(subH)

            switch s.kind {
            case .rectangle:
                return true
            case .roundedRectangle(let crCells):
                let rx = max(1.0, Double(crCells) * 2.0)
                let ry = max(1.0, Double(crCells) * 4.0)
                return insideRoundedRect(x: x, y: y, w: w, h: h, rx: rx, ry: ry)
            case .capsule:
                let rx = max(1.0, min(w, h) / 2.0)
                let ry = rx
                return insideRoundedRect(x: x, y: y, w: w, h: h, rx: rx, ry: ry)
            case .circle, .ellipse:
                let cx = w / 2.0
                let cy = h / 2.0
                let rx = max(1.0, (w - 1.0) / 2.0)
                let ry = max(1.0, (h - 1.0) / 2.0)
                let dx = (x - cx) / rx
                let dy = (y - cy) / ry
                return (dx * dx + dy * dy) <= 1.0
            case .path:
                return false
            }
        }

        if s.kind == .path {
            let (subStroke, segments) = strokePathMask(elements: s.pathElements ?? [], subW: subW, subH: subH)

            func windingContains(_ x: Double, _ y: Double) -> Bool {
                var winding = 0
                for s in segments {
                    let y0 = Double(s.1)
                    let y1 = Double(s.3)
                    let x0 = Double(s.0)
                    let x1 = Double(s.2)
                    if y0 == y1 { continue }
                    let upward = y0 < y1
                    let ymin = min(y0, y1)
                    let ymax = max(y0, y1)
                    if y < ymin || y >= ymax { continue }
                    let t = (y - y0) / (y1 - y0)
                    let ix = x0 + t * (x1 - x0)
                    if ix <= x { continue }
                    winding += upward ? 1 : -1
                }
                return winding != 0
            }

            func evenOddContains(_ x: Double, _ y: Double) -> Bool {
                var inside = false
                for s in segments {
                    let y0 = Double(s.1)
                    let y1 = Double(s.3)
                    let x0 = Double(s.0)
                    let x1 = Double(s.2)
                    if y0 == y1 { continue }
                    let ymin = min(y0, y1)
                    let ymax = max(y0, y1)
                    if y < ymin || y >= ymax { continue }
                    let t = (y - y0) / (y1 - y0)
                    let ix = x0 + t * (x1 - x0)
                    if ix > x { inside.toggle() }
                }
                return inside
            }

            for cy in y0..<y1 {
                for cx in x0..<x1 {
                    let baseSX = (cx - x0) * 2
                    let baseSY = (cy - y0) * 4

                    var strokeMask: UInt8 = 0
                    for sy in 0..<4 {
                        for sx in 0..<2 {
                            if subStroke[(baseSY + sy) * subW + (baseSX + sx)] {
                                strokeMask |= dotBit(sx, sy)
                            }
                        }
                    }

                    var fillMask: UInt8 = 0
                    var fillCount = 0
                    if fillEnabled, !segments.isEmpty {
                        for sy in 0..<4 {
                            for sx in 0..<2 {
                                let px = Double(baseSX + sx) + 0.5
                                let py = Double(baseSY + sy) + 0.5
                                let ins = eoFill ? evenOddContains(px, py) : windingContains(px, py)
                                if ins {
                                    fillCount += 1
                                    fillMask |= dotBit(sx, sy)
                                }
                            }
                        }
                    }

                    if fillEnabled, fillCount == 8, strokeMask == 0 {
                        setCell(cx, cy, " ", fillBG, fillBG)
                        continue
                    }

                    let mask = strokeMask | ((fillEnabled && fillCount > 0 && fillCount < 8) ? fillMask : 0)
                    guard mask != 0 else { continue }
                    let scalar = UnicodeScalar(0x2800 + Int(mask))!
                    let bg = fillEnabled ? fillBG : baseBG
                    setCell(cx, cy, String(Character(scalar)), strokeFG, bg)
                }
            }
            continue
        }

        // Filled primitives.
        for cy in y0..<y1 {
            for cx in x0..<x1 {
                let baseSX = (cx - x0) * 2
                let baseSY = (cy - y0) * 4
                var mask: UInt8 = 0
                var insideCount = 0
                for sy in 0..<4 {
                    for sx in 0..<2 {
                        if insideFilledShape(baseSX + sx, baseSY + sy) {
                            insideCount += 1
                            mask |= dotBit(sx, sy)
                        }
                    }
                }
                if fillEnabled, insideCount == 8 {
                    setCell(cx, cy, " ", fillBG, fillBG)
                    continue
                }
                guard mask != 0 else { continue }
                let scalar = UnicodeScalar(0x2800 + Int(mask))!
                let bg = fillEnabled ? fillBG : baseBG
                setCell(cx, cy, String(Character(scalar)), strokeFG, bg)
            }
        }
    }
}

private enum _MouseKind {
    case leftDown
    case wheelUp
    case wheelDown
}

private enum _Event {
    case quit
    case esc
    case tab(shift: Bool)
    case up
    case down
    case left
    case right
    case home
    case end
    case enter
    case backspace
    case delete
    case char(UInt32)
    case mouse(x: Int, y: Int, kind: _MouseKind)
}

private struct _InputParser {
    private var bytes: [UInt8] = []
    private var pending: [_Event] = []
    private var inPaste = false

    mutating func push(_ chunk: ArraySlice<UInt8>) {
        bytes.append(contentsOf: chunk)
    }

    mutating func next() -> _Event? {
        if !pending.isEmpty { return pending.removeFirst() }
        if bytes.isEmpty { return nil }

        // Bracketed paste mode:
        // - Begin: ESC [ 200 ~
        // - End:   ESC [ 201 ~
        if inPaste {
            if bytes.count >= 6,
               bytes[0] == 0x1B, bytes[1] == UInt8(ascii: "["),
               bytes[2] == UInt8(ascii: "2"), bytes[3] == UInt8(ascii: "0"),
               bytes[4] == UInt8(ascii: "1"), bytes[5] == UInt8(ascii: "~") {
                bytes.removeFirst(6)
                inPaste = false
                return nil
            }
            return _nextUTF8ScalarEvent()
        }

        let b = bytes.removeFirst()

        // Quit.
        if b == UInt8(ascii: "q") { return .quit }

        // Control keys.
        if b == 9 { return .tab(shift: false) }
        if b == 13 || b == 10 { return .enter }
        if b == 127 || b == 8 { return .backspace }

        if b == 0x1B {
            // ESC sequences. If no more bytes, treat as ESC.
            guard let n0 = bytes.first else { return .esc }
            if n0 == UInt8(ascii: "[") {
                // CSI.
                bytes.removeFirst()
                // Bracketed paste begin: ESC [ 200 ~
                if bytes.count >= 4,
                   bytes[0] == UInt8(ascii: "2"), bytes[1] == UInt8(ascii: "0"),
                   bytes[2] == UInt8(ascii: "0"), bytes[3] == UInt8(ascii: "~") {
                    bytes.removeFirst(4)
                    inPaste = true
                    return nil
                }
                // Shift+Tab is ESC [ Z
                if let z = bytes.first, z == UInt8(ascii: "Z") {
                    bytes.removeFirst()
                    return .tab(shift: true)
                }
                // Arrow keys ESC [ A/B
                if let a = bytes.first, a == UInt8(ascii: "A") {
                    bytes.removeFirst()
                    return .up
                }
                if let b = bytes.first, b == UInt8(ascii: "B") {
                    bytes.removeFirst()
                    return .down
                }
                if let c = bytes.first, c == UInt8(ascii: "C") {
                    bytes.removeFirst()
                    return .right
                }
                if let d = bytes.first, d == UInt8(ascii: "D") {
                    bytes.removeFirst()
                    return .left
                }
                if let h = bytes.first, h == UInt8(ascii: "H") {
                    bytes.removeFirst()
                    return .home
                }
                if let f = bytes.first, f == UInt8(ascii: "F") {
                    bytes.removeFirst()
                    return .end
                }

                // Delete: ESC [ 3 ~
                if let three = bytes.first, three == UInt8(ascii: "3") {
                    if bytes.count >= 2, bytes[1] == UInt8(ascii: "~") {
                        bytes.removeFirst()
                        bytes.removeFirst()
                        return .delete
                    }
                }

                // SGR mouse: ESC [ < b ; x ; y M/m
                if let lt = bytes.first, lt == UInt8(ascii: "<") {
                    bytes.removeFirst()
                    if let (code, x, y, upDown) = _parseSGRMouse(&bytes) {
                        let kind: _MouseKind?
                        switch code {
                        case 0: kind = upDown ? nil : .leftDown
                        case 64: kind = .wheelUp
                        case 65: kind = .wheelDown
                        default: kind = nil
                        }
                        if let kind {
                            return .mouse(x: x - 1, y: y - 1, kind: kind)
                        }
                    }
                    return nil
                }

                return .esc
            }
            return .esc
        }

        bytes.insert(b, at: 0)
        return _nextUTF8ScalarEvent()
    }

    private mutating func _nextUTF8ScalarEvent() -> _Event? {
        guard !bytes.isEmpty else { return nil }
        let b = bytes.removeFirst()
        if b < 0x80 {
            return .char(UInt32(b))
        }

        let expected: Int
        if (b & 0xE0) == 0xC0 { expected = 2 }
        else if (b & 0xF0) == 0xE0 { expected = 3 }
        else if (b & 0xF8) == 0xF0 { expected = 4 }
        else {
            return nil
        }

        if bytes.count < expected - 1 {
            // Wait for more bytes.
            bytes.insert(b, at: 0)
            return nil
        }

        var seq = [UInt8]()
        seq.reserveCapacity(expected)
        seq.append(b)
        for _ in 0..<(expected - 1) {
            let c = bytes.removeFirst()
            if (c & 0xC0) != 0x80 {
                // Invalid continuation; drop and resync.
                return nil
            }
            seq.append(c)
        }

        let s = String(decoding: seq, as: UTF8.self)
        if s.unicodeScalars.count == 1, let scalar = s.unicodeScalars.first {
            return .char(scalar.value)
        }
        return nil
    }
}

private func _parseSGRMouse(_ bytes: inout [UInt8]) -> (Int, Int, Int, Bool)? {
    func parseInt() -> Int? {
        var v = 0
        var seen = false
        while let b = bytes.first {
            if b >= UInt8(ascii: "0"), b <= UInt8(ascii: "9") {
                bytes.removeFirst()
                v = v * 10 + Int(b - UInt8(ascii: "0"))
                seen = true
            } else {
                break
            }
        }
        return seen ? v : nil
    }

    guard let code = parseInt() else { return nil }
    guard bytes.first == UInt8(ascii: ";") else { return nil }
    bytes.removeFirst()
    guard let x = parseInt() else { return nil }
    guard bytes.first == UInt8(ascii: ";") else { return nil }
    bytes.removeFirst()
    guard let y = parseInt() else { return nil }
    guard let end = bytes.first else { return nil }
    bytes.removeFirst()
    if end == UInt8(ascii: "M") { return (code, x, y, false) }
    if end == UInt8(ascii: "m") { return (code, x, y, true) }
    return nil
}

private struct _RGB: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
}

private struct _Cell: Equatable {
    var ch: String
    var fg: _RGB
    var bg: _RGB
}

private func _fg(_ c: _RGB) -> String { "\u{001B}[38;2;\(c.r);\(c.g);\(c.b)m" }
private func _bg(_ c: _RGB) -> String { "\u{001B}[48;2;\(c.r);\(c.g);\(c.b)m" }
private func _move(row: Int, col: Int) -> String { "\u{001B}[\(row);\(col)H" }

private func _terminalSize() -> _Size {
    var ws = winsize()
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 {
        let w = max(1, Int(ws.ws_col))
        let h = max(1, Int(ws.ws_row))
        return _Size(width: w, height: h)
    }
    return _Size(width: 80, height: 24)
}

private func _sysWrite(_ fd: Int32, _ p: UnsafePointer<CChar>, _ n: Int) -> Int {
    #if os(Linux)
    return Glibc.write(fd, p, n)
    #else
    return Darwin.write(fd, p, n)
    #endif
}

private func _sysRead(_ fd: Int32, _ buf: inout [UInt8], _ n: Int) -> Int {
    return buf.withUnsafeMutableBytes { raw in
        guard let base = raw.baseAddress else { return -1 }
        #if os(Linux)
        return Glibc.read(fd, base, n)
        #else
        return Darwin.read(fd, base, n)
        #endif
    }
}

private func _setCC(_ t: inout termios, _ idx: Int32, _ value: cc_t) {
    withUnsafeMutablePointer(to: &t.c_cc) { ccp in
        ccp.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { ptr in
            ptr[Int(idx)] = value
        }
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        guard idx >= 0, idx < count else { return nil }
        return self[idx]
    }
}

private func _isBorderGlyph(_ c: Character) -> Bool {
    switch c {
    case "┌", "┐", "└", "┘", "┬", "┴", "├", "┤", "┼", "─", "│",
         "╭", "╮", "╰", "╯", "═", "║", "╬", "╦", "╩", "╠", "╣":
        return true
    default:
        return false
    }
}

private func _boxify(_ c: Character, left: Character?, right: Character?, up: Character?, down: Character?) -> Character {
    switch c {
    case "|":
        return "│"
    case "-":
        return "─"
    case "+":
        let l = (left == "-" || left == "+")
        let r = (right == "-" || right == "+")
        let u = (up == "|" || up == "+")
        let d = (down == "|" || down == "+")
        if r && d && !l && !u { return "┌" }
        if l && d && !r && !u { return "┐" }
        if r && u && !l && !d { return "└" }
        if l && u && !r && !d { return "┘" }
        if l && r && d && !u { return "┬" }
        if l && r && u && !d { return "┴" }
        if u && d && r && !l { return "├" }
        if u && d && l && !r { return "┤" }
        if (l || r) && (u || d) { return "┼" }
        if l || r { return "─" }
        if u || d { return "│" }
        return "┼"
    default:
        return c
    }
}
