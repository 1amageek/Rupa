import Foundation
import SwiftCAD
import RupaCoreTypes

/// The two ends a Bridge joins, read from the selection.
public struct BridgeSelectionEndpoints: Equatable, Sendable {
    public var featureID: FeatureID
    public var first: BridgeCurveEndpoint
    public var second: BridgeCurveEndpoint
}

extension DesignDocument {
    /// Bridge's two ends for two selected targets of one sketch, in selection order. Two curves
    /// (lines, arcs, open splines) are joined at the pair of their ends nearest each other, as
    /// Bridge Curve does; two curve-end vertices are joined where they are, as Bridge Vertex does.
    /// Any other selection is refused.
    public func bridgeEndpoints(for targets: [SelectionTarget]) throws -> BridgeSelectionEndpoints {
        guard targets.count == 2 else {
            throw EditorError(code: .commandInvalid, message: "Bridge joins two curves or two curve ends.")
        }
        let resolved = try targets.map { try bridgeEndCandidates(for: $0) }
        guard resolved[0].featureID == resolved[1].featureID else {
            throw EditorError(code: .commandInvalid, message: "Bridge joins curves of one sketch.")
        }
        guard case .sketch(let sketch) = cadDocument.designGraph.nodes[resolved[0].featureID]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "Bridge needs the curves' sketch.")
        }
        let resolver = SketchCurveEndpointResolver()
        func point(_ reference: SketchReference) throws -> Point2D {
            guard let sample = try resolver.sample(for: reference, sketch: sketch, document: self) else {
                throw EditorError(code: .referenceUnresolved, message: "Bridge could not find a curve end.")
            }
            return sample.sample.point
        }
        var best: (SketchReference, SketchReference, Double)?
        for first in resolved[0].ends {
            for second in resolved[1].ends where first != second {
                let a = try point(first), b = try point(second)
                let distance = hypot(a.x - b.x, a.y - b.y)
                if best == nil || distance < best!.2 { best = (first, second, distance) }
            }
        }
        guard let best else {
            throw EditorError(code: .commandInvalid, message: "Bridge needs two distinct curve ends.")
        }
        return BridgeSelectionEndpoints(
            featureID: resolved[0].featureID,
            first: BridgeCurveEndpoint(reference: best.0),
            second: BridgeCurveEndpoint(reference: best.1)
        )
    }

    /// The ends a selected target offers: both ends of a curve, or the one end a vertex names.
    private func bridgeEndCandidates(for target: SelectionTarget) throws -> (featureID: FeatureID, ends: [SketchReference]) {
        guard case .sketchEntity(let component) = target.component else {
            throw EditorError(code: .commandInvalid, message: "Bridge joins sketch curves or their ends.")
        }
        if let vertex = component.sketchPointReference {
            guard case .sketch(let sketch) = cadDocument.designGraph.nodes[vertex.featureID]?.operation else {
                throw EditorError(code: .referenceUnresolved, message: "Bridge needs the vertex's sketch.")
            }
            guard isBridgeableEnd(vertex.reference, in: sketch) else {
                throw EditorError(code: .commandInvalid, message: "Bridge joins the end of a line, arc or open spline.")
            }
            return (vertex.featureID, [vertex.reference])
        }
        let curve = try editableSketchEntity(for: target, operationName: "Bridge")
        switch curve.entity {
        case .line:
            return (curve.featureID, [.lineStart(curve.entityID), .lineEnd(curve.entityID)])
        case .arc:
            return (curve.featureID, [.arcStart(curve.entityID), .arcEnd(curve.entityID)])
        case .spline(let spline) where !spline.isClosed:
            return (curve.featureID, [
                .splineControlPoint(entity: curve.entityID, index: 0),
                .splineControlPoint(entity: curve.entityID, index: spline.controlPoints.count - 1),
            ])
        default:
            throw EditorError(code: .commandInvalid, message: "Bridge joins lines, arcs and open splines.")
        }
    }

    private func isBridgeableEnd(_ reference: SketchReference, in sketch: Sketch) -> Bool {
        switch reference {
        case .lineStart, .lineEnd, .arcStart, .arcEnd:
            return true
        case let .splineControlPoint(entityID, index):
            guard case .spline(let spline) = sketch.entities[entityID], !spline.isClosed else { return false }
            return index == 0 || index == spline.controlPoints.count - 1
        default:
            return false
        }
    }
}
