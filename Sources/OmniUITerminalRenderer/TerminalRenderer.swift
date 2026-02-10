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
            var zbuf = Array(repeating: Int.min, count: size.width * size.height)
            // Rasterize typed ops into a cell buffer.
            func setCell(_ x: Int, _ y: Int, _ egc: String, _ fg: _RGB?, _ bg: _RGB?, z: Int) {
                guard x >= 0, y >= 0, x < size.width, y < size.height else { return }
                let idx = y * size.width + x
                if z < zbuf[idx] { return }
                var c = curr[idx]
                c.ch = egc
                if let fg { c.fg = fg }
                if let bg { c.bg = bg }
                curr[idx] = c
                zbuf[idx] = z
            }

            func intersect(_ a: _Rect, _ b: _Rect) -> _Rect? {
                let x0 = max(a.origin.x, b.origin.x)
                let y0 = max(a.origin.y, b.origin.y)
                let x1 = min(a.origin.x + a.size.width, b.origin.x + b.size.width)
                let y1 = min(a.origin.y + a.size.height, b.origin.y + b.size.height)
                if x1 <= x0 || y1 <= y0 { return nil }
                return _Rect(origin: _Point(x: x0, y: y0), size: _Size(width: x1 - x0, height: y1 - y0))
            }

            var clipStack: [_Rect] = [_Rect(origin: _Point(x: 0, y: 0), size: size)]
            func inClip(_ x: Int, _ y: Int) -> Bool {
                guard let c = clipStack.last else { return true }
                return c.contains(_Point(x: x, y: y))
            }

            var shapesByClip: [_Rect: [(_Rect, _ShapeNode, Int)]] = [:]

            for op in snapshot.ops {
                switch op.kind {
                case .glyph(let x, let y, let egc, let fg, let bg):
                    if !inClip(x, y) { break }
                    let mapped = egc.first ?? " "
                    let rfg = _resolveColor(fg)
                    let rbg = _resolveColor(bg)
                    var outFG = rfg ?? baseFG
                    let outBG = rbg ?? baseBG
                    if mapped == "*" { outFG = accentFG }
                    if _isBorderGlyph(mapped) { outFG = borderFG }
                    setCell(x, y, egc, outFG, outBG, z: op.zIndex)
                case .textRun(let x, let y, let text, let fg, let bg):
                    let rfg = _resolveColor(fg)
                    let rbg = _resolveColor(bg)
                    let outFG = rfg ?? baseFG
                    let outBG = rbg ?? baseBG
                    // Per-run specials aren't ideal, but this keeps legacy "border glyph" tinting working.
                    // We apply it per-character.
                    var xx = x
                    for ch in text {
                        if inClip(xx, y) {
                        let mapped = ch
                        var fg2 = outFG
                        if mapped == "*" { fg2 = accentFG }
                        if _isBorderGlyph(mapped) { fg2 = borderFG }
                        setCell(xx, y, String(ch), fg2, outBG, z: op.zIndex)
                        }
                        xx += 1
                        if xx >= size.width { break }
                    }
                case .fillRect(let rect, let color):
                    guard let c = _resolveColor(color) else { continue }
                    guard let clip = clipStack.last else { continue }
                    let rr = intersect(rect, clip) ?? _Rect(origin: _Point(x: 0, y: 0), size: _Size(width: 0, height: 0))
                    let x0 = max(0, rr.origin.x)
                    let y0 = max(0, rr.origin.y)
                    let x1 = min(size.width, rr.origin.x + rr.size.width)
                    let y1 = min(size.height, rr.origin.y + rr.size.height)
                    if x1 <= x0 || y1 <= y0 { continue }
                    for yy in y0..<y1 {
                        for xx in x0..<x1 {
                            setCell(xx, yy, " ", nil, c, z: op.zIndex)
                        }
                    }
                case .pushClip(let r):
                    if let top = clipStack.last, let i = intersect(top, r) {
                        clipStack.append(i)
                    } else {
                        clipStack.append(_Rect(origin: _Point(x: 0, y: 0), size: _Size(width: 0, height: 0)))
                    }
                case .popClip:
                    if clipStack.count > 1 { _ = clipStack.popLast() }
                case .shape:
                    if case .shape(let r, let s) = op.kind, let clip = clipStack.last, let rr = intersect(r, clip) {
                        // Render with braille clipped to rr.
                        shapesByClip[rr, default: []].append((r, s, op.zIndex))
                    }
                }
            }

            // Render shapes via braille into the cell grid (portable fallback).
            if !shapesByClip.isEmpty {
                for (clip, shapeRegions) in shapesByClip {
                    for (r, s, z) in shapeRegions {
                        BrailleRaster.render(
                            termSize: size,
                            shapes: [(r, s)],
                            clip: clip,
                            fillBG: _RGB(r: 0x12, g: 0x1B, b: 0x33),
                            strokeFG: borderFG,
                            baseBG: baseBG,
                            isEmpty: { x, y in curr[y * size.width + x].ch == " " },
                            set: { x, y, ch, fg, bg in setCell(x, y, ch, fg, bg, z: z) }
                        )
                    }
                }
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
    if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0 {
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
