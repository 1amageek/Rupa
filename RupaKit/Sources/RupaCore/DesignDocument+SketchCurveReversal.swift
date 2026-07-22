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
            spline.controlPoints = Array(spline.controlPoints.reversed())
            try validateSpline(spline, owner: "Sketch curve reverse")
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
            case .splineEndpointTangent(let tangency):
                guard tangency.splineEndpoint.splineID == entityID else {
                    return constraint
                }
                return .splineEndpointTangent(SketchSplineLineTangencyConstraint(
                    splineEndpoint: SketchSplineEndpointReference(
                        splineID: tangency.splineEndpoint.splineID,
                        endpoint: reversedSplineEndpoint(tangency.splineEndpoint.endpoint)
                    ),
                    line: tangency.line,
                    orientation: reversedTangentOrientation(tangency.orientation)
                ))
            case .tangentSplineEndpoints(let tangency):
                return .tangentSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: rewriteSplineEndpointReferenceAfterCurveReverse(
                        tangency.first,
                        entityID: entityID
                    ),
                    second: rewriteSplineEndpointReferenceAfterCurveReverse(
                        tangency.second,
                        entityID: entityID
                    ),
                    orientation: reversedPairTangentOrientation(tangency, entityID: entityID)
                ))
            case .smoothSplineEndpoints(let tangency):
                return .smoothSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: rewriteSplineEndpointReferenceAfterCurveReverse(
                        tangency.first,
                        entityID: entityID
                    ),
                    second: rewriteSplineEndpointReferenceAfterCurveReverse(
                        tangency.second,
                        entityID: entityID
                    ),
                    orientation: reversedPairTangentOrientation(tangency, entityID: entityID)
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

    private func reversedPairTangentOrientation(
        _ tangency: SketchSplineEndpointTangencyConstraint,
        entityID: SketchEntityID
    ) -> SketchTangentOrientation {
        let reversedCount = [tangency.first, tangency.second]
            .filter { $0.splineID == entityID }
            .count
        return reversedCount == 1
            ? reversedTangentOrientation(tangency.orientation)
            : tangency.orientation
    }

    private func reversedTangentOrientation(
        _ orientation: SketchTangentOrientation
    ) -> SketchTangentOrientation {
        orientation == .aligned ? .opposed : .aligned
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

    private func bridgeCurveSourcesAfterSketchCurveReverse(
        _ sources: [BridgeCurveSourceID: BridgeCurveSource],
        featureID: FeatureID,
        entityID: SketchEntityID,
        splineControlPointCount: Int?
    ) -> [BridgeCurveSourceID: BridgeCurveSource] {
        sources.mapValues { source in
            let firstEndpoint = BridgeCurveEndpoint(
                reference: rewriteSketchReferenceAfterCurveReverse(
                    source.firstEndpoint.reference,
                    entityID: entityID,
                    splineControlPointCount: splineControlPointCount
                ),
                parameter: rewriteBridgeEndpointParameterAfterCurveReverse(
                    source.firstEndpoint,
                    entityID: entityID
                ),
                reversesSense: rewriteBridgeEndpointSenseAfterCurveReverse(
                    source.firstEndpoint,
                    entityID: entityID
                ),
                trimSide: rewriteBridgeEndpointTrimSideAfterCurveReverse(
                    source.firstEndpoint,
                    entityID: entityID
                ),
                tension: source.firstEndpoint.tension
            )
            let secondEndpoint = BridgeCurveEndpoint(
                reference: rewriteSketchReferenceAfterCurveReverse(
                    source.secondEndpoint.reference,
                    entityID: entityID,
                    splineControlPointCount: splineControlPointCount
                ),
                parameter: rewriteBridgeEndpointParameterAfterCurveReverse(
                    source.secondEndpoint,
                    entityID: entityID
                ),
                reversesSense: rewriteBridgeEndpointSenseAfterCurveReverse(
                    source.secondEndpoint,
                    entityID: entityID
                ),
                trimSide: rewriteBridgeEndpointTrimSideAfterCurveReverse(
                    source.secondEndpoint,
                    entityID: entityID
                ),
                tension: source.secondEndpoint.tension
            )
            if source.featureID == featureID && source.entityID == entityID {
                return BridgeCurveSource(
                    id: source.id,
                    featureID: source.featureID,
                    entityID: source.entityID,
                    firstEndpoint: secondEndpoint,
                    secondEndpoint: firstEndpoint,
                    continuity: source.continuity,
                    trimsSourceCurves: source.trimsSourceCurves
                )
            }
            return BridgeCurveSource(
                id: source.id,
                featureID: source.featureID,
                entityID: source.entityID,
                firstEndpoint: firstEndpoint,
                secondEndpoint: secondEndpoint,
                continuity: source.continuity,
                trimsSourceCurves: source.trimsSourceCurves
            )
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
