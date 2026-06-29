import SwiftUI
import RupaCore

struct WorkspaceSurfaceInspectorView: View {
    var analysisResult: Result<InspectorSurfaceAnalysis?, Error>
    var continuityResult: Result<InspectorSurfaceContinuity?, Error>
    var boundaryContinuityStateResult: Result<SurfaceBoundaryContinuityInspectorState?, Error>
    var showsUnavailableSections: Bool
    var displayUnit: LengthDisplayUnit
    @Binding var boundaryContinuityLevel: SurfaceBoundaryContinuityLevel
    @Binding var boundaryMatchSide: SurfaceBoundaryMatchSide
    @Binding var boundaryReferenceDirection: SurfaceBoundaryReferenceDirection
    var onMatchBoundaryContinuity: (
        SelectionReference,
        SelectionReference,
        SurfaceBoundaryContinuityLevel,
        SurfaceBoundaryMatchSide,
        SurfaceBoundaryReferenceDirection
    ) -> Void

    var body: some View {
        surfaceAnalysisSection
        surfaceContinuitySection
        surfaceBoundaryContinuitySection
    }

    @ViewBuilder
    private var surfaceAnalysisSection: some View {
        switch analysisResult {
        case .success(let analysis):
            if let analysis {
                inspectorSection("Surface Analysis") {
                    workspaceInspectorValueRow("B-spline Faces", "\(analysis.bSplineFaceCount)")
                    workspaceInspectorValueRow("UV Samples", "\(analysis.sampleCount)")
                    workspaceInspectorValueRow(
                        "Comb Samples",
                        "\(analysis.uCurvatureCombCount) U, \(analysis.vCurvatureCombCount) V"
                    )
                    workspaceInspectorValueRow(
                        "Trim Boundaries",
                        surfaceTrimBoundarySummary(
                            boundaryCount: analysis.trimBoundaryCount,
                            innerCount: analysis.innerTrimBoundaryCount,
                            openCount: analysis.openTrimBoundaryCount
                        )
                    )
                    workspaceInspectorValueRow("Trim Edges", "\(analysis.trimBoundaryEdgeCount)")
                    if analysis.faces.isEmpty {
                        workspaceInspectorValueRow("Target", "No B-spline face")
                    } else {
                        ForEach(analysis.faces) { face in
                            faceAnalysisRows(face)
                        }
                    }
                    if analysis.diagnostics.isEmpty == false {
                        workspaceInspectorValueRow(
                            "Diagnostics",
                            surfaceDiagnosticsSummary(analysis.diagnostics)
                        )
                    }
                }
            }
        case .failure(let error):
            if showsUnavailableSections {
                inspectorSection("Surface Analysis") {
                    workspaceInspectorValueRow("Status", "Unavailable")
                    workspaceInspectorValueRow("Reason", error.localizedDescription)
                }
            }
        }
    }

    @ViewBuilder
    private func faceAnalysisRows(_ face: InspectorSurfaceFaceAnalysis) -> some View {
        workspaceInspectorValueRow("Face", surfaceAnalysisFaceSummary(face))
        workspaceInspectorValueRow("Degree", "\(face.uDegree) U, \(face.vDegree) V")
        workspaceInspectorValueRow(
            "Control Net",
            "\(face.uControlPointCount) U x \(face.vControlPointCount) V"
        )
        workspaceInspectorValueRow("Samples", "\(face.sampleCount)")
        workspaceInspectorValueRow(
            "Trim Boundary",
            surfaceTrimBoundarySummary(
                boundaryCount: face.trimBoundaryCount,
                innerCount: face.innerTrimBoundaryCount,
                openCount: face.openTrimBoundaryCount
            )
        )
        workspaceInspectorValueRow("Trim Edges", "\(face.trimBoundaryEdgeCount)")
        workspaceInspectorValueRow("Trim Length", formatted(face.trimBoundaryLength))
        workspaceInspectorValueRow(
            "U Curvature",
            formattedCurvature(face.maxAbsUNormalCurvature)
        )
        workspaceInspectorValueRow(
            "V Curvature",
            formattedCurvature(face.maxAbsVNormalCurvature)
        )
        workspaceInspectorValueRow(
            "Principal Curvature",
            formattedCurvature(face.maxAbsPrincipalCurvature)
        )
        if let direction = face.minimumPrincipalDirection {
            workspaceInspectorValueRow(
                "Min Direction",
                formattedSurfaceDirection(direction)
            )
        }
        if let direction = face.maximumPrincipalDirection {
            workspaceInspectorValueRow(
                "Max Direction",
                formattedSurfaceDirection(direction)
            )
        }
        workspaceInspectorValueRow(
            "Gaussian Curvature",
            formattedGaussianCurvature(face.maxAbsGaussianCurvature)
        )
        workspaceInspectorValueRow(
            "U Normal Change",
            formattedCurvature(face.maxUNormalChangePerLength)
        )
        workspaceInspectorValueRow(
            "V Normal Change",
            formattedCurvature(face.maxVNormalChangePerLength)
        )
        workspaceInspectorValueRow(
            "Max Normal Angle",
            formattedDegrees(degrees(fromRadians: face.maxNormalAngle))
        )
    }

