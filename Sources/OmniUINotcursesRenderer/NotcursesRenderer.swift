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
        var userRequestedExit = false
        var exitNote: String? = nil
        let clock = ContinuousClock()
        let smokeDeadline: ContinuousClock.Instant? = {
            guard let raw = getenv("OMNIUI_SMOKE_SECONDS") else { return nil }
            let s = String(cString: raw)
            guard let secs = Double(s), secs > 0 else { return nil }
            return clock.now.advanced(by: .milliseconds(Int64(secs * 1000.0)))
        }()
        // Smoke mode is enabled via `OMNIUI_SMOKE_SECONDS` (useful for automated runs).
        defer {
            _ = notcurses_stop(nc)
            omni_restore_terminal()
            if !userRequestedExit, let exitNote {
                fputs("OmniUI notcurses renderer exited: \(exitNote)\n", stderr)
                fflush(stderr)
            }
        }

        _ = notcurses_mice_enable(nc, omni_ncmice_all_events())
        // We install our own signal handlers; leave terminal line signals enabled.

        let runtime = _UIRuntime()
        var prev: [_NCCell]? = nil
        var sprixelPlane: OpaquePointer? = nil
        var sprixelPlaneSize: (w: Int, h: Int) = (0, 0)
        var lastSprixelSig: Int? = nil
        let forceNoPixels = (getenv("TMUX") != nil) // tmux generally won't support Kitty graphics passthrough

        defer {
            if let p = sprixelPlane {
                ncplane_destroy(p)
            }
        }

        let q: UInt32 = 113
        let esc: UInt32 = omni_nckey_esc()
        let backspace: UInt32 = omni_nckey_backspace()
        let enter: UInt32 = omni_nckey_enter()
        let up: UInt32 = omni_nckey_up()
        let down: UInt32 = omni_nckey_down()
        let left: UInt32 = omni_nckey_left()
        let right: UInt32 = omni_nckey_right()
        let home: UInt32 = omni_nckey_home()
        let end: UInt32 = omni_nckey_end()
        let del: UInt32 = omni_nckey_delete()
        let button1: UInt32 = omni_nckey_button1()
        let scrollUp: UInt32 = omni_nckey_scroll_up()
        let scrollDown: UInt32 = omni_nckey_scroll_down()

        while !Task.isCancelled {
            if let deadline = smokeDeadline, clock.now >= deadline {
                userRequestedExit = true
                return
            }
            let sig = omni_signal_received()
            if sig != 0 {
                exitNote = "signal \(sig)"
                return
            }
            guard let stdplane = notcurses_stdplane(nc) else { break }

            var rows: UInt32 = 0
            var cols: UInt32 = 0
            ncplane_dim_yx(stdplane, &rows, &cols)

            let height = max(1, Int(rows))
            let width = max(1, Int(cols))

            let snapshot = runtime.debugRender(root(), size: _Size(width: width, height: height), renderShapeGlyphs: false)

            let baseFG = _NCRGB(r: 0xD8, g: 0xDB, b: 0xE2)
            let baseBG = _NCRGB(r: 0x0B, g: 0x10, b: 0x20)
            let focusFG = _NCRGB(r: 0xFF, g: 0xFF, b: 0xFF)
            let focusBG = _NCRGB(r: 0x1D, g: 0x4E, b: 0xD8)
            let accentFG = _NCRGB(r: 0x34, g: 0xD3, b: 0x99)
            let shapeFillBG = _NCRGB(r: 0x12, g: 0x1B, b: 0x33)
            let borderFG = _NCRGB(r: 0xF2, g: 0xF4, b: 0xF8)

            let focusRect = snapshot.focusedRect

            // Prefer sprixels/pixels for shapes/paths; fall back to braille rasterization if pixels aren't supported.
            let cellpix = _ncCellPix(nc)
            let canSprixel: Bool = {
                if forceNoPixels { return false }
                guard let cellpix else { return false }
                if notcurses_check_pixel_support(nc) == NCPIXEL_NONE { return false }
                return cellpix.cdimx > 0 && cellpix.cdimy > 0 && cellpix.maxpixelx > 0 && cellpix.maxpixely > 0
            }()

            if canSprixel, let cellpix {
                var hasher = Hasher()
                hasher.combine(width)
                hasher.combine(height)
                hasher.combine(cellpix.cdimx)
                hasher.combine(cellpix.cdimy)
                hasher.combine(snapshot.shapeRegions.count)
                for (r, s) in snapshot.shapeRegions {
                    hasher.combine(r)
                    hasher.combine(s.kind)
                    if let e = s.pathElements { hasher.combine(e.count) ; for el in e { hasher.combine(el) } }
                }
                let sig = hasher.finalize()

                if sprixelPlane == nil || sprixelPlaneSize.w != width || sprixelPlaneSize.h != height {
                    if let p = sprixelPlane {
                        ncplane_destroy(p)
                        sprixelPlane = nil
                    }
                    var popts = ncplane_options()
                    popts.y = 0
                    popts.x = 0
                    popts.rows = UInt32(height)
                    popts.cols = UInt32(width)
                    popts.name = nil
                    popts.userptr = nil
                    popts.resizecb = nil
                    popts.flags = 0
                    popts.margin_b = 0
                    popts.margin_r = 0
                    sprixelPlane = ncplane_create(stdplane, &popts)
                    sprixelPlaneSize = (width, height)
                    if let p = sprixelPlane {
                        // Ensure shapes are behind the standard plane (text).
                        _ = ncplane_move_above(p, nil)
                    }
                }

                if let p = sprixelPlane {
                    if lastSprixelSig != sig {
                        ncplane_erase(p)
                        let ok = _renderSprixels(
                            nc: nc,
                            plane: p,
                            termSize: _Size(width: width, height: height),
                            cellpix: cellpix,
                            shapes: snapshot.shapeRegions,
                            fill: shapeFillBG,
                            stroke: borderFG
                        )
                        if !ok {
                            ncplane_destroy(p)
                            sprixelPlane = nil
                            sprixelPlaneSize = (0, 0)
                            lastSprixelSig = nil
                        } else {
                            lastSprixelSig = sig
                        }
                    }
                }
            } else {
                // No pixel support; tear down any existing sprixel plane so it can't leave artifacts.
                if let p = sprixelPlane {
                    ncplane_destroy(p)
                    sprixelPlane = nil
                }
                sprixelPlaneSize = (0, 0)
                lastSprixelSig = nil
            }

            var curr = Array(repeating: _NCCell(ch: " ", fg: baseFG, bg: baseBG), count: width * height)
            let inCells = snapshot.cells
            if inCells.count == width * height {
                for y in 0..<height {
                    for x in 0..<width {
                        let s = inCells[y * width + x]
                        let mapped = s.first ?? " "

                        var fg = baseFG
                        var bg = baseBG

                        if let fr = focusRect, fr.contains(_Point(x: x, y: y)) {
                            fg = focusFG
                            bg = focusBG
                        } else if mapped == "*" {
                            fg = accentFG
                        } else if mapped == "·" {
                            // Shape fill token: render as a space with filled background.
                            fg = baseFG
                            bg = shapeFillBG
                        } else if _isBorderGlyph(mapped) {
                            fg = borderFG
                        }

                        let ch: String = (mapped == "·") ? " " : s
                        curr[y * width + x] = _NCCell(ch: ch, fg: fg, bg: bg)
                    }
                }
            }

            if !canSprixel {
                // Braille fallback: rasterize shape regions into braille characters, but only over
                // empty cells so overlay text isn't clobbered.
                _renderBraille(
                    termSize: _Size(width: width, height: height),
                    shapes: snapshot.shapeRegions,
                    curr: &curr,
                    baseBG: baseBG,
                    fillFG: shapeFillBG,
                    strokeFG: borderFG
                )
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

            let rr = notcurses_render(nc)
            if rr != 0 {
                exitNote = "notcurses_render() failed (\(rr))"
                return
            }

            // Drain any queued inputs.
            var ni = ncinput()
            while true {
                let id = notcurses_get_nblock(nc, &ni)
                if id == 0 {
                    break
                }

                if id == q {
                    userRequestedExit = true
                    return
                }
                if id == esc {
                    if runtime.hasExpandedPicker() {
                        runtime.collapseExpandedPicker()
                        continue
                    }
                    userRequestedExit = true
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
                            runtime._handleKey(.char(32))
                        } else {
                            runtime.activateFocused()
                        }
                    } else if id == backspace || id == 127 { // Backspace/Delete (ASCII DEL on macOS)
                        if runtime.isTextEditingFocused() {
                            runtime._handleKey(.backspace)
                        } else if runtime.canPopNavigation() {
                            runtime.popNavigation()
                        }
                    } else if id == del {
                        if runtime.isTextEditingFocused() {
                            runtime._handleKey(.delete)
                        }
                    } else if id == left {
                        if runtime.isTextEditingFocused() { runtime._handleKey(.left) }
                    } else if id == right {
                        if runtime.isTextEditingFocused() { runtime._handleKey(.right) }
                    } else if id == home {
                        if runtime.isTextEditingFocused() { runtime._handleKey(.home) }
                    } else if id == end {
                        if runtime.isTextEditingFocused() { runtime._handleKey(.end) }
                    } else if id < 0x110000 {
                        runtime._handleKey(.char(id))
                    }
                }
            }

            try await Task.sleep(nanoseconds: 16_000_000) // ~60Hz
        }
        if Task.isCancelled {
            exitNote = "task cancelled"
        } else {
            exitNote = "loop ended"
        }
        #else
        throw OmniUINotcursesRendererError.notSupportedOnThisPlatform
        #endif
    }
}

