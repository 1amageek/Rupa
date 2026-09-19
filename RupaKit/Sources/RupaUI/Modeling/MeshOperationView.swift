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
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Select", selection: $domain) {
                        Text("Vertex").tag(GeometryAttributeDomain.vertex)
                        Text("Edge").tag(GeometryAttributeDomain.edge)
                        Text("Face").tag(GeometryAttributeDomain.face)
                    }
                    .pickerStyle(.segmented)
                    Text("Click to select; Shift-click to toggle. Coordinates are local to the Mesh source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected elements (\(draft.elements.count))")
                            .font(.subheadline.weight(.semibold))
                        if draft.elements.isEmpty {
                            Text("None")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(draft.elements, id: \.self) { element in
                                    HStack {
                                        Text(MeshOperationDraft.title(element))
                                            .font(.caption.monospaced())
                                        Spacer(minLength: 8)
                                        Button {
                                            draft.elements.removeAll { $0 == element }
                                        } label: {
                                            Image(systemName: "minus.circle")
                                        }
                                        .accessibilityLabel("Deselect \(MeshOperationDraft.title(element))")
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        Button("Clear Selection") { draft.elements.removeAll() }
                    }
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }

                    Picker("Operation", selection: $draft.kind) {
                        ForEach(MeshOperationDraft.Kind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    if draft.kind == .addFace {
                        Text("Select vertices in boundary order. A new face uses this order, not numeric ID order.")
                            .font(.caption)
                    } else if draft.kind != .delete {
                        ForEach(0..<3) { index in
                            TextField(
                                "\(["X", "Y", "Z"][index]) (\(draft.unit.symbol))",
                                text: Binding(
                                    get: { draft.coordinates[index] },
                                    set: { draft.coordinates[index] = $0 }
                                )
                            )
                        }
                    }
                    if draft.kind == .delete {
                        Text("Selected faces will be removed. Preview first; Apply is undoable.")
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .disabled(isBusy)
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
        }
        .padding(16)
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Modeling.mesh")
    }
}
