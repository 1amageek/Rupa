import SwiftUI
import RupaCore
import SwiftCAD

struct ModelingOperationView: View {
    @State private var pointEntryError: String?
    @Binding var draft: ModelingOperationDraft
    let document: DesignDocument
    let isBusy: Bool
    let hasMatchingPreview: Bool
    let errorMessage: String?
    let onUseSelection: () -> Void
    let onPreview: () -> Void
    let onApply: () -> Void
    let onCancel: () -> Void

    /// The reason the draft names no command for this document, or `nil` when
    /// it names one.
    ///
    /// `ModelingOperationDraft.command(in:)` is the one place that decides
    /// what a draft means, so the panel asks it rather than restating the
    /// preconditions. The answer is a function of the draft and the document
    /// read while the body is built, not an event, so it is displayed and not
    /// recorded. See `Modeling/DESIGN.md`.
    var planningRefusal: String? {
        switch Result(catching: { try draft.command(in: document) }) {
        case .success: nil
        case .failure(let error): error.localizedDescription
        }
    }

    var body: some View {
        // Planned once per body evaluation: `Preview` and the reason beside it
        // are the same answer, and planning twice would walk the operand
        // ancestors twice.
        let refusal = planningRefusal
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.isSurfaceCreation ? "Surface Creation" : draft.kind.rawValue).font(.headline)
            if draft.isSurfaceCreation {
                Picker("Operation", selection: Binding(
                    get: { draft.kind },
                    set: { draft.selectSurfaceOperation($0) }
                )) {
                    ForEach(ModelingOperationDraft.Kind.surfaceCreationOperations) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .contentShape(Rectangle())
                .accessibilityIdentifier("Modeling.surfaceOperation")
            }
            Text(instructions)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("Modeling.instructions")
            Form {
                TextField("Name", text: $draft.name).disabled(draft.constrainedFeatureID != nil)
                if ![.box, .cylinder, .sphere, .surfacePatch, .constrainedSurface].contains(draft.kind) {
                    Section("Operands (source coordinates)") {
                        ForEach(draft.targets.indices, id: \.self) { index in
                            HStack {
                                Text(draft.operandTitle(at: index, in: document))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button { draft.targets.swapAt(index, index - 1) } label: {
                                    Image(systemName: "arrow.up")
                                        .contentShape(Rectangle())
                                }
                                    .disabled(index == 0)
                                    .accessibilityLabel("Move operand up")
                                Button { draft.targets.remove(at: index) } label: {
                                    Image(systemName: "minus.circle")
                                        .contentShape(Rectangle())
                                }
                                    .accessibilityLabel("Remove operand")
                            }
                            if draft.kind == .loft {
                                let id = draft.targets[index].sceneNodeID
                                Toggle("Use as guide curve", isOn: Binding(
                                    get: { draft.loftGuideNodeIDs.contains(id) },
                                    set: { if $0 { draft.loftGuideNodeIDs.insert(id) } else { draft.loftGuideNodeIDs.remove(id) } }
                                )).contentShape(Rectangle())
                                if !draft.loftGuideNodeIDs.contains(id) { loftSectionFields(for: id) }
                            }
                            if draft.kind == .square {
                                let target = draft.targets[index]
                                Picker("Side continuity", selection: Binding(
                                    get: { draft.squareContinuity(of: target) },
                                    set: { draft.squareSideContinuity[target] = $0 }
                                )) {
                                    ForEach(ModelingOperationDraft.SquareContinuityChoice.allCases) { Text($0.rawValue).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                .contentShape(Rectangle())
                                .help("Free follows the side loosely by the Weight; G1 and G2 meet the face beside an edge.")
                            }
                        }
                        Button("Use Current Selection", action: onUseSelection)
                            .contentShape(Rectangle())
                    }
                }
                if draft.kind == .bridge, draft.targets.count == 2 {
                    Toggle("Reverse second boundary", isOn: $draft.reverseSecondBoundary)
                }
                parameters
                if [.shell, .fillet, .chamfer, .g2Blend, .surfaceOffset, .thicken].contains(draft.kind) {
                    Text("Amounts accept length expressions and named parameters from Definitions. Parameter changes reevaluate the applied operation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(isBusy)
            if let refusal {
                Text(refusal).foregroundStyle(.secondary).font(.callout).textSelection(.enabled)
                    .accessibilityIdentifier("Modeling.refusal")
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout).textSelection(.enabled)
                    .accessibilityIdentifier("Modeling.error")
            }
            if isBusy { ProgressView("Evaluating…").controlSize(.small) }
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                    .contentShape(Rectangle())
                Spacer()
                Button("Preview", action: onPreview).disabled(isBusy || refusal != nil)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("Modeling.preview")
                Button("Apply", action: onApply).disabled(isBusy || refusal != nil || !hasMatchingPreview)
                    .contentShape(Rectangle())
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("Modeling.apply")
            }
        }
        .padding(16)
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Modeling.operation")
    }

    private var instructions: String {
        if hasMatchingPreview {
            return "Preview ready. Choose Apply to add the result to the document."
        }
        if draft.kind == .constrainedSurface {
            return "Click points in the viewport or enter coordinates. Control-Z removes the last point. Preview validates the fitted surface before Apply."
        }
        if draft.kind == .patch {
            return "Select one edge of a hole, then Use Current Selection. Preview fills its complete boundary as a separate sheet; the source remains unchanged. A sheet's outer perimeter is not a hole."
        }
        if draft.kind == .bridge {
            return "Select two open edges, then Use Current Selection. Preview creates a separate ruled sheet with G0 boundary contact. This does not blend or trim the supporting walls and does not guarantee G1/G2 continuity."
        }
        if draft.isSurfaceCreation {
            switch draft.kind {
            case .surfacePatch:
                return "Create a planar B-spline sheet from its origin and dimensions. This is a starting surface, not a boundary fill."
            case .extrude:
                return "Select one profile or curve. Extrude translates its boundary into a sheet and preserves the source. Choose Vector to specify the direction; source-normal directions require a planar section."
            case .loft:
                return "Select profiles or curves in section order and mark any guide curves below. At least two sections are required. Loft creates an uncapped sheet and preserves the sources. Mixed profile/curve sections must each have one closed boundary; open curves must be paired with open curves."
            case .sweep:
                return "Select a profile or curve section first, optional guides next, and a separate curve path last. Sweep creates a sheet, not a capped solid."
            default: break
            }
        }
        return "Set dimensions, then choose Preview. Choose Apply after the preview is ready."
    }

    @ViewBuilder private var parameters: some View {
        switch draft.kind {
        case .box:
            vectorFields("Origin", values: $draft.origin, unit: draft.unit.symbol)
            lengthField("Width X", text: $draft.width)
            lengthField("Width Y", text: $draft.height)
            lengthField("Depth Z", text: $draft.distance)
        case .constrainedSurface:
            Section("Points") {
                ForEach(draft.constrainedPoints.indices, id: \.self) { index in
                    let point = draft.constrainedPoints[index].position
                    HStack {
                        Text("\(index + 1): \(point.x), \(point.y), \(point.z) m")
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") {
                            draft.constrainedPoints.remove(at: index)
                        }.labelStyle(.iconOnly).contentShape(Rectangle())
                    }
                }
                Button("Undo Last Point") { draft.undoConstrainedPoint() }
                    .disabled(draft.constrainedPoints.isEmpty)
                    .keyboardShortcut("z", modifiers: .control).contentShape(Rectangle())
                vectorFields("New Point", values: $draft.origin, unit: draft.unit.symbol)
                Button("Add Point") {
                    do { try draft.appendCoordinatePoint(); pointEntryError = nil }
                    catch { pointEntryError = error.localizedDescription }
                }.contentShape(Rectangle())
                if let pointEntryError { Text(pointEntryError).foregroundStyle(.red) }
            }
            lengthField("Tolerance", text: $draft.pointTolerance)
            TextField("Angular tolerance (degrees)", text: $draft.angularTolerance)
            Picker("Optimize", selection: $draft.pointOptimization) {
                Text("Performance").tag(ConstrainedSurfaceFeature.Optimization.performance)
                Text("Smoothness").tag(ConstrainedSurfaceFeature.Optimization.smoothness)
            }.contentShape(Rectangle())
        case .surfacePatch:
            vectorFields("Origin", values: $draft.origin, unit: draft.unit.symbol)
            lengthField("Width X", text: $draft.width)
            lengthField("Width Y", text: $draft.height)
        case .surfaceOffset:
            lengthField("Signed normal offset", text: $draft.distance)
        case .thicken:
            lengthField("Front", text: $draft.distance)
                .contentShape(Rectangle())
            lengthField("Back", text: $draft.thickenBack)
                .contentShape(Rectangle())
            Text("Thicken the entire sheet containing the selected face: Front along its normal, Back against it. Preview verifies the resulting solid.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .shell:
            lengthField("Wall thickness", text: $draft.distance)
            Text("Remove the selected face and hollow the body inward by the wall thickness. Preview verifies the thickness fits.")
                .font(.caption).foregroundStyle(.secondary)
        case .surfaceExtend:
            Text("Expand the trim within the underlying surface domain. U/V are surface parameters, not lengths.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("U minimum", text: $draft.uBounds[0])
            TextField("U maximum", text: $draft.uBounds[1])
            TextField("V minimum", text: $draft.vBounds[0])
            TextField("V maximum", text: $draft.vBounds[1])
        case .cylinder, .sphere:
            vectorFields(draft.kind == .sphere ? "Center" : "Base center", values: $draft.origin, unit: draft.unit.symbol)
            lengthField("Radius", text: $draft.width)
            if draft.kind == .cylinder { lengthField("Depth", text: $draft.distance) }
        case .extrude:
            if draft.extrusionDirection != .symmetric {
                lengthField("Start position", text: $draft.startDistance)
            }
            lengthField(draft.extrusionDirection == .symmetric ? "Total distance" : "End position", text: $draft.distance)
            Picker("Direction", selection: $draft.extrusionDirection) {
                ForEach(ModelingOperationDraft.ExtrusionDirectionChoice.allCases) { direction in
                    Text(direction.rawValue).tag(direction)
                }
            }
            .contentShape(Rectangle())
            if draft.extrusionDirection == .vector {
                vectorFields("Direction", values: $draft.axis, unit: "")
            }
            TextField("Degrees", text: $draft.draftDegrees)
                .accessibilityIdentifier("Modeling.extrusionDraftDegrees")
            if !draft.createsSheet {
                lengthField("Thickness", text: $draft.wallThickness)
            }
            if !draft.isSurfaceCreation {
                Toggle("Sheet output", isOn: $draft.sheet)
                Picker("Boolean", selection: $draft.solidBoolean) {
                    ForEach(ModelingOperationDraft.SolidBooleanChoice.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .contentShape(Rectangle())
                if draft.extrudesFaces {
                    Toggle("Individual", isOn: $draft.extrudesIndividually)
                        .accessibilityIdentifier("Modeling.extrudeFacesIndividually")
                }
                if draft.solidBoolean != .newBody {
                    Toggle("Keep Tools", isOn: $draft.keepsTools)
                    Text(draft.extrudesFaces
                        ? "Faces combine with the body they lie on."
                        : "Select the section first, then the bodies to combine with.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .revolve:
            Picker("Axis", selection: $draft.revolveAxisChoice) {
                ForEach(ModelingOperationDraft.RevolveAxisChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .contentShape(Rectangle())
            switch draft.revolveAxisChoice {
            case .direction:
                vectorFields("Axis origin", values: $draft.origin, unit: draft.unit.symbol)
                vectorFields("Axis direction", values: $draft.axis, unit: "")
            case .twoPoints:
                vectorFields("Axis start", values: $draft.origin, unit: draft.unit.symbol)
                vectorFields("Axis end", values: $draft.axisEnd, unit: draft.unit.symbol)
            case .normal, .binormal, .tangent:
                Text("Through the section's boundary start: Tangent along it, Normal along the section's normal, Binormal across both.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Angle (degrees)", text: $draft.angle)
            if !draft.createsSheet {
                lengthField("Thickness", text: $draft.wallThickness)
            }
            if !draft.isSurfaceCreation {
                Toggle("Sheet output", isOn: $draft.sheet)
                Picker("Boolean", selection: $draft.solidBoolean) {
                    ForEach(ModelingOperationDraft.SolidBooleanChoice.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .contentShape(Rectangle())
                if draft.solidBoolean != .newBody {
                    Toggle("Keep Tools", isOn: $draft.keepsTools)
                    Text("Select the section first, then the bodies to combine with.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .pipe:
            Toggle("Custom profile", isOn: $draft.pipeCustomProfile)
            if !draft.pipeCustomProfile {
                lengthField("Diameter", text: $draft.pipeDiameter)
            }
            lengthField("Thickness", text: $draft.wallThickness)
            if !draft.pipeCustomProfile {
                TextField("Vertices (0 for a circle)", text: $draft.pipeVertices)
            }
            TextField("Angle (degrees)", text: $draft.pipeAngle)
            TextField("Scale at the end", text: $draft.pipeEndScale)
            TextField("Start (0–1)", text: $draft.pipeStart)
            TextField("End (0–1)", text: $draft.pipeEnd)
            lengthField("Positional approximation allowance", text: $draft.pipeAllowance)
            Picker("Boolean", selection: $draft.solidBoolean) {
                ForEach(ModelingOperationDraft.SolidBooleanChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .contentShape(Rectangle())
            if draft.solidBoolean != .newBody {
                Toggle("Keep Tools", isOn: $draft.keepsTools)
            }
            Text(draft.pipeCustomProfile
                ? "Select the profile (a region or a face) first, then one or more curves, then any bodies to combine with. The profile is centred on each curve's start."
                : "Select one or more curves, then any bodies to combine with. A pipe follows each curve; along a curved path it is built within the allowance.")
                .font(.caption).foregroundStyle(.secondary)
        case .sweep:
            if !draft.isSurfaceCreation { Toggle("Sheet output", isOn: $draft.sheet) }
            Text("Select the section first, optional guides next, and the path last.").font(.caption).foregroundStyle(.secondary)
            Picker("Alignment", selection: $draft.sweepAlignment) {
                ForEach(ModelingOperationDraft.SweepAlignmentChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .contentShape(Rectangle())
            Picker("Corners", selection: $draft.sweepCorners) {
                ForEach(ModelingOperationDraft.SweepCornerChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .contentShape(Rectangle())
            Toggle("Simplify", isOn: $draft.sweepSimplify)
            Picker("Guide", selection: $draft.sweepGuide) {
                ForEach(ModelingOperationDraft.SweepGuideChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .contentShape(Rectangle())
            .help("With a straight guide selected between the section and the path: Point keeps the section's contact on the guide, Chord only turns the section toward it (within the allowance).")
            if !draft.isSurfaceCreation {
                Picker("Boolean", selection: $draft.solidBoolean) {
                    ForEach(ModelingOperationDraft.SolidBooleanChoice.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .contentShape(Rectangle())
                if draft.solidBoolean != .newBody {
                    Toggle("Keep Tools", isOn: $draft.keepsTools)
                    Text("Select the section and path first, then the bodies to combine with; a face combines with its own body.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            TextField("Twist angle (degrees)", text: $draft.twistAngle)
            Toggle("Reverse twist at midpoint (double helix)", isOn: $draft.doubleHelical)
            lengthField("Positional approximation allowance", text: $draft.approximationTolerance)
            Text("Twisted sweeps take no guides. For double helix, the angle is reached at the midpoint and returns to zero at the end. A twisted sweep, and a Normal sweep along a curved path, need the allowance. The allowance is a shape error bound, not display quality or manufacturing tolerance.")
                .font(.caption).foregroundStyle(.secondary)
        case .loft:
            if !draft.isSurfaceCreation { Toggle("Sheet output", isOn: $draft.sheet) }
            Toggle("Smooth connectors", isOn: $draft.smooth)
            TextField(text: $draft.loftDefaultTension) {
                Text("Default section tension").fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!draft.smooth).contentShape(Rectangle())
            .help("Positive dimensionless scale inherited by sections with blank tension. Applies to smooth connectors.")
            Toggle("Closed section loop", isOn: $draft.closesSectionLoop)
            Toggle("Simplify", isOn: $draft.loftSimplify)
            Picker("Start continuity", selection: $draft.loftStartContinuity) {
                ForEach(ModelingOperationDraft.LoftContinuityChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .contentShape(Rectangle())
            Picker("End continuity", selection: $draft.loftEndContinuity) {
                ForEach(ModelingOperationDraft.LoftContinuityChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .contentShape(Rectangle())
            if draft.loftStartContinuity != .g0 || draft.loftEndContinuity != .g0 {
                TextField("Edge tension", text: $draft.loftEdgeTension)
                TextField("Angle allowance beside curved faces (degrees)", text: $draft.continuityAllowance)
                if draft.loftStartContinuity == .g2 || draft.loftEndContinuity == .g2 {
                    lengthField("Curvature allowance radius beside curved faces", text: $draft.curvatureAllowanceRadius)
                }
                Text("G1 and G2 ends meet a planar face beside the edge exactly; beside a curved face within the allowances.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .fillet:
            Picker("Shape", selection: $draft.filletShape) {
                ForEach(ModelingOperationDraft.FilletShapeChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .contentShape(Rectangle())
            if draft.filletShape == .full {
                Text("Select the two edges on either side of a face: the round is tangent to it and to both faces beside it.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                lengthField(draft.filletShape == .round ? "Radius" : "Distance", text: $draft.distance)
                lengthField("End radius (variable; blank for constant)", text: $draft.filletEndRadius)
                TextField("Variable points (fraction@radius, …)", text: $draft.filletVariablePoints)
                TextField("Limit start (fraction of the edge; blank 0)", text: $draft.limitStart)
                TextField("Limit end (fraction of the edge; blank 1)", text: $draft.limitEnd)
                Toggle("Reverse limits", isOn: $draft.limitsReversed)
                Toggle("Tangent edges", isOn: $draft.tangentEdges)
            }
            if draft.filletShape.takesTension {
                TextField(draft.filletShape == .conic ? "Tension (rho, 0–1; blank 0.5)" : "Tension (blank 1)", text: $draft.filletTension)
            }
        case .chamfer:
            lengthField("Distance", text: $draft.distance)
            Picker("Mode", selection: $draft.chamferMode) {
                ForEach(ModelingOperationDraft.ChamferModeChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .contentShape(Rectangle())
            .disabled(draft.chamferAngle.trimmingCharacters(in: .whitespaces).isEmpty == false)
            TextField("Angle (degrees; blank for Offset or Apex)", text: $draft.chamferAngle)
            if draft.chamferAngle.trimmingCharacters(in: .whitespaces).isEmpty == false {
                Toggle("Flip reference face", isOn: $draft.chamferFlipped)
            }
            TextField("Limit start (fraction of the edge; blank 0)", text: $draft.limitStart)
            TextField("Limit end (fraction of the edge; blank 1)", text: $draft.limitEnd)
                Toggle("Reverse limits", isOn: $draft.limitsReversed)
                Toggle("Tangent edges", isOn: $draft.tangentEdges)
        case .g2Blend:
            lengthField("Distance", text: $draft.distance)
        case .patch, .bridge:
            EmptyView()
        case .bridgeSurface:
            lengthField("Width", text: $draft.distance)
            Picker("Shape", selection: $draft.bridgeShape) {
                ForEach(ModelingOperationDraft.BridgeShapeChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .contentShape(Rectangle())
            if draft.bridgeShape == .g2 {
                TextField("Tension", text: $draft.bridgeTension)
            }
            Toggle("Reverse sense", isOn: $draft.bridgeReversesSense)
            Picker("Trim walls", selection: $draft.bridgeTrim) {
                ForEach(ModelingOperationDraft.BridgeTrimChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .contentShape(Rectangle())
            .help("Cut both sheets, or the one reaching less (Short) or more (Long) far from where they meet, back to the bridge and join them with it into one sheet.")
            TextField("Angle allowance beside curved sheets (degrees)", text: $draft.continuityAllowance)
            if draft.bridgeShape == .g2 {
                lengthField("Curvature allowance radius beside curved sheets", text: $draft.curvatureAllowanceRadius)
            }
            Text("Two planar sheets meeting: the bridge meets each the width from where their planes meet. Curved or parallel sheets: the bridge spans their nearest boundary edges, G2 with both within the allowances, or chamfers across.")
                .font(.caption).foregroundStyle(.secondary)
        case .square:
            Picker("Continuity", selection: Binding(
                get: { draft.squareContinuity },
                set: { draft.squareContinuity = $0; draft.squareSideContinuity = [:] }
            )) {
                ForEach(ModelingOperationDraft.SquareContinuityChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .contentShape(Rectangle())
            .help("Every side's continuity; each side's own picker overrides it.")
            HStack {
                TextField("Degree U", text: $draft.squareUDegree)
                TextField("Degree V", text: $draft.squareVDegree)
            }
            HStack {
                TextField("Spans U", text: $draft.squareUSpans)
                TextField("Spans V", text: $draft.squareVSpans)
            }
            TextField("Flatness (0–1]", text: $draft.squareFlatness)
            TextField("Weight", text: $draft.squareWeight)
            Picker("Boundary", selection: $draft.squareBoundaryFlow) {
                Text("Natural").tag(SquareFitOptions.BoundaryFlow.natural)
                Text("Normal").tag(SquareFitOptions.BoundaryFlow.normal)
                Text("Next").tag(SquareFitOptions.BoundaryFlow.next)
                Text("Adjacent").tag(SquareFitOptions.BoundaryFlow.adjacent)
            }
            .contentShape(Rectangle())
            .help("Natural: no flow. Normal: the cross flow perpendicular to each side. Next: perpendicular within the frame's mean plane. Adjacent: following the neighbouring sides.")
            if draft.targets.contains(where: { draft.squareContinuity(of: $0).order != nil }) {
                TextField("Tension", text: $draft.squareTension)
                TextField("Angle allowance beside curved faces (degrees)", text: $draft.continuityAllowance)
                if draft.targets.contains(where: { draft.squareContinuity(of: $0) == .g2 }) {
                    lengthField("Curvature allowance radius beside curved faces", text: $draft.curvatureAllowanceRadius)
                }
            }
            Text("Select two to four sides: edges of bodies or curves. Four meeting end to end frame the sheet; three are closed by a straight side; two at a corner are completed by their copies; two apart are ruled between. Degree and Spans are the least the sheet takes; its other control points are as fair as Flatness asks, Free sides and the Boundary flow weighted by Weight. The sheet's Analysis is shown in its inspector.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func loftSectionFields(for id: SceneNodeID) -> some View {
        switch Result(catching: { try draft.sectionReference(for: id, in: document) }) {
        case .success(let section):
            LoftSectionEditorFields(controls: Binding(
            get: { draft.loftSectionControls[id] ?? LoftSectionDraft(section: LoftSectionReference(section: section)) },
            set: { draft.loftSectionControls[id] = $0 }
            ), smooth: draft.smooth, supportsCurveControls: !section.isProfile)
        case .failure(let error):
            Text(error.localizedDescription).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lengthField(_ title: String, text: Binding<String>) -> some View {
        TextField("\(title) (\(draft.unit.symbol))", text: text)
    }

    private func vectorFields(_ title: String, values: Binding<[String]>, unit: String) -> some View {
        Section(title) {
            ForEach(0..<3) { index in
                TextField("\(["X", "Y", "Z"][index]) \(unit)", text: Binding(
                    get: { values.wrappedValue[index] },
                    set: { values.wrappedValue[index] = $0 }
                ))
            }
        }
    }
}
