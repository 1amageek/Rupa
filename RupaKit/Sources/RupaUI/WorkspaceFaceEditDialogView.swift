import SwiftUI
import RupaCore
import RupaRendering
import SwiftCAD

/// The options of the running local face operation (`WorkspaceFaceEditSession`), laid out in the
/// context panel: Push Face's Distance and Angle Adjacent, Draft Face's Degrees and Offset, Match
/// Face's Front, and the Grow mode they share; Remove Fillets' Max Radius and Convexity; Align
/// Surface's Continuity, Tension, Blend rows, Influence, Partial Start and End, Degree/Spans and
/// the Analysis drawn along the previewed edges at its scale;
/// Rebuild Face's Method with its Degree and Spans or Tolerance, Extend U and V, and Shrink.
struct WorkspaceFaceEditDialogView: View {
    @Binding var dialog: WorkspaceFaceEditSession
    var displayUnit: LengthDisplayUnit
    /// The command's main value (Distance, Degrees, Thickness, Front, Max Radius), which D focuses.
    @FocusState private var primaryFocused: Bool

    var body: some View {
        fields
            .onChange(of: dialog.primaryFocusRequests) { primaryFocused = true }
    }

    @ViewBuilder private var fields: some View {
        switch dialog.kind {
        case let .push(_, onto):
            if onto == nil {
                lengthField("Distance", meters: $dialog.distanceMeters, identifier: "WorkspaceFaceEdit.distance", primary: true)
            } else {
                pickedLabel("Onto face", picked: true, identifier: "WorkspaceFaceEdit.ontoPicked")
            }
            TextField("Angle Adjacent", value: $dialog.adjacentAngleDegrees, format: .number)
                .frame(width: 56)
                .accessibilityIdentifier("WorkspaceFaceEdit.adjacentAngle")
        case let .draft(faces, neutral):
            pickedLabel("Plane", picked: neutral != nil, identifier: "WorkspaceFaceEdit.referencePicked")
            pickedLabel("Faces \(faces.count)", picked: faces.isEmpty == false, identifier: "WorkspaceFaceEdit.facesPicked")
            TextField("Degrees", value: $dialog.draftAngleDegrees, format: .number)
                .focused($primaryFocused)
                .frame(width: 56)
                .accessibilityIdentifier("WorkspaceFaceEdit.degrees")
            lengthField("Offset", meters: $dialog.neutralOffsetMeters, identifier: "WorkspaceFaceEdit.neutralOffset")
        case let .match(_, reference):
            pickedLabel("Face", picked: reference != nil, identifier: "WorkspaceFaceEdit.referencePicked")
            Toggle("Front", isOn: $dialog.front)
                .accessibilityIdentifier("WorkspaceFaceEdit.front")
        case let .extendSheet(_, limit):
            if limit == nil {
                lengthField("Distance", meters: $dialog.distanceMeters, identifier: "WorkspaceFaceEdit.extendDistance", primary: true)
            } else {
                Picker("Limit", selection: $dialog.limitMode) {
                    ForEach(SheetExtensionLimit.Mode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .fixedSize()
                .accessibilityIdentifier("WorkspaceFaceEdit.limitMode")
            }
            Picker("Shape", selection: $dialog.extensionShape) {
                ForEach(dialog.extensionShapes, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .fixedSize()
            .accessibilityIdentifier("WorkspaceFaceEdit.extensionShape")
            if dialog.offersModify {
                Toggle("Modify", isOn: $dialog.modifies)
                    .accessibilityIdentifier("WorkspaceFaceEdit.modifies")
            }
        case let .alignSurface(pairs):
            Picker("Continuity", selection: Binding(get: { dialog.continuity }, set: { dialog.continuity = $0; dialog.pairContinuity = [:] })) {
                ForEach(SurfaceContinuityLevel.allCases, id: \.self) { Text("G\($0.rawValue)").tag($0) }
            }
            .fixedSize()
            .accessibilityIdentifier("WorkspaceFaceEdit.continuity")
            if pairs.count > 1 {
                ForEach(pairs.indices, id: \.self) { index in
                    Picker("Edge \(index + 1)", selection: Binding(
                        get: { dialog.pairContinuity[index] ?? dialog.continuity },
                        set: { dialog.pairContinuity[index] = $0 }
                    )) {
                        ForEach(SurfaceContinuityLevel.allCases, id: \.self) { Text("G\($0.rawValue)").tag($0) }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                    if (dialog.pairContinuity[index] ?? dialog.continuity) != .positional {
                        TextField("Tension \(index + 1)", value: Binding(
                            get: { dialog.pairTension[index] ?? dialog.tension },
                            set: { dialog.pairTension[index] = $0 }
                        ), format: .number)
                        .frame(width: 56)
                        .accessibilityIdentifier("WorkspaceFaceEdit.tension\(index + 1)")
                    }
                }
            }
            TextField("Tension", value: Binding(get: { dialog.tension }, set: { dialog.tension = $0; dialog.pairTension = [:] }), format: .number)
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
            Picker("Boundary", selection: $dialog.boundaryFlow) {
                Text("Natural").tag(SquareFitOptions.BoundaryFlow.natural)
                Text("Normal").tag(SquareFitOptions.BoundaryFlow.normal)
                Text("Next").tag(SquareFitOptions.BoundaryFlow.next)
                Text("Adjacent").tag(SquareFitOptions.BoundaryFlow.adjacent)
            }
            .fixedSize()
            .contentShape(Rectangle())
            .help("The cross-edge flow at G1 and G2: Next follows the reference; Normal meets the edge square; Natural keeps the sheet's own; Adjacent follows its side edges. Flows other than Next raise the degree along the edge.")
            .accessibilityIdentifier("WorkspaceFaceEdit.boundaryFlow")
            Toggle("Degree/Spans", isOn: $dialog.refitsLayout)
                .accessibilityIdentifier("WorkspaceFaceEdit.refitsLayout")
            if dialog.refitsLayout {
                layoutFields($dialog.layout)
            }
            Picker("Analysis", selection: $dialog.analysisMeasure) {
                ForEach(ViewportEdgeAlignmentAnalysis.Measure.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            .contentShape(Rectangle())
            .help("Checks the previewed edges' continuity: G0 their gap, G1 the turn between the normals, G2 both surfaces' curvature combs across the edge, each drawn at its scale.")
            .accessibilityIdentifier("WorkspaceFaceEdit.analysisMeasure")
            TextField("\(dialog.analysisMeasure.rawValue) Scale", value: Binding(
                get: { dialog.analysisScales[dialog.analysisMeasure] ?? 10 },
                set: { dialog.analysisScales[dialog.analysisMeasure] = $0 > 0 ? $0 : dialog.analysisScales[dialog.analysisMeasure] }
            ), format: .number)
            .frame(width: 56)
            .accessibilityIdentifier("WorkspaceFaceEdit.analysisScale")
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
            lengthField("Thickness (+ outward, − inward)", meters: $dialog.wallThicknessMeters, identifier: "WorkspaceFaceEdit.wallThickness", primary: true)
        case .thicken:
            lengthField("Front", meters: $dialog.frontMeters, identifier: "WorkspaceFaceEdit.front", primary: true)
            if dialog.locksThicknesses == false {
                lengthField("Back", meters: $dialog.backMeters, identifier: "WorkspaceFaceEdit.back")
            }
            Toggle("Lock", isOn: $dialog.locksThicknesses)
                .accessibilityIdentifier("WorkspaceFaceEdit.lockThicknesses")
        case .polySplines:
            Toggle("Rounded corners", isOn: $dialog.polySplineRoundedCorners)
                .accessibilityIdentifier("WorkspaceFaceEdit.polySplineRoundedCorners")
            Toggle("Merge patches", isOn: $dialog.polySplineMergesPatches)
                .accessibilityIdentifier("WorkspaceFaceEdit.polySplineMergesPatches")
            Toggle("Interpolate boundary exactly", isOn: $dialog.polySplineInterpolatesBoundary)
                .accessibilityIdentifier("WorkspaceFaceEdit.polySplineInterpolatesBoundary")
        case .removeFillets:
            Toggle("Max Radius", isOn: $dialog.limitsRadius)
                .accessibilityIdentifier("WorkspaceFaceEdit.limitsRadius")
            lengthField("Max Radius", meters: $dialog.maximumRadiusMeters, identifier: "WorkspaceFaceEdit.maximumRadius", primary: true)
                .disabled(dialog.limitsRadius == false)
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
    /// A pick the dialog waits for: checked once it is made, as Plasticity's Select rows are.
    private func pickedLabel(_ title: String, picked: Bool, identifier: String) -> some View {
        Label(title, systemImage: picked ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(picked ? Color.green : Color.secondary)
            .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func lengthField(_ title: String, meters: Binding<Double>, identifier: String, primary: Bool = false) -> some View {
        let field = TextField(title, value: Binding(
            get: { meters.wrappedValue / displayUnit.metersPerUnit },
            set: { meters.wrappedValue = $0 * displayUnit.metersPerUnit }
        ), format: .number)
        .frame(width: 64)
        .accessibilityIdentifier(identifier)
        if primary {
            field.focused($primaryFocused)
        } else {
            field
        }
    }
}

#Preview("Face edit dialogs") {
    let face = SelectionTarget(sceneNodeID: SceneNodeID())
    VStack(alignment: .leading) {
        WorkspaceFaceEditDialogView(dialog: .constant(WorkspaceFaceEditSession(kind: .push(faces: [face]))), displayUnit: .millimeter)
        WorkspaceFaceEditDialogView(dialog: .constant(WorkspaceFaceEditSession(kind: .draft(faces: [face], neutral: face))), displayUnit: .millimeter)
        WorkspaceFaceEditDialogView(dialog: .constant(WorkspaceFaceEditSession(kind: .match(faces: [face], reference: nil))), displayUnit: .millimeter)
        WorkspaceFaceEditDialogView(dialog: .constant(WorkspaceFaceEditSession(kind: .removeFillets(object: SceneNodeID()))), displayUnit: .millimeter)
        WorkspaceFaceEditDialogView(dialog: .constant(WorkspaceFaceEditSession(kind: .alignSurface(pairs: [.init(edge: face, reference: face)]))),
                                    displayUnit: .millimeter)
        WorkspaceFaceEditDialogView(dialog: .constant(WorkspaceFaceEditSession(kind: .rebuildFace(faces: [face]))), displayUnit: .millimeter)
    }
    .padding()
}
