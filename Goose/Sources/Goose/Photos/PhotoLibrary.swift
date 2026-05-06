import AppKit
import Foundation

/// Resolves a random image from a configurable folder on disk. Defaults to
/// `~/Pictures`. Override with the `GOOSE_PHOTO_PATH` environment variable
/// to point at any other folder.
///
/// We deliberately read from a folder rather than via PhotoKit because the
/// PhotoKit path needs an Info.plist with `NSPhotoLibraryUsageDescription`,
/// which a Swift Package executable doesn't have. Dropping photos in
/// `~/Pictures` is the simplest UX.
enum PhotoLibrary {
    private static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp"
    ]
    private static let scanCap = 400

    static func directory() -> URL {
        let path: String
        if let override = ProcessInfo.processInfo.environment["GOOSE_PHOTO_PATH"], !override.isEmpty {
            path = (override as NSString).expandingTildeInPath
        } else {
            path = (NSString("~/Pictures") as String as NSString).expandingTildeInPath
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func randomImage() -> (image: NSImage, name: String)? {
        let urls = enumerateImageURLs()
        guard !urls.isEmpty else { return nil }

        for _ in 0..<5 {
            guard let url = urls.randomElement() else { return nil }
            if let image = NSImage(contentsOf: url), image.isValid {
                return (image, url.lastPathComponent)
            }
        }
        return nil
    }

    private static func enumerateImageURLs() -> [URL] {
        let dir = directory()
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        var results: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if results.count >= scanCap { break }
            let ext = url.pathExtension.lowercased()
            if supportedExtensions.contains(ext) {
                results.append(url)
            }
        }
        return results
    }
}
