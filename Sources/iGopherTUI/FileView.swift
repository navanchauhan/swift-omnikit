//
//  FileView.swift
//  iGopherBrowser
//
//  Created by Navan Chauhan on 12/16/23.
//
//  Adapted for TUI: removed QuickLook, NSSavePanel, ShareLink, TelemetryDeck.

import Foundation
@preconcurrency import GopherHelpers
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
    @State private var fileContent: [String] = []
    @State private var fileURL: URL?
    @State private var downloadedData: Data?
    @State private var showRawUnknown: Bool = false
    @State private var statusMessage = "Loading..."

    // CRT Mode
    @AppStorage("crtMode") var crtMode: Bool = false
    @AppStorage("crtPhosphorColor") var crtPhosphorColorRaw: String = CRTPhosphorColor.green.rawValue

    private var textColor: Color {
        crtMode ? (CRTPhosphorColor(rawValue: crtPhosphorColorRaw) ?? .green).color : .primary
    }

    private var requestID: String {
        "\(item.host):\(item.port)\(item.selector)"
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
            .task(id: requestID) { await readFile(item) }
            .listStyle(PlainListStyle())
        } else if [.doc, .image, .gif, .movie, .sound, .bitmap].contains(item.parsedItemType) {
            if fileURL != nil {
                VStack(spacing: 12) {
                    filenameLabel()
                    Text("Binary file downloaded. Preview not available in TUI mode.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(statusMessage)
                    .task(id: requestID) { await readFile(item) }
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
                Text(statusMessage)
                    .task(id: requestID) { await readFile(item) }
            }
        }
    }

    @MainActor
    private func readFile(_ item: gopherItem) async {
        statusMessage = item.parsedItemType == .text ? "Loading text..." : "Loading document..."
        fileContent = []
        fileURL = nil
        downloadedData = nil

        do {
            let fileData = try await GopherRequestService.shared.fetchData(
                to: item.host,
                port: item.port,
                message: "\(item.selector)\r\n"
            )

            let tempDirectory = FileManager.default.temporaryDirectory
            guard fileData.isEmpty == false else {
                fileContent = ["No file data was returned by the server."]
                statusMessage = "No file data returned."
                return
            }

            downloadedData = fileData

            if item.parsedItemType == .text,
                let string =
                    String(data: fileData, encoding: .utf8)
                    ?? String(data: fileData, encoding: .isoLatin1)
            {
                let lines = string.components(separatedBy: .newlines)
                let chunkSize = 100
                fileContent = stride(from: 0, to: lines.count, by: chunkSize).map { start in
                    lines[start..<min(start + chunkSize, lines.count)].joined(separator: "\n")
                }
                let textURL = tempDirectory.appending(path: "\(UUID().uuidString).txt")
                try fileData.write(to: textURL)
                fileURL = textURL
                statusMessage = "Loaded."
                return
            }

            let fileType = determineFileType(data: fileData) ?? "unknown"
            let outputURL = tempDirectory.appending(path: "\(UUID().uuidString).\(fileType)")
            try fileData.write(to: outputURL)
            fileURL = outputURL
            statusMessage = "Loaded."
        } catch {
            fileContent = ["Unable to fetch file due to network error: \(error.localizedDescription)"]
            statusMessage = "Unable to fetch file."
        }
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
        return data.map { byte in
            let hex = String(byte, radix: 16, uppercase: true)
            return hex.count == 1 ? "0\(hex)" : hex
        }.joined(separator: " ")
    }
}