private struct _CellPix {
    var cdimy: Int
    var cdimx: Int
    var maxpixely: Int
    var maxpixelx: Int
}

private func _ncCellPix(_ nc: OpaquePointer) -> _CellPix? {
    var cdimy: UInt32 = 0
    var cdimx: UInt32 = 0
    var maxpixely: UInt32 = 0
    var maxpixelx: UInt32 = 0
    let rc = omni_notcurses_cellpix(nc, &cdimy, &cdimx, &maxpixely, &maxpixelx)
    if rc != 0 { return nil }
    return _CellPix(cdimy: Int(cdimy), cdimx: Int(cdimx), maxpixely: Int(maxpixely), maxpixelx: Int(maxpixelx))
}

private struct _RGBA {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
}

private func _renderSprixels(
    nc: OpaquePointer,
    plane: OpaquePointer,
    termSize: _Size,
    cellpix: _CellPix,
    shapes: [(_Rect, _ShapeNode)],
    fill: _NCRGB,
    stroke: _NCRGB
) -> Bool {
    guard termSize.width > 0, termSize.height > 0 else { return false }

    let fillRGB = _RGBA(r: fill.r, g: fill.g, b: fill.b, a: 0xFF)
    let strokeRGB = _RGBA(r: stroke.r, g: stroke.g, b: stroke.b, a: 0xFF)

    func clamp01(_ x: Double) -> Double { min(1.0, max(0.0, x)) }

    func blend(dst: inout _RGBA, src: _RGBA) {
        let sa = Double(src.a) / 255.0
        if sa <= 0 { return }
        let da = Double(dst.a) / 255.0
        let oa = sa + da * (1.0 - sa)
        if oa <= 0 {
            dst = _RGBA(r: 0, g: 0, b: 0, a: 0)
            return
        }
        func comp(_ sc: UInt8, _ dc: UInt8) -> UInt8 {
            let s = Double(sc) / 255.0
            let d = Double(dc) / 255.0
            let o = (s * sa + d * da * (1.0 - sa)) / oa
            return UInt8(clamping: Int(o * 255.0))
        }
        dst.r = comp(src.r, dst.r)
        dst.g = comp(src.g, dst.g)
        dst.b = comp(src.b, dst.b)
        dst.a = UInt8(clamping: Int(oa * 255.0))
    }

    func sdfRoundedRect(px: Double, py: Double, w: Double, h: Double, r: Double) -> Double {
        // In pixels, centered at (0,0) spanning [-w/2,w/2]x[-h/2,h/2].
        let qx = abs(px) - (w / 2.0 - r)
        let qy = abs(py) - (h / 2.0 - r)
        let ox = max(qx, 0.0)
        let oy = max(qy, 0.0)
        let outside = hypot(ox, oy)
        let inside = min(max(qx, qy), 0.0)
        return outside + inside - r
    }

    func sdfEllipse(px: Double, py: Double, rx: Double, ry: Double) -> Double {
        // Approximate distance in pixels using normalized radial distance.
        let nx = px / max(1e-6, rx)
        let ny = py / max(1e-6, ry)
        let k = sqrt(nx * nx + ny * ny)
        // Scale back to pixels (roughly) so AA thickness stays consistent.
        return (k - 1.0) * min(rx, ry)
    }

    func rasterizeFilledShape(kind: _ShapeKind, pixelW: Int, pixelH: Int, radiusPx: Double?) -> [UInt8] {
        var buf = Array(repeating: UInt8(0), count: pixelW * pixelH * 4)

        func get(_ x: Int, _ y: Int) -> _RGBA {
            let i = (y * pixelW + x) * 4
            return _RGBA(r: buf[i + 0], g: buf[i + 1], b: buf[i + 2], a: buf[i + 3])
        }
        func set(_ x: Int, _ y: Int, _ c: _RGBA) {
            let i = (y * pixelW + x) * 4
            buf[i + 0] = c.r
            buf[i + 1] = c.g
            buf[i + 2] = c.b
            buf[i + 3] = c.a
        }

        let w = Double(pixelW)
        let h = Double(pixelH)
        let cx = (w - 1.0) / 2.0
        let cy = (h - 1.0) / 2.0

        let strokeWidth = 2.0
        let halfStroke = strokeWidth / 2.0

        for y in 0..<pixelH {
            for x in 0..<pixelW {
                let px = Double(x) - cx
                let py = Double(y) - cy

                let dist: Double
                switch kind {
                case .rectangle:
                    dist = sdfRoundedRect(px: px, py: py, w: w, h: h, r: 0.0)
                case .roundedRectangle:
                    let r = max(0.0, min(min(w, h) / 2.0, radiusPx ?? 0.0))
                    dist = sdfRoundedRect(px: px, py: py, w: w, h: h, r: r)
                case .capsule:
                    let r = max(0.0, min(w, h) / 2.0)
                    dist = sdfRoundedRect(px: px, py: py, w: w, h: h, r: r)
                case .circle:
                    let r = min(w, h) / 2.0
                    dist = sdfEllipse(px: px, py: py, rx: r, ry: r)
                case .ellipse:
                    let rx = w / 2.0
                    let ry = h / 2.0
                    dist = sdfEllipse(px: px, py: py, rx: rx, ry: ry)
                case .path:
                    continue
                }

                // AA: treat the edge as 1px wide transition.
                let fillA = clamp01(0.5 - dist) // inside => 1, outside => 0
                if fillA <= 0 { continue }

                let strokeA = clamp01((halfStroke + 0.5) - abs(dist))

                var out = _RGBA(r: 0, g: 0, b: 0, a: 0)
                if fillA > 0 {
                    out = _RGBA(r: fillRGB.r, g: fillRGB.g, b: fillRGB.b, a: UInt8(clamping: Int(fillA * 255.0)))
                }
                if strokeA > 0 {
                    let s = _RGBA(r: strokeRGB.r, g: strokeRGB.g, b: strokeRGB.b, a: UInt8(clamping: Int(strokeA * 255.0)))
                    blend(dst: &out, src: s)
                }

                let cur = get(x, y)
                var dst = cur
                blend(dst: &dst, src: out)
                set(x, y, dst)
            }
        }

        return buf
    }

    func rasterizePath(elements: [Path.Element], pixelW: Int, pixelH: Int) -> [UInt8] {
        var buf = Array(repeating: UInt8(0), count: pixelW * pixelH * 4)

        func put(_ x: Int, _ y: Int, _ c: _RGBA) {
            guard x >= 0, y >= 0, x < pixelW, y < pixelH else { return }
            let i = (y * pixelW + x) * 4
            var dst = _RGBA(r: buf[i + 0], g: buf[i + 1], b: buf[i + 2], a: buf[i + 3])
            blend(dst: &dst, src: c)
            buf[i + 0] = dst.r
            buf[i + 1] = dst.g
            buf[i + 2] = dst.b
            buf[i + 3] = dst.a
        }

        func drawLine(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, thickness: Int) {
            // Bresenham with simple square brush.
            var x0 = x0, y0 = y0
            let dx = abs(x1 - x0)
            let sx = x0 < x1 ? 1 : -1
            let dy = -abs(y1 - y0)
            let sy = y0 < y1 ? 1 : -1
            var err = dx + dy
            while true {
                let t = max(1, thickness)
                let r = t / 2
                for yy in (y0 - r)...(y0 + r) {
                    for xx in (x0 - r)...(x0 + r) {
                        put(xx, yy, _RGBA(r: strokeRGB.r, g: strokeRGB.g, b: strokeRGB.b, a: 0xFF))
                    }
                }
                if x0 == x1 && y0 == y1 { break }
                let e2 = 2 * err
                if e2 >= dy { err += dy; x0 += sx }
                if e2 <= dx { err += dx; y0 += sy }
            }
        }

        _strokePath(
            elements: elements,
            x0: 0, y0: 0, x1: pixelW, y1: pixelH,
            drawLine: { x0, y0, x1, y1 in
                drawLine(x0, y0, x1, y1, thickness: 2)
            },
            fillEllipse: { _, _, _, _ in },
            strokeRect: { _, _, _, _ in }
        )

        return buf
    }

    var ok = true
    for (r, s) in shapes {
        guard r.size.width > 0, r.size.height > 0 else { continue }
        if r.origin.x < 0 || r.origin.y < 0 { continue }
        if r.origin.x + r.size.width > termSize.width { continue }
        if r.origin.y + r.size.height > termSize.height { continue }

        let pixelW = r.size.width * cellpix.cdimx
        let pixelH = r.size.height * cellpix.cdimy
        if pixelW <= 0 || pixelH <= 0 { continue }
        if pixelW > cellpix.maxpixelx || pixelH > cellpix.maxpixely { continue }

        let buf: [UInt8]
        switch s.kind {
        case .path:
            buf = rasterizePath(elements: s.pathElements ?? [], pixelW: pixelW, pixelH: pixelH)
        case .roundedRectangle(let cr):
            buf = rasterizeFilledShape(kind: s.kind, pixelW: pixelW, pixelH: pixelH, radiusPx: Double(cr) * Double(cellpix.cdimx))
        default:
            buf = rasterizeFilledShape(kind: s.kind, pixelW: pixelW, pixelH: pixelH, radiusPx: nil)
        }

        var blitOK = false
        buf.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            guard let ncv = ncvisual_from_rgba(base, Int32(pixelH), Int32(pixelW * 4), Int32(pixelW)) else { return }
            defer { ncvisual_destroy(ncv) }

            var vopts = ncvisual_options()
            vopts.n = plane
            vopts.scaling = NCSCALE_NONE
            vopts.y = Int32(r.origin.y)
            vopts.x = Int32(r.origin.x)
            vopts.begy = 0
            vopts.begx = 0
            vopts.leny = 0
            vopts.lenx = 0
            vopts.blitter = ncblitter_e(rawValue: omni_ncblit_pixel())
            vopts.flags = omni_ncvisual_option_blend() | omni_ncvisual_option_nodegrade()
            vopts.transcolor = 0
            vopts.pxoffy = 0
            vopts.pxoffx = 0

            blitOK = (ncvisual_blit(nc, ncv, &vopts) != nil)
        }
        if !blitOK {
            ok = false
            break
        }
    }

    return ok
}

