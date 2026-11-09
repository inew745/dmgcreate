import AppKit
import UniformTypeIdentifiers

/// Thin wrappers around the standard open/save panels.
enum FileDialogs {

    static func chooseContents() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Add to Disk Image"
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseImage(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .bmp, .heic]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseICNS() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Volume Icon"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let icns = UTType(filenameExtension: "icns") {
            panel.allowedContentTypes = [icns]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseOutput(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Disk Image As"
        panel.prompt = "Choose"
        panel.nameFieldStringValue = suggestedName
        if let dmg = UTType(filenameExtension: "dmg") {
            panel.allowedContentTypes = [dmg]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func openProject() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let type = UTType(filenameExtension: "dmgproj") {
            panel.allowedContentTypes = [type]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func saveProject(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Project"
        panel.nameFieldStringValue = suggestedName + ".dmgproj"
        if let type = UTType(filenameExtension: "dmgproj") {
            panel.allowedContentTypes = [type]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