    @ViewBuilder
    private var surfaceContinuitySection: some View {
        switch continuityResult {
        case .success(let continuity):
            if let continuity {
                inspectorSection("Surface Continuity") {
                    workspaceInspectorValueRow("B-spline Faces", "\(continuity.bSplineFaceCount)")
                    workspaceInspectorValueRow("Shared Edges", "\(continuity.sharedEdgeCount)")
                    workspaceInspectorValueRow("Continuity", surfaceContinuityCountsSummary(continuity))
                    workspaceInspectorValueRow("G2 Solve", surfaceContinuitySolveSummary(continuity))
                    if continuity.adjacencies.isEmpty {
                        workspaceInspectorValueRow("Adjacency", "None for target")
                    } else {
                        ForEach(continuity.adjacencies) { adjacency in
                            adjacencyRows(adjacency)
                        }
                    }
                    if continuity.diagnostics.isEmpty == false {
                        workspaceInspectorValueRow(
                            "Diagnostics",
                            surfaceDiagnosticsSummary(continuity.diagnostics)
                        )
                    }
                }
            }
        case .failure(let error):
            if showsUnavailableSections {
                inspectorSection("Surface Continuity") {
                    workspaceInspectorValueRow("Status", "Unavailable")
                    workspaceInspectorValueRow("Reason", error.localizedDescription)
                }
            }
        }
    }

