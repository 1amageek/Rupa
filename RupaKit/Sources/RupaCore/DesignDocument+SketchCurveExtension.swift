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
        if case .spline(let original) = selection.entity, endpoint.isStart,
           case .spline(let extended) = extendedEntity {
            let shift = extended.controlPoints.count - original.controlPoints.count
            sketch.remapSplineControlPoints(entity: selection.entityID) { $0 + shift }
        }

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
        case (.line, .line), (.arc, .arc):
            break
        case (.spline(let spline), .spline):
            guard spline.isClosed == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve extend requires an open spline curve."
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

        let supported = ExtendCurveShape.supported(for: selection.entity)
        guard supported.contains(shape) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Extend Curve builds \(supported.map(\.rawValue).joined(separator: ", ")) on this curve, not \(shape.rawValue)."
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
        guard ExtendCurveShape.supported(for: .spline(spline)).contains(shape) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) does not build the \(shape.rawValue) shape on a spline."
            )
        }
        guard spline.isClosed == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires an open spline curve."
            )
        }
        try validateSplineForm(spline, owner: owner)

        var updated = spline
        if shape == .natural {
            try validateCubicBezierChainSpline(spline, owner: owner)
            // Swift-CAD continues the end span's own cubic by the arc length.
            let points = try spline.controlPoints.map { point -> Point2D in
                let resolved = try resolvedSketchPoint(point, owner: "\(owner) control point")
                return Point2D(x: resolved.x, y: resolved.y)
            }
            let length = try resolvedPositiveLengthValue(distance, owner: "\(owner) distance")
            let continued: [SketchPoint]
            do {
                continued = try CubicBezierChainExtension(tolerance: .standard).naturalSpan(
                    of: points, at: isStart ? .start : .end, length: length
                ).map { sketchPoint(x: $0.x, y: $0.y) }
            } catch let error as KernelError {
                throw EditorError(code: .commandInvalid, message: "\(owner): \(error.message)")
            }
            updated.controlPoints = isStart ? continued + spline.controlPoints : spline.controlPoints + continued
        } else {
            let count = spline.controlPoints.count
            let origin = spline.controlPoints[isStart ? 0 : count - 1]
            let adjacent = spline.controlPoints[isStart ? 1 : count - 2]
            // Validate the current tangent, then retain its full dependency graph.
            _ = try normalizedDirection(from: adjacent, to: origin, owner: "\(owner) tangent")
            let dx = CADExpression.subtract(origin.x, adjacent.x)
            let dy = CADExpression.subtract(origin.y, adjacent.y)
            let magnitude = CADExpression.hypot(dx, dy)
            let directionX = CADExpression.divide(dx, magnitude)
            let directionY = CADExpression.divide(dy, magnitude)
            let added = (1...spline.degree).map { index in
                let step = CADExpression.multiply(distance, .scalar(Double(index) / Double(spline.degree)))
                return SketchPoint(
                    x: .add(origin.x, .multiply(step, directionX)),
                    y: .add(origin.y, .multiply(step, directionY))
                )
            }
            updated.controlPoints = isStart
                ? Array(added.reversed()) + spline.controlPoints
                : spline.controlPoints + added
        }
        if let knots = spline.knots {
            let degree = spline.degree
            let first = knots[degree], last = knots[knots.count - degree - 1]
            if isStart {
                guard let next = knots.first(where: { $0 > first }) else {
                    throw EditorError(code: .commandInvalid, message: "\(owner) has no first knot span.")
                }
                updated.knots = Array(repeating: first - (next - first), count: degree + 1) + knots.dropFirst()
            } else {
                guard let previous = knots.last(where: { $0 < last }) else {
                    throw EditorError(code: .commandInvalid, message: "\(owner) has no last knot span.")
                }
                updated.knots = knots.dropLast() + Array(repeating: last + (last - previous), count: degree + 1)
            }
        }
        try validateSplineForm(updated, owner: owner)
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
             .equalLength(let first, let second):
            return first == entityID || second == entityID
        case .tangent(let tangency):
            switch tangency {
            case .lineCircular(let line, let circular, _):
                return line == entityID || circular == entityID
            case .circularCircular(let first, let second, _):
                return first == entityID || second == entityID
            }
        case .smoothSplineControlPoint(let id, _):
            return id == entityID
        case .splineEndpointTangent(let lineTangency):
            return lineTangency.splineEndpoint.splineID == entityID ||
                lineTangency.line == entityID
        case .tangentSplineEndpoints(let pair),
             .smoothSplineEndpoints(let pair):
            return pair.first.splineID == entityID || pair.second.splineID == entityID
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
