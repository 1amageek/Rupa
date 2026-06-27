import SwiftUI
import RupaCore

struct WorkspaceSketchCurveSelectionErrorView: View {
    var targetSummary: String
    var reason: String

    var body: some View {
        inspectorSection("Curve Selection") {
            workspaceInspectorValueRow("Target", targetSummary)
            workspaceInspectorValueRow("Status", "Unavailable")
            workspaceInspectorValueRow("Reason", reason)
        }
    }
}

struct WorkspaceSketchCurveInspectorView: View {
    var entity: InspectorSketchEntity
    var targetSummary: String
    var displayUnit: LengthDisplayUnit
    var curvatureDisplay: CurveCurvatureDisplay?
    var pointDisplay: PointDisplay?
    var onSetCurveCurvatureDisplay: (InspectorSketchEntity, Bool, Double) -> Void
    var onSetPointDisplay: (InspectorSketchEntity, Bool) -> Void

    var body: some View {
        selectionSection
        if let analysis = entity.analysis {
            analysisSection(analysis)
        }
    }

    private var selectionSection: some View {
        inspectorSection("Curve Selection") {
            workspaceInspectorValueRow("Kind", sketchEntityKindTitle(entity.entityKind))
            workspaceInspectorValueRow("Target", targetSummary)
            workspaceInspectorValueRow("Source", entity.sourceFeatureName ?? shortID(entity.sourceFeatureID))
            workspaceInspectorValueRow("Source ID", shortID(entity.sourceFeatureID))
            workspaceInspectorValueRow("Entity ID", shortID(entity.entityID))
            if let joinedCurveSourceID = entity.joinedCurveSourceID {
                workspaceInspectorValueRow("Join Source", shortID(joinedCurveSourceID))
            }
            if let joinedCurveGroupSourceID = entity.joinedCurveGroupSourceID {
                workspaceInspectorValueRow("Join Group", shortID(joinedCurveGroupSourceID))
            }
            if let continuity = entity.joinedCurveGroupContinuity {
                workspaceInspectorValueRow("Join Continuity", sketchCurveJoinContinuityTitle(continuity))
            }
            if let center = entity.center {
                workspaceInspectorValueRow("Center", sketchPointSummary(center))
            }
            if let start = entity.start {
                workspaceInspectorValueRow("Start", sketchPointSummary(start))
            }
            if let end = entity.end {
                workspaceInspectorValueRow("End", sketchPointSummary(end))
            }
        }
    }

    private func analysisSection(_ analysis: InspectorCurveAnalysis) -> some View {
        inspectorSection("Curve Analysis") {
            workspaceInspectorValueRow("Samples", "\(analysis.sampleCount)")
            workspaceInspectorValueRow("Length", formatted(analysis.approximateLength))
            workspaceInspectorValueRow("Max Curvature", formattedCurvature(analysis.maxAbsCurvature))
            workspaceInspectorValueRow("Curvature Comb", curvatureDisplay == nil ? "Off" : "On")
            if analysis.maxAbsCurvature <= 1.0e-12 {
                workspaceInspectorValueRow("Comb Output", "Flat curve")
            }
            inspectorActionRow {
                Button {
                    onSetCurveCurvatureDisplay(
                        entity,
                        curvatureDisplay == nil,
                        curvatureDisplay?.combScale ?? CurveCurvatureDisplay.defaultCombScale
                    )
                } label: {
                    Label(
                        curvatureDisplay == nil ? "Show Comb" : "Hide Comb",
                        systemImage: curvatureDisplay == nil ? "waveform.path.ecg" : "eye.slash"
                    )
                }
                .accessibilityIdentifier("InspectorCurve.curvatureComb.toggle")
            }
            if let curvatureDisplay {
                numericControl(
                    "Comb Scale",
                    values: [curvatureDisplay.combScale],
                    sliderRange: 0.01 ... max(1.0, curvatureDisplay.combScale * 2.0)
                ) { value in
                    onSetCurveCurvatureDisplay(
                        entity,
                        true,
                        max(value, 1.0e-6)
                    )
                }
            }
            workspaceInspectorValueRow("Points", pointDisplayTitle(pointDisplay))
            inspectorActionRow {
                Button {
                    onSetPointDisplay(
                        entity,
                        pointDisplay?.isVisible == false
                    )
                } label: {
                    Label(
                        pointDisplay?.isVisible == false ? "Show Points" : "Hide Points",
                        systemImage: pointDisplay?.isVisible == false ? "smallcircle.filled.circle" : "eye.slash"
                    )
                }
                .accessibilityIdentifier("InspectorCurve.points.toggle")
            }
            if analysis.continuityJoins.isEmpty {
                workspaceInspectorValueRow("Continuity", "No joins")
            } else {
                workspaceInspectorValueRow("Continuity", "\(analysis.continuityJoins.count) joins")
                ForEach(analysis.continuityJoins) { join in
                    workspaceInspectorValueRow("Join", curveContinuityJoinSummary(join))
                    workspaceInspectorValueRow("Gap", formatted(join.positionGap))
                    if let tangentAngle = join.tangentAngle {
                        workspaceInspectorValueRow("Tangent", formattedDegrees(degrees(fromRadians: tangentAngle)))
                    }
                    if let curvatureGap = join.curvatureGap {
                        workspaceInspectorValueRow("Curvature", formattedCurvature(curvatureGap))
                    }
                }
            }
        }
    }

