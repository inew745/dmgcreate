import Foundation

/// Finds the artwork that ships with the app.
///
/// In a built `DMG Creator.app` these live in `Contents/Resources`. When the
/// app is run straight from a checkout (`swift run`) they are found in the
/// repository's `assets` folder instead.
enum AppResources {

    static let defaultBackgroundPath: String? = find("default-background", "png")
    static let defaultBackground2xPath: String? = find("default-background@2x", "png")

    private static func find(_ name: String, _ ext: String) -> String? {
        if let bundled = Bundle.main.url(forResource: name, withExtension: ext) {
            return bundled.path
        }
        var directory = Bundle.main.bundleURL
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("assets/\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }
}
