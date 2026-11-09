import SwiftUI
import AppKit

/// The build button, progress, and the log coming back from make-dmg.sh.
struct BuildPane: View {

    enum Pane: String, CaseIterable, Identifiable {
        case log = "Log"
        case builds = "Builds"
        var id: String { rawValue }
    }

    @EnvironmentObject var model: ProjectModel
    @State private var showPane = true
    @State private var pane: Pane = .log

    private var problems: [String] { model.data.validationProblems() }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            controls
            if showPane {
                Divider()
                switch pane {
                case .log:
                    logView
                case .builds:
                    BuildsListView(history: model.history)
                        .frame(height: 150)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                model.build()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox")
                    Text(model.isBuilding ? "Building…" : "Build DMG")
                }
                .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBuilding || !problems.isEmpty)

            if model.isBuilding {
                ProgressView()
                    .controlSize(.small)
                Button("Cancel") { model.cancelBuild() }
            }

            status

            Spacer()

            if model.lastBuiltDMG != nil {
                Button("Show in Finder") { model.revealLastBuild() }
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(DMGBuilder.shellCommand(for: model.data),
                                               forType: .string)
            } label: {
                Image(systemName: "terminal")
            }
            .help("Copy the equivalent command line")

            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { option in
                    Text(option == .builds && !model.history.records.isEmpty
                         ? "Builds (\(model.history.records.count))"
                         : option.rawValue)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            .onChange(of: pane) { _ in showPane = true }

            Button {
                showPane.toggle()
            } label: {
                Image(systemName: showPane ? "chevron.down" : "chevron.up")
            }
            .help(showPane ? "Hide this pane" : "Show this pane")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var status: some View {
        Group {
            if model.isBuilding {
                Text(model.logLines.last(where: { $0.hasPrefix("==> ") })
                        .map { String($0.dropFirst(4)) } ?? "Working…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let built = model.lastBuiltDMG {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(built.lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else if let first = problems.first {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(problems.count > 1 ? "\(first) (+\(problems.count - 1) more)" : first)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .help(problems.joined(separator: "\n"))
            } else {
                Text("Ready")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if model.logLines.isEmpty {
                        Text("The build log appears here.")
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(Array(model.logLines.enumerated()), id: \.offset) { pair in
                        Text(pair.element)
                            .foregroundStyle(colorFor(line: pair.element))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(pair.offset)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(10)
            }
            .frame(height: 150)
            .onChange(of: model.logLines.count) { count in
                if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
    }

    private func colorFor(line: String) -> Color {
        if line.hasPrefix("ERROR:") { return .red }
        if line.hasPrefix("WARNING:") { return .orange }
        if line.hasPrefix("==> ") { return .accentColor }
        if line.hasPrefix("$ ") { return .secondary }
        return .primary
    }
}
