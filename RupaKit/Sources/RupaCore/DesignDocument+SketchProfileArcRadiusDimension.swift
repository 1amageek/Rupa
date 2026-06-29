import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func profileArcMoveSketch(
        featureID: FeatureID,
        entityID: SketchEntityID,
        sketch: Sketch,
        deltaX: CADExpression,
        deltaY: CADExpression
    ) throws -> Sketch? {
        guard featureIsProfileOfNormalExtrude(featureID) else {
            return nil
        }
        guard let entity = sketch.entities[entityID],
              case let .arc(arc) = entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch profile arc move requires an arc entity."
            )
        }
        let deltaXMeters = try resolvedLengthValue(deltaX, owner: "Sketch profile arc move delta X")
        let deltaYMeters = try resolvedLengthValue(deltaY, owner: "Sketch profile arc move delta Y")
        let currentCenter = try sketchCornerPoint(
            .arcCenter(entityID),
            in: sketch,
            owner: "Sketch profile arc move"
        )
        let desiredCenter = currentCenter.adding(
            SketchCornerPoint(x: deltaXMeters, y: deltaYMeters)
        )
        let currentRadius = try resolvedPositiveLengthValue(
            arc.radius,
            owner: "Sketch profile arc move radius"
        )
        let nextRadius = try profileArcMoveRadius(
            entityID: entityID,
            sketch: sketch,
            desiredCenter: desiredCenter,
            owner: "Sketch profile arc move"
        )
        guard abs(nextRadius - currentRadius) > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch profile arc move delta does not move the arc along the supported tangent-preserving direction."
            )
        }
        return try profileArcRadiusDimensionSketch(
            featureID: featureID,
            entityID: entityID,
            sketch: sketch,
            kind: .radius,
            value: .length(nextRadius, .meter)
        )
    }

    func profileArcRadiusDimensionSketch(
        featureID: FeatureID,
        entityID: SketchEntityID,
        sketch: Sketch,
        kind: SketchEntityDimensionKind,
        value: CADExpression
    ) throws -> Sketch? {
        guard kind == .radius || kind == .diameter else {
            return nil
        }
        guard featureIsProfileOfNormalExtrude(featureID) else {
            return nil
        }

        let nextRadiusExpression = try radiusExpression(for: kind, value: value)
        let radiusMeters = try resolvedPositiveLengthValue(
            nextRadiusExpression,
            owner: "Sketch profile arc radius dimension"
        )
        let startAdjacent = try adjacentProfileLineEndpoint(
            to: .arcStart(entityID),
            in: sketch,
            owner: "Sketch profile arc radius dimension"
        )
        let endAdjacent = try adjacentProfileLineEndpoint(
            to: .arcEnd(entityID),
            in: sketch,
            owner: "Sketch profile arc radius dimension"
        )
        guard startAdjacent.endpoint.entityID != endAdjacent.endpoint.entityID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch profile arc radius dimension requires a line-arc-line profile corner."
            )
        }
        try validateProfileArcRadiusDimensionRewrite(
            sketch: sketch,
            arcID: entityID,
            startLineEndpoint: startAdjacent.endpoint,
            endLineEndpoint: endAdjacent.endpoint
        )

        let startConnected = try sketchCornerPoint(
            startAdjacent.endpoint.reference,
            in: sketch,
            owner: "Sketch profile arc radius dimension"
        )
        let startFar = try sketchCornerPoint(
            startAdjacent.endpoint.oppositeReference,
            in: sketch,
            owner: "Sketch profile arc radius dimension"
        )
        let endConnected = try sketchCornerPoint(
            endAdjacent.endpoint.reference,
            in: sketch,
            owner: "Sketch profile arc radius dimension"
        )
        let endFar = try sketchCornerPoint(
            endAdjacent.endpoint.oppositeReference,
            in: sketch,
            owner: "Sketch profile arc radius dimension"
        )
        let corner = try lineIntersection(
            firstStart: startConnected,
            firstEnd: startFar,
            secondStart: endConnected,
            secondEnd: endFar,
            owner: "Sketch profile arc radius dimension"
        )
        let selectedGeometry = try profileLineEndpointGeometry(
            endpoint: startAdjacent.endpoint,
            entity: startAdjacent.entity,
            corner: corner,
            farPoint: startFar,
            owner: "Sketch profile arc radius dimension"
        )
        let adjacentGeometry = try profileLineEndpointGeometry(
            endpoint: endAdjacent.endpoint,
            entity: endAdjacent.entity,
            corner: corner,
            farPoint: endFar,
            owner: "Sketch profile arc radius dimension"
        )
        let candidate = try sketchLineLineCornerFilletCandidate(
            selectedGeometry: selectedGeometry,
            adjacentGeometry: adjacentGeometry,
            radius: radiusMeters
        )
        let fillet = try sketchCornerFilletEntity(
            center: candidate.center,
            selectedPoint: candidate.selectedPoint,
            adjacentPoint: candidate.adjacentPoint,
            radius: radiusMeters,
            insertedEntityID: entityID
        )
        guard case var .arc(updatedArc) = fillet.entity,
              case let .line(startLine) = startAdjacent.entity,
              case let .line(endLine) = endAdjacent.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch profile arc radius dimension requires a line-arc-line profile corner."
            )
        }
        updatedArc.radius = nextRadiusExpression
        try validateArc(updatedArc, owner: "Sketch profile arc radius dimension")

        var updatedSketch = sketch
        updatedSketch.entities[startAdjacent.endpoint.entityID] = .line(
            lineBySettingEndpoint(
                startLine,
                endpoint: startAdjacent.endpoint,
                point: literalSketchPoint(candidate.selectedPoint)
            )
        )
        updatedSketch.entities[endAdjacent.endpoint.entityID] = .line(
            lineBySettingEndpoint(
                endLine,
                endpoint: endAdjacent.endpoint,
                point: literalSketchPoint(candidate.adjacentPoint)
            )
        )
        updatedSketch.entities[entityID] = .arc(updatedArc)
        updatedSketch.constraints = constraintsAfterProfileArcRadiusDimension(
            sketch.constraints,
            arcID: entityID,
            startLineEndpoint: startAdjacent.endpoint,
            endLineEndpoint: endAdjacent.endpoint,
            startArcReference: fillet.selectedReference,
            endArcReference: fillet.adjacentReference
        )
        return updatedSketch
    }

    private func profileArcMoveRadius(
        entityID: SketchEntityID,
        sketch: Sketch,
        desiredCenter: SketchCornerPoint,
        owner: String
    ) throws -> Double {
        let startAdjacent = try adjacentProfileLineEndpoint(
            to: .arcStart(entityID),
            in: sketch,
            owner: owner
        )
        let endAdjacent = try adjacentProfileLineEndpoint(
            to: .arcEnd(entityID),
            in: sketch,
            owner: owner
        )
        guard startAdjacent.endpoint.entityID != endAdjacent.endpoint.entityID else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line-arc-line profile corner."
            )
        }
        let startConnected = try sketchCornerPoint(
            startAdjacent.endpoint.reference,
            in: sketch,
            owner: owner
        )
        let startFar = try sketchCornerPoint(
            startAdjacent.endpoint.oppositeReference,
            in: sketch,
            owner: owner
        )
        let endConnected = try sketchCornerPoint(
            endAdjacent.endpoint.reference,
            in: sketch,
            owner: owner
        )
        let endFar = try sketchCornerPoint(
            endAdjacent.endpoint.oppositeReference,
            in: sketch,
            owner: owner
        )
        let corner = try lineIntersection(
            firstStart: startConnected,
            firstEnd: startFar,
            secondStart: endConnected,
            secondEnd: endFar,
            owner: owner
        )
        let selectedGeometry = try profileLineEndpointGeometry(
            endpoint: startAdjacent.endpoint,
            entity: startAdjacent.entity,
            corner: corner,
            farPoint: startFar,
            owner: owner
        )
        let adjacentGeometry = try profileLineEndpointGeometry(
            endpoint: endAdjacent.endpoint,
            entity: endAdjacent.entity,
            corner: corner,
            farPoint: endFar,
            owner: owner
        )
        let dot = selectedGeometry.unit.dot(adjacentGeometry.unit)
        let angle = acos(min(max(dot, -1.0), 1.0))
        let sine = sin(angle / 2.0)
        guard angle > ModelingTolerance.standard.angle,
              abs(Double.pi - angle) > ModelingTolerance.standard.angle,
              sine > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a non-collinear line-arc-line profile corner."
            )
        }
        let bisector = try selectedGeometry.unit.adding(adjacentGeometry.unit).normalized(
            owner: "\(owner) bisector",
            tolerance: ModelingTolerance.standard.distance
        )
        let centerDistance = desiredCenter.subtracting(corner).dot(bisector)
        let radius = centerDistance * sine
        guard radius.isFinite,
              radius > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) would collapse the profile arc."
            )
        }
        _ = try sketchLineLineCornerFilletCandidate(
            selectedGeometry: selectedGeometry,
            adjacentGeometry: adjacentGeometry,
            radius: radius
        )
        return radius
    }

    private func featureIsProfileOfNormalExtrude(_ featureID: FeatureID) -> Bool {
        cadDocument.designGraph.nodes.values.contains { feature in
            guard case let .extrude(extrude) = feature.operation,
                  extrude.profile.featureID == featureID,
                  case .normal = extrude.direction else {
                return false
            }
            return true
        }
    }

    private func adjacentProfileLineEndpoint(
        to reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> (endpoint: LineEndpoint, entity: SketchEntity) {
        let adjacent = try adjacentSketchCurveEndpoint(
            to: reference,
            in: sketch,
            owner: owner
        )
        guard case let .line(endpoint) = adjacent.endpoint,
              case .line = adjacent.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line-arc-line profile corner."
            )
        }
        return (endpoint, adjacent.entity)
    }

    private func validateProfileArcRadiusDimensionRewrite(
        sketch: Sketch,
        arcID: SketchEntityID,
        startLineEndpoint: LineEndpoint,
        endLineEndpoint: LineEndpoint
    ) throws {
        let affectedEntityIDs: Set<SketchEntityID> = [
            arcID,
            startLineEndpoint.entityID,
            endLineEndpoint.entityID,
        ]
        for dimension in sketch.dimensions where dimensionReferencesAny(
            dimension,
            entityIDs: affectedEntityIDs
        ) {
            guard isCircularSizeDimension(dimension, entityID: arcID) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch profile arc radius dimension cannot preserve other dimensions attached to the re-trimmed profile corner."
                )
            }
        }
        for constraint in sketch.constraints where profileArcRadiusDimensionBlocksConstraint(
            constraint,
            affectedEntityIDs: affectedEntityIDs,
            arcID: arcID,
            startLineEndpoint: startLineEndpoint,
            endLineEndpoint: endLineEndpoint
        ) {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch profile arc radius dimension cannot preserve unsupported constraints attached to the re-trimmed profile corner."
            )
        }
    }

    private func profileArcRadiusDimensionBlocksConstraint(
        _ constraint: SketchConstraint,
        affectedEntityIDs: Set<SketchEntityID>,
        arcID: SketchEntityID,
        startLineEndpoint: LineEndpoint,
        endLineEndpoint: LineEndpoint
    ) -> Bool {
        switch constraint {
        case .horizontal,
             .vertical,
             .parallel,
             .perpendicular:
            return false
        case .coincident(let first, let second):
            if referencesAreCoincident(first, second, startLineEndpoint.reference, .arcStart(arcID)) ||
                referencesAreCoincident(first, second, endLineEndpoint.reference, .arcEnd(arcID)) {
                return false
            }
            return profileArcRadiusDimensionReferenceIsMoved(
                first,
                arcID: arcID,
                startLineEndpoint: startLineEndpoint,
                endLineEndpoint: endLineEndpoint
            ) || profileArcRadiusDimensionReferenceIsMoved(
                second,
                arcID: arcID,
                startLineEndpoint: startLineEndpoint,
                endLineEndpoint: endLineEndpoint
            )
        case .fixed(let reference):
            return profileArcRadiusDimensionReferenceIsMoved(
                reference,
                arcID: arcID,
                startLineEndpoint: startLineEndpoint,
                endLineEndpoint: endLineEndpoint
            )
        case .equalLength(let first, let second),
             .tangent(let first, let second),
             .concentric(let first, let second),
             .equalRadius(let first, let second):
            return affectedEntityIDs.contains(first) || affectedEntityIDs.contains(second)
        case .smoothSplineControlPoint(let entityID, _):
            return affectedEntityIDs.contains(entityID)
        case .splineEndpointTangent(let splineID, _, let lineID):
            return affectedEntityIDs.contains(splineID) || affectedEntityIDs.contains(lineID)
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            return affectedEntityIDs.contains(first.splineID) ||
                affectedEntityIDs.contains(second.splineID)
        }
    }

    private func profileArcRadiusDimensionReferenceIsMoved(
        _ reference: SketchReference,
        arcID: SketchEntityID,
        startLineEndpoint: LineEndpoint,
        endLineEndpoint: LineEndpoint
    ) -> Bool {
        if reference == startLineEndpoint.reference ||
            reference == endLineEndpoint.reference ||
            reference == .arcStart(arcID) ||
            reference == .arcEnd(arcID) ||
            reference == .arcCenter(arcID) ||
            reference == .arcRadius(arcID) {
            return true
        }
        switch reference {
        case .entity(let entityID):
            return entityID == arcID ||
                entityID == startLineEndpoint.entityID ||
                entityID == endLineEndpoint.entityID
        case .circleCenter,
             .circleRadius,
             .splineControlPoint:
            return false
        case .lineStart,
             .lineEnd,
             .arcStart,
             .arcEnd,
             .arcCenter,
             .arcRadius:
            return false
        }
    }

    private func constraintsAfterProfileArcRadiusDimension(
        _ constraints: [SketchConstraint],
        arcID: SketchEntityID,
        startLineEndpoint: LineEndpoint,
        endLineEndpoint: LineEndpoint,
        startArcReference: SketchReference,
        endArcReference: SketchReference
    ) -> [SketchConstraint] {
        var updated = constraints.filter { constraint in
            guard case let .coincident(first, second) = constraint else {
                return true
            }
            if referencesAreCoincident(first, second, startLineEndpoint.reference, .arcStart(arcID)) {
                return false
            }
            if referencesAreCoincident(first, second, endLineEndpoint.reference, .arcEnd(arcID)) {
                return false
            }
            return true
        }
        updated.append(.coincident(startLineEndpoint.reference, startArcReference))
        updated.append(.coincident(endArcReference, endLineEndpoint.reference))
        return updated
    }

    private func profileLineEndpointGeometry(
        endpoint: LineEndpoint,
        entity: SketchEntity,
        corner: SketchCornerPoint,
        farPoint: SketchCornerPoint,
        owner: String
    ) throws -> SketchCornerEndpointGeometry {
        let delta = farPoint.subtracting(corner)
        let length = corner.distance(to: farPoint)
        guard length > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires adjacent line segments with non-zero length."
            )
        }
        return SketchCornerEndpointGeometry(
            endpoint: .line(endpoint),
            entity: entity,
            vertex: corner,
            length: length,
            unit: delta.scaled(by: 1.0 / length),
            arc: nil
        )
    }

    private func lineIntersection(
        firstStart: SketchCornerPoint,
        firstEnd: SketchCornerPoint,
        secondStart: SketchCornerPoint,
        secondEnd: SketchCornerPoint,
        owner: String
    ) throws -> SketchCornerPoint {
        let firstDirection = firstEnd.subtracting(firstStart)
        let secondDirection = secondEnd.subtracting(secondStart)
        let firstLength = hypot(firstDirection.x, firstDirection.y)
        let secondLength = hypot(secondDirection.x, secondDirection.y)
        guard firstLength > ModelingTolerance.standard.distance,
              secondLength > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires adjacent line segments with non-zero length."
            )
        }
        let denominator = firstDirection.cross(secondDirection)
        let normalizedCross = abs(denominator) / (firstLength * secondLength)
        guard normalizedCross > ModelingTolerance.standard.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires non-parallel adjacent line segments."
            )
        }
        let delta = secondStart.subtracting(firstStart)
        let distance = delta.cross(secondDirection) / denominator
        return firstStart.adding(firstDirection.scaled(by: distance))
    }

    private func sketchCornerPoint(
        _ reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> SketchCornerPoint {
        guard let point = try resolvedPoint(reference, in: sketch, owner: owner) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires endpoint references."
            )
        }
        return SketchCornerPoint(x: point.x, y: point.y)
    }

    private func referencesAreCoincident(
        _ first: SketchReference,
        _ second: SketchReference,
        _ expectedFirst: SketchReference,
        _ expectedSecond: SketchReference
    ) -> Bool {
        (first == expectedFirst && second == expectedSecond) ||
            (first == expectedSecond && second == expectedFirst)
    }
}
