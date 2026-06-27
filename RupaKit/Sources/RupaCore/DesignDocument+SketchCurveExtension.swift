import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func extendSketchCurve(
        target: SelectionTarget,
        distance: CADExpression,
        shape: ExtendCurveShape = .natural,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedDistance = try resolvedPositiveLengthValue(
            distance,
            owner: "Sketch curve extend distance"
        )
        let selection = try editableSketchEntityBase(
            for: target,
            operationName: "Sketch curve extend"
        )
        let endpoint = try extendCurveEndpoint(
            for: target,
            selection: selection,
            operationName: "Sketch curve extend"
        )
        try validateSketchCurveCanExtend(
            selection: selection,
            endpoint: endpoint,
            shape: shape
        )
        let extendedEntity = try extendedSketchCurveEntity(
            selection.entity,
            endpoint: endpoint,
            distance: distance,
            resolvedDistance: resolvedDistance,
            shape: shape,
            owner: "Sketch curve extend"
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = extendedEntity

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitExtend = false
        defer {
            if didCommitExtend == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        if selection.sketch.entities.count == 1 {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch curve extend"
        )
        didCommitExtend = true
    }

    private enum ExtendCurveEndpoint {
        case line(LineEndpoint)
        case arc(ArcEndpoint)
        case spline(entityID: SketchEntityID, isStart: Bool, controlPointIndex: Int)

        var entityID: SketchEntityID {
            switch self {
            case .line(let endpoint):
                endpoint.entityID
            case .arc(let endpoint):
                endpoint.entityID
            case .spline(let entityID, _, _):
                entityID
            }
        }

        var isStart: Bool {
            switch self {
            case .line(let endpoint):
                endpoint.isStart
            case .arc(let endpoint):
                endpoint.isStart
            case .spline(_, let isStart, _):
                isStart
            }
        }

        var reference: SketchReference {
            switch self {
            case .line(let endpoint):
                endpoint.reference
            case .arc(let endpoint):
                endpoint.reference
            case .spline(let entityID, _, let controlPointIndex):
                .splineControlPoint(entity: entityID, index: controlPointIndex)
            }
        }
    }

    private func extendCurveEndpoint(
        for target: SelectionTarget,
        selection: EditableSketchEntitySelection,
        operationName: String
    ) throws -> ExtendCurveEndpoint {
        guard case .sketchEntity(let componentID) = target.component else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch entity endpoint target."
            )
        }
        if let reference = componentID.sketchPointHandleReference {
            guard reference.featureID == selection.featureID,
                  reference.entityID == selection.entityID else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(operationName) endpoint target does not match the selected source curve."
                )
            }
            switch reference.handle {
            case .lineStart:
                return .line(LineEndpoint(entityID: reference.entityID, isStart: true))
            case .lineEnd:
                return .line(LineEndpoint(entityID: reference.entityID, isStart: false))
            case .arcStart:
                return .arc(ArcEndpoint(entityID: reference.entityID, isStart: true))
            case .arcEnd:
                return .arc(ArcEndpoint(entityID: reference.entityID, isStart: false))
            case .point,
                 .circleCenter,
                 .arcCenter:
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) requires a line endpoint, arc endpoint, or spline endpoint target."
                )
            }
        }
        if let reference = componentID.sketchControlPointReference {
            guard reference.featureID == selection.featureID,
                  reference.entityID == selection.entityID else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(operationName) control point target does not match the selected source curve."
                )
            }
            guard case .spline(let spline) = selection.entity else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) control point targets are only valid for spline curves."
                )
            }
            if reference.index == 0 {
                return .spline(entityID: reference.entityID, isStart: true, controlPointIndex: 0)
            }
            if reference.index == spline.controlPoints.count - 1 {
                return .spline(
                    entityID: reference.entityID,
                    isStart: false,
                    controlPointIndex: reference.index
                )
            }
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a spline endpoint control point target."
            )
        }
        throw EditorError(
            code: .commandInvalid,
            message: "\(operationName) follows Plasticity Extend Curve endpoint selection; select a curve endpoint, not the whole curve."
        )
    }

    private func validateSketchCurveCanExtend(
        selection: EditableSketchEntitySelection,
        endpoint: ExtendCurveEndpoint,
        shape: ExtendCurveShape
    ) throws {
        guard selection.entityID == endpoint.entityID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch curve extend endpoint target does not match the selected curve."
            )
        }
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve extend cannot edit a generated Bridge Curve source."
            )
        }

        switch (selection.entity, endpoint) {
        case (.line, .line):
            guard shape != .arc else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve extend Arc shape for line curves requires arc construction parameters."
                )
            }
        case (.arc, .arc):
            guard shape != .linear else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve extend Linear shape for arcs would create a new tangent line segment and is not supported yet."
                )
            }
        case (.spline(let spline), .spline):
            guard spline.isClosed == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve extend requires an open spline curve."
                )
            }
            guard shape == .linear else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve extend supports spline extension with Linear shape only until higher-continuity spline extension is implemented."
                )
            }
        case (.point, _),
             (.circle, _),
             (.line, _),
             (.arc, _),
             (.spline, _):
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve extend requires an endpoint target that belongs to the selected source curve type."
            )
        }

        for constraint in selection.sketch.constraints where sketchCurveExtendBlocksConstraint(
            constraint,
            entityID: selection.entityID,
            endpoint: endpoint,
            entity: selection.entity
        ) {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve extend cannot preserve an attached constraint on the moved endpoint or whole curve yet."
            )
        }
        for dimension in selection.sketch.dimensions where sketchCurveExtendBlocksDimension(
            dimension,
            entityID: selection.entityID,
            entity: selection.entity
        ) {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve extend cannot preserve dimensions attached to the changing curve extent yet."
            )
        }
    }

    private func extendedSketchCurveEntity(
        _ entity: SketchEntity,
        endpoint: ExtendCurveEndpoint,
        distance: CADExpression,
        resolvedDistance: Double,
        shape: ExtendCurveShape,
        owner: String
    ) throws -> SketchEntity {
        switch (entity, endpoint) {
        case (.line(let line), .line(let lineEndpoint)):
            let extended = try extendedLine(
                line,
                endpoint: lineEndpoint,
                distance: distance,
                shape: shape,
                owner: owner
            )
            return .line(extended)
        case (.arc(let arc), .arc(let arcEndpoint)):
            let extended = try extendedArc(
                arc,
                endpoint: arcEndpoint,
                distance: distance,
                resolvedDistance: resolvedDistance,
                shape: shape,
                owner: owner
            )
            return .arc(extended)
        case (.spline(let spline), .spline):
            let extended = try extendedSpline(
                spline,
                endpoint: endpoint,
                distance: distance,
                shape: shape,
                owner: owner
            )
            return .spline(extended)
        case (.point, _),
             (.circle, _),
             (.line, _),
             (.arc, _),
             (.spline, _):
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) endpoint target does not match the selected curve type."
            )
        }
    }

    private func extendedLine(
        _ line: SketchLine,
        endpoint: LineEndpoint,
        distance: CADExpression,
        shape: ExtendCurveShape,
        owner: String
    ) throws -> SketchLine {
        guard shape != .arc else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Arc shape for line curves requires arc construction parameters."
            )
        }
        let metrics = try resolvedLineMetrics(line, owner: owner)
        let directionX = cos(metrics.angleRadians) * (endpoint.isStart ? -1.0 : 1.0)
        let directionY = sin(metrics.angleRadians) * (endpoint.isStart ? -1.0 : 1.0)
        let extendedPoint = translatedSketchPoint(
            endpoint.isStart ? line.start : line.end,
            directionX: directionX,
            directionY: directionY,
            distance: distance
        )
        let extended = endpoint.isStart
            ? SketchLine(start: extendedPoint, end: line.end)
            : SketchLine(start: line.start, end: extendedPoint)
        _ = try resolvedLineMetrics(extended, owner: owner)
        return extended
    }

    private func extendedArc(
        _ arc: SketchArc,
        endpoint: ArcEndpoint,
        distance: CADExpression,
        resolvedDistance: Double,
        shape: ExtendCurveShape,
        owner: String
    ) throws -> SketchArc {
        guard shape != .linear else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Linear shape for arcs would create a new tangent line segment and is not supported yet."
            )
        }
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius")
        let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
        let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
        let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
        let deltaAngle = resolvedDistance / radius
        guard span + deltaAngle < (2.0 * Double.pi) - 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot extend an arc to a full or over-full circle."
            )
        }
        let deltaAngleExpression = CADExpression.multiply(
            .angle(1.0, .radian),
            .divide(distance, arc.radius)
        )
        let extended = endpoint.isStart
            ? SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: .subtract(arc.startAngle, deltaAngleExpression),
                endAngle: arc.endAngle
            )
            : SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: arc.startAngle,
                endAngle: .add(arc.endAngle, deltaAngleExpression)
            )
        try validateArc(extended, owner: owner)
        return extended
    }

    private func extendedSpline(
        _ spline: SketchSpline,
        endpoint: ExtendCurveEndpoint,
        distance: CADExpression,
        shape: ExtendCurveShape,
        owner: String
    ) throws -> SketchSpline {
        guard case .spline(_, let isStart, _) = endpoint else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a spline endpoint target."
            )
        }
        guard shape == .linear else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) supports spline extension with Linear shape only."
            )
        }
        guard spline.isClosed == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires an open spline curve."
            )
        }
        try validateSpline(spline, owner: owner)

        var updated = spline
        if isStart {
            let first = spline.controlPoints[0]
            let next = spline.controlPoints[1]
            let direction = try normalizedDirection(
                from: next,
                to: first,
                owner: "\(owner) start tangent"
            )
            updated.controlPoints = [
                translatedSketchPoint(first, directionX: direction.x, directionY: direction.y, distance: distance),
                translatedSketchPoint(first, directionX: direction.x, directionY: direction.y, distance: distance, scale: 2.0 / 3.0),
                translatedSketchPoint(first, directionX: direction.x, directionY: direction.y, distance: distance, scale: 1.0 / 3.0),
            ] + spline.controlPoints
        } else {
            let count = spline.controlPoints.count
            let previous = spline.controlPoints[count - 2]
            let last = spline.controlPoints[count - 1]
            let direction = try normalizedDirection(
                from: previous,
                to: last,
                owner: "\(owner) end tangent"
            )
            updated.controlPoints.append(
                translatedSketchPoint(last, directionX: direction.x, directionY: direction.y, distance: distance, scale: 1.0 / 3.0)
            )
            updated.controlPoints.append(
                translatedSketchPoint(last, directionX: direction.x, directionY: direction.y, distance: distance, scale: 2.0 / 3.0)
            )
            updated.controlPoints.append(
                translatedSketchPoint(last, directionX: direction.x, directionY: direction.y, distance: distance)
            )
        }
        try validateSpline(updated, owner: owner)
        return updated
    }

    private func sketchCurveExtendBlocksConstraint(
        _ constraint: SketchConstraint,
        entityID: SketchEntityID,
        endpoint: ExtendCurveEndpoint,
        entity: SketchEntity
    ) -> Bool {
        switch constraint {
        case .coincident(let first, let second):
            return first == endpoint.reference || second == endpoint.reference
        case .fixed(let reference):
            return reference == endpoint.reference || reference == .entity(entityID)
        case .horizontal(let id),
             .vertical(let id):
            if case .line = entity {
                return false
            }
            return id == entityID
        case .concentric(let first, let second),
             .equalRadius(let first, let second):
            if case .arc = entity {
                return false
            }
            return first == entityID || second == entityID
        case .parallel(let first, let second),
             .perpendicular(let first, let second),
             .equalLength(let first, let second),
             .tangent(let first, let second):
            return first == entityID || second == entityID
        case .smoothSplineControlPoint(let id, _):
            return id == entityID
        case .splineEndpointTangent(let splineID, _, let lineID):
            return splineID == entityID || lineID == entityID
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            return first.splineID == entityID || second.splineID == entityID
        }
    }

    private func sketchCurveExtendBlocksDimension(
        _ dimension: SketchDimension,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) -> Bool {
        switch dimension {
        case .distance(let from, let to, _),
             .angle(let from, let to, _):
            return sketchReference(from, references: entityID) ||
                sketchReference(to, references: entityID)
        case .radius(let id, _),
             .diameter(let id, _):
            if case .arc = entity {
                return false
            }
            return id == entityID
        }
    }
}
