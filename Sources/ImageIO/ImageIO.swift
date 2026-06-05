@_exported import Foundation
@_exported import CoreFoundation
@_exported import CoreGraphics

public let kCGImageSourceShouldCache = "kCGImageSourceShouldCache"
public let kCGImageSourceShouldCacheImmediately = "kCGImageSourceShouldCacheImmediately"
public let kCGImageSourceCreateThumbnailFromImageAlways = "kCGImageSourceCreateThumbnailFromImageAlways"
public let kCGImageSourceCreateThumbnailWithTransform = "kCGImageSourceCreateThumbnailWithTransform"
public let kCGImageSourceThumbnailMaxPixelSize = "kCGImageSourceThumbnailMaxPixelSize"

public final class CGImageSource: @unchecked Sendable {
    public let url: URL
    public let options: CFDictionary?

    public init(url: URL, options: CFDictionary? = nil) {
        self.url = url
        self.options = options
    }
}

public func CGImageSourceCreateWithURL(_ url: CFURL, _ options: CFDictionary?) -> CGImageSource? {
    guard url.isFileURL else {
        return CGImageSource(url: url, options: options)
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
        return nil
    }
    return CGImageSource(url: url, options: options)
}

public func CGImageSourceCreateThumbnailAtIndex(_ source: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? {
    guard index == 0 else { return nil }
    guard let data = try? Data(contentsOf: source.url) else { return nil }
    let maxPixelSize = options?[kCGImageSourceThumbnailMaxPixelSize] as? Int ?? 0
    return CGImage(width: maxPixelSize, height: maxPixelSize, data: data)
}
