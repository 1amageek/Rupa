import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func convertSketchLineToArc(
        target: SelectionTarget,
        sagitta: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedSagitta = try resolvedLengthValue(sagitta, owner: "Sketch line arc sagitta")
        guard abs(resolvedSagitta) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line arc sagitta must not be zero."
            )
        }

        let selection = try editableSketchEntity(for: target, operationName: "Sketch line arc conversion")
        guard case let .line(line) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line arc conversion requires a line entity target."
            )
        }
        let arc = try convertedArc(
            from: line,
            sagitta: resolvedSagitta,
            owner: "Sketch line arc conversion"
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .arc(arc)
        sketch.constraints = constraintsAfterLineToArcConversion(
            sketch.constraints,
            entityID: selection.entityID
        )
        sketch.dimensions = dimensionsAfterLineToArcConversion(
            sketch.dimensions,
            entityID: selection.entityID
        )

        if sketch.entities.count == 1 {
            try setSketchObjectType(
                featureID: selection.featureID,
                typeID: .arc,
                objectRegistry: objectRegistry
            )
        } else {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch line arc conversion"
        )
    }

    public mutating func convertSketchLineToSpline(
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let selection = try editableSketchEntity(for: target, operationName: "Sketch line spline conversion")
        guard case let .line(line) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line spline conversion requires a line entity target."
            )
        }
        try validateLineCanConvertToSpline(
            entityID: selection.entityID,
            sketch: selection.sketch,
            owner: "Sketch line spline conversion"
        )
        let spline = try convertedSpline(
            from: line,
            owner: "Sketch line spline conversion"
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .spline(spline)
        sketch.constraints = try constraintsAfterLineToSplineConversion(
            sketch.constraints,
            entityID: selection.entityID,
            originalSketch: selection.sketch,
            owner: "Sketch line spline conversion"
        )
        sketch.dimensions = dimensionsAfterLineToSplineConversion(
            sketch.dimensions,
            entityID: selection.entityID
        )

        if sketch.entities.count == 1 {
            try setSketchObjectType(
                featureID: selection.featureID,
                typeID: .spline,
                objectRegistry: objectRegistry
            )
        } else {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch line spline conversion"
        )
    }

    private func convertedArc(
        from line: SketchLine,
        sagitta: Double,
        owner: String
    ) throws -> SketchArc {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let chordLength = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard chordLength > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }

        let midpointX = (startX + endX) / 2.0
        let midpointY = (startY + endY) / 2.0
        let normalX = -deltaY / chordLength
        let normalY = deltaX / chordLength
        let centerOffset = (chordLength * chordLength) / (8.0 * sagitta) - sagitta / 2.0
        let centerX = midpointX + normalX * centerOffset
        let centerY = midpointY + normalY * centerOffset
        let radius = sqrt(pow(chordLength / 2.0, 2.0) + centerOffset * centerOffset)
        guard radius.isFinite,
              radius > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) produced an invalid arc radius."
            )
        }

        let rawStartAngle = atan2(startY - centerY, startX - centerX)
        let rawEndAngle = atan2(endY - centerY, endX - centerX)
        let span = positiveArcSpan(startAngle: rawStartAngle, endAngle: rawEndAngle)
        _ = try normalizedPartialArcSpan(
            startAngle: rawStartAngle,
            endAngle: rawStartAngle + span
        )

        return SketchArc(
            center: sketchPoint(x: centerX, y: centerY),
            radius: .length(radius, .meter),
            startAngle: .angle(rawStartAngle, .radian),
            endAngle: .angle(rawStartAngle + span, .radian)
        )
    }

    private func convertedSpline(
        from line: SketchLine,
        owner: String
    ) throws -> SketchSpline {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        return SketchSpline(controlPoints: [
            sketchPoint(x: startX, y: startY),
            sketchPoint(x: startX + deltaX / 3.0, y: startY + deltaY / 3.0),
            sketchPoint(x: startX + deltaX * 2.0 / 3.0, y: startY + deltaY * 2.0 / 3.0),
            sketchPoint(x: endX, y: endY),
        ])
    }

    private func constraintsAfterLineToArcConversion(
        _ constraints: [SketchConstraint],
        entityID: SketchEntityID
    ) -> [SketchConstraint] {
        constraints.compactMap { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    rewriteLineEndpointReference(first, entityID: entityID),
                    rewriteLineEndpointReference(second, entityID: entityID)
                )
            case .horizontal(let id), .vertical(let id):
                return id == entityID ? nil : constraint
            case .parallel(let first, let second),
                 .perpendicular(let first, let second),
                 .equalLength(let first, let second),
                 .tangent(let first, let second):
                return first == entityID || second == entityID ? nil : constraint
            case .concentric, .equalRadius:
                return constraint
            case .smoothSplineControlPoint:
                return constraint
            case .splineEndpointTangent(_, _, let lineID):
                return lineID == entityID ? nil : constraint
            case .tangentSplineEndpoints,
                 .smoothSplineEndpoints:
                return constraint
            case .fixed(let reference):
                return .fixed(
                    rewriteLineEndpointReference(reference, entityID: entityID)
                )
            }
        }
    }

    private func dimensionsAfterLineToArcConversion(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID
    ) -> [SketchDimension] {
        dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: rewriteLineEndpointReference(from, entityID: entityID),
                    to: rewriteLineEndpointReference(to, entityID: entityID),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: rewriteLineEndpointReference(from, entityID: entityID),
                    to: rewriteLineEndpointReference(to, entityID: entityID),
                    value: value
                )
            case .radius, .diameter:
                return dimension
            }
        }
    }

    private func validateLineCanConvertToSpline(
        entityID: SketchEntityID,
        sketch: Sketch,
        owner: String
    ) throws {
        for constraint in sketch.constraints {
            try validateConstraintCanConvertLineToSpline(
                constraint,
                entityID: entityID,
                owner: owner
            )
        }
        for dimension in sketch.dimensions {
            try validateDimensionCanConvertLineToSpline(
                dimension,
                entityID: entityID,
                owner: owner
            )
        }
    }

    private func validateConstraintCanConvertLineToSpline(
        _ constraint: SketchConstraint,
        entityID: SketchEntityID,
        owner: String
    ) throws {
        switch constraint {
        case .coincident:
            return
        case .horizontal(let id),
             .vertical(let id):
            if id == entityID {
                throw lineSplineConversionError(owner, reason: "line orientation constraints")
            }
        case .parallel(let first, let second),
             .perpendicular(let first, let second),
             .equalLength(let first, let second),
             .tangent(let first, let second):
            if first == entityID || second == entityID {
                throw lineSplineConversionError(owner, reason: "line relationship constraints")
            }
        case .concentric(let first, let second),
             .equalRadius(let first, let second):
            if first == entityID || second == entityID {
                throw lineSplineConversionError(owner, reason: "circular constraints")
            }
        case .smoothSplineControlPoint:
            return
        case .splineEndpointTangent:
            return
        case .tangentSplineEndpoints,
             .smoothSplineEndpoints:
            return
        case .fixed(let reference):
            if sketchReference(reference, references: entityID),
               isLineEndpointReference(reference, entityID: entityID) == false {
                throw lineSplineConversionError(owner, reason: "entity-level fixed constraints")
            }
        }
    }

    private func validateDimensionCanConvertLineToSpline(
        _ dimension: SketchDimension,
        entityID: SketchEntityID,
        owner: String
    ) throws {
        switch dimension {
        case .distance(let first, let second, _),
             .angle(let first, let second, _):
            if sketchReference(first, references: entityID),
               isLineEndpointReference(first, entityID: entityID) == false {
                throw lineSplineConversionError(owner, reason: "entity-level dimensions")
            }
            if sketchReference(second, references: entityID),
               isLineEndpointReference(second, entityID: entityID) == false {
                throw lineSplineConversionError(owner, reason: "entity-level dimensions")
            }
        case .radius(let id, _),
             .diameter(let id, _):
            if id == entityID {
                throw lineSplineConversionError(owner, reason: "circular dimensions")
            }
        }
    }

    private func constraintsAfterLineToSplineConversion(
        _ constraints: [SketchConstraint],
        entityID: SketchEntityID,
        originalSketch: Sketch,
        owner: String
    ) throws -> [SketchConstraint] {
        try constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    rewriteLineEndpointToSplineReference(first, entityID: entityID),
                    rewriteLineEndpointToSplineReference(second, entityID: entityID)
                )
            case .fixed(let reference):
                return .fixed(
                    rewriteLineEndpointToSplineReference(reference, entityID: entityID)
                )
            case .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints:
                return constraint
            case .splineEndpointTangent(let splineID, let endpoint, let lineID):
                guard lineID == entityID else {
                    return constraint
                }
                let source = SketchSplineEndpointReference(splineID: splineID, endpoint: endpoint)
                let convertedEndpoint = try convertedLineSplineEndpointForTangency(
                    source: source,
                    lineID: entityID,
                    constraints: constraints,
                    originalSketch: originalSketch,
                    owner: owner
                )
                return .tangentSplineEndpoints(
                    first: source,
                    second: SketchSplineEndpointReference(
                        splineID: entityID,
                        endpoint: convertedEndpoint
                    )
                )
            }
        }
    }

    private func dimensionsAfterLineToSplineConversion(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID
    ) -> [SketchDimension] {
        dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: rewriteLineEndpointToSplineReference(from, entityID: entityID),
                    to: rewriteLineEndpointToSplineReference(to, entityID: entityID),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: rewriteLineEndpointToSplineReference(from, entityID: entityID),
                    to: rewriteLineEndpointToSplineReference(to, entityID: entityID),
                    value: value
                )
            case .radius, .diameter:
                return dimension
            }
        }
    }

    private func convertedLineSplineEndpointForTangency(
        source: SketchSplineEndpointReference,
        lineID: SketchEntityID,
        constraints: [SketchConstraint],
        originalSketch: Sketch,
        owner: String
    ) throws -> SketchSplineEndpoint {
        let sourceReference = try splineEndpointPointReference(source, in: originalSketch, owner: owner)
        let connectedReferences = coincidentPointReferences(
            connectedTo: sourceReference,
            constraints: constraints
        )
        if connectedReferences.contains(.lineStart(lineID)) {
            return .start
        }
        if connectedReferences.contains(.lineEnd(lineID)) {
            return .end
        }

        guard let sourcePoint = try resolvedPoint(sourceReference, in: originalSketch, owner: owner),
              let startPoint = try resolvedPoint(.lineStart(lineID), in: originalSketch, owner: owner),
              let endPoint = try resolvedPoint(.lineEnd(lineID), in: originalSketch, owner: owner) else {
            return .start
        }
        let startDistance = squaredDistance(sourcePoint, startPoint)
        let endDistance = squaredDistance(sourcePoint, endPoint)
        return startDistance <= endDistance ? .start : .end
    }

    private func splineEndpointPointReference(
        _ endpoint: SketchSplineEndpointReference,
        in sketch: Sketch,
        owner: String
    ) throws -> SketchReference {
        guard let entity = sketch.entities[endpoint.splineID],
              case let .spline(spline) = entity,
              spline.controlPoints.count >= 4 else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires a spline endpoint reference."
            )
        }
        switch endpoint.endpoint {
        case .start:
            return .splineControlPoint(entity: endpoint.splineID, index: 0)
        case .end:
            return .splineControlPoint(entity: endpoint.splineID, index: spline.controlPoints.count - 1)
        }
    }

    private func coincidentPointReferences(
        connectedTo reference: SketchReference,
        constraints: [SketchConstraint]
    ) -> Set<SketchReference> {
        var connectedReferences: Set<SketchReference> = [reference]
        var changed = true
        while changed {
            changed = false
            for constraint in constraints {
                guard case let .coincident(first, second) = constraint else {
                    continue
                }
                if connectedReferences.contains(first), connectedReferences.insert(second).inserted {
                    changed = true
                }
                if connectedReferences.contains(second), connectedReferences.insert(first).inserted {
                    changed = true
                }
            }
        }
        return connectedReferences
    }

    private func isLineEndpointReference(
        _ reference: SketchReference,
        entityID: SketchEntityID
    ) -> Bool {
        switch reference {
        case .lineStart(let id), .lineEnd(let id):
            return id == entityID
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcStart,
             .arcEnd,
             .arcRadius,
             .splineControlPoint:
            return false
        }
    }

    private func lineSplineConversionError(
        _ owner: String,
        reason: String
    ) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "\(owner) cannot preserve \(reason) as spline point references."
        )
    }

    private func rewriteLineEndpointReference(
        _ reference: SketchReference,
        entityID: SketchEntityID
    ) -> SketchReference {
        switch reference {
        case .lineStart(let id) where id == entityID:
            return .arcStart(entityID)
        case .lineEnd(let id) where id == entityID:
            return .arcEnd(entityID)
        default:
            return reference
        }
    }

    private func rewriteLineEndpointToSplineReference(
        _ reference: SketchReference,
        entityID: SketchEntityID
    ) -> SketchReference {
        switch reference {
        case .lineStart(let id) where id == entityID:
            return .splineControlPoint(entity: entityID, index: 0)
        case .lineEnd(let id) where id == entityID:
            return .splineControlPoint(entity: entityID, index: 3)
        default:
            return reference
        }
    }
}
