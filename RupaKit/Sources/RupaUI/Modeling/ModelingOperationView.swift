import SwiftUI
import RupaCore

struct ModelingOperationView: View {
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
                TextField("Name", text: $draft.name)
                if ![.box, .cylinder, .sphere, .surfacePatch].contains(draft.kind) {
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
        case .surfacePatch:
            vectorFields("Origin", values: $draft.origin, unit: draft.unit.symbol)
            lengthField("Width X", text: $draft.width)
            lengthField("Width Y", text: $draft.height)
        case .surfaceOffset:
            lengthField("Signed normal offset", text: $draft.distance)
        case .thicken:
            lengthField("Thickness", text: $draft.distance)
                .contentShape(Rectangle())
            Picker("Side", selection: $draft.thickenSide) {
                Text("Positive normal").tag(ThickenSide.positive)
                Text("Negative normal").tag(ThickenSide.negative)
                Text("Symmetric").tag(ThickenSide.symmetric)
            }
            .contentShape(Rectangle())
            Text("Thicken the entire sheet containing the selected face. Symmetric distributes the total thickness equally on both sides. Preview verifies the resulting solid.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .shell:
            lengthField("Wall thickness", text: $draft.distance)
            Text("Remove the selected face and hollow the body inward. The native Shell currently requires one orthogonal six-face solid; Preview verifies the wall thickness fits.")
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
            lengthField("Distance", text: $draft.distance)
            Picker("Direction", selection: $draft.extrusionDirection) {
                ForEach(ModelingOperationDraft.ExtrusionDirectionChoice.allCases) { direction in
                    Text(direction.rawValue).tag(direction)
                }
            }
            .contentShape(Rectangle())
            if draft.extrusionDirection == .vector {
                vectorFields("Direction", values: $draft.axis, unit: "")
            }
            if !draft.isSurfaceCreation { Toggle("Sheet output", isOn: $draft.sheet) }
        case .revolve:
            vectorFields("Axis origin", values: $draft.origin, unit: draft.unit.symbol)
            vectorFields("Axis direction", values: $draft.axis, unit: "")
            TextField("Angle (degrees)", text: $draft.angle)
        case .sweep:
            if !draft.isSurfaceCreation { Toggle("Sheet output", isOn: $draft.sheet) }
            Text("Select the section first, optional guides next, and the path last.").font(.caption).foregroundStyle(.secondary)
            TextField("Twist angle (degrees)", text: $draft.twistAngle)
            Toggle("Reverse twist at midpoint (double helix)", isOn: $draft.doubleHelical)
            lengthField("Positional approximation allowance", text: $draft.approximationTolerance)
            Text("Twisted sweeps require a straight path normal to the section and no guides. For double helix, the angle is reached at the midpoint and returns to zero at the end. The allowance is a shape error bound, not display quality or manufacturing tolerance.")
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
        case .boolean:
            Picker("Operation", selection: $draft.booleanOperation) {
                Text("Union").tag(BooleanOperation.union)
                Text("Subtract").tag(BooleanOperation.difference)
                Text("Intersect").tag(BooleanOperation.intersect)
                Text("Slice").tag(BooleanOperation.slice)
            }
            Toggle("Keep tool bodies", isOn: $draft.keepTools)
        case .fillet:
            lengthField("Radius", text: $draft.distance)
        case .chamfer, .g2Blend:
            lengthField("Distance", text: $draft.distance)
        case .patch, .bridge:
            EmptyView()
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