    private func sketchEntityKindTitle(_ kind: String) -> String {
        switch kind {
        case "point":
            return "Point"
        case "line":
            return "Line"
        case "circle":
            return "Circle"
        case "arc":
            return "Arc"
        case "spline":
            return "Spline"
        default:
            return kind
        }
    }

    private func sketchCurveJoinContinuityTitle(_ continuity: SketchCurveJoinContinuity) -> String {
        switch continuity {
        case .g0:
            return "G0"
        case .g1:
            return "G1"
        case .g2:
            return "G2"
        }
    }

    private func sketchPointSummary(_ point: SketchEntitySummaryResult.Point) -> String {
        "x \(formatted(point.x)), y \(formatted(point.y))"
    }

    private func pointDisplayTitle(_ display: PointDisplay?) -> String {
        guard let display else {
            return "Default"
        }
        return display.isVisible ? "Visible" : "Hidden"
    }

    private func curveContinuityJoinSummary(_ join: InspectorCurveContinuityJoin) -> String {
        var parts = [
            continuityJoinKindTitle(join.joinKind),
            continuityTitle(join.actualContinuity),
        ]
        if let requiredContinuity = join.requiredContinuity {
            parts.append("requires \(continuityTitle(requiredContinuity))")
        }
        let constraints = constraintKindsSummary(join.constraintKinds)
        if constraints.isEmpty == false {
            parts.append(constraints)
        }
        return parts.joined(separator: " / ")
    }

    private func continuityJoinKindTitle(_ kind: CurveAnalysisResult.ContinuityJoinKind) -> String {
        switch kind {
        case .internalSplineKnot:
            return "Internal knot"
        case .constrainedEndpoint:
            return "Endpoint"
        }
    }

    private func continuityTitle(_ level: CurveAnalysisResult.ContinuityLevel) -> String {
        switch level {
        case .disconnected:
            return "Disconnected"
        case .g0:
            return "G0"
        case .g1:
            return "G1"
        case .g2:
            return "G2"
        }
    }

    private func constraintKindsSummary(_ kinds: [String]) -> String {
        kinds.map { kind in
            switch kind {
            case "coincident":
                return "Coincident"
            case "tangentSplineEndpoints":
                return "Tangent"
            case "smoothSplineEndpoints":
                return "Smooth"
            case "splineKnot":
                return "Spline knot"
            default:
                return kind
            }
        }
        .joined(separator: ", ")
    }

    private func formatted(_ meters: Double) -> String {
        let value = displayUnit.value(fromMeters: meters)
        return "\(value.formatted(.number.precision(.fractionLength(0...4)))) \(displayUnit.symbol)"
    }

    private func formattedCurvature(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...4)))) 1/m"
    }

    private func formattedDegrees(_ degrees: Double) -> String {
        "\(degrees.formatted(.number.precision(.fractionLength(0...2)))) deg"
    }

    private func degrees(fromRadians radians: Double) -> Double {
        radians * 180.0 / Double.pi
    }

    private func shortID<T: CustomStringConvertible>(_ id: T) -> String {
        String(id.description.prefix(8))
    }
}
