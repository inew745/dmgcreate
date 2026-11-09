import SwiftUI

struct ContentView: View {

    @EnvironmentObject var model: ProjectModel

    var body: some View {
        HSplitView {
            InspectorView()
            VStack(spacing: 0) {
                LayoutCanvas()
                    .frame(minHeight: 260)
                BuildPane()
            }
            .frame(minWidth: 460)
        }
        .frame(minWidth: 900, minHeight: 620)
        .navigationTitle(model.documentName + (model.hasUnsavedChanges ? " — Edited" : ""))
        .alert("Something needs attention",
               isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
