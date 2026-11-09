import SwiftUI
import AppKit

/// The settings sidebar: everything about the image that is not a position.
struct InspectorView: View {

    @EnvironmentObject var model: ProjectModel

    var body: some View {
        Form {
            volumeSection
            backgroundSection
            windowSection
            contentsSection
            outputSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 330, idealWidth: 360)
    }

    // MARK: - Volume

    private var volumeSection: some View {
        Section("Volume") {
            TextField("Name", text: Binding(
                get: { model.data.volumeName },
                set: { newValue in
                    let wasSuggested = model.data.outputPath ==
                        ProjectData.suggestedOutputPath(for: model.data.volumeName)
                    model.data.volumeName = newValue
                    if wasSuggested {
                        model.data.outputPath = ProjectData.suggestedOutputPath(for: newValue)
                    }
                    model.markDirty()
                }))
            .help("Shown in the Finder sidebar when the image is mounted. Up to 27 characters.")

            LabeledContent("Characters") {
                Text("\(model.data.volumeName.count) / 27")
                    .foregroundStyle(model.data.volumeName.count > 27 ? Color.red : Color.secondary)
                    .font(.caption)
            }

            PathRow(label: "Volume icon",
                    path: model.data.volumeIconPath,
                    placeholder: "Default disk icon",
                    choose: {
                        if let url = FileDialogs.chooseICNS() {
                            model.data.volumeIconPath = url.path
                            model.markDirty()
                        }
                    },
                    clear: {
                        model.data.volumeIconPath = ""
                        model.markDirty()
                    })
        }
    }

    // MARK: - Background

