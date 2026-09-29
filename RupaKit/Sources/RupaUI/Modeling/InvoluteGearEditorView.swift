import SwiftUI
import RupaCore

struct InvoluteGearEditorView: View {
    @State var draft: InvoluteGearDraft
    let parameters: ParameterTable
    let tolerance: ModelingTolerance
    let onCancel: () -> Void
    let onPreview: (EditorCommand) -> Void

    var body: some View {
        let command = Result { try draft.command(parameters: parameters, tolerance: tolerance) }
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.featureID == nil ? "Create Involute Gear" : "Edit Involute Gear").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if draft.featureID == nil { field("Name", text: $draft.name) }
                    field("Tooth count", text: $draft.toothCount)
                    ForEach(InvoluteGearFeature.Dimension.allCases, id: \.self) { dimension in
                        field(title(dimension), text: Binding(
                            get: { draft.text[dimension] ?? "" },
                            set: { draft.text[dimension] = $0 }))
                    }
                    Toggle("Double helical", isOn: $draft.doubleHelical).contentShape(Rectangle())
                    field("Maximum profile segments", text: $draft.maximumSegments)
                    Text("Zero twist creates a spur gear. Double helical reaches the specified twist at half width and returns to zero. Root fillets are circular, not hob-generated. Named parameter expressions remain editable.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if case .failure(let error) = command {
                Text(error.localizedDescription).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel", action: onCancel).contentShape(Rectangle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Preview") {
                    if case .success(let value) = command { onPreview(value) }
                }
                .contentShape(Rectangle()).keyboardShortcut(.defaultAction)
                .disabled({ if case .failure = command { true } else { false } }())
                .accessibilityIdentifier("InvoluteGear.preview")
            }
        }
        .padding(16).frame(width: 420, height: 640)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).fixedSize(horizontal: false, vertical: true)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
                .contentShape(Rectangle()).accessibilityLabel(label)
        }
    }

    private func title(_ field: InvoluteGearFeature.Dimension) -> String {
        switch field {
        case .baseRadius: "Base radius"
        case .pitchRadius: "Pitch radius"
        case .tipRadius: "Tip radius"
        case .rootRadius: "Root radius"
        case .filletRadius: "Root fillet radius"
        case .pitchToothAngle: "Tooth thickness angle at pitch circle"
        case .width: "Face width"
        case .twistAngle: "Axial twist angle"
        case .profileError: "Maximum profile approximation error"
        case .sweepError: "Maximum sweep approximation error"
        }
    }
}
