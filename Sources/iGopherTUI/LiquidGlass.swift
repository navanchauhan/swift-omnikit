//
//  LiquidGlass.swift
//  iGopherBrowser
//
//  Created by Navan Chauhan on 12/12/23.
//
//  Stubbed for TUI: all liquid glass effects are no-ops.

import SwiftUI

extension View {
    @ViewBuilder
    func liquidGlass() -> some View {
        self
    }

    @ViewBuilder
    func liquidGlassInteractive() -> some View {
        self
    }

    @ViewBuilder
    func liquidGlassBar() -> some View {
        self
    }
}

struct LiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle()
    }
}

struct LiquidGlassToolbar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
    }
}
