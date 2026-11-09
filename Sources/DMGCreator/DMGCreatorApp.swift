import SwiftUI
import AppKit

@main
struct DMGCreatorApp: App {

    @StateObject private var model = ProjectModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") { model.newProject() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open Project…") {
                    if let url = FileDialogs.openProject() { model.open(from: url) }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Project") {
                    if let url = model.projectURL {
                        model.save(to: url)
                    } else if let url = FileDialogs.saveProject(suggestedName: model.data.volumeName) {
                        model.save(to: url)
                    }
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save Project As…") {
                    if let url = FileDialogs.saveProject(suggestedName: model.data.volumeName) {
                        model.save(to: url)
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandMenu("Image") {
                Button("Build DMG") { model.build() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Add Files…") {
                    let urls = FileDialogs.chooseContents()
                    if !urls.isEmpty { model.addItems(urls: urls) }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
                Button("Auto-arrange Icons") { model.autoArrange() }
                Button("Match Window to Background") { model.matchWindowToBackground() }
                Divider()
                Button("Show Last Build in Finder") { model.revealLastBuild() }
                    .disabled(model.lastBuiltDMG == nil)
            }
        }
    }
}
