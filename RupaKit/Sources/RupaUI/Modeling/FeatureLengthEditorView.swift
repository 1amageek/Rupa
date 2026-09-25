import SwiftUI
import RupaCore

struct FeatureLengthEditorView: View {
    @State var draft: FeatureLengthDraft
    let parameters: ParameterTable
    let onCancel: () -> Void
    let onPreview: (EditorCommand) -> Void

    var body: some View {
        let command = Result { try draft.command(parameters: parameters) }
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Dimension").font(.headline)
            Text("\(draft.title) (\(draft.unit.symbol))")
                .fixedSize(horizontal: false, vertical: true)
            if draft.startText != nil {
                TextField("Start position", text: Binding(
                    get: { draft.startText ?? "" }, set: { draft.startText = $0 }))
                    .contentShape(Rectangle()).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("FeatureLength.start")
            }
            TextField(draft.startText == nil ? "Length expression" : "End position", text: $draft.text)
                .contentShape(Rectangle())
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("FeatureLength.expression")
            Text("Use a length or named parameter expression. Preview reevaluates this feature and its dependents; Apply keeps the same feature identity.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if case .failure(let error) = command {
                Text(error.localizedDescription).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel", action: onCancel)
                    .contentShape(Rectangle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Preview") {
                    if case .success(let value) = command { onPreview(value) }
                }
                .contentShape(Rectangle()).keyboardShortcut(.defaultAction)
                .disabled({ if case .failure = command { true } else { false } }())
                .accessibilityIdentifier("FeatureLength.preview")
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
