import SwiftUI
import RupaCore

struct WorkspaceTopologyEditInspectorView: View {
    var state: WorkspaceTopologyEditInspectorState
    var displayUnit: LengthDisplayUnit
    @Binding var faceDraftAngleDegrees: Double
    @Binding var edgeOffsetDistanceMeters: Double
    @Binding var edgeOffsetGapFill: OffsetCurveGapFill
    @Binding var regionOffsetDistanceMeters: Double
    @Binding var regionOffsetGapFill: OffsetCurveGapFill
    var offsetSliderRange: ClosedRange<Double>
    var onOffsetFace: (SelectionTarget, Double) -> Void
    var onDeleteFaces: ([SelectionTarget]) -> Void
    var onDraftFace: (SelectionTarget, SelectionTarget, Double) -> Void
    var onOffsetEdges: ([SelectionTarget], Double, OffsetCurveGapFill) -> Void
    var onProjectEdges: ([SelectionTarget]) -> Void
    var onFilletEdges: ([SelectionTarget], Double) -> Void
    var onChamferEdges: ([SelectionTarget], Double) -> Void
    var onMoveVertex: (SelectionTarget, Double, Double) -> Void
    var onOffsetRegions: ([SelectionTarget], Double, OffsetCurveGapFill, Bool, Bool) -> Void

    var body: some View {
        faceEditSection
        faceDeleteSection
        faceDraftSection
        edgeEditSection
        vertexEditSection
        regionEditSection
    }

    @ViewBuilder
    private var faceEditSection: some View {
        if state.canEditFace, let faceTarget = state.faceTarget {
            inspectorSection("Face Edit") {
                workspaceInspectorValueRow("Target", state.selectedTargetSummary)
                inspectorActionRow {
                    Button {
                        onOffsetFace(faceTarget, -state.faceOffsetStepMeters)
                    } label: {
                        Label(
                            "Offset -\(formatted(state.faceOffsetStepMeters))",
                            systemImage: "minus"
                        )
                    }
                    .accessibilityIdentifier("InspectorFace.offsetNegative")

                    Button {
                        onOffsetFace(faceTarget, state.faceOffsetStepMeters)
                    } label: {
                        Label(
                            "Offset +\(formatted(state.faceOffsetStepMeters))",
                            systemImage: "plus"
                        )
                    }
                    .accessibilityIdentifier("InspectorFace.offsetPositive")
                }
            }
        }
    }

    @ViewBuilder
    private var faceDeleteSection: some View {
        if state.canDeleteFaces {
            inspectorSection("Delete Face") {
                workspaceInspectorValueRow("Targets", faceTargetSummary)
                inspectorActionRow {
                    Button(role: .destructive) {
                        onDeleteFaces(state.faceTargets)
                    } label: {
                        Label(
                            state.faceTargets.count == 1 ? "Delete Face" : "Delete Faces",
                            systemImage: "trash"
                        )
                    }
                    .accessibilityIdentifier("InspectorFace.delete")
                }
            }
        }
    }

    @ViewBuilder
    private var faceDraftSection: some View {
        if state.canDraftFace,
           let draftFaceTarget = state.draftFaceTarget,
           let draftNeutralFaceTarget = state.draftNeutralFaceTarget {
            inspectorSection("Draft Face") {
                workspaceInspectorValueRow("Target", "First selected face")
                workspaceInspectorValueRow("Neutral", "Second selected face")
                faceDraftAngleControl
                inspectorActionRow {
                    Button {
                        onDraftFace(
                            draftFaceTarget,
                            draftNeutralFaceTarget,
                            -draftAngleMagnitudeDegrees
                        )
                    } label: {
                        Label(
                            "Draft -\(formattedDegrees(draftAngleMagnitudeDegrees))",
                            systemImage: "minus"
                        )
                    }
                    .accessibilityIdentifier("InspectorFaceDraft.negative")

                    Button {
                        onDraftFace(
                            draftFaceTarget,
                            draftNeutralFaceTarget,
                            draftAngleMagnitudeDegrees
                        )
                    } label: {
                        Label(
                            "Draft +\(formattedDegrees(draftAngleMagnitudeDegrees))",
                            systemImage: "plus"
                        )
                    }
                    .accessibilityIdentifier("InspectorFaceDraft.positive")
                }
            }
        }
    }

