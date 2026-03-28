//
//  main.swift
//  iGopherTUI
//
//  Entry point for the iGopher TUI built on OmniUI/Notcurses.
//

import Foundation
import OmniUINotcursesRenderer
import SwiftUI

@MainActor
func launch() async throws {
    try await NotcursesApp { ContentView() }.run()
}

try await launch()