private func _fillRoundedRect(
    x0: Int,
    y0: Int,
    x1: Int,
    y1: Int,
    radius: Int,
    border: Int,
    fill: _RGBA,
    stroke: _RGBA,
    setPixel: (Int, Int, _RGBA) -> Void
) {
    let w = x1 - x0
    let h = y1 - y0
    guard w > 0, h > 0 else { return }

    let rOuter = max(0, radius)
    let rInner = max(0, radius - border)

    func inside(_ x: Int, _ y: Int, _ inset: Int, _ r: Int) -> Bool {
        let ax0 = x0 + inset
        let ay0 = y0 + inset
        let ax1 = x1 - inset
        let ay1 = y1 - inset
        if x < ax0 || x >= ax1 || y < ay0 || y >= ay1 { return false }

        let rx = r
        let ry = r
        // Fast path: not in a corner square.
        if x >= ax0 + rx && x < ax1 - rx { return true }
        if y >= ay0 + ry && y < ay1 - ry { return true }

        // Corner arcs.
        let cx = (x < ax0 + rx) ? (ax0 + rx - 1) : (ax1 - rx)
        let cy = (y < ay0 + ry) ? (ay0 + ry - 1) : (ay1 - ry)
        let dx = x - cx
        let dy = y - cy
        return dx * dx + dy * dy <= max(1, rx - 1) * max(1, rx - 1)
    }

    for y in y0..<y1 {
        for x in x0..<x1 {
            let out = inside(x, y, 0, rOuter)
            if !out { continue }
            let inn = inside(x, y, border, rInner)
            setPixel(x, y, inn ? fill : stroke)
        }
    }
}

