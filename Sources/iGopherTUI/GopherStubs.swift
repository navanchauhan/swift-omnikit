//
//  GopherStubs.swift
//  iGopherTUI
//
//  Stub types replacing GopherHelpers + SwiftGopherClient for compilation.
//

import Foundation

// MARK: - gopherItem stub

enum GopherItemType: Sendable {
    case info
    case directory
    case search
    case text
    case doc
    case image
    case gif
    case movie
    case sound
    case bitmap
    case binary
    case unknown
}

struct gopherItem: Sendable {
    var rawLine: String
    var message: String
    var host: String
    var port: Int
    var selector: String
    var parsedItemType: GopherItemType

    init(rawLine: String) {
        self.rawLine = rawLine
        self.message = rawLine
        self.host = ""
        self.port = 70
        self.selector = ""
        self.parsedItemType = .info
    }
}

// MARK: - GopherClient stub

final class GopherClient: Sendable {
    init() {}

    func sendRequest(
        to host: String, port: Int, message: String
    ) async throws -> [gopherItem] {
        return []
    }

    /// Returns sample gopher menu items for showcase/demo purposes.
    static func sampleMenu(host: String = "gopher.navan.dev", port: Int = 70) -> [gopherItem] {
        func item(_ type: GopherItemType, _ msg: String, selector: String = "", host h: String? = nil) -> gopherItem {
            var i = gopherItem(rawLine: msg)
            i.parsedItemType = type
            i.message = msg
            i.host = h ?? host
            i.port = port
            i.selector = selector
            return i
        }
        return [
            item(.info, "Welcome to \(host)"),
            item(.info, "========================================"),
            item(.directory, "About This Server", selector: "/about"),
            item(.directory, "Phlog (Gopher Blog)", selector: "/phlog"),
            item(.text, "README", selector: "/readme.txt"),
            item(.search, "Search Gopherspace", selector: "/search"),
            item(.info, ""),
            item(.info, "External Links:"),
            item(.directory, "Floodgap Gopher", selector: "/", host: "gopher.floodgap.com"),
            item(.text, "Gopher Protocol FAQ", selector: "/faq.txt"),
        ]
    }
}

// MARK: - Helper from GopherHelpers

func itemToImageType(_ item: gopherItem) -> String {
    switch item.parsedItemType {
    case .image, .gif, .bitmap: return "photo"
    case .movie: return "film"
    case .sound: return "speaker.wave.2"
    case .doc: return "doc"
    case .binary: return "doc.zipper"
    default: return "questionmark.app.dashed"
    }
}
