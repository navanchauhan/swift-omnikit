import Foundation

public struct UTType: Hashable, Sendable {
    public let identifier: String
    public let preferredFilenameExtension: String?
    public let preferredMIMEType: String?

    private init(identifier: String, preferredFilenameExtension: String? = nil, preferredMIMEType: String? = nil) {
        self.identifier = identifier
        self.preferredFilenameExtension = preferredFilenameExtension
        self.preferredMIMEType = preferredMIMEType
    }

    public init?(_ identifier: String) {
        let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        self = Self.type(forIdentifier: value)
    }

    public init?(filenameExtension: String) {
        let ext = filenameExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard !ext.isEmpty else { return nil }
        self = Self.type(forFilenameExtension: ext)
    }

    public func conforms(to type: UTType) -> Bool {
        if self == type { return true }
        if type.identifier == Self.item.identifier { return true }
        if type.identifier == Self.data.identifier {
            return identifier.hasPrefix("public.") || identifier.hasPrefix("com.")
        }
        if type.identifier == Self.image.identifier {
            return Self.imageTypeIdentifiers.contains(identifier)
        }
        if type.identifier == Self.text.identifier {
            return identifier == Self.plainText.identifier || identifier.hasPrefix("public.text")
        }
        return false
    }

    public static let plainText = UTType(identifier: "public.plain-text", preferredFilenameExtension: "txt", preferredMIMEType: "text/plain")
    public static let text = UTType(identifier: "public.text", preferredFilenameExtension: "txt", preferredMIMEType: "text/plain")
    public static let url = UTType(identifier: "public.url")
    public static let fileURL = UTType(identifier: "public.file-url")
    public static let data = UTType(identifier: "public.data")
    public static let item = UTType(identifier: "public.item")
    public static let image = UTType(identifier: "public.image")
    public static let png = UTType(identifier: "public.png", preferredFilenameExtension: "png", preferredMIMEType: "image/png")
    public static let jpeg = UTType(identifier: "public.jpeg", preferredFilenameExtension: "jpg", preferredMIMEType: "image/jpeg")
    public static let tiff = UTType(identifier: "public.tiff", preferredFilenameExtension: "tiff", preferredMIMEType: "image/tiff")
    public static let gif = UTType(identifier: "com.compuserve.gif", preferredFilenameExtension: "gif", preferredMIMEType: "image/gif")
    public static let heic = UTType(identifier: "public.heic", preferredFilenameExtension: "heic", preferredMIMEType: "image/heic")
    public static let heif = UTType(identifier: "public.heif", preferredFilenameExtension: "heif", preferredMIMEType: "image/heif")
    public static let bmp = UTType(identifier: "com.microsoft.bmp", preferredFilenameExtension: "bmp", preferredMIMEType: "image/bmp")
    public static let webP = UTType(identifier: "org.webmproject.webp", preferredFilenameExtension: "webp", preferredMIMEType: "image/webp")

    private static let imageTypeIdentifiers: Set<String> = [
        image.identifier,
        png.identifier,
        jpeg.identifier,
        tiff.identifier,
        gif.identifier,
        heic.identifier,
        heif.identifier,
        bmp.identifier,
        webP.identifier,
    ]

    private static func type(forIdentifier identifier: String) -> UTType {
        switch identifier {
        case plainText.identifier, "public.utf8-plain-text":
            return .plainText
        case text.identifier:
            return .text
        case url.identifier:
            return .url
        case fileURL.identifier:
            return .fileURL
        case data.identifier:
            return .data
        case item.identifier:
            return .item
        case image.identifier:
            return .image
        case png.identifier:
            return .png
        case jpeg.identifier:
            return .jpeg
        case tiff.identifier:
            return .tiff
        case gif.identifier:
            return .gif
        case heic.identifier:
            return .heic
        case heif.identifier:
            return .heif
        case bmp.identifier:
            return .bmp
        case webP.identifier, "public.webp":
            return .webP
        default:
            return UTType(identifier: identifier)
        }
    }

    private static func type(forFilenameExtension ext: String) -> UTType {
        switch ext {
        case "png":
            return .png
        case "jpg", "jpeg", "jpe":
            return .jpeg
        case "tif", "tiff":
            return .tiff
        case "gif":
            return .gif
        case "heic":
            return .heic
        case "heif":
            return .heif
        case "webp":
            return .webP
        case "bmp":
            return .bmp
        case "txt", "text":
            return .plainText
        default:
            return UTType(identifier: "public.filename-extension.\(ext)", preferredFilenameExtension: ext)
        }
    }
}

public extension URLResourceKey {
    static let contentTypeKey = URLResourceKey("NSURLContentTypeKey")
}

public extension URLResourceValues {
    var contentType: UTType? { nil }
}
