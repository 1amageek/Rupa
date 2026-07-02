import SwiftUI
import RupaCore

struct WorkspaceSplineEndpointConstraintControlsView: View {
    var entity: InspectorSketchEntity
    var displayUnit: LengthDisplayUnit
    var onAddLineTangency: (InspectorSketchEntity, SketchSplineEndpoint, SketchEntityID) -> Void
    var onAddEndpointTangency: (InspectorSketchEntity, SketchSplineEndpoint, SketchSplineEndpointReference) -> Void
    var onAddEndpointSmoothness: (InspectorSketchEntity, SketchSplineEndpoint, SketchSplineEndpointReference) -> Void

    var body: some View {
        tangencyControls
        smoothnessControls
    }

    @ViewBuilder
    private var tangencyControls: some View {
        if entity.tangentLineCandidates.isEmpty && entity.tangentSplineEndpointCandidates.isEmpty {
            workspaceInspectorValueRow("Endpoint Tangency", "No Targets")
        } else {
            if hasSplineEndpointTangency(endpoint: .start) {
                workspaceInspectorValueRow(
                    "Start Tangent",
                    splineEndpointTangencySummary(
                        lineIDs: entity.startTangentLineIDs,
                        endpoints: entity.startTangentSplineEndpoints
                    )
                )
            }
            if hasSplineEndpointTangency(endpoint: .end) {
                workspaceInspectorValueRow(
                    "End Tangent",
                    splineEndpointTangencySummary(
                        lineIDs: entity.endTangentLineIDs,
                        endpoints: entity.endTangentSplineEndpoints
                    )
                )
            }
            inspectorActionRow {
                if hasSplineEndpointTangency(endpoint: .start) == false {
                    splineEndpointTangencyMenu(
                        "Start Tangent",
                        endpoint: .start
                    )
                } else {
                    Label("Start On", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("InspectorCurve.spline.startTangentOn")
                }

                if hasSplineEndpointTangency(endpoint: .end) == false {
                    splineEndpointTangencyMenu(
                        "End Tangent",
                        endpoint: .end
                    )
                } else {
                    Label("End On", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("InspectorCurve.spline.endTangentOn")
                }
            }
        }
    }

    @ViewBuilder
    private var smoothnessControls: some View {
        if entity.tangentSplineEndpointCandidates.isEmpty {
            workspaceInspectorValueRow("Endpoint Smooth", "No Targets")
        } else {
            if hasSplineEndpointSmoothness(endpoint: .start) {
                workspaceInspectorValueRow(
                    "Start Smooth",
                    splineEndpointSmoothSummary(endpoints: entity.startSmoothSplineEndpoints)
                )
            }
            if hasSplineEndpointSmoothness(endpoint: .end) {
                workspaceInspectorValueRow(
                    "End Smooth",
                    splineEndpointSmoothSummary(endpoints: entity.endSmoothSplineEndpoints)
                )
            }
            inspectorActionRow {
                if hasSplineEndpointSmoothness(endpoint: .start) == false {
                    splineEndpointSmoothMenu(
                        "Start Smooth",
                        endpoint: .start
                    )
                } else {
                    Label("Start On", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("InspectorCurve.spline.startSmoothOn")
                }

                if hasSplineEndpointSmoothness(endpoint: .end) == false {
                    splineEndpointSmoothMenu(
                        "End Smooth",
                        endpoint: .end
                    )
                } else {
                    Label("End On", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("InspectorCurve.spline.endSmoothOn")
                }
            }
        }
    }

    private func splineEndpointTangencyMenu(
        _ title: String,
        endpoint: SketchSplineEndpoint
    ) -> some View {
        Menu {
            if entity.tangentLineCandidates.isEmpty == false {
                Section("Lines") {
                    ForEach(entity.tangentLineCandidates) { candidate in
                        Button {
                            onAddLineTangency(entity, endpoint, candidate.id)
                        } label: {
                            Label(sketchLineCandidateTitle(candidate), systemImage: "line.diagonal")
                        }
                    }
                }
            }
            if entity.tangentSplineEndpointCandidates.isEmpty == false {
                Section("Splines") {
                    ForEach(entity.tangentSplineEndpointCandidates) { candidate in
                        Button {
                            onAddEndpointTangency(entity, endpoint, candidate.reference)
                        } label: {
                            Label(
                                sketchSplineEndpointCandidateTitle(candidate),
                                systemImage: "point.3.connected.trianglepath.dotted"
                            )
                        }
                    }
                }
            }
        } label: {
            Label(title, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
        }
        .accessibilityIdentifier("InspectorCurve.spline.\(endpoint.rawValue)Tangent")
    }

    private func splineEndpointSmoothMenu(
        _ title: String,
        endpoint: SketchSplineEndpoint
    ) -> some View {
        Menu {
            ForEach(entity.tangentSplineEndpointCandidates) { candidate in
                Button {
                    onAddEndpointSmoothness(entity, endpoint, candidate.reference)
                } label: {
                    Label(
                        sketchSplineEndpointCandidateTitle(candidate),
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                }
            }
        } label: {
            Label(title, systemImage: "point.3.connected.trianglepath.dotted")
        }
        .accessibilityIdentifier("InspectorCurve.spline.\(endpoint.rawValue)Smooth")
    }

    private func hasSplineEndpointTangency(endpoint: SketchSplineEndpoint) -> Bool {
        switch endpoint {
        case .start:
            return entity.startTangentLineIDs.isEmpty == false ||
                entity.startTangentSplineEndpoints.isEmpty == false
        case .end:
            return entity.endTangentLineIDs.isEmpty == false ||
                entity.endTangentSplineEndpoints.isEmpty == false
        }
    }

    private func hasSplineEndpointSmoothness(endpoint: SketchSplineEndpoint) -> Bool {
        switch endpoint {
        case .start:
            return entity.startSmoothSplineEndpoints.isEmpty == false
        case .end:
            return entity.endSmoothSplineEndpoints.isEmpty == false
        }
    }

    private func splineEndpointTangencySummary(
        lineIDs: Set<SketchEntityID>,
        endpoints: Set<SketchSplineEndpointReference>
    ) -> String {
        let lineSummaries = lineIDs.map { "Line \(shortID($0))" }
        let endpointSummaries = endpoints.map { "Spline \(shortID($0.splineID)) \($0.endpoint.rawValue)" }
        return (lineSummaries + endpointSummaries)
            .sorted()
            .joined(separator: ", ")
    }

    private func splineEndpointSmoothSummary(
        endpoints: Set<SketchSplineEndpointReference>
    ) -> String {
        endpoints.map { "Spline \(shortID($0.splineID)) \($0.endpoint.rawValue)" }
            .sorted()
            .joined(separator: ", ")
    }

    private func sketchLineCandidateTitle(_ candidate: InspectorSketchLineCandidate) -> String {
        if let length = sketchLineLength(start: candidate.start, end: candidate.end) {
            return "Line \(shortID(candidate.id))  \(formatted(length))"
        }
        return "Line \(shortID(candidate.id))"
    }

    private func sketchSplineEndpointCandidateTitle(_ candidate: InspectorSplineEndpointCandidate) -> String {
        "Spline \(shortID(candidate.splineID)) \(candidate.endpoint.rawValue)"
    }

    private func sketchLineLength(
        start: SketchEntitySummaryResult.Point,
        end: SketchEntitySummaryResult.Point
    ) -> Double? {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        return length.isFinite && length > 0.0 ? length : nil
    }

    private func formatted(_ meters: Double) -> String {
        WorkspaceInspectorNumberText.readableLengthString(
            fromMeters: meters,
            preferredUnit: displayUnit
        )
    }

    private func shortID<T: CustomStringConvertible>(_ id: T) -> String {
        String(id.description.prefix(8))
    }
}