    @ViewBuilder
    private var surfaceBoundaryContinuitySection: some View {
        switch boundaryContinuityStateResult {
        case .success(let state):
            if let state {
                inspectorSection("Boundary Continuity") {
                    workspaceInspectorValueRow("Selection", "\(state.selectedTrimCount) trims")
                    workspaceInspectorValueRow("Status", state.statusTitle)
                    Picker("Level", selection: $boundaryContinuityLevel) {
                        ForEach(SurfaceBoundaryContinuityLevel.allCases, id: \.self) { level in
                            Text(surfaceBoundaryContinuityTitle(level)).tag(level)
                        }
                    }
                    Picker("Side", selection: $boundaryMatchSide) {
                        ForEach(SurfaceBoundaryMatchSide.allCases, id: \.self) { side in
                            Text(surfaceBoundaryMatchSideTitle(side)).tag(side)
                        }
                    }
                    Picker("Reference", selection: $boundaryReferenceDirection) {
                        ForEach(SurfaceBoundaryReferenceDirection.allCases, id: \.self) { direction in
                            Text(surfaceBoundaryReferenceDirectionTitle(direction)).tag(direction)
                        }
                    }
                    Button {
                        if let target = state.targetReference,
                           let reference = state.referenceReference {
                            onMatchBoundaryContinuity(
                                target,
                                reference,
                                boundaryContinuityLevel,
                                boundaryMatchSide,
                                boundaryReferenceDirection
                            )
                        }
                    } label: {
                        Label("Match Boundary", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!state.canMatch)
                }
            }
        case .failure(let error):
            if showsUnavailableSections {
                inspectorSection("Boundary Continuity") {
                    workspaceInspectorValueRow("Status", "Unavailable")
                    workspaceInspectorValueRow("Reason", error.localizedDescription)
                }
            }
        }
    }

    @ViewBuilder
    private func adjacencyRows(_ adjacency: InspectorSurfaceAdjacency) -> some View {
        workspaceInspectorValueRow("Edge", surfaceAdjacencyEdgeSummary(adjacency))
        workspaceInspectorValueRow("Faces", surfaceAdjacencyFaceSummary(adjacency))
        workspaceInspectorValueRow("Status", surfaceAdjacencyContinuitySummary(adjacency))
        if let normalAngle = adjacency.normalAngle {
            workspaceInspectorValueRow(
                "Normal Angle",
                formattedDegrees(degrees(fromRadians: normalAngle))
            )
        }
        workspaceInspectorValueRow("Position Gap", formatted(adjacency.positionGap))
        if let curvatureGap = adjacency.curvatureGap {
            workspaceInspectorValueRow("Curvature Gap", formattedCurvature(curvatureGap))
        }
        workspaceInspectorValueRow(
            "G2 Required",
            adjacency.requiresCurvatureContinuitySolve ? "Yes" : "No"
        )
    }

    private func surfaceContinuityCountsSummary(_ continuity: InspectorSurfaceContinuity) -> String {
        [
            "\(continuity.g0AdjacencyCount) G0",
            "\(continuity.g1AdjacencyCount) G1",
            "\(continuity.g2AdjacencyCount) G2",
        ]
        .joined(separator: ", ")
    }

    private func surfaceContinuitySolveSummary(_ continuity: InspectorSurfaceContinuity) -> String {
        continuity.unresolvedG2AdjacencyCount == 0
            ? "Not required"
            : "\(continuity.unresolvedG2AdjacencyCount) required"
    }

    private func surfaceAdjacencyEdgeSummary(_ adjacency: InspectorSurfaceAdjacency) -> String {
        let names = adjacency.edgePersistentNames.map(surfacePersistentNameTail)
        return valueSummary(names.isEmpty ? [shortID(adjacency.id)] : names)
    }

    private func surfaceAdjacencyFaceSummary(_ adjacency: InspectorSurfaceAdjacency) -> String {
        valueSummary([
            surfacePersistentNameTail(adjacency.firstFacePersistentName),
            surfacePersistentNameTail(adjacency.secondFacePersistentName),
        ])
    }

    private func surfaceAdjacencyContinuitySummary(_ adjacency: InspectorSurfaceAdjacency) -> String {
        var parts = [surfaceContinuityTitle(adjacency.continuity)]
        if adjacency.requiresCurvatureContinuitySolve {
            parts.append("G2 solve required")
        }
        return parts.joined(separator: " / ")
    }

    private func surfaceAnalysisFaceSummary(_ face: InspectorSurfaceFaceAnalysis) -> String {
        let names = face.facePersistentNames.map(surfacePersistentNameTail)
        return valueSummary(names.isEmpty ? [shortID(face.id)] : names)
    }

    private func surfaceContinuityTitle(
        _ level: RupaCore.SurfaceContinuityResult.ContinuityLevel
    ) -> String {
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

    private func surfaceBoundaryContinuityTitle(_ level: SurfaceBoundaryContinuityLevel) -> String {
        switch level {
        case .g0:
            return "G0"
        case .g1:
            return "G1"
        case .g2:
            return "G2"
        }
    }

    private func surfaceBoundaryMatchSideTitle(_ side: SurfaceBoundaryMatchSide) -> String {
        switch side {
        case .automatic:
            return "Auto"
        case .same:
            return "Same"
        case .opposite:
            return "Opposite"
        }
    }

    private func surfaceBoundaryReferenceDirectionTitle(
        _ direction: SurfaceBoundaryReferenceDirection
    ) -> String {
        switch direction {
        case .automatic:
            return "Auto"
        case .forward:
            return "Forward"
        case .reversed:
            return "Reversed"
        }
    }

    private func surfaceTrimBoundarySummary(
        boundaryCount: Int,
        innerCount: Int,
        openCount: Int
    ) -> String {
        var parts = ["\(boundaryCount) total"]
        if innerCount > 0 {
            parts.append("\(innerCount) inner")
        }
        if openCount > 0 {
            parts.append("\(openCount) open")
        }
        return parts.joined(separator: ", ")
    }

    private func surfacePersistentNameTail(_ name: String?) -> String {
        guard let name, name.isEmpty == false else {
            return "Unknown"
        }
        return name.split(separator: "/").last.map(String.init) ?? name
    }

    private func surfaceDiagnosticsSummary(_ diagnostics: [EditorDiagnostic]) -> String {
        let errors = diagnostics.filter { $0.severity == .error }.count
        let warnings = diagnostics.filter { $0.severity == .warning }.count
        let info = diagnostics.filter { $0.severity == .info }.count
        return "\(errors) errors, \(warnings) warnings, \(info) info"
    }

    private func formatted(_ meters: Double) -> String {
        let value = displayUnit.value(fromMeters: meters)
        return "\(value.formatted(.number.precision(.fractionLength(0...4)))) \(displayUnit.symbol)"
    }

    private func formattedCurvature(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...4)))) 1/m"
    }

    private func formattedGaussianCurvature(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...4)))) 1/m^2"
    }

    private func formattedSurfaceDirection(_ vector: SurfaceAnalysisResult.Vector) -> String {
        let x = vector.x.formatted(.number.precision(.fractionLength(0...3)))
        let y = vector.y.formatted(.number.precision(.fractionLength(0...3)))
        let z = vector.z.formatted(.number.precision(.fractionLength(0...3)))
        return "x \(x), y \(y), z \(z)"
    }

    private func formattedDegrees(_ degrees: Double) -> String {
        "\(degrees.formatted(.number.precision(.fractionLength(0...2)))) deg"
    }

    private func degrees(fromRadians radians: Double) -> Double {
        radians * 180.0 / .pi
    }

    private func valueSummary(_ values: [String]) -> String {
        values.isEmpty ? "None" : values.joined(separator: ", ")
    }

    private func shortID<T: CustomStringConvertible>(_ id: T) -> String {
        String(id.description.prefix(8))
    }
}
