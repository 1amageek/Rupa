import SwiftUI
import RupaGeometry

struct MeshOperationView: View {
    @Binding var draft: MeshOperationDraft
    @Binding var domain: GeometryAttributeDomain
    let isBusy: Bool
    let hasMatchingPreview: Bool
    let errorMessage: String?
    let onPreview: () -> Void
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mesh Editing").font(.headline)
            Form {
                Picker("Select", selection: $domain) {
                    Text("Vertex").tag(GeometryAttributeDomain.vertex)
                    Text("Edge").tag(GeometryAttributeDomain.edge)
                    Text("Face").tag(GeometryAttributeDomain.face)
                }.pickerStyle(.segmented)
                Text("Click to select; Shift-click to toggle. Coordinates are local to the Mesh source.")
                    .font(.caption).foregroundStyle(.secondary)
                Section("Selected elements (\(draft.elements.count))") {
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(draft.elements, id: \.self) { element in
                                HStack {
                                    Text(MeshOperationDraft.title(element)).font(.caption.monospaced())
                                    Spacer()
                                    Button { draft.elements.removeAll { $0 == element } } label: { Image(systemName: "minus.circle") }
                                        .accessibilityLabel("Deselect \(MeshOperationDraft.title(element))")
                                }
                            }
                        }
                    }.frame(maxHeight: 160)
                    Button("Clear Selection") { draft.elements.removeAll() }
                }
                Picker("Operation", selection: $draft.kind) {
                    ForEach(MeshOperationDraft.Kind.allCases) { kind in Text(kind.rawValue).tag(kind) }
                }
                if draft.kind == .addFace {
                    Text("Select vertices in boundary order. A new face uses this order, not numeric ID order.").font(.caption)
                } else if draft.kind != .delete {
                    ForEach(0..<3) { index in
                        TextField("\(["X", "Y", "Z"][index]) (\(draft.unit.symbol))", text: Binding(get: { draft.coordinates[index] }, set: { draft.coordinates[index] = $0 }))
                    }
                }
                if draft.kind == .delete { Text("Selected faces will be removed. Preview first; Apply is undoable.").foregroundStyle(.orange) }
            }.disabled(isBusy)
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .accessibilityIdentifier("Modeling.mesh.error")
            }
            if isBusy { ProgressView("Evaluating…").controlSize(.small) }
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Preview", action: onPreview).disabled(isBusy || draft.elements.isEmpty)
                Button("Apply", action: onApply).disabled(isBusy || !hasMatchingPreview).keyboardShortcut(.defaultAction)
            }
        }.padding(16).frame(minWidth: 320, idealWidth: 360)
            .accessibilityIdentifier("Modeling.mesh")
    }
}
