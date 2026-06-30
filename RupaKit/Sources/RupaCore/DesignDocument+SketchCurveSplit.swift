import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func splitSketchCurve(
        target: SelectionTarget,
        fraction: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchEntityID {
        let resolvedFraction = try resolvedScalarValue(fraction, owner: "Sketch curve split fraction")
        guard resolvedFraction > ModelingTolerance.standard.distance,
              resolvedFraction < 1.0 - ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve split fraction must be greater than zero and less than one."
            )
        }
        let selection = try editableSketchEntity(for: target, operationName: "Sketch curve split")
        try validateSketchCurveCanSplit(selection: selection)

        let newEntityID = SketchEntityID()
        let split = try splitSketchCurveEntity(
            selection.entity,
            entityID: selection.entityID,
            newEntityID: newEntityID,
            fraction: resolvedFraction,
            owner: "Sketch curve split"
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = split.retainedEntity
        sketch.entities[newEntityID] = split.newEntity
        sketch.constraints = constraintsAfterSketchCurveSplit(
            sketch.constraints,
            split: split
        )
        sketch.dimensions = dimensionsAfterSketchCurveSplit(
            sketch.dimensions,
            split: split
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitSplit = false
        defer {
            if didCommitSplit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        if selection.sketch.entities.count == 1 {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        productMetadata.bridgeCurveSources = try bridgeCurveSourcesAfterSketchCurveSplit(
            productMetadata.bridgeCurveSources,
            split: split
        )
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch curve split"
        )
        didCommitSplit = true
        return newEntityID
    }

    private func validateSketchCurveCanSplit(
        selection: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            feature: FeatureNode,
            sketch: Sketch,
            entity: SketchEntity
        )
    ) throws {
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve split cannot split a generated Bridge Curve source."
            )
        }

        switch selection.entity {
        case .line:
            break
        case .spline(let spline):
            guard spline.isClosed == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve split requires an open spline curve."
                )
            }
        case .arc:
            break
        case .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve split requires an open line, arc, or spline curve; circles do not expose a split segment."
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve split requires a line, arc, or spline curve target."
            )
        }

        for constraint in selection.sketch.constraints {
            try validateConstraintCanSplitSketchCurve(
                constraint,
                entityID: selection.entityID,
                entity: selection.entity
            )
        }
        for dimension in selection.sketch.dimensions {
            try validateDimensionCanSplitSketchCurve(
                dimension,
                entityID: selection.entityID,
                entity: selection.entity
            )
        }
    }

    private func validateConstraintCanSplitSketchCurve(
        _ constraint: SketchConstraint,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) throws {
        switch constraint {
        case .coincident(let first, let second):
            try validateSketchReferenceCanSplit(first, entityID: entityID, entity: entity)
            try validateSketchReferenceCanSplit(second, entityID: entityID, entity: entity)
        case .fixed(let reference):
            try validateSketchReferenceCanSplit(reference, entityID: entityID, entity: entity)
        case .horizontal(let id),
             .vertical(let id):
            if id == entityID, case .spline = entity {
                throw sketchCurveSplitUnsupportedConstraint("spline orientation constraints")
            }
        case .parallel(let first, let second),
             .perpendicular(let first, let second):
            if first == entityID || second == entityID,
               case .spline = entity {
                throw sketchCurveSplitUnsupportedConstraint("spline line relationship constraints")
            }
        case .equalLength(let first, let second):
            if first == entityID || second == entityID {
                throw sketchCurveSplitUnsupportedConstraint("equal-length constraints")
            }
        case .tangent(let first, let second):
            if first == entityID || second == entityID {
                throw sketchCurveSplitUnsupportedConstraint("curve tangent constraints")
            }
        case .concentric(let first, let second),
             .equalRadius(let first, let second):
            if first == entityID || second == entityID {
                throw sketchCurveSplitUnsupportedConstraint("circular constraints")
            }
        case .smoothSplineControlPoint(let id, _):
            if id == entityID {
                throw sketchCurveSplitUnsupportedConstraint("internal spline smooth constraints")
            }
        case .splineEndpointTangent:
            return
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            try validateSplineEndpointReferenceCanSplit(first, entityID: entityID, entity: entity)
            try validateSplineEndpointReferenceCanSplit(second, entityID: entityID, entity: entity)
        }
    }

    private func validateDimensionCanSplitSketchCurve(
        _ dimension: SketchDimension,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) throws {
        switch dimension {
        case .distance(let from, let to, _),
             .angle(let from, let to, _):
            try validateSketchReferenceCanSplit(from, entityID: entityID, entity: entity)
            try validateSketchReferenceCanSplit(to, entityID: entityID, entity: entity)
        case .radius(let id, _),
             .diameter(let id, _):
            if id == entityID {
                throw sketchCurveSplitUnsupportedConstraint("circular dimensions")
            }
        }
    }

    private func validateSketchReferenceCanSplit(
        _ reference: SketchReference,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) throws {
        guard sketchReference(reference, references: entityID) else {
            return
        }
        switch (reference, entity) {
        case (.lineStart(let id), .line) where id == entityID:
            return
        case (.lineEnd(let id), .line) where id == entityID:
            return
        case (.arcStart(let id), .arc) where id == entityID:
            return
        case (.arcEnd(let id), .arc) where id == entityID:
            return
        case (.splineControlPoint(let id, let index), .spline(let spline)) where id == entityID:
            guard index == 0 || index == spline.controlPoints.count - 1 else {
                throw sketchCurveSplitUnsupportedConstraint("internal spline control-point references")
            }
        default:
            throw sketchCurveSplitUnsupportedConstraint("entity-level or incompatible references")
        }
    }

    private func validateSplineEndpointReferenceCanSplit(
        _ reference: SketchSplineEndpointReference,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) throws {
        guard reference.splineID == entityID else {
            return
        }
        guard case .spline = entity else {
            throw sketchCurveSplitUnsupportedConstraint("incompatible spline endpoint references")
        }
    }

    private func sketchCurveSplitUnsupportedConstraint(_ reason: String) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Sketch curve split cannot preserve \(reason) yet."
        )
    }

    private func constraintsAfterSketchCurveSplit(
        _ constraints: [SketchConstraint],
        split: SketchCurveSegmentSplitResult
    ) -> [SketchConstraint] {
        var updated: [SketchConstraint] = []
        for constraint in constraints {
            switch constraint {
            case .coincident(let first, let second):
                updated.append(.coincident(
                    rewriteSketchReferenceAfterCurveSplit(first, split: split),
                    rewriteSketchReferenceAfterCurveSplit(second, split: split)
                ))
            case .fixed(let reference):
                updated.append(.fixed(rewriteSketchReferenceAfterCurveSplit(reference, split: split)))
            case .horizontal(let entityID):
                updated.append(constraint)
                if entityID == split.originalEntityID,
                   case .line = split.retainedEntity {
                    updated.append(.horizontal(split.newEntityID))
                }
            case .vertical(let entityID):
                updated.append(constraint)
                if entityID == split.originalEntityID,
                   case .line = split.retainedEntity {
                    updated.append(.vertical(split.newEntityID))
                }
            case .parallel(let first, let second):
                updated.append(constraint)
                if first == split.originalEntityID,
                   case .line = split.retainedEntity {
                    updated.append(.parallel(split.newEntityID, second))
                } else if second == split.originalEntityID,
                          case .line = split.retainedEntity {
                    updated.append(.parallel(first, split.newEntityID))
                }
            case .perpendicular(let first, let second):
                updated.append(constraint)
                if first == split.originalEntityID,
                   case .line = split.retainedEntity {
                    updated.append(.perpendicular(split.newEntityID, second))
                } else if second == split.originalEntityID,
                          case .line = split.retainedEntity {
                    updated.append(.perpendicular(first, split.newEntityID))
                }
            case .splineEndpointTangent(let splineID, let endpoint, let lineID):
                if splineID == split.originalEntityID,
                   endpoint == .end {
                    updated.append(.splineEndpointTangent(
                        spline: split.newEntityID,
                        endpoint: .end,
                        line: lineID
                    ))
                } else {
                    updated.append(constraint)
                }
            case .tangentSplineEndpoints(let first, let second):
                updated.append(.tangentSplineEndpoints(
                    first: rewriteSplineEndpointReferenceAfterCurveSplit(first, split: split),
                    second: rewriteSplineEndpointReferenceAfterCurveSplit(second, split: split)
                ))
            case .smoothSplineEndpoints(let first, let second):
                updated.append(.smoothSplineEndpoints(
                    first: rewriteSplineEndpointReferenceAfterCurveSplit(first, split: split),
                    second: rewriteSplineEndpointReferenceAfterCurveSplit(second, split: split)
                ))
            case .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint:
                updated.append(constraint)
            }
        }
        updated.append(.coincident(split.insertedRetainedReference, split.insertedNewReference))
        return updated
    }

    private func dimensionsAfterSketchCurveSplit(
        _ dimensions: [SketchDimension],
        split: SketchCurveSegmentSplitResult
    ) -> [SketchDimension] {
        dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: rewriteSketchReferenceAfterCurveSplit(from, split: split),
                    to: rewriteSketchReferenceAfterCurveSplit(to, split: split),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: rewriteSketchReferenceAfterCurveSplit(from, split: split),
                    to: rewriteSketchReferenceAfterCurveSplit(to, split: split),
                    value: value
                )
            case .radius, .diameter:
                return dimension
            }
        }
    }

    private func bridgeCurveSourcesAfterSketchCurveSplit(
        _ sources: [BridgeCurveSourceID: BridgeCurveSource],
        split: SketchCurveSegmentSplitResult
    ) throws -> [BridgeCurveSourceID: BridgeCurveSource] {
        try sources.mapValues { source in
            BridgeCurveSource(
                id: source.id,
                featureID: source.featureID,
                entityID: source.entityID,
                firstEndpoint: try rewriteBridgeEndpointAfterCurveSplit(source.firstEndpoint, split: split),
                secondEndpoint: try rewriteBridgeEndpointAfterCurveSplit(source.secondEndpoint, split: split),
                continuity: source.continuity,
                trimsSourceCurves: source.trimsSourceCurves
            )
        }
    }

    private func rewriteBridgeEndpointAfterCurveSplit(
        _ endpoint: BridgeCurveEndpoint,
        split: SketchCurveSegmentSplitResult
    ) throws -> BridgeCurveEndpoint {
        guard let parameter = endpoint.parameter,
              bridgeEndpointReferencesEntity(endpoint.reference, entityID: split.originalEntityID) else {
            return BridgeCurveEndpoint(
                reference: rewriteSketchReferenceAfterCurveSplit(endpoint.reference, split: split),
                parameter: endpoint.parameter,
                reversesSense: endpoint.reversesSense,
                trimSide: endpoint.trimSide,
                tension: endpoint.tension
            )
        }

        let resolvedParameter = try resolvedScalarValue(
            parameter,
            owner: "Bridge curve endpoint parameter"
        )
        let splitExpression = CADExpression.scalar(split.fraction)
        if resolvedParameter <= split.fraction {
            return BridgeCurveEndpoint(
                reference: endpoint.reference,
                parameter: .divide(parameter, splitExpression),
                reversesSense: endpoint.reversesSense,
                trimSide: endpoint.trimSide,
                tension: endpoint.tension
            )
        }
        return BridgeCurveEndpoint(
            reference: rewriteBridgeParametricReferenceToNewSplitEntity(
                endpoint.reference,
                split: split
            ),
            parameter: .divide(
                .subtract(parameter, splitExpression),
                .subtract(.scalar(1.0), splitExpression)
            ),
            reversesSense: endpoint.reversesSense,
            trimSide: endpoint.trimSide,
            tension: endpoint.tension
        )
    }

    private func rewriteBridgeParametricReferenceToNewSplitEntity(
        _ reference: SketchReference,
        split: SketchCurveSegmentSplitResult
    ) -> SketchReference {
        switch reference {
        case .entity(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .lineStart(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .lineEnd(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .arcStart(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .arcEnd(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .splineControlPoint(let entityID, _) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        default:
            return reference
        }
    }

    private func rewriteSketchReferenceAfterCurveSplit(
        _ reference: SketchReference,
        split: SketchCurveSegmentSplitResult
    ) -> SketchReference {
        reference == split.originalEndReference ? split.migratedEndReference : reference
    }

    private func rewriteSplineEndpointReferenceAfterCurveSplit(
        _ reference: SketchSplineEndpointReference,
        split: SketchCurveSegmentSplitResult
    ) -> SketchSplineEndpointReference {
        guard reference.splineID == split.originalEntityID,
              reference.endpoint == .end else {
            return reference
        }
        return SketchSplineEndpointReference(splineID: split.newEntityID, endpoint: .end)
    }
}
