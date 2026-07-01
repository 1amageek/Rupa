import SwiftUI
import RupaCore

struct WorkspaceSketchCurveOperationControlsView: View {
    var entity: InspectorSketchEntity
    var controls: [WorkspaceSketchCurveOperationControl]
    var state: WorkspaceSketchCurveOperationControlsState
    var displayUnit: LengthDisplayUnit
    @Binding var extendDistanceMeters: Double
    @Binding var extendShape: ExtendCurveShape
    @Binding var vertexOffsetDistanceMeters: Double
    @Binding var cornerTreatmentDistanceMeters: Double
    @Binding var cornerTreatment: SketchCornerTreatment
    @Binding var joinContinuity: SketchCurveJoinContinuity
    @Binding var vertexAlignmentContinuity: SketchVertexAlignmentContinuity
    var sliderMetersRange: (Double) -> ClosedRange<Double>
    var onExtend: (SelectionTarget) -> Void
    var onOffsetVertex: (InspectorSketchEntity) -> Void
    var onApplyCornerTreatment: (SelectionTarget) -> Void
    var onJoin: (InspectorSketchEntity) -> Void
    var onUnjoin: (InspectorSketchEntity) -> Void
    var onAlignVertex: (InspectorSketchEntity) -> Void
    var onProject: (InspectorSketchEntity) -> Void

    var body: some View {
        ForEach(controls, id: \.self) { control in
            controlView(control)
        }
    }

    @ViewBuilder
    private func controlView(_ control: WorkspaceSketchCurveOperationControl) -> some View {
        switch control {
        case .projection:
            projectionControls
        case .alignment:
            alignmentControls
        case .vertexOffset:
            vertexOffsetControls
        case .cornerTreatment:
            cornerTreatmentControls
        case .extend:
            extendControls
        case .join:
            joinControls
        }
    }

    private var projectionControls: some View {
        inspectorActionRow {
            Button {
                onProject(entity)
            } label: {
                Label("Project", systemImage: "square.on.square")
            }
            .disabled(state.canProject == false)
            .accessibilityIdentifier("InspectorCurve.\(entity.entityKind).project")
        }
    }

    @ViewBuilder
    private var alignmentControls: some View {
        inspectorControlRow("Align") {
            Picker("", selection: $vertexAlignmentContinuity) {
                ForEach(SketchVertexAlignmentContinuity.allCases, id: \.self) { continuity in
                    Text(vertexAlignmentContinuityTitle(continuity)).tag(continuity)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("InspectorCurve.\(entity.entityKind).alignContinuity")
        }
        inspectorActionRow {
            Button {
                onAlignVertex(entity)
            } label: {
                Label("Align", systemImage: "arrow.triangle.merge")
            }
            .disabled(state.canAlignVertex == false)
            .accessibilityIdentifier("InspectorCurve.\(entity.entityKind).alignVertex")
        }
    }

    @ViewBuilder
    private var vertexOffsetControls: some View {
        workspaceLengthControl(
            "Vertex Offset",
            values: [vertexOffsetDistanceMeters],
            displayUnit: displayUnit,
            sliderMetersRange: sliderMetersRange(vertexOffsetDistanceMeters)
        ) { meters in
            vertexOffsetDistanceMeters = max(meters, 1.0e-9)
        }
        inspectorActionRow {
            Button {
                onOffsetVertex(entity)
            } label: {
                Label("Offset Vertex", systemImage: "arrow.left.and.right")
            }
            .disabled(state.canOffsetVertex == false)
            .accessibilityIdentifier("InspectorCurve.offsetVertex")
        }
    }

    @ViewBuilder
    private var cornerTreatmentControls: some View {
        workspaceLengthControl(
            "Corner",
            values: [cornerTreatmentDistanceMeters],
            displayUnit: displayUnit,
            sliderMetersRange: sliderMetersRange(cornerTreatmentDistanceMeters)
        ) { meters in
            cornerTreatmentDistanceMeters = max(meters, 1.0e-9)
        }
        inspectorControlRow("Treatment") {
            Picker("", selection: $cornerTreatment) {
                ForEach(SketchCornerTreatment.allCases, id: \.self) { treatment in
                    Text(cornerTreatmentTitle(treatment)).tag(treatment)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("InspectorCurve.cornerTreatment")
        }
        inspectorActionRow {
            Button {
                onApplyCornerTreatment(entity.target)
            } label: {
                Label(
                    cornerTreatmentTitle(cornerTreatment),
                    systemImage: cornerTreatment == .fillet ? "circle.dashed" : "line.diagonal"
                )
            }
            .disabled(state.canApplyCornerTreatment == false)
            .accessibilityIdentifier("InspectorCurve.cornerTreatment.apply")
        }
    }

    @ViewBuilder
    private var extendControls: some View {
        workspaceLengthControl(
            "Extend",
            values: [extendDistanceMeters],
            displayUnit: displayUnit,
            sliderMetersRange: sliderMetersRange(extendDistanceMeters)
        ) { meters in
            extendDistanceMeters = max(meters, 1.0e-9)
        }
        inspectorControlRow("Shape") {
            Picker("", selection: $extendShape) {
                ForEach(ExtendCurveShape.allCases, id: \.self) { shape in
                    Text(extendCurveShapeTitle(shape)).tag(shape)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityIdentifier("InspectorCurve.extendShape")
        }
        inspectorActionRow {
            Button {
                onExtend(entity.target)
            } label: {
                Label("Extend", systemImage: "arrow.up.right.line")
            }
            .disabled(state.canExtend == false)
            .accessibilityIdentifier("InspectorCurve.extend")
        }
    }

    @ViewBuilder
    private var joinControls: some View {
        inspectorControlRow("Continuity") {
            Picker("", selection: $joinContinuity) {
                ForEach([SketchCurveJoinContinuity.g0, .g1], id: \.self) { continuity in
                    Text(curveJoinContinuityTitle(continuity)).tag(continuity)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("InspectorCurve.\(entity.entityKind).joinContinuity")
        }
        inspectorActionRow {
            Button {
                onJoin(entity)
            } label: {
                Label("Join", systemImage: "link.badge.plus")
            }
            .disabled(state.canJoin == false)
            .accessibilityIdentifier("InspectorCurve.\(entity.entityKind).join")

            Button {
                onUnjoin(entity)
            } label: {
                Label("Unjoin", systemImage: "link.badge.minus")
            }
            .disabled(state.canUnjoin == false)
            .accessibilityIdentifier("InspectorCurve.\(entity.entityKind).unjoin")
        }
    }

    private func extendCurveShapeTitle(_ shape: ExtendCurveShape) -> String {
        switch shape {
        case .natural:
            return "Natural"
        case .linear:
            return "Linear"
        case .soft:
            return "Soft"
        case .reflective:
            return "Reflective"
        case .arc:
            return "Arc"
        }
    }

    private func cornerTreatmentTitle(_ treatment: SketchCornerTreatment) -> String {
        switch treatment {
        case .fillet:
            return "Fillet"
        case .chamfer:
            return "Chamfer"
        }
    }

    private func curveJoinContinuityTitle(_ continuity: SketchCurveJoinContinuity) -> String {
        switch continuity {
        case .g0:
            return "G0"
        case .g1:
            return "G1"
        case .g2:
            return "G2"
        }
    }

    private func vertexAlignmentContinuityTitle(_ continuity: SketchVertexAlignmentContinuity) -> String {
        switch continuity {
        case .g0:
            return "G0"
        case .g1:
            return "G1"
        case .g2:
            return "G2"
        }
    }
}
