import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A live preview of the mounted disk image window: the background picture at
/// the real window size, with every icon where the Finder will put it.
/// Icons can be dragged, and files can be dropped straight onto it.
struct LayoutCanvas: View {

    @EnvironmentObject var model: ProjectModel

    @State private var dragOrigins: [UUID: CGPoint] = [:]
    @State private var isDropTarget = false

    private let outerPadding: CGFloat = 28
    private let titleBarHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            content(available: geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .onDeleteCommand { if let id = model.selectedItemID { model.remove(id: id) } }
    }

    // MARK: - Layout

    private func scale(for available: CGSize) -> CGFloat {
        let window = model.data.windowSize
        guard window.width > 0, window.height > 0 else { return 1 }
        let usableWidth = max(available.width - outerPadding * 2, 120)
        let usableHeight = max(available.height - outerPadding * 2 - titleBarHeight, 120)
        return min(usableWidth / window.width, usableHeight / window.height, 1)
    }

    private func content(available: CGSize) -> some View {
        let s = scale(for: available)
        let size = CGSize(width: model.data.windowSize.width * s,
                          height: model.data.windowSize.height * s)

        return VStack(spacing: 10) {
            VStack(spacing: 0) {
                titleBar(width: size.width)
                contentArea(size: size, scale: s)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isDropTarget ? Color.accentColor : Color.black.opacity(0.25),
                                  lineWidth: isDropTarget ? 3 : 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 14, y: 6)

            caption(scale: s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func titleBar(width: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color(nsColor: .windowBackgroundColor))
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1.00, green: 0.37, blue: 0.35)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 1.00, green: 0.74, blue: 0.21)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 0.31, green: 0.78, blue: 0.27)).frame(width: 10, height: 10)
                Spacer()
            }
            .padding(.leading, 10)
            Text(model.data.volumeName.isEmpty ? "Untitled" : model.data.volumeName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: max(width, 120), height: titleBarHeight)
        .overlay(Divider(), alignment: .bottom)
    }

    private func contentArea(size: CGSize, scale s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            backgroundLayer(size: size)

            ForEach(model.data.items) { item in
                IconBadge(item: item,
                          iconSize: CGFloat(model.data.iconSize) * s,
                          textSize: max(CGFloat(model.data.textSize) * s, 7),
                          isSelected: model.selectedItemID == item.id)
                    .position(x: item.position.x * s, y: item.position.y * s)
                    .gesture(dragGesture(for: item, scale: s))
                    .onTapGesture { model.selectedItemID = item.id }
                    .contextMenu {
                        Button("Remove from Image") { model.remove(id: item.id) }
                        if !item.isApplicationsLink {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            }
                        }
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedItemID = nil }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers, location in
            handleDrop(providers: providers, location: location, scale: s)
        }
    }

    private func backgroundLayer(size: CGSize) -> some View {
        Group {
            if let image = ImageCache.shared.image(atPath: model.data.backgroundPath) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
            } else {
                ZStack {
                    Rectangle().fill(Color(nsColor: .controlBackgroundColor))
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 26))
                            .foregroundStyle(.tertiary)
                        Text("No background image")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Drop a PNG here, or choose one in the sidebar")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    private func caption(scale s: CGFloat) -> some View {
        HStack(spacing: 12) {
            Text("\(model.data.windowWidth) × \(model.data.windowHeight) pt")
            Text("•")
            Text("icons \(model.data.iconSize) pt")
            if s < 0.999 {
                Text("•")
                Text("preview at \(Int((s * 100).rounded()))%")
            }
            if let id = model.selectedItemID,
               let item = model.data.items.first(where: { $0.id == id }) {
                Text("•")
                Text("\(item.displayName) at \(Int(item.position.x)), \(Int(item.position.y))")
                    .foregroundStyle(.primary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Interaction

    private func dragGesture(for item: DMGItem, scale s: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let origin: CGPoint
                if let stored = dragOrigins[item.id] {
                    origin = stored
                } else {
                    origin = item.position
                    dragOrigins[item.id] = origin
                }
                model.selectedItemID = item.id
                let point = CGPoint(x: origin.x + value.translation.width / s,
                                    y: origin.y + value.translation.height / s)
                model.move(id: item.id, to: point)
            }
            .onEnded { _ in
                dragOrigins[item.id] = nil
            }
    }

    private func handleDrop(providers: [NSItemProvider], location: CGPoint, scale s: CGFloat) -> Bool {
        let point = CGPoint(x: location.x / s, y: location.y / s)
        let model = self.model
        var handled = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var resolved: URL?
                if let data = item as? Data {
                    resolved = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    resolved = direct
                }
                guard let url = resolved else { return }
                DispatchQueue.main.async {
                    if LayoutCanvas.isImage(url) && model.data.backgroundPath.isEmpty {
                        model.setBackground(url)
                    } else {
                        model.addItems(urls: [url], at: point)
                    }
                }
            }
        }
        return handled
    }

    static func isImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "tiff", "tif", "gif", "bmp", "heic"]
            .contains(url.pathExtension.lowercased())
    }
}

/// One icon with its label, drawn the way the Finder will draw it.
private struct IconBadge: View {

    let item: DMGItem
    let iconSize: CGFloat
    let textSize: CGFloat
    let isSelected: Bool

    var body: some View {
        VStack(spacing: max(textSize * 0.25, 2)) {
            Image(nsImage: ImageCache.shared.fileIcon(atPath: item.sourcePath))
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)

            Text(item.displayName)
                .font(.system(size: textSize))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.55))
                )
                .frame(maxWidth: iconSize * 1.6)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }
}