    private var backgroundSection: some View {
        Section("Background") {
            PathRow(label: "Image",
                    path: model.data.backgroundPath,
                    placeholder: "None",
                    detail: model.data.backgroundURL.map { ImageInfo.describe($0) },
                    choose: {
                        if let url = FileDialogs.chooseImage(title: "Choose a Background Image") {
                            model.setBackground(url)
                        }
                    },
                    clear: { model.setBackground(nil) })

            PathRow(label: "Retina (@2x)",
                    path: model.data.background2xPath,
                    placeholder: "Optional",
                    detail: model.data.background2xURL.map { ImageInfo.describe($0) },
                    choose: {
                        if let url = FileDialogs.chooseImage(title: "Choose a @2x Background Image") {
                            model.data.background2xPath = url.path
                            model.markDirty()
                        }
                    },
                    clear: {
                        model.data.background2xPath = ""
                        model.markDirty()
                    })

            Button("Match Window Size to Image") { model.matchWindowToBackground() }
                .disabled(model.data.backgroundPath.isEmpty)
                .help("Sets the window to the background image's size, so the image is shown pixel for pixel.")

            Text("Make the background exactly the window size. Add a @2x copy at double the pixels and both are packed into one image so Retina Macs stay sharp.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Window

    private var windowSection: some View {
        Section("Window") {
            LabeledContent("Size") {
                HStack(spacing: 6) {
                    TextField("Width", value: intBinding(\.windowWidth, min: 200, max: 4000), format: .number)
                        .frame(width: 70)
                    Text("×").foregroundStyle(.secondary)
                    TextField("Height", value: intBinding(\.windowHeight, min: 150, max: 3000), format: .number)
                        .frame(width: 70)
                    Text("pt").foregroundStyle(.secondary)
                }
            }

            LabeledContent("Position on screen") {
                HStack(spacing: 6) {
                    TextField("X", value: intBinding(\.windowX, min: 0, max: 6000), format: .number)
                        .frame(width: 70)
                    Text(",").foregroundStyle(.secondary)
                    TextField("Y", value: intBinding(\.windowY, min: 0, max: 4000), format: .number)
                        .frame(width: 70)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                LabeledContent("Icon size") {
                    Text("\(model.data.iconSize) pt").foregroundStyle(.secondary)
                }
                Slider(value: doubleBinding(\.iconSize, min: 16, max: 512),
                       in: 16...512, step: 8)
            }

            Stepper("Label size: \(model.data.textSize) pt",
                    value: intBinding(\.textSize, min: 10, max: 16),
                    in: 10...16)
        }
    }

    // MARK: - Contents

    private var contentsSection: some View {
        Section("Contents") {
            if model.data.items.isEmpty {
                Text("Nothing added yet. Drop an app on the preview, or use Add Files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.data.items) { item in
                HStack(spacing: 8) {
                    Image(nsImage: ImageCache.shared.fileIcon(atPath: item.sourcePath))
                        .resizable()
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.displayName)
                            .lineLimit(1)
                        Text(item.isApplicationsLink
                             ? "Symlink to /Applications"
                             : "\(Int(item.position.x)), \(Int(item.position.y))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        model.remove(id: item.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove from the image")
                }
                .padding(.vertical, 1)
                .background(model.selectedItemID == item.id
                            ? Color.accentColor.opacity(0.12) : Color.clear)
                .onTapGesture { model.selectedItemID = item.id }
            }

            HStack {
                Button("Add Files…") {
                    let urls = FileDialogs.chooseContents()
                    if !urls.isEmpty { model.addItems(urls: urls) }
                }
                Button("Auto-arrange") { model.autoArrange() }
                    .disabled(model.data.items.isEmpty)
            }

            Toggle("Include “Applications” shortcut", isOn: Binding(
                get: { model.data.hasApplicationsLink },
                set: { model.setApplicationsLink($0) }))
            .help("Adds the /Applications symlink people drag an app onto.")

            Toggle("Snap positions to an 8 pt grid", isOn: Binding(
                get: { model.snapToGrid },
                set: { model.snapToGrid = $0 }))

            Button("Snap to the Background's Slots") { applyClassicLayout() }
                .help("660 × 400 window, with the icons centred in the two slots of the default background.")
        }
    }

    // MARK: - Output

    private var outputSection: some View {
        Section("Output") {
            PathRow(label: "Save to",
                    path: model.data.outputPath,
                    placeholder: "Choose a location",
                    choose: {
                        let suggestion = model.data.outputURL?.lastPathComponent
                            ?? "\(model.data.volumeName).dmg"
                        if let url = FileDialogs.chooseOutput(suggestedName: suggestion) {
                            model.data.outputPath = url.path
                            model.markDirty()
                        }
                    },
                    clear: nil)

            Picker("Format", selection: Binding(
                get: { model.data.format },
                set: { model.data.format = $0; model.markDirty() })) {
                    ForEach(DMGFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }

            TextField("Signing identity", text: Binding(
                get: { model.data.codesignIdentity },
                set: { model.data.codesignIdentity = $0; model.markDirty() }),
                       prompt: Text("Optional, e.g. Developer ID Application: …"))
            .help("Leave empty to ship an unsigned image.")
        }
    }

    private func applyClassicLayout() {
        model.data.windowWidth = 660
        model.data.windowHeight = 400
        model.data.iconSize = 104
        if !model.data.hasApplicationsLink {
            model.setApplicationsLink(true)
        }
        for index in model.data.items.indices {
            model.data.items[index].position = model.data.items[index].isApplicationsLink
                ? ProjectData.applicationsSlot
                : ProjectData.appSlot
        }
        model.clampAllItems()
        model.markDirty()
    }

    // MARK: - Bindings

    private func intBinding(_ keyPath: WritableKeyPath<ProjectData, Int>,
                            min lower: Int,
                            max upper: Int) -> Binding<Int> {
        Binding(
            get: { model.data[keyPath: keyPath] },
            set: { newValue in
                model.data[keyPath: keyPath] = Swift.min(Swift.max(newValue, lower), upper)
                model.clampAllItems()
                model.markDirty()
            })
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<ProjectData, Int>,
                               min lower: Int,
                               max upper: Int) -> Binding<Double> {
        Binding(
            get: { Double(model.data[keyPath: keyPath]) },
            set: { newValue in
                let rounded = Int(newValue.rounded())
                model.data[keyPath: keyPath] = Swift.min(Swift.max(rounded, lower), upper)
                model.clampAllItems()
                model.markDirty()
            })
    }
}

/// A label, the file currently chosen, and buttons to change or clear it.
private struct PathRow: View {

    let label: String
    let path: String
    let placeholder: String
    var detail: String?
    let choose: () -> Void
    let clear: (() -> Void)?

    init(label: String,
         path: String,
         placeholder: String,
         detail: String? = nil,
         choose: @escaping () -> Void,
         clear: (() -> Void)?) {
        self.label = label
        self.path = path
        self.placeholder = placeholder
        self.detail = detail
        self.choose = choose
        self.clear = clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Button("Choose…", action: choose)
                if let clear, !path.isEmpty {
                    Button(action: clear) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear")
                }
            }
            Text(path.isEmpty ? placeholder : (detail ?? (path as NSString).lastPathComponent))
                .font(.caption)
                .foregroundStyle(path.isEmpty ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(path)
        }
    }
}
