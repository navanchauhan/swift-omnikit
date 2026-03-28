//
//  FileView.swift
//  iGopherBrowser
//
//  Created by Navan Chauhan on 12/16/23.
//
//  Adapted for TUI: removed QuickLook, NSSavePanel, ShareLink, TelemetryDeck.

import Foundation
import SwiftUI

func determineFileType(data: Data) -> String? {
    let signatures: [Data: String] = [
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]): "png",
        Data([0xFF, 0xD8, 0xFF]): "jpeg",
        Data("GIF87a".utf8): "gif",
        Data("GIF89a".utf8): "gif",
        Data("BM".utf8): "bmp",
        Data("%PDF-".utf8): "pdf",
        Data([0x50, 0x4B, 0x03, 0x04]): "docx",
        Data([0x50, 0x4B, 0x05, 0x06]): "docx",
        Data([0x50, 0x4B, 0x07, 0x08]): "docx",
        Data([0x49, 0x44, 0x33]): "mp3",
        Data([0x52, 0x49, 0x46, 0x46]): "wav",
        Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]): "mp4",
        Data([0x6D, 0x6F, 0x6F, 0x76]): "mov",
        Data([0x1F, 0x8B]): "gz",
    ]

    for (signature, fileType) in signatures {
        if data.starts(with: signature) {
            return fileType
        }
    }

    return nil
}

struct FileView: View {
    var item: gopherItem
    let client = GopherClient()
    @State private var fileContent: [String] = []
    @State private var fileURL: URL?
    @State private var downloadedData: Data?
    @State private var showRawUnknown: Bool = false

    // CRT Mode
    @AppStorage("crtMode") var crtMode: Bool = false
    @AppStorage("crtPhosphorColor") var crtPhosphorColorRaw: String = CRTPhosphorColor.green.rawValue

    private var textColor: Color {
        crtMode ? (CRTPhosphorColor(rawValue: crtPhosphorColorRaw) ?? .green).color : .primary
    }

    var body: some View {
        if item.parsedItemType == .text {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    filenameLabel()
                    Spacer()
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(fileContent.indices, id: \.self) { index in
                            Text(fileContent[index])
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(textColor)
                                .textSelection(.enabled)
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .task { readFile(item) }
            .listStyle(PlainListStyle())
        } else if [.doc, .image, .gif, .movie, .sound, .bitmap].contains(item.parsedItemType) {
            if fileURL != nil {
                VStack(spacing: 12) {
                    filenameLabel()
                    Text("Binary file downloaded. Preview not available in TUI mode.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Loading Document...")
                    .onAppear { readFile(item) }
            }
        } else {
            if fileURL != nil {
                VStack(alignment: .leading, spacing: 12) {
                    filenameLabel()
                    HStack(spacing: 12) {
                        Button(showRawUnknown ? "Hide Raw" : "Show Raw") {
                            showRawUnknown.toggle()
                        }
                    }
                    if showRawUnknown, let data = downloadedData {
                        ScrollView {
                            Text(rawText(from: data))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(textColor)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 400)
                    }
                }
                .padding()
            } else {
                Text("Loading...")
                    .onAppear { readFile(item) }
            }
        }
    }

    private func readFile(_ item: gopherItem) {
        // Stub: just set content directly (no real networking)
        self.fileContent = ["[Stub] File content would appear here."]
        self.fileURL = URL(string: "file:///tmp/stub")
        self.downloadedData = Data()
    }

    // MARK: - UI helpers
    @ViewBuilder
    private func filenameLabel() -> some View {
        let name = item.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "doc")
                    .foregroundStyle(crtMode ? textColor : .secondary)
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(crtMode ? textColor : .secondary)
            }
        }
    }

    private func rawText(from data: Data) -> String {
        if let string = String(data: data, encoding: .utf8), string.isEmpty == false {
            return string
        }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
