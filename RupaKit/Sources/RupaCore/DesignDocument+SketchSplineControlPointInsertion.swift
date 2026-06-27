import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func insertSketchSplineControlPoint(
        target: SelectionTarget,
        fraction: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> Int {
        let resolvedFraction = try resolvedScalarValue(
            fraction,
            owner: "Sketch spline control point insertion fraction"
        )
        guard resolvedFraction > ModelingTolerance.standard.distance,
              resolvedFraction < 1.0 - ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point insertion fraction must be greater than zero and less than one."
            )
        }

        let selection = try editableSketchEntity(
            for: target,
            operationName: "Sketch spline control point insertion"
        )
        guard case .spline(let spline) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point insertion requires a spline entity."
            )
        }
        guard spline.isClosed == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point insertion requires an open spline curve."
            )
        }
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point insertion cannot edit a generated Bridge Curve source."
            )
        }

        let insertion = try insertedSplineControlPoint(
            in: spline,
            fraction: resolvedFraction,
            owner: "Sketch spline control point insertion"
        )
        let constraints = try constraintsAfterSketchSplineControlPointInsertion(
            selection.sketch.constraints,
            entityID: selection.entityID,
            insertion: insertion
        )
        let dimensions = try dimensionsAfterSketchSplineControlPointInsertion(
            selection.sketch.dimensions,
            entityID: selection.entityID,
            insertion: insertion
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .spline(insertion.spline)
        sketch.constraints = constraints
        sketch.dimensions = dimensions

        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch spline control point insertion"
        )
        return insertion.insertedControlPointIndex
    }

    private struct SketchSplineControlPointInsertion {
        var spline: SketchSpline
        var originalControlPointCount: Int
        var segmentStartIndex: Int
        var segmentEndIndex: Int
        var insertedControlPointIndex: Int
    }

    private func insertedSplineControlPoint(
        in spline: SketchSpline,
        fraction: Double,
        owner: String
    ) throws -> SketchSplineControlPointInsertion {
        let controlPoints = spline.controlPoints
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }
        let segmentCount = (controlPoints.count - 1) / 3
        let scaledParameter = fraction * Double(segmentCount)
        let segmentIndex = Int(floor(scaledParameter))
        let localFraction = scaledParameter - Double(segmentIndex)
        let tolerance = 1.0e-9
        guard localFraction > tolerance,
              localFraction < 1.0 - tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) fraction must resolve inside a cubic spline span, not on an existing knot."
            )
        }

        let segmentStart = segmentIndex * 3
        let p0 = controlPoints[segmentStart]
        let p1 = controlPoints[segmentStart + 1]
        let p2 = controlPoints[segmentStart + 2]
        let p3 = controlPoints[segmentStart + 3]
        let split = splitCubicBezier(
            p0,
            p1,
            p2,
            p3,
            fraction: .scalar(localFraction)
        )

        var next = Array(controlPoints[0 ... segmentStart])
        next.append(contentsOf: [
            split.left.1,
            split.left.2,
            split.left.3,
            split.right.1,
            split.right.2,
            split.right.3,
        ])
        if segmentStart + 4 < controlPoints.count {
            next.append(contentsOf: controlPoints[(segmentStart + 4)...])
        }

        let updatedSpline = SketchSpline(
            controlPoints: next,
            isClosed: spline.isClosed
        )
        try validateSpline(updatedSpline, owner: owner)
        return SketchSplineControlPointInsertion(
            spline: updatedSpline,
            originalControlPointCount: controlPoints.count,
            segmentStartIndex: segmentStart,
            segmentEndIndex: segmentStart + 3,
            insertedControlPointIndex: segmentStart + 3
        )
    }

    private func constraintsAfterSketchSplineControlPointInsertion(
        _ constraints: [SketchConstraint],
        entityID: SketchEntityID,
        insertion: SketchSplineControlPointInsertion
    ) throws -> [SketchConstraint] {
        try constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        first,
                        entityID: entityID,
                        insertion: insertion
                    ),
                    try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        second,
                        entityID: entityID,
                        insertion: insertion
                    )
                )
            case .fixed(let reference):
                return .fixed(
                    try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        reference,
                        entityID: entityID,
                        insertion: insertion
                    )
                )
            case .smoothSplineControlPoint(let id, let index):
                guard id == entityID else {
                    return constraint
                }
                return .smoothSplineControlPoint(
                    entity: id,
                    index: try rewriteSmoothSplineControlPointIndexAfterInsertion(
                        index,
                        insertion: insertion
                    )
                )
            case .splineEndpointTangent:
                return constraint
            case .tangentSplineEndpoints:
                return constraint
            case .smoothSplineEndpoints(let first, let second):
                guard splineEndpointHandleIsShortenedByInsertion(
                    first,
                    entityID: entityID,
                    insertion: insertion
                ) == false,
                    splineEndpointHandleIsShortenedByInsertion(
                        second,
                        entityID: entityID,
                        insertion: insertion
                    ) == false else {
                    throw sketchSplineControlPointInsertionUnsupportedReference(
                        "smooth spline endpoint constraints"
                    )
                }
                return constraint
            case .horizontal(let id),
                 .vertical(let id):
                guard id != entityID else {
                    throw sketchSplineControlPointInsertionUnsupportedReference(
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
                    throw sketchSplineControlPointInsertionUnsupportedReference(
                        "whole-spline relationship constraints"
                    )
                }
                return constraint
            }
        }
    }

    private func dimensionsAfterSketchSplineControlPointInsertion(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID,
        insertion: SketchSplineControlPointInsertion
    ) throws -> [SketchDimension] {
        try dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        from,
                        entityID: entityID,
                        insertion: insertion
                    ),
                    to: try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        to,
                        entityID: entityID,
                        insertion: insertion
                    ),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        from,
                        entityID: entityID,
                        insertion: insertion
                    ),
                    to: try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        to,
                        entityID: entityID,
                        insertion: insertion
                    ),
                    value: value
                )
            case .radius(let id, _),
                 .diameter(let id, _):
                guard id != entityID else {
                    throw sketchSplineControlPointInsertionUnsupportedReference(
                        "circular dimensions"
                    )
                }
                return dimension
            }
        }
    }

    private func rewriteSketchReferenceAfterSplineControlPointInsertion(
        _ reference: SketchReference,
        entityID: SketchEntityID,
        insertion: SketchSplineControlPointInsertion
    ) throws -> SketchReference {
        switch reference {
        case .splineControlPoint(let id, let index) where id == entityID:
            return .splineControlPoint(
                entity: id,
                index: try rewriteSplineControlPointIndexAfterInsertion(
                    index,
                    insertion: insertion
                )
            )
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
                throw sketchSplineControlPointInsertionUnsupportedReference(
                    "incompatible point references"
                )
            }
            return reference
        }
    }

    private func rewriteSplineControlPointIndexAfterInsertion(
        _ index: Int,
        insertion: SketchSplineControlPointInsertion
    ) throws -> Int {
        if index == insertion.segmentStartIndex + 1 ||
            index == insertion.segmentStartIndex + 2 {
            throw sketchSplineControlPointInsertionUnsupportedReference(
                "references to replaced spline handles"
            )
        }
        if index >= insertion.segmentEndIndex {
            return index + 3
        }
        return index
    }

    private func rewriteSmoothSplineControlPointIndexAfterInsertion(
        _ index: Int,
        insertion: SketchSplineControlPointInsertion
    ) throws -> Int {
        if index == insertion.segmentStartIndex ||
            index == insertion.segmentEndIndex {
            throw sketchSplineControlPointInsertionUnsupportedReference(
                "smooth constraints on the insertion span boundary"
            )
        }
        return try rewriteSplineControlPointIndexAfterInsertion(
            index,
            insertion: insertion
        )
    }

    private func splineEndpointHandleIsShortenedByInsertion(
        _ reference: SketchSplineEndpointReference,
        entityID: SketchEntityID,
        insertion: SketchSplineControlPointInsertion
    ) -> Bool {
        guard reference.splineID == entityID else {
            return false
        }
        switch reference.endpoint {
        case .start:
            return insertion.segmentStartIndex == 0
        case .end:
            return insertion.segmentEndIndex == insertion.originalControlPointCount - 1
        }
    }

    private func sketchSplineControlPointInsertionUnsupportedReference(
        _ reason: String
    ) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Sketch spline control point insertion cannot preserve \(reason) yet."
        )
    }
}
