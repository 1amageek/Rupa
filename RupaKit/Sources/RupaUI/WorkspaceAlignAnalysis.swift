import Foundation
import RupaCore
import RupaRendering
import SwiftCAD

/// Align Surface's Analysis of a previewed alignment: each aligned edge's samples measured by the
/// kernel on the preview's evaluation, kept apart from what is drawn of them, so a change of the
/// measure or its scale redraws without evaluating again.
struct WorkspaceAlignAnalysis: Equatable, Sendable {
    struct Edge: Equatable, Sendable {
        let samples: [ViewportEdgeAlignmentAnalysis.Sample]
        /// The modeling distance the G0 gap is judged against.
        let positionLimit: Double
    }

    let edges: [Edge]

    /// The analysis of the alignments `preview` adds to `base`, its evaluation reusing `current`;
    /// nil when it adds none.
    static func evaluate(preview: DesignDocument, base: DesignDocument, current: DocumentEvaluationContext?) throws -> WorkspaceAlignAnalysis? {
        let features = addedAlignments(in: preview, over: base)
        guard !features.isEmpty else { return nil }
        let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(
            document: preview, currentEvaluation: current, failurePrefix: "The Align Surface analysis could not evaluate the preview"
        )
        return try measure(features, in: evaluated)
    }

    /// The Align Surface features `preview` adds to `base`, ordered by identifier (each edge's label
    /// sits on its own edge, so their order draws nothing different).
    static func addedAlignments(in preview: DesignDocument, over base: DesignDocument) -> [FeatureID] {
        let existing = Set(base.cadDocument.designGraph.nodes.keys)
        return preview.cadDocument.designGraph.nodes.values.compactMap { node -> FeatureID? in
            guard case .surfaceAlign = node.operation, !existing.contains(node.id) else { return nil }
            return node.id
        }.sorted { $0.description < $1.description }
    }

    /// The samples of `features` on the evaluated preview.
    static func measure(_ features: [FeatureID], in document: EvaluatedDocument) throws -> WorkspaceAlignAnalysis {
        let analyzer = SurfaceAlignAnalyzer()
        let limit = document.configuration.tolerance.distance
        return WorkspaceAlignAnalysis(edges: try features.map { feature in
            Edge(samples: try analyzer.samples(feature, in: document).map {
                ViewportEdgeAlignmentAnalysis.Sample(
                    edgePoint: $0.edgePoint, sheetPoint: $0.sheetPoint, sheetNormal: $0.sheetNormal,
                    referenceNormal: $0.referenceNormal, sheetCurvature: $0.sheetCurvature, referenceCurvature: $0.referenceCurvature
                )
            }, positionLimit: limit)
        })
    }

    /// What the viewport draws of it for `measure` at `scale`: each edge labelled with its worst
    /// value, a distance in `displayUnit`, an angle in degrees or a curvature difference in m⁻¹,
    /// within or beyond the kernel's limit.
    func drawn(measure: ViewportEdgeAlignmentAnalysis.Measure, scale: Double, displayUnit: LengthDisplayUnit) -> ViewportEdgeAlignmentAnalysis {
        ViewportEdgeAlignmentAnalysis(measure: measure, scale: scale, edges: edges.map { edge in
            let label: String
            let isWithin: Bool
            switch measure {
            case .position:
                let gap = edge.samples.map { ($0.sheetPoint - $0.edgePoint).length }.max() ?? 0
                label = WorkspaceInspectorNumberText.readableLengthString(fromMeters: gap, preferredUnit: displayUnit)
                isWithin = gap <= edge.positionLimit
            case .tangent:
                let angle = edge.samples.map { acos(min(1, abs($0.sheetNormal.dot($0.referenceNormal)))) }.max() ?? 0
                label = "\(WorkspaceInspectorNumberText.compact(WorkspaceInspectorNumberText.degrees(fromRadians: angle))) deg"
                isWithin = angle <= SurfaceAlignAnalyzer.angleLimit
            case .curvature:
                let difference = edge.samples.map { abs($0.sheetCurvature - $0.referenceCurvature) }.max() ?? 0
                label = "\(WorkspaceInspectorNumberText.compact(difference)) /m"
                isWithin = difference <= SurfaceAlignAnalyzer.curvatureLimit
            }
            return ViewportEdgeAlignmentAnalysis.Edge(samples: edge.samples, label: label, isWithin: isWithin)
        })
    }
}
