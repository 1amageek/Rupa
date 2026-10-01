import SwiftUI
import RupaCore
import SwiftCAD

/// The options of the running local face operation (`WorkspaceFaceEditSession`), laid out in the
/// context panel: Push Face's Distance and Angle Adjacent, Draft Face's Degrees and Offset, Match
/// Face's Front, and the Grow mode they share; Remove Fillets' Max Radius and Convexity; Align
/// Surface's Continuity, Tension, Blend rows, Influence, Partial Start and End, and Degree/Spans;
/// Rebuild Face's Method with its Degree and Spans or Tolerance, Extend U and V, and Shrink.
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
        case .extendSheet:
            lengthField("Distance", meters: $dialog.distanceMeters, identifier: "WorkspaceFaceEdit.extendDistance")
            Picker("Shape", selection: $dialog.extensionShape) {
                ForEach(SheetExtensionShape.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .fixedSize()
            .accessibilityIdentifier("WorkspaceFaceEdit.extensionShape")
            Toggle("Modify", isOn: $dialog.modifies)
                .accessibilityIdentifier("WorkspaceFaceEdit.modifies")
        case .alignSurface:
            Picker("Continuity", selection: $dialog.continuity) {
                ForEach(SurfaceContinuityLevel.allCases, id: \.self) { Text("G\($0.rawValue)").tag($0) }
            }
            .fixedSize()
            .accessibilityIdentifier("WorkspaceFaceEdit.continuity")
            TextField("Tension", value: $dialog.tension, format: .number)
                .frame(width: 56)
                .accessibilityIdentifier("WorkspaceFaceEdit.tension")
            Stepper("Blend \(dialog.blendRows)", value: $dialog.blendRows, in: 0...64)
                .fixedSize()
                .accessibilityIdentifier("WorkspaceFaceEdit.blendRows")
            if dialog.blendRows > 0 {
                TextField("Influence", value: $dialog.inputShapeInfluence, format: .number)
                    .frame(width: 56)
                    .accessibilityIdentifier("WorkspaceFaceEdit.inputShapeInfluence")
            }
            TextField("Partial Start", value: $dialog.partialStart, format: .number)
                .frame(width: 56)
                .accessibilityIdentifier("WorkspaceFaceEdit.partialStart")
            TextField("Partial End", value: $dialog.partialEnd, format: .number)
                .frame(width: 56)
                .accessibilityIdentifier("WorkspaceFaceEdit.partialEnd")
            Toggle("Degree/Spans", isOn: $dialog.refitsLayout)
                .accessibilityIdentifier("WorkspaceFaceEdit.refitsLayout")
            if dialog.refitsLayout {
                layoutFields($dialog.layout)
            }
        case .rebuildFace:
            Picker("Method", selection: $dialog.rebuildMethod) {
                ForEach(WorkspaceFaceEditSession.RebuildMethodChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            .accessibilityIdentifier("WorkspaceFaceEdit.rebuildMethod")
            switch dialog.rebuildMethod {
            case .tolerance:
                lengthField("Tolerance", meters: $dialog.rebuildToleranceMeters, identifier: "WorkspaceFaceEdit.rebuildTolerance")
            case .explicit:
                layoutFields($dialog.layout)
            case .nominal:
                EmptyView()
            }
            TextField("Extend U", value: $dialog.extendU, format: .number)
                .frame(width: 56)
                .accessibilityIdentifier("WorkspaceFaceEdit.extendU")
            TextField("Extend V", value: $dialog.extendV, format: .number)
                .frame(width: 56)
                .accessibilityIdentifier("WorkspaceFaceEdit.extendV")
            Toggle("Shrink", isOn: $dialog.shrinks)
                .accessibilityIdentifier("WorkspaceFaceEdit.shrinks")
        case .hollow:
            lengthField("Thickness", meters: $dialog.wallThicknessMeters, identifier: "WorkspaceFaceEdit.wallThickness")
        case .thicken:
            lengthField("Front", meters: $dialog.frontMeters, identifier: "WorkspaceFaceEdit.front")
            if dialog.locksThicknesses == false {
                lengthField("Back", meters: $dialog.backMeters, identifier: "WorkspaceFaceEdit.back")
            }
            Toggle("Lock", isOn: $dialog.locksThicknesses)
                .accessibilityIdentifier("WorkspaceFaceEdit.lockThicknesses")
        case .removeFillets:
            lengthField("Max Radius", meters: $dialog.maximumRadiusMeters, identifier: "WorkspaceFaceEdit.maximumRadius")
            Picker("Convexity", selection: $dialog.convexity) {
                ForEach(FilletConvexity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .fixedSize()
            .accessibilityIdentifier("WorkspaceFaceEdit.convexity")
        }
        if dialog.hasGrow {
            Picker("Grow", selection: $dialog.grow) {
                ForEach(FaceEditGrow.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .fixedSize()
            .accessibilityIdentifier("WorkspaceFaceEdit.grow")
        }
    }

    /// A surface layout's degrees and spans along U and V.
    @ViewBuilder
    private func layoutFields(_ layout: Binding<SurfaceControlLayout>) -> some View {
        Stepper("Degree U \(layout.wrappedValue.uDegree)", value: layout.uDegree, in: SurfaceControlLayout.degrees)
            .fixedSize()
            .accessibilityIdentifier("WorkspaceFaceEdit.uDegree")
        Stepper("V \(layout.wrappedValue.vDegree)", value: layout.vDegree, in: SurfaceControlLayout.degrees)
            .fixedSize()
            .accessibilityIdentifier("WorkspaceFaceEdit.vDegree")
        Stepper("Spans U \(layout.wrappedValue.uSpans)", value: layout.uSpans, in: SurfaceControlLayout.spans)
            .fixedSize()
            .accessibilityIdentifier("WorkspaceFaceEdit.uSpans")
        Stepper("V \(layout.wrappedValue.vSpans)", value: layout.vSpans, in: SurfaceControlLayout.spans)
            .fixedSize()
            .accessibilityIdentifier("WorkspaceFaceEdit.vSpans")
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
        WorkspaceFaceEditDialogView(dialog: .constant(WorkspaceFaceEditSession(kind: .alignSurface(edge: face, reference: face))), displayUnit: .millimeter)
        WorkspaceFaceEditDialogView(dialog: .constant(WorkspaceFaceEditSession(kind: .rebuildFace(faces: [face]))), displayUnit: .millimeter)
    }
    .padding()
}
