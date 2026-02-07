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

            ncplane_erase(stdplane)

            for y in 0..<height {
                let src = y
                guard src < snapshot.lines.count else { break }
                let line = snapshot.lines[src]
                line.utf8CString.withUnsafeBufferPointer { buf in
                    _ = ncplane_putstr_yx(stdplane, Int32(y), 0, buf.baseAddress)
                }
            }

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
                        if runtime.hasExpandedPicker() {
                            runtime.focusNextWithinExpandedPicker()
                        } else {
                            runtime.focusNext()
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
                    } else if id == backspace {
                        runtime._handleKeyPress(8)
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
