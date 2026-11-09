import Foundation
import CoreGraphics

/// One thing that ends up inside the disk image.
///
/// `position` is where the icon sits in the mounted window, measured in points
/// from the top-left of the window content area. The Finder treats a position
/// as the centre of the icon, and so does this app.
struct DMGItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var sourcePath: String
    var position: CGPoint
    var isApplicationsLink: Bool = false

    /// The name the item will have inside the image.
    var displayName: String {
        if isApplicationsLink { return "Applications" }
        return (sourcePath as NSString).lastPathComponent
    }

    var url: URL { URL(fileURLWithPath: sourcePath) }

    static func applicationsLink(at position: CGPoint) -> DMGItem {
        DMGItem(sourcePath: "/Applications", position: position, isApplicationsLink: true)
    }
}

/// Output formats `hdiutil` can convert to, in the order we offer them.
enum DMGFormat: String, Codable, CaseIterable, Identifiable {
    case udzo = "UDZO"
    case ulfo = "ULFO"
    case udbz = "UDBZ"
    case ulmo = "ULMO"
    case udro = "UDRO"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .udzo: return "Compressed (zlib) — most compatible"
        case .ulfo: return "Compressed (lzfse) — fast, macOS 10.11+"
        case .udbz: return "Compressed (bzip2) — smaller, slower"
        case .ulmo: return "Compressed (lzma) — smallest, macOS 10.15+"
        case .udro: return "Read-only, uncompressed"
        }
    }
}

/// Everything that describes a disk image. This is the whole document: it is
/// what gets saved to a `.dmgproj` file and what the builder turns into
/// arguments for `make-dmg.sh`.
struct ProjectData: Codable, Equatable {
    var volumeName: String = "My App"
    var outputPath: String = ""

    var backgroundPath: String = AppResources.defaultBackgroundPath ?? ""
    var background2xPath: String = AppResources.defaultBackground2xPath ?? ""
    var volumeIconPath: String = ""

    var windowX: Int = 200
    var windowY: Int = 140
    var windowWidth: Int = 660
    var windowHeight: Int = 400

    var iconSize: Int = 104
    var textSize: Int = 12

    var format: DMGFormat = .udzo
    var codesignIdentity: String = ""

    var items: [DMGItem] = []

    // MARK: - Derived values

    var hasApplicationsLink: Bool {
        items.contains { $0.isApplicationsLink }
    }

    var backgroundURL: URL? {
        backgroundPath.isEmpty ? nil : URL(fileURLWithPath: backgroundPath)
    }

    var background2xURL: URL? {
        background2xPath.isEmpty ? nil : URL(fileURLWithPath: background2xPath)
    }

    var volumeIconURL: URL? {
        volumeIconPath.isEmpty ? nil : URL(fileURLWithPath: volumeIconPath)
    }

    var outputURL: URL? {
        outputPath.isEmpty ? nil : URL(fileURLWithPath: outputPath)
    }

    var windowSize: CGSize {
        CGSize(width: CGFloat(windowWidth), height: CGFloat(windowHeight))
    }

    /// A default output location derived from the volume name, used until the
    /// person picks one themselves.
    /// Where the two icon slots sit in the background the app ships with.
    static let appSlot = CGPoint(x: 181, y: 186)
    static let applicationsSlot = CGPoint(x: 471, y: 186)

    static func suggestedOutputPath(for volumeName: String) -> String {
        let name = volumeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = (name.isEmpty ? "Untitled" : name)
            .replacingOccurrences(of: "/", with: "-")
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return desktop.appendingPathComponent("\(file).dmg").path
    }

    /// Problems that would stop a build, in the order worth fixing them.
    func validationProblems() -> [String] {
        var problems: [String] = []
        let trimmedName = volumeName.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            problems.append("Give the volume a name.")
        } else if trimmedName.count > 27 {
            problems.append("The volume name is \(trimmedName.count) characters; Mac disk images allow 27.")
        } else if trimmedName.contains(":") {
            problems.append("Volume names cannot contain a colon.")
        }

        if items.isEmpty {
            problems.append("Add at least one file, folder or app.")
        }

        var seen: Set<String> = []
        for item in items {
            if !seen.insert(item.displayName).inserted {
                problems.append("Two items are both named “\(item.displayName)”.")
            }
            if !item.isApplicationsLink,
               !FileManager.default.fileExists(atPath: item.sourcePath) {
                problems.append("“\(item.displayName)” is no longer at \(item.sourcePath).")
            }
        }

        if !backgroundPath.isEmpty, !FileManager.default.fileExists(atPath: backgroundPath) {
            problems.append("The background image is missing: \(backgroundPath)")
        }
        if !background2xPath.isEmpty, backgroundPath.isEmpty {
            problems.append("A @2x background needs a 1x background as well.")
        }
        if !volumeIconPath.isEmpty, !FileManager.default.fileExists(atPath: volumeIconPath) {
            problems.append("The volume icon is missing: \(volumeIconPath)")
        }
        if outputPath.isEmpty {
            problems.append("Choose where to save the .dmg.")
        }

        return problems
    }
}
