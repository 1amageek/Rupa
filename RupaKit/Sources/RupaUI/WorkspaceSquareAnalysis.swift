import Foundation
import RupaCore
import RupaRendering
import SwiftCAD

/// Square's Analysis of a previewed Square (Plasticity's ANALYSIS → Continuity): each side measured
/// by the kernel on the preview's evaluation (`SquareSideAnalyzer`) with the continuity the side
/// asks for, kept apart from what is drawn of them, so a change of the checked continuity redraws
/// without evaluating again.
struct WorkspaceSquareAnalysis: Equatable, Sendable {
    struct Side: Equatable, Sendable {
        let analysis: SquareSideAnalysis
        /// The order the side holds: nil for a Free side, 0 for G0, 1 for G1 and 2 for G2.
        let order: Int?
    }

    let sides: [Side]

    /// The analysis of the Squares `preview` adds to `base`, its evaluation reusing `current`; nil
    /// when it adds none.
    static func evaluate(preview: DesignDocument, base: DesignDocument, current: DocumentEvaluationContext?) throws -> WorkspaceSquareAnalysis? {
        let existing = Set(base.cadDocument.designGraph.nodes.keys)
        let squares = preview.cadDocument.designGraph.nodes.values.compactMap { node -> (FeatureID, SquareSurfaceFeature)? in
            guard case let .squareSurface(square) = node.operation, !existing.contains(node.id) else { return nil }
            return (node.id, square)
        }.sorted { $0.0.description < $1.0.description }
        guard !squares.isEmpty else { return nil }
        let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(
            document: preview, currentEvaluation: current, failurePrefix: "The Square analysis could not evaluate the preview"
        )
        let analyzer = SquareSideAnalyzer()
        return WorkspaceSquareAnalysis(sides: try squares.flatMap { featureID, square in
            try analyzer.analyze(featureID, in: evaluated).map { analysis in
                let side = square.sides[analysis.side]
                let order: Int?
                switch side.continuity?.order {
                case .tangent: order = 1
                case .curvature: order = 2
                case nil: order = side.isFree ? nil : 0
                }
                return Side(analysis: analysis, order: order)
            }
        })
    }

    /// The labels the viewport draws at `level` (0 for G0, 1 for G1, 2 for G2): beside each side
    /// its value at that continuity — a distance in `displayUnit`, an angle in degrees or a
    /// curvature difference in m⁻¹ — with ✓ within its limit, ⊘ beyond it, and ⚠ where the side
    /// asks for less than the check, so nothing holds it there. A side beside no face is checked at
    /// G0, the only continuity a curve has.
    func drawn(level: Int, displayUnit: LengthDisplayUnit) -> [ViewportAnalysisLabel] {
        sides.compactMap { side in
            guard let anchor = side.analysis.point else { return nil }
            let analysis = side.analysis
            var checked = level
            if checked >= 2, analysis.curvature == nil { checked = analysis.angle == nil ? 0 : 1 }
            if checked == 1, analysis.angle == nil { checked = 0 }
            let value: String
            let isWithin: Bool
            switch checked {
            case 0:
                value = WorkspaceInspectorNumberText.readableLengthString(fromMeters: analysis.position, preferredUnit: displayUnit)
                isWithin = analysis.position <= analysis.positionLimit
            case 1:
                let angle = analysis.angle ?? 0
                value = "\(WorkspaceInspectorNumberText.compact(WorkspaceInspectorNumberText.degrees(fromRadians: angle))) deg"
                isWithin = angle <= (analysis.angleLimit ?? 0)
            default:
                let curvature = analysis.curvature ?? 0
                value = "\(WorkspaceInspectorNumberText.compact(curvature)) /m"
                isWithin = curvature <= (analysis.curvatureLimit ?? 0)
            }
            let verdict: ViewportAnalysisLabel.Verdict
            if (side.order ?? -1) < level {
                verdict = .unconstrained
            } else {
                verdict = isWithin ? .within : .beyond
            }
            let mark: String
            switch verdict {
            case .within: mark = "✓"
            case .unconstrained: mark = "⚠"
            case .beyond: mark = "⊘"
            }
            return ViewportAnalysisLabel(anchor: anchor, text: "G\(checked) \(mark) \(value)", verdict: verdict)
        }
    }
}
