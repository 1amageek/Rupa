import SwiftUI
import RupaCore
import SwiftCAD

/// The options of the running local face operation (`WorkspaceFaceEditSession`), laid out in the
/// context panel: Push Face's Distance and Angle Adjacent, Draft Face's Degrees and Offset, Match
/// Face's Front, and the Grow mode they share; Remove Fillets' Max Radius and Convexity.
struct WorkspaceFaceEditDialogView: View {
    @Binding var dialog: WorkspaceFaceEditSession
    var displayUnit: LengthDisplayUnit

    var body: some View {
        switch dialog.kind {
        case .push:
            lengthField("Distance", meters: $dialog.distanceMeters, identifier: "WorkspaceFaceEdit.distance")
            TextField("Angle Adjacent", value: $dialog.adjacentAngleDegrees, format: .number)
                .frame(width: 56)
                .accessibilityIdentifier("WorkspaceFaceEdit.adjacentAngle")
        case .draft:
            TextField("Degrees", value: $dialog.draftAngleDegrees, format: .number)
                .frame(width: 56)
                .accessibilityIdentifier("WorkspaceFaceEdit.degrees")
            lengthField("Offset", meters: $dialog.neutralOffsetMeters, identifier: "WorkspaceFaceEdit.neutralOffset")
        case .match:
            Toggle("Front", isOn: $dialog.front)
                .accessibilityIdentifier("WorkspaceFaceEdit.front")
        case .removeFillets:
            lengthField("Max Radius", meters: $dialog.maximumRadiusMeters, identifier: "WorkspaceFaceEdit.maximumRadius")
            Picker("Convexity", selection: $dialog.convexity) {
                ForEach(FilletConvexity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .fixedSize()
            .accessibilityIdentifier("WorkspaceFaceEdit.convexity")
        }
        if case .removeFillets = dialog.kind {} else {
            Picker("Grow", selection: $dialog.grow) {
                ForEach(FaceEditGrow.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .fixedSize()
            .accessibilityIdentifier("WorkspaceFaceEdit.grow")
        }
    }

    /// A length typed in the display unit and kept in meters.
    private func lengthField(_ title: String, meters: Binding<Double>, identifier: String) -> some View {
        TextField(title, value: Binding(
            get: { meters.wrappedValue / displayUnit.metersPerUnit },
            set: { meters.wrappedValue = $0 * displayUnit.metersPerUnit }
        ), format: .number)
        .frame(width: 64)
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Face edit dialogs") {
    let face = SelectionTarget(sceneNodeID: SceneNodeID())
    VStack(alignment: .leading) {
        WorkspaceFaceEditDialogView(dialog: .constant(WorkspaceFaceEditSession(kind: .push(faces: [face]))), displayUnit: .millimeter)
        WorkspaceFaceEditDialogView(dialog: .constant(WorkspaceFaceEditSession(kind: .draft(faces: [face], neutral: face))), displayUnit: .millimeter)
        WorkspaceFaceEditDialogView(dialog: .constant(WorkspaceFaceEditSession(kind: .match(faces: [face], reference: face))), displayUnit: .millimeter)
        WorkspaceFaceEditDialogView(dialog: .constant(WorkspaceFaceEditSession(kind: .removeFillets(object: SceneNodeID()))), displayUnit: .millimeter)
    }
    .padding()
}
