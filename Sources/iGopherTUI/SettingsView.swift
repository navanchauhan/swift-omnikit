//
//  SettingsView.swift
//  iGopherBrowser
//
//  Created by Navan Chauhan on 12/22/23.
//
//  Adapted for TUI: removed NSColor/UIColor archiving, TelemetryDeck, platform splits.

import SwiftUI

struct SettingsView: View {
    @AppStorage("accentColour", store: .standard) var accentColour: Color = Color(.blue)
    @AppStorage("linkColour", store: .standard) var linkColour: Color = Color(.white)
    @AppStorage("shareThroughProxy", store: .standard) var shareThroughProxy: Bool = true
    @AppStorage("telemetryOptOut", store: .standard) var telemetryOptOut: Bool = false

    // CRT Mode settings
    @AppStorage("crtMode") var crtMode: Bool = false
    @AppStorage("crtScanlines") var crtScanlines: Bool = true
    @AppStorage("crtVignette") var crtVignette: Bool = true
    @AppStorage("crtPhosphorColor") var crtPhosphorColor: String = CRTPhosphorColor.green.rawValue

    @AppStorage("homeURL") var homeURL: URL = URL(string: "gopher://gopher.navan.dev:70/")!
    @State var homeURLString: String = ""

    @State private var showAlert = false
    @State private var alertMessage: String = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Navigation section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Home URL")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("Enter home URL", text: $homeURLString)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                if let url = URL(string: homeURLString) {
                                    self.homeURL = url
                                }
                            }

                        HStack(spacing: 8) {
                            Button("Save") {
                                if let url = URL(string: homeURLString) {
                                    homeURL = url
                                } else {
                                    self.alertMessage = "Unable to convert \(homeURLString) to a URL"
                                    self.showAlert = true
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("Reset to Default") {
                                self.homeURL = URL(string: "gopher://gopher.navan.dev:70/")!
                                self.homeURLString = "gopher://gopher.navan.dev:70/"
                            }
                            .buttonStyle(.bordered)

                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Navigation", systemImage: "house")
                }

                // Retro Display section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("CRT Mode", isOn: $crtMode)

                        if crtMode {
                            HStack {
                                Text("Phosphor Color")
                                Spacer()
                                Picker("", selection: $crtPhosphorColor) {
                                    ForEach(CRTPhosphorColor.allCases) { color in
                                        HStack {
                                            Text(color.displayName)
                                        }
                                        .tag(color.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            .padding(.leading, 20)

                            Toggle("Scanlines", isOn: $crtScanlines)
                                .padding(.leading, 20)
                            Toggle("Screen Vignette", isOn: $crtVignette)
                                .padding(.leading, 20)
                        }

                        Text("Enable CRT display mode with phosphor glow effects.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Retro Display", systemImage: "tv")
                }

                // Privacy section
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Opt out of anonymous telemetry", isOn: $telemetryOptOut)
                        Text("Opt out of anonymous telemetry.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Privacy", systemImage: "hand.raised")
                }

                // Share Settings section
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Share links through HTTP(s) proxy", isOn: $shareThroughProxy)
                        Text("Shares Gopher URLs through an HTTP proxy.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Sharing", systemImage: "square.and.arrow.up")
                }
            }
            .padding(20)
        }
        .frame(minWidth: 450, maxWidth: 500)
        .frame(minHeight: 480, maxHeight: 600)
        .onAppear {
            self.homeURLString = homeURL.absoluteString
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Error Saving"),
                message: Text(alertMessage),
                dismissButton: .default(Text("Got it!"))
            )
        }
    }
}
