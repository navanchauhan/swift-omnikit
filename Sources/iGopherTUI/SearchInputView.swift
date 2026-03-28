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

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            Text("Enter your query")
            TextField("Search", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .onSubmit {
                    onSearch(searchText)
                }
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .padding()

                Button("Search") {
                    onSearch(searchText)
                }
                .keyboardShortcut(.return, modifiers: [])
                .padding()
            }
        }
        .padding()
    }
}
