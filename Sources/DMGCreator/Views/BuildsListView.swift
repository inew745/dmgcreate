import SwiftUI
import AppKit

/// Every disk image built so far: open one, show it in the Finder, or load its
/// settings back into the editor and build it again.
struct BuildsListView: View {

    @EnvironmentObject var model: ProjectModel
    @ObservedObject var history: BuildHistory

    var body: some View {
        Group {
            if history.records.isEmpty {
                empty
            } else {
                list
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "externaldrive")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("No images built yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Everything you build shows up here, ready to open again.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(history.records) { record in
                        row(record)
                        Divider()
                    }
                }
            }
            footer
        }
    }

    private func row(_ record: BuildRecord) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: ImageCache.shared.fileIcon(atPath: record.stillThere
                                                      ? record.path : "/"))
                .resizable()
                .frame(width: 28, height: 28)
                .opacity(record.stillThere ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(record.fileName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if record.path == model.lastBuiltDMG?.path {
                        Text("latest")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    }
                }
                Text(record.stillThere
                     ? "\(record.summary) · \(record.sizeText)"
                     : "\(record.summary) — moved or deleted")
                    .font(.caption)
                    .foregroundStyle(record.stillThere ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                history.mount(record)
            } label: {
                Image(systemName: "eject.circle")
            }
            .buttonStyle(.borderless)
            .disabled(!record.stillThere)
            .help("Mount the image")

            Button {
                history.reveal(record)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .disabled(!record.stillThere)
            .help("Show in Finder")

            Button {
                load(record)
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.borderless)
            .help("Load these settings back into the editor")

            Button {
                history.remove(id: record.id)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove from this list (the file is kept)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Mount") { history.mount(record) }
                .disabled(!record.stillThere)
            Button("Show in Finder") { history.reveal(record) }
                .disabled(!record.stillThere)
            Button("Load Settings") { load(record) }
            Divider()
            Button("Remove from List") { history.remove(id: record.id) }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(history.records.count == 1 ? "1 image" : "\(history.records.count) images")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if history.missingCount > 0 {
                Button("Remove \(history.missingCount) missing") { history.removeMissing() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Button("Clear list") { history.clear() }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(Divider(), alignment: .top)
    }

    private func load(_ record: BuildRecord) {
        model.data = record.project
        model.selectedItemID = nil
        model.clampAllItems()
        model.markDirty()
    }
}