    private var faceDraftAngleControl: some View {
        numericControl(
            "Angle",
            values: [draftAngleMagnitudeDegrees],
            sliderRange: 0.1...89.0
        ) { degrees in
            faceDraftAngleDegrees = clampedDraftAngleMagnitude(degrees)
        } unitLabel: {
            "deg"
        }
        .accessibilityIdentifier("InspectorFaceDraft.angle")
    }

    @ViewBuilder
    private var edgeEditSection: some View {
        if state.canEditEdges {
            inspectorSection("Edge Edit") {
                workspaceInspectorValueRow("Targets", "\(state.edgeTargets.count)")
                edgeOffsetDistanceControl
                gapFillPicker("Gap Fill", selection: $edgeOffsetGapFill)
                    .accessibilityIdentifier("InspectorEdge.gapFill")
                inspectorActionRow {
                    Button {
                        onOffsetEdges(
                            state.edgeTargets,
                            edgeOffsetDistanceMeters,
                            edgeOffsetGapFill
                        )
                    } label: {
                        Label(
                            "Offset \(formatted(edgeOffsetDistanceMeters))",
                            systemImage: "arrow.up.left.and.arrow.down.right"
                        )
                    }
                    .accessibilityIdentifier("InspectorEdge.offset")
                }

                inspectorActionRow {
                    Button {
                        onProjectEdges(state.projectableEdgeTargets)
                    } label: {
                        Label("Project", systemImage: "square.on.square")
                    }
                    .disabled(state.projectableEdgeTargets.isEmpty)
                    .accessibilityIdentifier("InspectorEdge.project")
                }

                inspectorActionRow {
                    Button {
                        onFilletEdges(state.edgeTargets, state.edgeFilletRadiusMeters)
                    } label: {
                        Label(
                            "Fillet \(formatted(state.edgeFilletRadiusMeters))",
                            systemImage: "circle.dashed"
                        )
                    }
                    .accessibilityIdentifier("InspectorEdge.fillet")

                    Button {
                        onChamferEdges(state.edgeTargets, state.edgeChamferStepMeters)
                    } label: {
                        Label(
                            "Chamfer \(formatted(state.edgeChamferStepMeters))",
                            systemImage: "line.diagonal"
                        )
                    }
                    .accessibilityIdentifier("InspectorEdge.chamfer")
                }
            }
        }
    }

    private var edgeOffsetDistanceControl: some View {
        workspaceLengthControl(
            "Offset",
            values: [edgeOffsetDistanceMeters],
            displayUnit: displayUnit,
            sliderRange: offsetSliderRange
        ) { meters in
            edgeOffsetDistanceMeters = max(meters, 1.0e-9)
        }
        .accessibilityIdentifier("InspectorEdge.offsetDistance")
    }

    @ViewBuilder
    private var vertexEditSection: some View {
        if state.canEditVertex, let vertexTarget = state.vertexTarget {
            inspectorSection("Vertex Edit") {
                workspaceInspectorValueRow("Target", state.selectedTargetSummary)
                inspectorActionRow {
                    Button {
                        onMoveVertex(vertexTarget, -state.vertexMoveStepMeters, 0.0)
                    } label: {
                        Label(
                            "X -\(formatted(state.vertexMoveStepMeters))",
                            systemImage: "arrow.left"
                        )
                    }
                    .accessibilityIdentifier("InspectorVertex.moveXNegative")

                    Button {
                        onMoveVertex(vertexTarget, state.vertexMoveStepMeters, 0.0)
                    } label: {
                        Label(
                            "X +\(formatted(state.vertexMoveStepMeters))",
                            systemImage: "arrow.right"
                        )
                    }
                    .accessibilityIdentifier("InspectorVertex.moveXPositive")
                }
                inspectorActionRow {
                    Button {
                        onMoveVertex(vertexTarget, 0.0, -state.vertexMoveStepMeters)
                    } label: {
                        Label(
                            "Y -\(formatted(state.vertexMoveStepMeters))",
                            systemImage: "arrow.down"
                        )
                    }
                    .accessibilityIdentifier("InspectorVertex.moveYNegative")

                    Button {
                        onMoveVertex(vertexTarget, 0.0, state.vertexMoveStepMeters)
                    } label: {
                        Label(
                            "Y +\(formatted(state.vertexMoveStepMeters))",
                            systemImage: "arrow.up"
                        )
                    }
                    .accessibilityIdentifier("InspectorVertex.moveYPositive")
                }
            }
        }
    }

