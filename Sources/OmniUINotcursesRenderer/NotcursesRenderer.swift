import OmniUICore

#if os(Linux) || os(macOS)
import CNotcurses
#if os(Linux)
import Glibc
#else
import Darwin
#endif
#endif

public enum OmniUINotcursesRendererError: Error {
    case notSupportedOnThisPlatform
    case notcursesUnavailable
}

/// A minimal notcurses-based renderer loop.
///
/// This currently renders using OmniUICore's debug snapshot (plaintext grid) and uses notcurses
/// for drawing + input (mouse clicks + scroll wheel + basic keyboard).
public struct NotcursesApp<V: View> {
    let root: () -> V

    public init(root: @escaping () -> V) {
        self.root = root
    }

    @MainActor
    public func run() async throws {
        #if os(Linux) || os(macOS)
        omni_install_signal_handlers()

        var opts = notcurses_options()
        opts.flags |= UInt64(NCOPTION_SUPPRESS_BANNERS)
        guard let nc = notcurses_init(&opts, stdout) else {
            omni_restore_terminal()
            throw OmniUINotcursesRendererError.notcursesUnavailable
        }
        defer {
            _ = notcurses_stop(nc)
            omni_restore_terminal()
        }

        _ = notcurses_mice_enable(nc, omni_ncmice_all_events())
        // We install our own signal handlers; leave terminal line signals enabled.

        let runtime = _UIRuntime()
        var prev: [_NCCell]? = nil
        let q: UInt32 = 113
        let esc: UInt32 = omni_nckey_esc()
        let backspace: UInt32 = omni_nckey_backspace()
        let enter: UInt32 = omni_nckey_enter()
        let up: UInt32 = omni_nckey_up()
        let down: UInt32 = omni_nckey_down()
        let button1: UInt32 = omni_nckey_button1()
        let scrollUp: UInt32 = omni_nckey_scroll_up()
        let scrollDown: UInt32 = omni_nckey_scroll_down()

        while !Task.isCancelled {
            if omni_signal_received() != 0 {
                return
            }
            guard let stdplane = notcurses_stdplane(nc) else { break }

            var rows: UInt32 = 0
            var cols: UInt32 = 0
            ncplane_dim_yx(stdplane, &rows, &cols)

            let height = max(1, Int(rows))
            let width = max(1, Int(cols))

            let snapshot = runtime.debugRender(root(), size: _Size(width: width, height: height))

            let baseFG = _NCRGB(r: 0xD8, g: 0xDB, b: 0xE2)
            let baseBG = _NCRGB(r: 0x0B, g: 0x10, b: 0x20)
            let focusFG = _NCRGB(r: 0xFF, g: 0xFF, b: 0xFF)
            let focusBG = _NCRGB(r: 0x1D, g: 0x4E, b: 0xD8)
            let accentFG = _NCRGB(r: 0x34, g: 0xD3, b: 0x99)

            let focusRect = snapshot.focusedRect

            var curr = Array(repeating: _NCCell(ch: " ", fg: baseFG, bg: baseBG), count: width * height)
            let lineChars: [[Character]] = snapshot.lines.map { Array($0) }
            for y in 0..<height {
                guard y < lineChars.count else { break }
                let chars = lineChars[y]
                for x in 0..<min(width, chars.count) {
                    let c = chars[x]
                    let left = x > 0 ? chars[x - 1] : nil
                    let right = x + 1 < chars.count ? chars[x + 1] : nil
                    let up: Character? = (y > 0 && y - 1 < lineChars.count) ? lineChars[y - 1][safe: x] : nil
                    let down: Character? = (y + 1 < lineChars.count) ? lineChars[y + 1][safe: x] : nil
                    let mapped = _boxify(c, left: left, right: right, up: up, down: down)

                    var fg = baseFG
                    var bg = baseBG

                    if let fr = focusRect, fr.contains(_Point(x: x, y: y)) {
                        fg = focusFG
                        bg = focusBG
                    } else if mapped == "*" {
                        fg = accentFG
                    }

                    curr[y * width + x] = _NCCell(ch: String(mapped), fg: fg, bg: bg)
                }
            }

            // Differential paint (cell-level). This avoids full repaint when only a few cells change.
            let toPaint: [(Int, _NCCell)]
            if let prev {
                toPaint = curr.enumerated().compactMap { idx, c in prev[idx] == c ? nil : (idx, c) }
            } else {
                toPaint = curr.enumerated().map { ($0.offset, $0.element) }
            }

            // Track ncplane style state to avoid redundant setters.
            var lastFG: _NCRGB? = nil
            var lastBG: _NCRGB? = nil

            for (idx, cell) in toPaint {
                let y = idx / width
                let x = idx % width
                if lastFG == nil || lastFG! != cell.fg {
                    _ = ncplane_set_fg_rgb8(stdplane, UInt32(cell.fg.r), UInt32(cell.fg.g), UInt32(cell.fg.b))
                    lastFG = cell.fg
                }
                if lastBG == nil || lastBG! != cell.bg {
                    _ = ncplane_set_bg_rgb8(stdplane, UInt32(cell.bg.r), UInt32(cell.bg.g), UInt32(cell.bg.b))
                    lastBG = cell.bg
                }
                cell.ch.utf8CString.withUnsafeBufferPointer { buf in
                    if let p = buf.baseAddress {
                        _ = ncplane_putegc_yx(stdplane, Int32(y), Int32(x), p, nil)
                    }
                }
            }

            prev = curr

            _ = notcurses_render(nc)

            // Drain any queued inputs.
            var ni = ncinput()
            while true {
                let id = notcurses_get_nblock(nc, &ni)
                if id == 0 {
                    break
                }

                if id == q {
                    return
                }
                if id == esc {
                    if runtime.hasExpandedPicker() {
                        runtime.collapseExpandedPicker()
                        continue
                    }
                    return
                }

                // notcurses can deliver PRESS+RELEASE for mouse buttons and keys. Only react to:
                // - mouse click/scroll on PRESS
                // - keypresses on PRESS and REPEAT
                if ni.evtype == NCTYPE_PRESS {
                    if id == button1 {
                        snapshot.click(x: Int(ni.x), y: Int(ni.y))
                        continue
                    } else if id == scrollUp {
                        snapshot.scroll(x: Int(ni.x), y: Int(ni.y), deltaY: -1)
                        continue
                    } else if id == scrollDown {
                        snapshot.scroll(x: Int(ni.x), y: Int(ni.y), deltaY: 1)
                        continue
                    }
                }

                if ni.evtype == NCTYPE_PRESS || ni.evtype == NCTYPE_REPEAT {
                    if id == 9 { // Tab
                        let isShift = omni_ncinput_shift(&ni) != 0
                        if isShift {
                            if runtime.hasExpandedPicker() {
                                runtime.focusPrevWithinExpandedPicker()
                            } else {
                                runtime.focusPrev()
                            }
                        } else {
                            if runtime.hasExpandedPicker() {
                                runtime.focusNextWithinExpandedPicker()
                            } else {
                                runtime.focusNext()
                            }
                        }
                    } else if id == up {
                        if runtime.hasExpandedPicker() {
                            runtime.focusPrevWithinExpandedPicker()
                        } else {
                            runtime.focusPrev()
                        }
                    } else if id == down {
                        if runtime.hasExpandedPicker() {
                            runtime.focusNextWithinExpandedPicker()
                        } else {
                            runtime.focusNext()
                        }
                    } else if id == enter || id == 10 || id == 13 { // Enter/Return
                        runtime.activateFocused()
                    } else if id == 32 { // Space
                        if runtime.isTextEditingFocused() {
                            runtime._handleKeyPress(32)
                        } else {
                            runtime.activateFocused()
                        }
                    } else if id == backspace || id == 127 { // Backspace/Delete (ASCII DEL on macOS)
                        if runtime.isTextEditingFocused() {
                            runtime._handleKeyPress(8)
                        } else if runtime.canPopNavigation() {
                            runtime.popNavigation()
                        }
                    } else if id < 0x110000 {
                        runtime._handleKeyPress(id)
                    }
                }
            }

            try await Task.sleep(nanoseconds: 16_000_000) // ~60Hz
        }
        #else
        throw OmniUINotcursesRendererError.notSupportedOnThisPlatform
        #endif
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        guard idx >= 0, idx < count else { return nil }
        return self[idx]
    }
}

private struct _NCRGB: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
}

private struct _NCCell: Equatable {
    var ch: String
    var fg: _NCRGB
    var bg: _NCRGB
}

private func _boxify(_ c: Character, left: Character?, right: Character?, up: Character?, down: Character?) -> Character {
    // Convert ASCII box drawing used by the debug snapshot into Unicode box drawing.
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
        // Corners
        if r && d && !l && !u { return "┌" }
        if l && d && !r && !u { return "┐" }
        if r && u && !l && !d { return "└" }
        if l && u && !r && !d { return "┘" }
        // Tee junctions
        if l && r && d && !u { return "┬" }
        if l && r && u && !d { return "┴" }
        if u && d && r && !l { return "├" }
        if u && d && l && !r { return "┤" }
        // Cross/lines
        if (l || r) && (u || d) { return "┼" }
        if l || r { return "─" }
        if u || d { return "│" }
        return "┼"
    default:
        return c
    }
}
