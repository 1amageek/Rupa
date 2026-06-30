import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func constraintsAfterSketchCurveRebuild(
        _ constraints: [SketchConstraint],
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> [SketchConstraint] {
        try constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    try rewriteSketchReferenceAfterCurveRebuild(
                        first,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    try rewriteSketchReferenceAfterCurveRebuild(
                        second,
                        entityID: entityID,
                        rebuilt: rebuilt
                    )
                )
            case .fixed(let reference):
                return .fixed(
                    try rewriteSketchReferenceAfterCurveRebuild(
                        reference,
                        entityID: entityID,
                        rebuilt: rebuilt
                    )
                )
            case .smoothSplineControlPoint(let id, let index):
                guard id == entityID else {
                    return constraint
                }
                if let rebuiltIndex = rebuilt.controlPointIndexMap[index] {
                    return .smoothSplineControlPoint(entity: id, index: rebuiltIndex)
                }
                guard rebuilt.changesControlPointCount == false else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "internal smooth spline constraints when the point count changes"
                    )
                }
                return .smoothSplineControlPoint(entity: id, index: index)
            case .splineEndpointTangent:
                return constraint
            case .tangentSplineEndpoints:
                return constraint
            case .smoothSplineEndpoints(let first, let second):
                guard rebuilt.changesControlPointCount == false ||
                    (first.splineID != entityID && second.splineID != entityID) else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "smooth spline endpoint constraints when the point count changes"
                    )
                }
                return constraint
            case .horizontal(let id),
                 .vertical(let id):
                guard id != entityID else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "whole-spline orientation constraints"
                    )
                }
                return constraint
            case .parallel(let first, let second),
                 .perpendicular(let first, let second),
                 .equalLength(let first, let second),
                 .tangent(let first, let second),
                 .concentric(let first, let second),
                 .equalRadius(let first, let second):
                guard first != entityID && second != entityID else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "whole-spline relationship constraints"
                    )
                }
                return constraint
            }
        }
    }

    func dimensionsAfterSketchCurveRebuild(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> [SketchDimension] {
        try dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: try rewriteSketchReferenceAfterCurveRebuild(
                        from,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    to: try rewriteSketchReferenceAfterCurveRebuild(
                        to,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: try rewriteSketchReferenceAfterCurveRebuild(
                        from,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    to: try rewriteSketchReferenceAfterCurveRebuild(
                        to,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    value: value
                )
            case .radius(let id, _),
                 .diameter(let id, _):
                guard id != entityID else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "circular dimensions"
                    )
                }
                return dimension
            }
        }
    }

    func bridgeCurveSourcesAfterSketchCurveRebuild(
        _ sources: [BridgeCurveSourceID: BridgeCurveSource],
        featureID: FeatureID,
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> [BridgeCurveSourceID: BridgeCurveSource] {
        var updated: [BridgeCurveSourceID: BridgeCurveSource] = [:]
        updated.reserveCapacity(sources.count)
        for (id, source) in sources {
            guard source.featureID != featureID || source.entityID != entityID else {
                throw sketchCurveRebuildUnsupportedReference(
                    "generated Bridge Curve source entities"
                )
            }
            updated[id] = BridgeCurveSource(
                id: source.id,
                featureID: source.featureID,
                entityID: source.entityID,
                firstEndpoint: BridgeCurveEndpoint(
                    reference: try rewriteSketchReferenceAfterCurveRebuild(
                        source.firstEndpoint.reference,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    parameter: source.firstEndpoint.parameter,
                    reversesSense: source.firstEndpoint.reversesSense,
                    trimSide: source.firstEndpoint.trimSide,
                    tension: source.firstEndpoint.tension
                ),
                secondEndpoint: BridgeCurveEndpoint(
                    reference: try rewriteSketchReferenceAfterCurveRebuild(
                        source.secondEndpoint.reference,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    parameter: source.secondEndpoint.parameter,
                    reversesSense: source.secondEndpoint.reversesSense,
                    trimSide: source.secondEndpoint.trimSide,
                    tension: source.secondEndpoint.tension
                ),
                continuity: source.continuity,
                trimsSourceCurves: source.trimsSourceCurves
            )
        }
        return updated
    }

    private func rewriteSketchReferenceAfterCurveRebuild(
        _ reference: SketchReference,
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> SketchReference {
        switch reference {
        case .splineControlPoint(let id, let index) where id == entityID:
            guard index >= 0,
                  index < rebuilt.originalControlPointCount else {
                throw sketchCurveRebuildUnsupportedReference(
                    "out-of-range spline control-point references"
                )
            }
            if let rebuiltIndex = rebuilt.controlPointIndexMap[index] {
                return .splineControlPoint(
                    entity: entityID,
                    index: rebuiltIndex
                )
            }
            guard rebuilt.changesControlPointCount == false else {
                throw sketchCurveRebuildUnsupportedReference(
                    "internal spline control-point references when the point count changes"
                )
            }
            return reference
        case .splineControlPoint:
            return reference
        case .lineStart(let id),
             .lineEnd(let id),
             .entity(let id),
             .circleCenter(let id),
             .circleRadius(let id),
             .arcCenter(let id),
             .arcStart(let id),
             .arcEnd(let id),
             .arcRadius(let id):
            guard id != entityID else {
                throw sketchCurveRebuildUnsupportedReference(
                    "incompatible point references"
                )
            }
            return reference
        }
    }

    private func sketchCurveRebuildUnsupportedReference(
        _ reason: String
    ) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Sketch curve rebuild cannot preserve \(reason) yet."
        )
    }

}
