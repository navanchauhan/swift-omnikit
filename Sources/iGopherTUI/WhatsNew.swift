//
//  WhatsNew.swift
//  iGopherBrowser
//
//  Created by ChatGPT on 11/27/25.
//
//  Adapted for TUI: removed platform-specific backgrounds/colors.

import SwiftUI

/// Central configuration for "What's New" content.
struct WhatsNewConfig {
    static let currentVersion = "2025.11-crt-mode"
    static let title = "What's New"
    static let subtitle =
        "Relive the glow of vintage terminals with the brand-new CRT Display Mode."
}

/// Describes a single entry in the What's New list.
struct WhatsNewFeature: Identifiable {
    let id: String
    let title: String
    let message: String
    let iconSystemName: String
    let accessory: AnyView?

    init(
        id: String,
        title: String,
        message: String,
        iconSystemName: String,
        accessory: AnyView? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.iconSystemName = iconSystemName
        self.accessory = accessory
    }
}

struct WhatsNewView: View {
    let features: [WhatsNewFeature]
    let dismissTitle: String
    let onPrimaryAction: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            content
                .padding(24)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(WhatsNewConfig.title)
                    .font(.largeTitle.weight(.bold))
                Text(WhatsNewConfig.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(features) { feature in
                        featureRow(feature)
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                onPrimaryAction?()
                onDismiss()
            } label: {
                Text(dismissTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Later") { onDismiss() }
            }
        }
    }

    @ViewBuilder
    private func featureRow(_ feature: WhatsNewFeature) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: feature.iconSystemName)
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.title)
                        .font(.headline)
                    Text(feature.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let accessory = feature.accessory {
                accessory
                    .padding()
            }
        }
        .padding(16)
    }
}
