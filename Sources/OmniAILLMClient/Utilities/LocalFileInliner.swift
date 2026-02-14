import Foundation

/// Checks whether a URL string looks like a local file path.
func isLocalFilePath(_ urlString: String) -> Bool {
    urlString.hasPrefix("/") ||
    urlString.hasPrefix("./") ||
    urlString.hasPrefix("../") ||
    urlString.hasPrefix("~")
}

/// Resolves a local file path to a `data:<mime>;base64,<data>` URL.
/// Returns nil if the file cannot be read.
func inlineLocalFile(_ path: String) -> (dataURL: String, mimeType: String, data: Data)? {
    let resolved: String
    if path.hasPrefix("~") {
        resolved = NSString(string: path).expandingTildeInPath
    } else {
        resolved = path
    }

    let url = URL(fileURLWithPath: resolved)
    guard let fileData = try? Data(contentsOf: url) else {
        return nil
    }

    let mimeType = guessMimeTypeFromExtension(url.pathExtension)
    let b64 = fileData.base64EncodedString()
    let dataURL = "data:\(mimeType);base64,\(b64)"

    return (dataURL: dataURL, mimeType: mimeType, data: fileData)
}

/// Guesses MIME type from a file extension.
func guessMimeTypeFromExtension(_ ext: String) -> String {
    switch ext.lowercased() {
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "svg": return "image/svg+xml"
    case "bmp": return "image/bmp"
    case "tiff", "tif": return "image/tiff"
    case "mp3": return "audio/mp3"
    case "wav": return "audio/wav"
    case "ogg": return "audio/ogg"
    case "mp4": return "video/mp4"
    case "pdf": return "application/pdf"
    default: return "application/octet-stream"
    }
}