private func _strokePath(
    elements: [Path.Element],
    x0: Int, y0: Int, x1: Int, y1: Int,
    drawLine: (Int, Int, Int, Int) -> Void,
    fillEllipse: (Int, Int, Int, Int) -> Void,
    strokeRect: (Int, Int, Int, Int) -> Void
) {
    // Map element coordinates into the target pixel rect by normalizing to the
    // bounds of the path data.
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
            consider(p)
            consider(c)
        case .curve(let p, let c1, let c2):
            consider(p)
            consider(c1)
            consider(c2)
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
        return
    }

    let rangeX = max(1e-6, maxX - minX)
    let rangeY = max(1e-6, maxY - minY)
    let pad = 2
    let tw = max(1, (x1 - x0) - pad * 2)
    let th = max(1, (y1 - y0) - pad * 2)

    func map(_ p: CGPoint) -> (Int, Int) {
        let nx = (Double(p.x) - minX) / rangeX
        let ny = (Double(p.y) - minY) / rangeY
        let px = x0 + pad + Int(nx * Double(tw - 1))
        let py = y0 + pad + Int(ny * Double(th - 1))
        return (px, py)
    }

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
                drawLine(c.0, c.1, mp.0, mp.1)
            }
            curr = mp
            currSrc = p
        case .rect(let r):
            let p0 = map(r.origin)
            let p1 = map(CGPoint(x: r.origin.x + r.size.width, y: r.origin.y + r.size.height))
            strokeRect(min(p0.0, p1.0), min(p0.1, p1.1), max(p0.0, p1.0), max(p0.1, p1.1))
        case .ellipse(let r):
            let p0 = map(r.origin)
            let p1 = map(CGPoint(x: r.origin.x + r.size.width, y: r.origin.y + r.size.height))
            fillEllipse(min(p0.0, p1.0), min(p0.1, p1.1), max(p0.0, p1.0), max(p0.1, p1.1))
        case .quadCurve(let p, let c):
            guard let s0 = currSrc else {
                currSrc = p
                curr = map(p)
                break
            }
            let steps = 24
            var prev = s0
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                let a = _lerp(s0, c, t)
                let b = _lerp(c, p, t)
                let q = _lerp(a, b, t)
                let m0 = map(prev)
                let m1 = map(q)
                drawLine(m0.0, m0.1, m1.0, m1.1)
                prev = q
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
            var prev = s0
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                let q = _cubic(s0, c1, c2, p, t)
                let m0 = map(prev)
                let m1 = map(q)
                drawLine(m0.0, m0.1, m1.0, m1.1)
                prev = q
            }
            currSrc = p
            curr = map(p)
        case .closeSubpath:
            if let c = curr, let s = start {
                drawLine(c.0, c.1, s.0, s.1)
            }
            curr = start
            currSrc = startSrc
        }
    }
}

