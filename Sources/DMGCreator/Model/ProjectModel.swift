import Foundation
import CoreGraphics
import AppKit

/// Holds the document being edited plus the transient state around it: the
/// build log, whether a build is running, where the last image landed.
final class ProjectModel: ObservableObject {

    @Published var data = ProjectData()

    /// Where the project was last saved or opened from, if anywhere.
    @Published var projectURL: URL?
    @Published var hasUnsavedChanges = false

    @Published var isBuilding = false
    @Published var logLines: [String] = []
    @Published var lastBuiltDMG: URL?
    @Published var errorMessage: String?
    @Published var selectedItemID: UUID?

    @Published var snapToGrid = true
    let gridStep: CGFloat = 8

    private var builder: DMGBuilder?

    init() {
        data.outputPath = ProjectData.suggestedOutputPath(for: data.volumeName)
        data.items = [DMGItem.applicationsLink(at: CGPoint(x: 480, y: 185))]
    }

    // MARK: - Document

    var documentName: String {
        projectURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    func markDirty() {
        hasUnsavedChanges = true
    }

    func newProject() {
        data = ProjectData()
        data.outputPath = ProjectData.suggestedOutputPath(for: data.volumeName)
        data.items = [DMGItem.applicationsLink(at: CGPoint(x: 480, y: 185))]
        projectURL = nil
        hasUnsavedChanges = false
        logLines = []
        lastBuiltDMG = nil
        selectedItemID = nil
    }

    func open(from url: URL) {
        do {
            let raw = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(ProjectData.self, from: raw)
            data = decoded
            projectURL = url
            hasUnsavedChanges = false
            logLines = []
            lastBuiltDMG = nil
            selectedItemID = nil
        } catch {
            errorMessage = "That project could not be opened: \(error.localizedDescription)"
        }
    }

    func save(to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: url, options: .atomic)
            projectURL = url
            hasUnsavedChanges = false
        } catch {
            errorMessage = "The project could not be saved: \(error.localizedDescription)"
        }
    }

    // MARK: - Items

    /// Adds files, skipping anything already in the project, and lays new
    /// items out from the given point (or the middle of the window).
    func addItems(urls: [URL], at dropPoint: CGPoint? = nil) {
        var next = dropPoint ?? CGPoint(x: CGFloat(data.windowWidth) / 3,
                                        y: CGFloat(data.windowHeight) / 2)
        for url in urls {
            let path = url.standardizedFileURL.path
            if data.items.contains(where: { $0.sourcePath == path }) { continue }
            let item = DMGItem(sourcePath: path, position: clamp(next))
            data.items.append(item)
            selectedItemID = item.id
            next.x += CGFloat(data.iconSize) + 40
            if next.x > CGFloat(data.windowWidth) - 40 {
                next.x = CGFloat(data.iconSize)
                next.y += CGFloat(data.iconSize) + 40
            }
        }
        markDirty()
    }

    func remove(id: UUID) {
        data.items.removeAll { $0.id == id }
        if selectedItemID == id { selectedItemID = nil }
        markDirty()
    }

    func move(id: UUID, to point: CGPoint) {
        guard let index = data.items.firstIndex(where: { $0.id == id }) else { return }
        var p = clamp(point)
        if snapToGrid {
            p.x = (p.x / gridStep).rounded() * gridStep
            p.y = (p.y / gridStep).rounded() * gridStep
        }
        data.items[index].position = p
        markDirty()
    }

    func setApplicationsLink(_ enabled: Bool) {
        if enabled {
            guard !data.hasApplicationsLink else { return }
            let x = CGFloat(data.windowWidth) * 0.75
            let y = CGFloat(data.windowHeight) * 0.5
            data.items.append(DMGItem.applicationsLink(at: clamp(CGPoint(x: x, y: y))))
        } else {
            data.items.removeAll { $0.isApplicationsLink }
        }
        markDirty()
    }

    /// Spreads every item across one row, centred vertically.
    func autoArrange() {
        guard !data.items.isEmpty else { return }
        let count = CGFloat(data.items.count)
        let width = CGFloat(data.windowWidth)
        let step = width / (count + 1)
        let y = CGFloat(data.windowHeight) * 0.55
        for (index, _) in data.items.enumerated() {
            data.items[index].position = clamp(CGPoint(x: step * CGFloat(index + 1), y: y))
        }
        markDirty()
    }

    /// Keeps an icon fully inside the window.
    func clamp(_ point: CGPoint) -> CGPoint {
        let half = CGFloat(data.iconSize) / 2
        let maxX = max(half, CGFloat(data.windowWidth) - half)
        let maxY = max(half, CGFloat(data.windowHeight) - half - CGFloat(data.textSize) * 2)
        return CGPoint(x: min(max(point.x, half), maxX),
                       y: min(max(point.y, half), maxY))
    }

    // MARK: - Background

    func setBackground(_ url: URL?, matchWindowSize: Bool = true) {
        guard let url else {
            data.backgroundPath = ""
            data.background2xPath = ""
            markDirty()
            return
        }
        data.backgroundPath = url.path
        if matchWindowSize, let size = ImageInfo.pointSize(of: url) {
            data.windowWidth = Int(size.width.rounded())
            data.windowHeight = Int(size.height.rounded())
            clampAllItems()
        }
        // Pick up a sibling @2x file automatically: background.png -> background@2x.png
        let retina = url.deletingPathExtension().path + "@2x." + url.pathExtension
        if !url.path.contains("@2x"), FileManager.default.fileExists(atPath: retina) {
            data.background2xPath = retina
        }
        markDirty()
    }

    func matchWindowToBackground() {
        guard let url = data.backgroundURL, let size = ImageInfo.pointSize(of: url) else {
            errorMessage = "The background image's size could not be read."
            return
        }
        data.windowWidth = Int(size.width.rounded())
        data.windowHeight = Int(size.height.rounded())
        clampAllItems()
        markDirty()
    }

    func clampAllItems() {
        for index in data.items.indices {
            data.items[index].position = clamp(data.items[index].position)
        }
    }

    // MARK: - Building

    func build() {
        let problems = data.validationProblems()
        guard problems.isEmpty else {
            errorMessage = problems.joined(separator: "\n")
            return
        }
        guard !isBuilding else { return }

        logLines = []
        lastBuiltDMG = nil
        isBuilding = true

        let builder = DMGBuilder()
        self.builder = builder
        builder.build(
            data: data,
            onOutput: { [weak self] line in
                self?.logLines.append(line)
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.isBuilding = false
                self.builder = nil
                switch result {
                case .success(let url):
                    self.lastBuiltDMG = url
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        )
    }

    func cancelBuild() {
        builder?.cancel()
    }

    func revealLastBuild() {
        guard let url = lastBuiltDMG else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    var logText: String {
        logLines.joined(separator: "\n")
    }
}
