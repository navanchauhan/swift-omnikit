//
//  SearchInputView.swift
//  iGopherBrowser
//
//  Created by Navan Chauhan on 12/16/23.
//
//  Adapted for TUI: removed macOS NSViewRepresentable escape-key capture.

import SwiftUI

struct SearchInputView: View {
    var host: String
    var port: Int
    var selector: String
    @Binding var searchText: String
    var onSearch: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isQueryFocused: Bool

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Search Gopherspace")
                .bold()
            Text("\(host):\(port)\(selector)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Search", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isQueryFocused)
                .onSubmit {
                    let query = trimmedQuery
                    guard !query.isEmpty else { return }
                    onSearch(query)
                }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Search") {
                    let query = trimmedQuery
                    guard !query.isEmpty else { return }
                    onSearch(query)
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(trimmedQuery.isEmpty)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            isQueryFocused = true
        }
        .onExitCommand {
            dismiss()
        }
    }
}