    @ViewBuilder
    private var regionEditSection: some View {
        if state.canEditRegions {
            inspectorSection("Region Edit") {
                workspaceInspectorValueRow("Targets", state.regionTargetSummary)
                regionOffsetDistanceControl
                gapFillPicker("Gap Fill", selection: $regionOffsetGapFill)
                    .accessibilityIdentifier("InspectorRegion.gapFill")
                inspectorActionRow {
                    Button {
                        onOffsetRegions(
                            state.regionTargets,
                            -regionOffsetDistanceMeters,
                            regionOffsetGapFill,
                            state.usesLockedRegionDistance,
                            state.combinesRegions
                        )
                    } label: {
                        Label("Inward", systemImage: "minus.circle")
                    }
                    .accessibilityIdentifier("InspectorRegion.offsetInward")

                    Button {
                        onOffsetRegions(
                            state.regionTargets,
                            regionOffsetDistanceMeters,
                            regionOffsetGapFill,
                            state.usesLockedRegionDistance,
                            state.combinesRegions
                        )
                    } label: {
                        Label("Outward", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("InspectorRegion.offsetOutward")
                }
            }
        }
    }

    private var regionOffsetDistanceControl: some View {
        workspaceLengthControl(
            "Distance",
            values: [regionOffsetDistanceMeters],
            displayUnit: displayUnit,
            sliderRange: offsetSliderRange
        ) { meters in
            regionOffsetDistanceMeters = max(meters, 1.0e-9)
        }
        .accessibilityIdentifier("InspectorRegion.distance")
    }

    private func gapFillPicker(
        _ title: String,
        selection: Binding<OffsetCurveGapFill>
    ) -> some View {
        inspectorControlRow(title) {
            Picker(
                "",
                selection: selection
            ) {
                ForEach(OffsetCurveGapFill.allCases, id: \.self) { gapFill in
                    Text(gapFillTitle(gapFill))
                        .tag(gapFill)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: inspectorControlWidth)
        }
    }

    private func formatted(_ meters: Double) -> String {
        let value = displayUnit.value(fromMeters: meters)
        return "\(value.formatted(.number.precision(.fractionLength(0...4)))) \(displayUnit.symbol)"
    }

    private var faceTargetSummary: String {
        state.faceTargets.count == 1 ? state.selectedTargetSummary : "\(state.faceTargets.count)"
    }

    private var draftAngleMagnitudeDegrees: Double {
        clampedDraftAngleMagnitude(faceDraftAngleDegrees)
    }

    private func clampedDraftAngleMagnitude(_ degrees: Double) -> Double {
        guard degrees.isFinite else {
            return 5.0
        }
        return min(max(abs(degrees), 0.1), 89.0)
    }

    private func formattedDegrees(_ degrees: Double) -> String {
        "\(degrees.formatted(.number.precision(.fractionLength(0...2)))) deg"
    }

    private func gapFillTitle(_ gapFill: OffsetCurveGapFill) -> String {
        switch gapFill {
        case .round:
            return "Round"
        case .linear:
            return "Linear"
        case .natural:
            return "Natural"
        }
    }
}
