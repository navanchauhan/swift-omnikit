//
//  CRTEffect.swift
//  iGopherBrowser
//
//  Created by Navan Chauhan on 12/12/23.
//

import SwiftUI

// MARK: - CRT Phosphor Color Options

enum CRTPhosphorColor: String, CaseIterable, Identifiable {
    case green = "green"
    case amber = "amber"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .green: return "P1 Green"
        case .amber: return "P3 Amber"
        }
    }

    var color: Color {
        switch self {
        case .green: return Color(red: 0.2, green: 1.0, blue: 0.4)
        case .amber: return Color(red: 1.0, green: 0.7, blue: 0.2)
        }
    }
}

// MARK: - CRT Color Theme

struct CRTTheme {
    static let phosphorGreen = Color(red: 0.2, green: 1.0, blue: 0.4)
    static let phosphorAmber = Color(red: 1.0, green: 0.7, blue: 0.2)
    static let screenBackground = Color(red: 0.05, green: 0.05, blue: 0.08)
    static let scanlineColor = Color.black.opacity(0.3)
    static let glowColor = Color(red: 0.2, green: 1.0, blue: 0.4).opacity(0.15)

    static func phosphorColor(for type: CRTPhosphorColor) -> Color {
        type.color
    }
}

// MARK: - Scanline Overlay (simplified for TUI)

struct ScanlineOverlay: View {
    var body: some View {
        // No-op in TUI mode; scanlines are a visual-only effect
        EmptyView()
    }
}

// MARK: - CRT Vignette Effect (simplified for TUI)

struct CRTVignette: View {
    var body: some View {
        EmptyView()
    }
}

// MARK: - CRT Screen Curvature

struct CRTCurvature: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

// MARK: - CRT Text Style

struct CRTTextStyle: ViewModifier {
    let color: Color

    init(color: Color = CRTTheme.phosphorGreen) {
        self.color = color
    }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(color)
    }
}

// MARK: - Full CRT Effect Modifier

struct CRTEffectModifier: ViewModifier {
    @AppStorage("crtScanlines") var showScanlines: Bool = true
    @AppStorage("crtVignette") var showVignette: Bool = true

    func body(content: Content) -> some View {
        content
            .background(CRTTheme.screenBackground)
    }
}

// MARK: - CRT Container View

struct CRTContainer<Content: View>: View {
    @AppStorage("crtMode") var crtMode: Bool = false
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if crtMode {
            content
                .modifier(CRTEffectModifier())
        } else {
            content
        }
    }
}

// MARK: - View Extensions

extension View {
    func crtEffect(enabled: Bool = true) -> some View {
        modifier(CRTEffectModifier())
            .opacity(enabled ? 1 : 0)
    }

    func crtTextStyle(color: Color = CRTTheme.phosphorGreen) -> some View {
        modifier(CRTTextStyle(color: color))
    }

    func crtScreen() -> some View {
        modifier(CRTCurvature())
    }
}

// MARK: - CRT Mode Environment Key

struct CRTModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var crtMode: Bool {
        get { self[CRTModeKey.self] }
        set { self[CRTModeKey.self] = newValue }
    }
}