private func _lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
    CGPoint(
        x: CGFloat(Double(a.x) + (Double(b.x) - Double(a.x)) * t),
        y: CGFloat(Double(a.y) + (Double(b.y) - Double(a.y)) * t)
    )
}

private func _cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, _ t: Double) -> CGPoint {
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

private func _isShapePlaceholderCell(_ ch: String) -> Bool {
    guard let c = ch.first else { return false }
    if c == " " { return false }
    if c == "·" { return true }
    if _isBorderGlyph(c) { return true }
    // Path placeholder glyphs used by the debug layout.
    if c == "╱" || c == "╲" || c == "⬭" || c == "─" { return true }
    return false
}

private func _renderBraille(
    termSize: _Size,
    shapes: [(_Rect, _ShapeNode)],
    curr: inout [_NCCell],
    baseBG: _NCRGB,
    fillFG: _NCRGB,
    strokeFG: _NCRGB
) {
    func setCell(_ x: Int, _ y: Int, _ ch: String, _ fg: _NCRGB, _ bg: _NCRGB) {
        guard x >= 0, y >= 0, x < termSize.width, y < termSize.height else { return }
        let idx = y * termSize.width + x
        if curr[idx].ch != " " { return }
        curr[idx] = _NCCell(ch: ch, fg: fg, bg: bg)
    }

    func dotBit(_ sx: Int, _ sy: Int) -> UInt8 {
        // Braille dots:
        // (0,0)=1 (0,1)=2 (0,2)=3 (1,0)=4 (1,1)=5 (1,2)=6 (0,3)=7 (1,3)=8
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

    for (r, s) in shapes {
        let x0 = max(0, r.origin.x)
        let y0 = max(0, r.origin.y)
        let x1 = min(termSize.width, r.origin.x + r.size.width)
        let y1 = min(termSize.height, r.origin.y + r.size.height)
        guard x1 > x0, y1 > y0 else { continue }

        // Rasterize at braille-dot resolution (2x4 per cell). For filled shapes, we:
        // - paint fully-covered cells as spaces with filled background
        // - paint partially-covered cells as braille dots with stroke foreground + filled background
        // This yields a solid interior with a smooth-ish edge, instead of a noisy dotted fill.
        let regionW = x1 - x0
        let regionH = y1 - y0
        let subW = regionW * 2
        let subH = regionH * 4
        if subW <= 0 || subH <= 0 { continue }

        func insideFilledShape(_ sx: Int, _ sy: Int) -> Bool {
            // Use the center of the subpixel for sampling.
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
                return _insideRoundedRect(x: x, y: y, w: w, h: h, rx: rx, ry: ry)
            case .capsule:
                let rx = max(1.0, min(w, h) / 2.0)
                let ry = rx
                return _insideRoundedRect(x: x, y: y, w: w, h: h, rx: rx, ry: ry)
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

        // Fast path: stroke-only paths.
        if s.kind == .path {
            var sub = Array(repeating: false, count: subW * subH)
            func setSub(_ sx: Int, _ sy: Int) {
                guard sx >= 0, sy >= 0, sx < subW, sy < subH else { return }
                sub[sy * subW + sx] = true
            }
            if let elements = s.pathElements {
                _strokePathBraille(elements: elements, subW: subW, subH: subH, set: setSub)
            }
            for cy in y0..<y1 {
                for cx in x0..<x1 {
                    var mask: UInt8 = 0
                    let baseSX = (cx - x0) * 2
                    let baseSY = (cy - y0) * 4
                    for sy in 0..<4 {
                        for sx in 0..<2 {
                            if sub[(baseSY + sy) * subW + (baseSX + sx)] {
                                mask |= dotBit(sx, sy)
                            }
                        }
                    }
                    guard mask != 0 else { continue }
                    let scalar = UnicodeScalar(0x2800 + Int(mask))!
                    setCell(cx, cy, String(Character(scalar)), strokeFG, baseBG)
                }
            }
            continue
        }

        // Filled shapes.
        for cy in y0..<y1 {
            for cx in x0..<x1 {
                var insideCount = 0
                var mask: UInt8 = 0
                let baseSX = (cx - x0) * 2
                let baseSY = (cy - y0) * 4
                for sy in 0..<4 {
                    for sx in 0..<2 {
                        if insideFilledShape(baseSX + sx, baseSY + sy) {
                            insideCount += 1
                            mask |= dotBit(sx, sy)
                        }
                    }
                }
                if insideCount == 0 {
                    continue
                } else if insideCount == 8 {
                    setCell(cx, cy, " ", fillFG, fillFG) // solid fill via background; fg doesn't matter
                } else {
                    let scalar = UnicodeScalar(0x2800 + Int(mask))!
                    setCell(cx, cy, String(Character(scalar)), strokeFG, fillFG)
                }
            }
        }
    }
}

private func _insideRoundedRect(x: Double, y: Double, w: Double, h: Double, rx: Double, ry: Double) -> Bool {
    // Standard rounded-rect: central rect + four quarter-ellipses.
    let left = 0.0
    let top = 0.0
    let right = w
    let bottom = h

    let crx = min(rx, w / 2.0)
    let cry = min(ry, h / 2.0)

    // Central bands.
    if (x >= left + crx && x <= right - crx) { return true }
    if (y >= top + cry && y <= bottom - cry) { return true }

    // Corner ellipses.
    let cx = (x < left + crx) ? (left + crx) : (right - crx)
    let cy = (y < top + cry) ? (top + cry) : (bottom - cry)
    let dx = (x - cx) / max(1e-6, crx)
    let dy = (y - cy) / max(1e-6, cry)
    return (dx * dx + dy * dy) <= 1.0
}

private func _strokePathBraille(
    elements: [Path.Element],
    subW: Int,
    subH: Int,
    set: (Int, Int) -> Void
) {
    // Normalize to element bounds then draw into [0..subW)x[0..subH).
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
            consider(p)
            consider(c)
        case .curve(let p, let c1, let c2):
            consider(p)
            consider(c1)
            consider(c2)
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

    if !minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite { return }
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
            set(x0, y0)
            if x0 == x1 && y0 == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
    }

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
            if let c = curr { line(c.0, c.1, mp.0, mp.1) }
            curr = mp
            currSrc = p
        case .rect(let r):
            let p0 = map(r.origin)
            let p1 = map(CGPoint(x: r.origin.x + r.size.width, y: r.origin.y + r.size.height))
            let ax0 = min(p0.0, p1.0), ay0 = min(p0.1, p1.1)
            let ax1 = max(p0.0, p1.0), ay1 = max(p0.1, p1.1)
            line(ax0, ay0, ax1, ay0)
            line(ax1, ay0, ax1, ay1)
            line(ax1, ay1, ax0, ay1)
            line(ax0, ay1, ax0, ay0)
        case .ellipse(let r):
            // Approximate ellipse outline by sampling angles.
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
                if let p = prev { line(p.0, p.1, x, y) }
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
                let a = _lerp(s0, c, tt)
                let b = _lerp(c, p, tt)
                let q = _lerp(a, b, tt)
                let m0 = map(prevP)
                let m1 = map(q)
                line(m0.0, m0.1, m1.0, m1.1)
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
                let q = _cubic(s0, c1, c2, p, tt)
                let m0 = map(prevP)
                let m1 = map(q)
                line(m0.0, m0.1, m1.0, m1.1)
                prevP = q
            }
            currSrc = p
            curr = map(p)
        case .closeSubpath:
            if let c = curr, let s = start { line(c.0, c.1, s.0, s.1) }
            curr = start
            currSrc = startSrc
        }
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
