import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func reverseSketchCurve(
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let selection = try editableSketchEntity(for: target, operationName: "Sketch curve reverse")
        let reversedEntity: SketchEntity
        let splineControlPointCount: Int?
        switch selection.entity {
        case .line(let line):
            let reversedLine = SketchLine(start: line.end, end: line.start)
            _ = try resolvedLineMetrics(reversedLine, owner: "Sketch curve reverse")
            reversedEntity = .line(reversedLine)
            splineControlPointCount = nil
        case .spline(var spline):
            // The reversed curve runs over the mirrored knots: u becomes a + b − u on [a, b].
            spline.controlPoints = Array(spline.controlPoints.reversed())
            if let knots = spline.knots, let lower = knots.first, let upper = knots.last {
                spline.knots = knots.reversed().map { lower + upper - $0 }
            }
            try validateSplineForm(spline, owner: "Sketch curve reverse")
            reversedEntity = .spline(spline)
            splineControlPointCount = spline.controlPoints.count
        case .arc:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve reverse cannot reverse arc direction until arc source direction is represented."
            )
        case .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve reverse requires an open line or spline curve; circles do not expose direction."
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve reverse requires a line or spline curve target."
            )
        }

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = reversedEntity
        sketch.constraints = constraintsAfterSketchCurveReverse(
            sketch.constraints,
            entityID: selection.entityID,
            splineControlPointCount: splineControlPointCount
        )
        sketch.dimensions = dimensionsAfterSketchCurveReverse(
            sketch.dimensions,
            entityID: selection.entityID,
            splineControlPointCount: splineControlPointCount
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitReverse = false
        defer {
            if didCommitReverse == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        productMetadata.bridgeCurveSources = bridgeCurveSourcesAfterSketchCurveReverse(
            productMetadata.bridgeCurveSources,
            featureID: selection.featureID,
            entityID: selection.entityID,
            splineControlPointCount: splineControlPointCount
        )
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch curve reverse"
        )
        didCommitReverse = true
    }

    private func constraintsAfterSketchCurveReverse(
        _ constraints: [SketchConstraint],
        entityID: SketchEntityID,
        splineControlPointCount: Int?
    ) -> [SketchConstraint] {
        constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    rewriteSketchReferenceAfterCurveReverse(
                        first,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    rewriteSketchReferenceAfterCurveReverse(
                        second,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    )
                )
            case .fixed(let reference):
                return .fixed(
                    rewriteSketchReferenceAfterCurveReverse(
                        reference,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    )
                )
            case .smoothSplineControlPoint(let id, let index):
                guard id == entityID,
                      let count = splineControlPointCount else {
                    return constraint
                }
                return .smoothSplineControlPoint(
                    entity: entityID,
                    index: reversedSplineControlPointIndex(index, controlPointCount: count)
                )
            case .splineEndpointTangent(let lineTangency):
                guard lineTangency.splineEndpoint.splineID == entityID else {
                    return constraint
                }
                return .splineEndpointTangent(SketchSplineLineTangencyConstraint(
                    splineEndpoint: SketchSplineEndpointReference(
                        splineID: lineTangency.splineEndpoint.splineID,
                        endpoint: reversedSplineEndpoint(lineTangency.splineEndpoint.endpoint)
                    ),
                    line: lineTangency.line,
                    orientation: lineTangency.orientation
                ))
            case .tangentSplineEndpoints(let pair):
                return .tangentSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: rewriteSplineEndpointReferenceAfterCurveReverse(
                        pair.first,
                        entityID: entityID
                    ),
                    second: rewriteSplineEndpointReferenceAfterCurveReverse(
                        pair.second,
                        entityID: entityID
                    ),
                    orientation: pair.orientation
                ))
            case .smoothSplineEndpoints(let pair):
                return .smoothSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: rewriteSplineEndpointReferenceAfterCurveReverse(
                        pair.first,
                        entityID: entityID
                    ),
                    second: rewriteSplineEndpointReferenceAfterCurveReverse(
                        pair.second,
                        entityID: entityID
                    ),
                    orientation: pair.orientation
                ))
            case .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius:
                return constraint
            }
        }
    }

    private func dimensionsAfterSketchCurveReverse(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID,
        splineControlPointCount: Int?
    ) -> [SketchDimension] {
        dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: rewriteSketchReferenceAfterCurveReverse(
                        from,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    to: rewriteSketchReferenceAfterCurveReverse(
                        to,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: rewriteSketchReferenceAfterCurveReverse(
                        from,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    to: rewriteSketchReferenceAfterCurveReverse(
                        to,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    value: value
                )
            case .radius, .diameter:
                return dimension
            }
        }
    }

    /// Bridge sources after `entityID` is reversed: ends on it follow the reversed parameter
    /// and sense, including the untrimmed ends a trim record keeps. A reversed bridge runs from
    /// its second end to its first, so its ends, their continuities and its trim record's ends
    /// swap and the regenerated bridge is the same curve traversed backwards.
    private func bridgeCurveSourcesAfterSketchCurveReverse(
        _ sources: [BridgeCurveSourceID: BridgeCurveSource],
        featureID: FeatureID,
        entityID: SketchEntityID,
        splineControlPointCount: Int?
    ) -> [BridgeCurveSourceID: BridgeCurveSource] {
        func rewritten(_ endpoint: BridgeCurveEndpoint) -> BridgeCurveEndpoint {
            BridgeCurveEndpoint(
                reference: rewriteSketchReferenceAfterCurveReverse(
                    endpoint.reference,
                    entityID: entityID,
                    splineControlPointCount: splineControlPointCount
                ),
                parameter: rewriteBridgeEndpointParameterAfterCurveReverse(endpoint, entityID: entityID),
                reversesSense: rewriteBridgeEndpointSenseAfterCurveReverse(endpoint, entityID: entityID),
                trimSide: rewriteBridgeEndpointTrimSideAfterCurveReverse(endpoint, entityID: entityID),
                tension: endpoint.tension
            )
        }
        return sources.mapValues { source in
            var next = source
            next.firstEndpoint = rewritten(source.firstEndpoint)
            next.secondEndpoint = rewritten(source.secondEndpoint)
            if var record = source.trimRecord {
                record.untrimmedFirstEndpoint = rewritten(record.untrimmedFirstEndpoint)
                record.untrimmedSecondEndpoint = rewritten(record.untrimmedSecondEndpoint)
                next.trimRecord = record
            }
            guard source.featureID == featureID, source.entityID == entityID else {
                return next
            }
            swap(&next.firstEndpoint, &next.secondEndpoint)
            next.continuity = BridgeCurveContinuity(first: source.continuity.second, second: source.continuity.first)
            if var record = next.trimRecord {
                swap(&record.untrimmedFirstEndpoint, &record.untrimmedSecondEndpoint)
                next.trimRecord = record
            }
            return next
        }
    }

    private func rewriteSketchReferenceAfterCurveReverse(
        _ reference: SketchReference,
        entityID: SketchEntityID,
        splineControlPointCount: Int?
    ) -> SketchReference {
        switch reference {
        case .lineStart(let id) where id == entityID:
            return .lineEnd(entityID)
        case .lineEnd(let id) where id == entityID:
            return .lineStart(entityID)
        case .splineControlPoint(let id, let index) where id == entityID:
            guard let count = splineControlPointCount else {
                return reference
            }
            return .splineControlPoint(
                entity: entityID,
                index: reversedSplineControlPointIndex(index, controlPointCount: count)
            )
        default:
            return reference
        }
    }

    private func rewriteBridgeEndpointParameterAfterCurveReverse(
        _ endpoint: BridgeCurveEndpoint,
        entityID: SketchEntityID
    ) -> CADExpression? {
        guard let parameter = endpoint.parameter,
              bridgeEndpointReferencesEntity(endpoint.reference, entityID: entityID) else {
            return endpoint.parameter
        }
        return .subtract(.scalar(1.0), parameter)
    }

    private func rewriteBridgeEndpointSenseAfterCurveReverse(
        _ endpoint: BridgeCurveEndpoint,
        entityID: SketchEntityID
    ) -> Bool {
        guard endpoint.parameter != nil,
              bridgeEndpointReferencesEntity(endpoint.reference, entityID: entityID) else {
            return endpoint.reversesSense
        }
        return !endpoint.reversesSense
    }

    private func rewriteBridgeEndpointTrimSideAfterCurveReverse(
        _ endpoint: BridgeCurveEndpoint,
        entityID: SketchEntityID
    ) -> BridgeCurveTrimSide {
        guard bridgeEndpointReferencesEntity(endpoint.reference, entityID: entityID) else {
            return endpoint.trimSide
        }
        return endpoint.trimSide.reversed
    }

    private func rewriteSplineEndpointReferenceAfterCurveReverse(
        _ reference: SketchSplineEndpointReference,
        entityID: SketchEntityID
    ) -> SketchSplineEndpointReference {
        guard reference.splineID == entityID else {
            return reference
        }
        return SketchSplineEndpointReference(
            splineID: reference.splineID,
            endpoint: reversedSplineEndpoint(reference.endpoint)
        )
    }

    private func reversedSplineEndpoint(_ endpoint: SketchSplineEndpoint) -> SketchSplineEndpoint {
        switch endpoint {
        case .start:
            return .end
        case .end:
            return .start
        }
    }

    private func reversedSplineControlPointIndex(
        _ index: Int,
        controlPointCount: Int
    ) -> Int {
        controlPointCount - 1 - index
    }
}
