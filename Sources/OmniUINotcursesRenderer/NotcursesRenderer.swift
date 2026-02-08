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

private struct _NCShapePlaneEntry {
    var plane: OpaquePointer
    var rect: _Rect
    var sig: Int
}

/// A minimal notcurses-based renderer loop.
///
/// This renders OmniUICore's typed `RenderOp`s and uses notcurses for drawing + input
/// (mouse clicks + scroll wheel + basic keyboard).
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
        // Prime notcurses once so the stdplane dimensions/colors are stable before our first frame.
        // Without this, some terminals report 0x0 for a short period and we'd "render" a 1x1 frame.
        _ = notcurses_render(nc)
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
        let forceNoPixels = (getenv("TMUX") != nil) // tmux generally won't support Kitty graphics passthrough
        var didRenderAtLeastOneFullFrame = false
        var shapePlanes: [Int: _NCShapePlaneEntry] = [:]

        defer {
            for (_, e) in shapePlanes {
                ncplane_destroy(e.plane)
            }
            shapePlanes.removeAll()
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

            // Some terminals report 0x0 until at least one render; avoid "1x1" diffs that
            // make it look like nothing rendered until the user interacts.
            if rows == 0 || cols == 0 {
                _ = notcurses_render(nc)
                try await Task.sleep(nanoseconds: 16_000_000)
                continue
            }

            let height = Int(rows)
            let width = Int(cols)

            let snapshot = runtime.render(root(), size: _Size(width: width, height: height))

            let baseFG = _NCRGB(r: 0xD8, g: 0xDB, b: 0xE2)
            let baseBG = _NCRGB(r: 0x0B, g: 0x10, b: 0x20)
            let focusFG = _NCRGB(r: 0xFF, g: 0xFF, b: 0xFF)
            let focusBG = _NCRGB(r: 0x1D, g: 0x4E, b: 0xD8)
            let accentFG = _NCRGB(r: 0x34, g: 0xD3, b: 0x99)
            let shapeFillBG = _NCRGB(r: 0x12, g: 0x1B, b: 0x33)
            let borderFG = _NCRGB(r: 0xF2, g: 0xF4, b: 0xF8)

            let focusRect = snapshot.focusedRect

            // Force a full repaint on the very first frame and any terminal resize.
            // This fixes "background/shapes only appear after first interaction" issues by ensuring
            // we explicitly set every cell at least once.
            if !didRenderAtLeastOneFullFrame || (prev != nil && prev!.count != width * height) {
                prev = nil
                didRenderAtLeastOneFullFrame = true
                ncplane_home(stdplane)
                ncplane_erase(stdplane)
            }

            // Prefer sprixels/pixels for shapes/paths; fall back to braille rasterization if pixels aren't supported.
            let cellpix = _ncCellPix(nc)
            let canSprixel: Bool = {
                if forceNoPixels { return false }
                guard let cellpix else { return false }
                if notcurses_check_pixel_support(nc) == NCPIXEL_NONE { return false }
                return cellpix.cdimx > 0 && cellpix.cdimy > 0 && cellpix.maxpixelx > 0 && cellpix.maxpixely > 0
            }()

            var curr = Array(repeating: _NCCell(ch: " ", fg: baseFG, bg: baseBG), count: width * height)
            var zbuf = Array(repeating: Int.min, count: width * height)
            func setCell(_ x: Int, _ y: Int, _ egc: String, _ fg: _NCRGB?, _ bg: _NCRGB?, z: Int) {
                guard x >= 0, y >= 0, x < width, y < height else { return }
                let idx = y * width + x
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

            let fullClip = _Rect(origin: _Point(x: 0, y: 0), size: _Size(width: width, height: height))
            var clipStack: [_Rect] = [fullClip]
            func inClip(_ x: Int, _ y: Int) -> Bool {
                guard let c = clipStack.last else { return true }
                return c.contains(_Point(x: x, y: y))
            }

            // Shapes either go to sprixels (full-screen / unclipped only) or to braille (clipped fallback).
            var shapesForSprixel: [(_Rect, _ShapeNode)] = []
            shapesForSprixel.reserveCapacity(16)
            var shapesByClip: [_Rect: [(_Rect, _ShapeNode, Int)]] = [:]

            for op in snapshot.ops {
                switch op.kind {
                case .glyph(let x, let y, let egc, let fg, let bg):
                    if !inClip(x, y) { break }
                    let mapped = egc.first ?? " "
                    var outFG = _resolveColorNC(fg) ?? baseFG
                    let outBG = _resolveColorNC(bg) ?? baseBG
                    if mapped == "*" { outFG = accentFG }
                    if _isBorderGlyph(mapped) { outFG = borderFG }
                    setCell(x, y, egc, outFG, outBG, z: op.zIndex)
                case .textRun(let x, let y, let text, let fg, let bg):
                    let outFG = _resolveColorNC(fg) ?? baseFG
                    let outBG = _resolveColorNC(bg) ?? baseBG
                    var xx = x
                    for ch in text {
                        if inClip(xx, y) {
                        var fg2 = outFG
                        if ch == "*" { fg2 = accentFG }
                        if _isBorderGlyph(ch) { fg2 = borderFG }
                        setCell(xx, y, String(ch), fg2, outBG, z: op.zIndex)
                        }
                        xx += 1
                        if xx >= width { break }
                    }
                case .fillRect(let rect, let color):
                    guard let c = _resolveColorNC(color) else { continue }
                    guard let top = clipStack.last, let rr = intersect(rect, top) else { continue }
                    let x0 = max(0, rr.origin.x)
                    let y0 = max(0, rr.origin.y)
                    let x1 = min(width, rr.origin.x + rr.size.width)
                    let y1 = min(height, rr.origin.y + rr.size.height)
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
                case .shape(let rect, let shape):
                    if canSprixel, clipStack.last == fullClip {
                        shapesForSprixel.append((rect, shape))
                    } else if let top = clipStack.last, let rr = intersect(rect, top) {
                        shapesByClip[rr, default: []].append((rect, shape, op.zIndex))
                    }
                }
            }

            // Update per-shape sprixel planes after collecting shapes for this frame.
            if canSprixel, let cellpix {
                var alive: Set<Int> = []
                alive.reserveCapacity(shapesForSprixel.count)

                for (idx, (r, s)) in shapesForSprixel.enumerated() {
                    alive.insert(idx)

                    var hasher = Hasher()
                    hasher.combine(width)
                    hasher.combine(height)
                    hasher.combine(cellpix.cdimx)
                    hasher.combine(cellpix.cdimy)
                    hasher.combine(r)
                    hasher.combine(s.kind)
                    hasher.combine(s.fillStyle)
                    hasher.combine(s.strokeStyle)
                    if let e = s.pathElements {
                        hasher.combine(e.count)
                        for el in e { hasher.combine(el) }
                    }
                    let sig = hasher.finalize()

                    let needsNewPlane: Bool = {
                        guard let existing = shapePlanes[idx] else { return true }
                        if existing.rect.size != r.size { return true }
                        return false
                    }()

                    if needsNewPlane {
                        if let existing = shapePlanes[idx] {
                            ncplane_destroy(existing.plane)
                            shapePlanes[idx] = nil
                        }
                        var popts = ncplane_options()
                        popts.y = Int32(r.origin.y)
                        popts.x = Int32(r.origin.x)
                        popts.rows = UInt32(r.size.height)
                        popts.cols = UInt32(r.size.width)
                        popts.name = nil
                        popts.userptr = nil
                        popts.resizecb = nil
                        popts.flags = 0
                        popts.margin_b = 0
                        popts.margin_r = 0
                        if let p = ncplane_create(stdplane, &popts) {
                            // Ensure shapes are behind the standard plane (text).
                            _ = ncplane_move_above(p, nil)
                            shapePlanes[idx] = _NCShapePlaneEntry(plane: p, rect: r, sig: Int.min)
                        } else {
                            // If we can't create planes, fall back to braille for this frame.
                            for (_, e) in shapePlanes { ncplane_destroy(e.plane) }
                            shapePlanes.removeAll()
                            break
                        }
                    } else if let existing = shapePlanes[idx], existing.rect.origin != r.origin {
                        ncplane_move_yx(existing.plane, Int32(r.origin.y), Int32(r.origin.x))
                        shapePlanes[idx]?.rect = r
                    }

                    guard var entry = shapePlanes[idx] else { continue }
                    if entry.sig == sig { continue }

                    ncplane_erase(entry.plane)
                    let ok = _renderSprixels(
                        nc: nc,
                        plane: entry.plane,
                        termSize: _Size(width: width, height: height),
                        cellpix: cellpix,
                        shapes: [(_Rect(origin: _Point(x: 0, y: 0), size: r.size), s)],
                        fill: shapeFillBG,
                        stroke: borderFG
                    )
                    if ok {
                        entry.sig = sig
                        entry.rect = r
                        shapePlanes[idx] = entry
                    } else {
                        // Pixel blit failed; destroy all planes so we can cleanly fall back.
                        for (_, e) in shapePlanes { ncplane_destroy(e.plane) }
                        shapePlanes.removeAll()
                        break
                    }
                }

                // Delete planes for shapes that no longer exist.
                if !shapePlanes.isEmpty {
                    for (idx, e) in shapePlanes where !alive.contains(idx) {
                        ncplane_destroy(e.plane)
                        shapePlanes[idx] = nil
                    }
                }
            } else {
                // No pixel support; tear down any existing sprixel planes so they can't leave artifacts.
                for (_, e) in shapePlanes { ncplane_destroy(e.plane) }
                shapePlanes.removeAll()
            }

            // Braille fallback: rasterize clipped/unsupported shapes into braille characters, but only
            // over empty cells so overlay text isn't clobbered.
            if !shapesByClip.isEmpty {
                for (clip, shapeRegions) in shapesByClip {
                    for (r, s, z) in shapeRegions {
                        BrailleRaster.render(
                            termSize: _Size(width: width, height: height),
                            shapes: [(r, s)],
                            clip: clip,
                            fillBG: shapeFillBG,
                            strokeFG: borderFG,
                            baseBG: baseBG,
                            isEmpty: { x, y in curr[y * width + x].ch == " " },
                            set: { x, y, ch, fg, bg in setCell(x, y, ch, fg, bg, z: z) }
                        )
                    }
                }
            }

            if let fr = focusRect {
                // Focus highlight over cells.
                for y in max(0, fr.origin.y)..<min(height, fr.origin.y + fr.size.height) {
                    for x in max(0, fr.origin.x)..<min(width, fr.origin.x + fr.size.width) {
                        let idx = y * width + x
                        curr[idx].fg = focusFG
                        curr[idx].bg = focusBG
                    }
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

private func _resolveColorNC(_ c: Color?) -> _NCRGB? {
    guard let c, c.alpha > 0 else { return nil }
    switch c.name {
    case "primary":
        return _NCRGB(r: 0xD8, g: 0xDB, b: 0xE2)
    case "secondary":
        return _NCRGB(r: 0xA5, g: 0xAC, b: 0xB8)
    case "tertiary":
        return _NCRGB(r: 0x7D, g: 0x86, b: 0x96)
    case "white":
        return _NCRGB(r: 0xFF, g: 0xFF, b: 0xFF)
    case "gray":
        return _NCRGB(r: 0x99, g: 0xA1, b: 0xAE)
    case "yellow":
        return _NCRGB(r: 0xFA, g: 0xD3, b: 0x5D)
    case "accentColor":
        return _NCRGB(r: 0x34, g: 0xD3, b: 0x99)
    case "black":
        return _NCRGB(r: 0x00, g: 0x00, b: 0x00)
    case "clear":
        return nil
    default:
        return nil
    }
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

    func rgba(_ c: _NCRGB) -> _RGBA { _RGBA(r: c.r, g: c.g, b: c.b, a: 0xFF) }

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

    func rasterizeFilledShape(
        kind: _ShapeKind,
        pixelW: Int,
        pixelH: Int,
        radiusPx: Double?,
        fillEnabled: Bool,
        strokeWidthPx: Double,
        fillRGB: _RGBA,
        strokeRGB: _RGBA
    ) -> [UInt8] {
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

        let halfStroke = max(0.0, strokeWidthPx) / 2.0

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
                let fillA = fillEnabled ? clamp01(0.5 - dist) : 0.0 // inside => 1, outside => 0
                let strokeA = (strokeWidthPx > 0) ? clamp01((halfStroke + 0.5) - abs(dist)) : 0.0
                if fillA <= 0, strokeA <= 0 { continue }

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

    func rasterizePath(
        elements: [Path.Element],
        pixelW: Int,
        pixelH: Int,
        fillEnabled: Bool,
        eoFill: Bool,
        antialiased: Bool,
        strokeWidthPx: Double,
        fillRGB: _RGBA,
        strokeRGB: _RGBA
    ) -> [UInt8] {
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

        struct Seg { var ax: Double; var ay: Double; var bx: Double; var by: Double }

        func distToSegment(px: Double, py: Double, _ s: Seg) -> Double {
            let vx = s.bx - s.ax
            let vy = s.by - s.ay
            let wx = px - s.ax
            let wy = py - s.ay
            let vv = vx * vx + vy * vy
            if vv <= 1e-9 {
                return hypot(px - s.ax, py - s.ay)
            }
            var t = (wx * vx + wy * vy) / vv
            t = min(1.0, max(0.0, t))
            let cx = s.ax + t * vx
            let cy = s.ay + t * vy
            return hypot(px - cx, py - cy)
        }

        // Build a flattened segment list in pixel space using the same mapping as `_strokePath`.
        var segments: [Seg] = []
        segments.reserveCapacity(max(16, elements.count * 4))
        _strokePathCollectSegments(
            elements: elements,
            x0: 0, y0: 0, x1: pixelW, y1: pixelH,
            addSegment: { x0, y0, x1, y1 in
                segments.append(Seg(ax: Double(x0), ay: Double(y0), bx: Double(x1), by: Double(y1)))
            },
            fillEllipse: { _, _, _, _ in },
            strokeRect: { _, _, _, _ in }
        )

        // Fill using a simple point-in-polygon test against the flattened segments.
        // This supports both even-odd and (approx) nonzero winding rules.
        func windingContains(_ x: Double, _ y: Double) -> Bool {
            var winding = 0
            for s in segments {
                let y0 = s.ay
                let y1 = s.by
                let x0 = s.ax
                let x1 = s.bx
                // Ignore horizontal edges.
                if y0 == y1 { continue }
                let upward = y0 < y1
                let ymin = min(y0, y1)
                let ymax = max(y0, y1)
                if y < ymin || y >= ymax { continue }
                // Compute x intersection at y.
                let t = (y - y0) / (y1 - y0)
                let ix = x0 + t * (x1 - x0)
                if ix <= x { continue }
                if upward {
                    winding += 1
                } else {
                    winding -= 1
                }
            }
            return winding != 0
        }

        func evenOddContains(_ x: Double, _ y: Double) -> Bool {
            var inside = false
            for s in segments {
                let y0 = s.ay
                let y1 = s.by
                let x0 = s.ax
                let x1 = s.bx
                if y0 == y1 { continue }
                let ymin = min(y0, y1)
                let ymax = max(y0, y1)
                if y < ymin || y >= ymax { continue }
                let t = (y - y0) / (y1 - y0)
                let ix = x0 + t * (x1 - x0)
                if ix > x {
                    inside.toggle()
                }
            }
            return inside
        }

        if fillEnabled, !segments.isEmpty {
            let samples: [(Double, Double)] = antialiased ? [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)] : [(0.5, 0.5)]
            for y in 0..<pixelH {
                for x in 0..<pixelW {
                    var covered = 0
                    for (ox, oy) in samples {
                        let px = Double(x) + ox
                        let py = Double(y) + oy
                        let ins = eoFill ? evenOddContains(px, py) : windingContains(px, py)
                        if ins { covered += 1 }
                    }
                    if covered == 0 { continue }
                    let a = UInt8(clamping: Int((Double(covered) / Double(samples.count)) * 255.0))
                    put(x, y, _RGBA(r: fillRGB.r, g: fillRGB.g, b: fillRGB.b, a: a))
                }
            }
        }

        if strokeWidthPx > 0, !segments.isEmpty {
            let half = strokeWidthPx / 2.0
            for y in 0..<pixelH {
                for x in 0..<pixelW {
                    let px = Double(x) + 0.5
                    let py = Double(y) + 0.5
                    var best = Double.greatestFiniteMagnitude
                    for s in segments {
                        best = min(best, distToSegment(px: px, py: py, s))
                    }
                    // 1px AA ramp.
                    let aa = antialiased ? 0.75 : 0.0
                    let alpha = clamp01((half + aa) - best)
                    if alpha <= 0 { continue }
                    put(x, y, _RGBA(r: strokeRGB.r, g: strokeRGB.g, b: strokeRGB.b, a: UInt8(clamping: Int(alpha * 255.0))))
                }
            }
        }

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

        let fillEnabled = (s.fillStyle != nil)
        let eoFill = s.fillStyle?.isEOFilled ?? false
        let aa = s.fillStyle?.antialiased ?? true
        let strokeWidthPx: Double = {
            guard let st = s.strokeStyle else { return 0.0 }
            // Treat `lineWidth` as "terminal points" and map to pixels conservatively.
            return max(1.0, Double(st.lineWidth))
        }()

        let localFill = (s.fillColor.flatMap(_resolveColorNC) ?? fill)
        let localStroke = (s.strokeColor.flatMap(_resolveColorNC) ?? stroke)
        let fillRGB = rgba(localFill)
        let strokeRGB = rgba(localStroke)

        let buf: [UInt8]
        switch s.kind {
        case .path:
            buf = rasterizePath(
                elements: s.pathElements ?? [],
                pixelW: pixelW,
                pixelH: pixelH,
                fillEnabled: fillEnabled,
                eoFill: eoFill,
                antialiased: aa,
                strokeWidthPx: strokeWidthPx,
                fillRGB: fillRGB,
                strokeRGB: strokeRGB
            )
        case .roundedRectangle(let cr):
            buf = rasterizeFilledShape(
                kind: s.kind,
                pixelW: pixelW,
                pixelH: pixelH,
                radiusPx: Double(cr) * Double(cellpix.cdimx),
                fillEnabled: fillEnabled,
                strokeWidthPx: strokeWidthPx,
                fillRGB: fillRGB,
                strokeRGB: strokeRGB
            )
        default:
            buf = rasterizeFilledShape(
                kind: s.kind,
                pixelW: pixelW,
                pixelH: pixelH,
                radiusPx: nil,
                fillEnabled: fillEnabled,
                strokeWidthPx: strokeWidthPx,
                fillRGB: fillRGB,
                strokeRGB: strokeRGB
            )
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

private func _strokePathCollectSegments(
    elements: [Path.Element],
    x0: Int, y0: Int, x1: Int, y1: Int,
    addSegment: (Int, Int, Int, Int) -> Void,
    fillEllipse: (Int, Int, Int, Int) -> Void,
    strokeRect: (Int, Int, Int, Int) -> Void
) {
    _strokePath(
        elements: elements,
        x0: x0, y0: y0, x1: x1, y1: y1,
        drawLine: { ax, ay, bx, by in
            addSegment(ax, ay, bx, by)
        },
        fillEllipse: { ex0, ey0, ex1, ey1 in
            // Approximate ellipse boundary with a polyline so fills have a contour.
            let cx = Double(ex0 + ex1) / 2.0
            let cy = Double(ey0 + ey1) / 2.0
            let rx = max(1.0, Double(ex1 - ex0) / 2.0)
            let ry = max(1.0, Double(ey1 - ey0) / 2.0)
            let steps = 48
            var prevX = cx + rx
            var prevY = cy
            for i in 1...steps {
                let t = (Double(i) / Double(steps)) * (Double.pi * 2.0)
                let x = cx + cos(t) * rx
                let y = cy + sin(t) * ry
                addSegment(Int(prevX.rounded()), Int(prevY.rounded()), Int(x.rounded()), Int(y.rounded()))
                prevX = x
                prevY = y
            }
            fillEllipse(ex0, ey0, ex1, ey1)
        },
        strokeRect: { rx0, ry0, rx1, ry1 in
            addSegment(rx0, ry0, rx1, ry0)
            addSegment(rx1, ry0, rx1, ry1)
            addSegment(rx1, ry1, rx0, ry1)
            addSegment(rx0, ry1, rx0, ry0)
            strokeRect(rx0, ry0, rx1, ry1)
        }
    )
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
