import AppKit

/// Small cache so the canvas does not re-read images and file icons from disk
/// on every redraw. Entries are keyed by path and modification date, so
/// editing a background in another app and coming back shows the new version.
final class ImageCache {

    static let shared = ImageCache()

    private var images: [String: NSImage] = [:]
    private let lock = NSLock()

    private func key(for path: String) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(path)|\(modified)"
    }

    func image(atPath path: String) -> NSImage? {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        let cacheKey = "img:" + key(for: path)
        lock.lock()
        if let hit = images[cacheKey] { lock.unlock(); return hit }
        lock.unlock()

        guard let image = NSImage(contentsOfFile: path) else { return nil }
        lock.lock()
        images[cacheKey] = image
        lock.unlock()
        return image
    }

    func fileIcon(atPath path: String) -> NSImage {
        let cacheKey = "icon:" + key(for: path)
        lock.lock()
        if let hit = images[cacheKey] { lock.unlock(); return hit }
        lock.unlock()

        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 512, height: 512)
        lock.lock()
        images[cacheKey] = icon
        lock.unlock()
        return icon
    }
}
