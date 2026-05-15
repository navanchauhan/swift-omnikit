import Foundation

public struct UTType: Hashable, Sendable {
    public let identifier: String
    public let preferredFilenameExtension: String?

    public init(_ identifier: String, preferredFilenameExtension: String? = nil) {
        self.identifier = identifier
        self.preferredFilenameExtension = preferredFilenameExtension
    }

    public init?(filenameExtension: String) {
        let ext = filenameExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard !ext.isEmpty else { return nil }
        self.identifier = "public.filename-extension.\(ext)"
        self.preferredFilenameExtension = ext
    }

    public static let plainText = UTType("public.plain-text", preferredFilenameExtension: "txt")
    public static let text = UTType("public.text", preferredFilenameExtension: "txt")
    public static let url = UTType("public.url")
    public static let fileURL = UTType("public.file-url")
    public static let data = UTType("public.data")
    public static let item = UTType("public.item")
}
