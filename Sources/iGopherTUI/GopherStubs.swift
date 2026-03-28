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
