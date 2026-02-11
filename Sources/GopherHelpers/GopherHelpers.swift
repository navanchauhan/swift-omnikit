import SwiftGopherClient

public func itemToImageType(_ item: gopherItem) -> String {
    switch item.parsedItemType {
    case .directory:
        return "folder"
    case .search:
        return "magnifyingglass"
    case .text:
        return "doc.plaintext"
    case .doc:
        return "doc.richtext"
    case .image, .gif, .bitmap:
        return "photo"
    case .movie:
        return "film"
    case .sound:
        return "speaker.wave.2"
    case .binary:
        return "doc"
    case .info:
        return "info.circle"
    case .unknown:
        return "questionmark.app.dashed"
    }
}

