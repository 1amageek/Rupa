import SwiftUI
import RupaCore
import SwiftCAD

/// The options of the running imprinting dialog (`WorkspaceImprintSession`), laid out in the
/// context panel: Imprint Curve Body's Method, Vector direction, Bidirectional, Hide occlusion
/// and Completion; Imprint Body Body's Complete target, Imprint tool and Complete tool;
/// Isoparam's Direction, Count, Param and Subdivide; Untrim's Keep edges.
struct WorkspaceImprintDialogView: View {
    @Binding var dialog: WorkspaceImprintSession

    var body: some View {
        switch dialog.kind {
        case .curves:
            Picker("Method", selection: $dialog.method) {
                ForEach(WorkspaceImprintSession.Method.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("WorkspaceImprint.method")
            if dialog.method == .vector {
                TextField("X", value: $dialog.vectorX, format: .number)
                    .frame(width: 48)
                    .accessibilityIdentifier("WorkspaceImprint.vectorX")
                TextField("Y", value: $dialog.vectorY, format: .number)
                    .frame(width: 48)
                    .accessibilityIdentifier("WorkspaceImprint.vectorY")
                TextField("Z", value: $dialog.vectorZ, format: .number)
                    .frame(width: 48)
                    .accessibilityIdentifier("WorkspaceImprint.vectorZ")
                Toggle("Bidirectional", isOn: $dialog.isBidirectional)
                    .accessibilityIdentifier("WorkspaceImprint.bidirectional")
                Toggle("Hide occlusion", isOn: $dialog.hidesOcclusion)
                    .accessibilityIdentifier("WorkspaceImprint.hidesOcclusion")
            }
            completionPicker("Completion", selection: $dialog.completion, choices: [.none, .edge, .boundary])
        case .bodies:
            completionPicker("Complete target", selection: $dialog.completion, choices: [.none, .edge])
            Toggle("Imprint tool", isOn: $dialog.imprintsTool)
                .accessibilityIdentifier("WorkspaceImprint.imprintsTool")
            if dialog.imprintsTool {
                completionPicker("Complete tool", selection: $dialog.toolCompletion, choices: [.none, .edge])
            }
        case .isoparam:
            Picker("Direction", selection: $dialog.direction) {
                Text("U").tag(SurfaceParameterDirection.u)
                Text("V").tag(SurfaceParameterDirection.v)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("WorkspaceImprint.direction")
            Stepper("Count \(dialog.count)", value: $dialog.count, in: 1...64)
                .fixedSize()
                .accessibilityIdentifier("WorkspaceImprint.count")
            if dialog.count == 1 {
                TextField("Param", value: $dialog.parameter, format: .number)
                    .frame(width: 56)
                    .accessibilityIdentifier("WorkspaceImprint.parameter")
            }
            Toggle("Subdivide", isOn: $dialog.subdividesControlNet)
                .accessibilityIdentifier("WorkspaceImprint.subdivide")
        case .untrim:
            Toggle("Keep edges", isOn: $dialog.keepsEdges)
                .accessibilityIdentifier("WorkspaceImprint.keepsEdges")
        }
    }

    private func completionPicker(_ title: String, selection: Binding<ImprintCompletion>, choices: [ImprintCompletion]) -> some View {
        Picker(title, selection: selection) {
            ForEach(choices, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        .fixedSize()
        .accessibilityIdentifier("WorkspaceImprint.\(title.replacingOccurrences(of: " ", with: ""))")
    }
}

#Preview("Imprint dialogs") {
    VStack(alignment: .leading) {
        WorkspaceImprintDialogView(dialog: .constant(WorkspaceImprintSession(kind: .curves(target: SceneNodeID(), curves: []))))
        WorkspaceImprintDialogView(dialog: .constant(WorkspaceImprintSession(kind: .bodies(target: SceneNodeID(), tool: SceneNodeID()))))
        WorkspaceImprintDialogView(dialog: .constant(WorkspaceImprintSession(kind: .isoparam(face: SelectionTarget(sceneNodeID: SceneNodeID())))))
        WorkspaceImprintDialogView(dialog: .constant(WorkspaceImprintSession(kind: .untrim(face: SelectionTarget(sceneNodeID: SceneNodeID())))))
    }
    .padding()
}
