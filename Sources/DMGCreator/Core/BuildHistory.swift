import Foundation
import AppKit

/// One disk image this app has built.
///
/// The whole project is kept alongside the path, so a build from weeks ago can
/// be loaded back into the editor and made again.
struct BuildRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var path: String
    var volumeName: String
    var builtAt: Date
    var byteSize: Int64
    var project: ProjectData

    var url: URL { URL(fileURLWithPath: path) }
    var fileName: String { (path as NSString).lastPathComponent }
    var folderName: String { ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent }
    var stillThere: Bool { FileManager.default.fileExists(atPath: path) }

    var itemCount: Int { project.items.count }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    var dateText: String {
        builtAt.formatted(date: .abbreviated, time: .shortened)
    }

    var summary: String {
        let items = itemCount == 1 ? "1 item" : "\(itemCount) items"
        return "\(volumeName) · \(items) · \(dateText)"
    }
}

/// The list of images built so far, kept in Application Support so it survives
/// quitting the app.
final class BuildHistory: ObservableObject {

    @Published private(set) var records: [BuildRecord] = []

    static let limit = 50

    private let storeURL: URL

    init(storeURL: URL? = nil) {
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            let folder = support.appendingPathComponent("DMG Creator", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.storeURL = folder.appendingPathComponent("builds.json")
        }
        load()
    }

    // MARK: - Changing the list

    /// Records a finished build, newest first. A rebuild to the same path
    /// replaces the earlier entry rather than piling up.
    func record(project: ProjectData, dmg: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: dmg.path)[.size] as? NSNumber)??.int64Value ?? 0
        let entry = BuildRecord(path: dmg.path,
                                volumeName: project.volumeName,
                                builtAt: Date(),
                                byteSize: size,
                                project: project)
        records.removeAll { $0.path == entry.path }
        records.insert(entry, at: 0)
        if records.count > BuildHistory.limit {
            records.removeSubrange(BuildHistory.limit..<records.count)
        }
        save()
    }

    func remove(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    func removeMissing() {
        records.removeAll { !$0.stillThere }
        save()
    }

    func clear() {
        records.removeAll()
        save()
    }

    var missingCount: Int {
        records.filter { !$0.stillThere }.count
    }

    // MARK: - Doing something with one

    func reveal(_ record: BuildRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.url])
    }

    /// Opens the image, which mounts it and shows the window you designed.
    func mount(_ record: BuildRecord) {
        NSWorkspace.shared.open(record.url)
    }

    // MARK: - Storage

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        records = (try? JSONDecoder().decode([BuildRecord].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
