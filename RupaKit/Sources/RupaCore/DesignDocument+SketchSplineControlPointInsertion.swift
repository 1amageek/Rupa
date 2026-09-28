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
        guard resolvedFraction.isFinite, resolvedFraction > 0,
              resolvedFraction < 1 else {
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
        try validateSplineForm(spline, owner: owner)
        let degree = spline.degree
        if let sourceKnots = spline.knots {
            let lower = sourceKnots[degree]
            let upper = sourceKnots[sourceKnots.count - degree - 1]
            let parameter = lower + fraction * (upper - lower)
            guard let span = sourceKnots.lastIndex(where: { $0 <= parameter }),
                  span < sourceKnots.count - degree - 1,
                  !sourceKnots.contains(parameter) else {
                throw EditorError(code: .commandInvalid, message: "\(owner) needs a point inside a knot span.")
            }
            let updated: SketchSpline
            do {
                updated = try SketchSplineRefinement().insertingKnot(in: spline, at: parameter, multiplicity: degree)
            } catch let error as SketchError {
                throw EditorError(code: .commandInvalid, message: "\(owner): \(error)")
            }
            try validateSplineForm(updated, owner: owner)
            return SketchSplineControlPointInsertion(
                spline: updated, originalControlPointCount: spline.controlPoints.count,
                segmentStartIndex: span - degree, segmentEndIndex: span,
                insertedControlPointIndex: span
            )
        }

        let count = try requireSplineSpanCount(spline, owner: owner)
        let scaled = fraction * Double(count)
        let span = Int(floor(scaled))
        let local = scaled - Double(span)
        guard local > 0, local < 1 else {
            throw EditorError(code: .commandInvalid, message: "\(owner) needs a point inside a Bezier span.")
        }
        let start = span * degree
        var row = Array(spline.controlPoints[start...(start + degree)])
        var left = [row[0]]
        var right = [row[degree]]
        while row.count > 1 {
            row = zip(row, row.dropFirst()).map { interpolatedSketchPoint($0, $1, fraction: .scalar(local)) }
            left.append(row[0])
            right.append(row[row.count - 1])
        }
        let next = Array(spline.controlPoints.prefix(start)) + left + right.dropLast().reversed()
            + spline.controlPoints.dropFirst(start + degree + 1)
        let updated = SketchSpline(controlPoints: next, isClosed: spline.isClosed, degree: degree)
        try validateSplineForm(updated, owner: owner)
        return SketchSplineControlPointInsertion(
            spline: updated, originalControlPointCount: spline.controlPoints.count,
            segmentStartIndex: start, segmentEndIndex: start + degree,
            insertedControlPointIndex: start + degree
        )
    }

    private func requireSplineSpanCount(_ spline: SketchSpline, owner: String) throws -> Int {
        guard let count = spline.spanCount else {
            throw EditorError(code: .commandInvalid, message: "\(owner) has an invalid Bezier chain.")
        }
        return count
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
            case .smoothSplineEndpoints(let endpointPair):
                guard splineEndpointHandleIsShortenedByInsertion(
                    endpointPair.first,
                    entityID: entityID,
                    insertion: insertion
                ) == false,
                    splineEndpointHandleIsShortenedByInsertion(
                        endpointPair.second,
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
                 .concentric(let first, let second),
                 .equalRadius(let first, let second):
                guard first != entityID && second != entityID else {
                    throw sketchSplineControlPointInsertionUnsupportedReference(
                        "whole-spline relationship constraints"
                    )
                }
                return constraint
            case .tangent(let tangency):
                let references: Bool
                switch tangency {
                case .lineCircular(let line, let circular, _):
                    references = line == entityID || circular == entityID
                case .circularCircular(let first, let second, _):
                    references = first == entityID || second == entityID
                }
                guard references == false else {
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
        if index > insertion.segmentStartIndex && index < insertion.segmentEndIndex {
            throw sketchSplineControlPointInsertionUnsupportedReference(
                "references to replaced spline handles"
            )
        }
        if index >= insertion.segmentEndIndex {
            return index + insertion.spline.controlPoints.count - insertion.originalControlPointCount
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
