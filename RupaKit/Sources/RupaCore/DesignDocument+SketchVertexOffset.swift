import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func offsetSketchVertex(
        target: SelectionTarget,
        handle: SketchEntityPointHandle,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let distanceMeters = try resolvedPositiveLengthValue(distance, owner: "Sketch vertex offset distance")
        let selection = try editableSketchEntity(for: target, operationName: "Sketch vertex offset")
        let selectedReference = try sketchPointReference(
            entityID: selection.entityID,
            entity: selection.entity,
            handle: handle,
            operationName: "Sketch vertex offset"
        )
        guard let selectedEndpoint = sketchCurveEndpoint(for: selectedReference) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch vertex offset requires a line or arc endpoint handle."
            )
        }

        let adjacentReference = try adjacentSketchCurveEndpoint(
            to: selectedReference,
            in: selection.sketch,
            owner: "Sketch vertex offset"
        )
        let adjacentEndpoint = adjacentReference.endpoint
        let adjacentEntityID = adjacentEndpoint.entityID

        try validateSketchVertexOffsetConstraints(
            selection.sketch,
            affectedEntityIDs: [selection.entityID, adjacentEntityID]
        )

        let selectedCornerID = SketchEntityID()
        let adjacentCornerID = SketchEntityID()
        let selectedSplit = try splitSketchCurve(
            selection.entity,
            targetEndpoint: selectedEndpoint,
            distance: distance,
            resolvedDistance: distanceMeters,
            owner: "Sketch vertex offset selected side"
        )
        let adjacentSplit = try splitSketchCurve(
            adjacentReference.entity,
            targetEndpoint: adjacentEndpoint,
            distance: distance,
            resolvedDistance: distanceMeters,
            owner: "Sketch vertex offset adjacent side"
        )

        var sketch = selection.sketch
        sketch.entities[selection.entityID] = selectedSplit.outer
        sketch.entities[adjacentEntityID] = adjacentSplit.outer
        sketch.entities[selectedCornerID] = selectedSplit.corner
        sketch.entities[adjacentCornerID] = adjacentSplit.corner
        sketch.constraints = offsetVertexConstraints(
            from: sketch.constraints,
            selectedReference: selectedReference,
            adjacentReference: adjacentReference.reference,
            selectedEndpoint: selectedEndpoint,
            adjacentEndpoint: adjacentEndpoint,
            selectedCornerID: selectedCornerID,
            adjacentCornerID: adjacentCornerID,
            selectedSplit: selectedSplit,
            adjacentSplit: adjacentSplit
        )
        sketch.dimensions = try dimensionsAfterSketchVertexOffset(
            sketch.dimensions,
            affectedEntityIDs: [selection.entityID, adjacentEntityID],
            selectedEndpoint: selectedEndpoint,
            adjacentEndpoint: adjacentEndpoint,
            selectedCornerID: selectedCornerID,
            adjacentCornerID: adjacentCornerID,
            selectedSplit: selectedSplit,
            adjacentSplit: adjacentSplit,
            in: sketch
        )

        var feature = selection.feature
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch vertex offset"
        )
    }

    private struct LineSplitResult {
        var outer: SketchLine
        var corner: SketchLine
        var targetEndpointIsStart: Bool
    }

    private struct ArcSplitResult {
        var outer: SketchArc
        var corner: SketchArc
        var targetEndpointIsStart: Bool
    }

    private struct SketchCurveSplitResult {
        var outer: SketchEntity
        var corner: SketchEntity
        var targetEndpointIsStart: Bool
    }

    private func splitPoint(
        on line: SketchLine,
        movingFrom endpoint: LineEndpoint,
        distance: CADExpression,
        resolvedDistance: Double,
        owner: String
    ) throws -> SketchPoint {
        let vertex = endpoint.isStart ? line.start : line.end
        let far = endpoint.isStart ? line.end : line.start
        let vertexX = try resolvedLengthValue(vertex.x, owner: "\(owner) vertex x")
        let vertexY = try resolvedLengthValue(vertex.y, owner: "\(owner) vertex y")
        let farX = try resolvedLengthValue(far.x, owner: "\(owner) far x")
        let farY = try resolvedLengthValue(far.y, owner: "\(owner) far y")
        let deltaX = farX - vertexX
        let deltaY = farY - vertexY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a non-zero adjacent line."
            )
        }
        guard resolvedDistance < length - 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) distance must be smaller than the adjacent line length."
            )
        }
        return SketchPoint(
            x: .add(vertex.x, .multiply(distance, .scalar(deltaX / length))),
            y: .add(vertex.y, .multiply(distance, .scalar(deltaY / length)))
        )
    }

    private func splitLine(
        _ line: SketchLine,
        targetEndpoint: LineEndpoint,
        splitPoint: SketchPoint
    ) -> LineSplitResult {
        if targetEndpoint.isStart {
            return LineSplitResult(
                outer: SketchLine(start: splitPoint, end: line.end),
                corner: SketchLine(start: line.start, end: splitPoint),
                targetEndpointIsStart: true
            )
        }
        return LineSplitResult(
            outer: SketchLine(start: line.start, end: splitPoint),
            corner: SketchLine(start: splitPoint, end: line.end),
            targetEndpointIsStart: false
        )
    }

    private func splitArc(
        _ arc: SketchArc,
        targetEndpoint: ArcEndpoint,
        distance: CADExpression,
        resolvedDistance: Double,
        owner: String
    ) throws -> ArcSplitResult {
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius")
        let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
        let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
        let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
        let arcLength = radius * span
        guard resolvedDistance < arcLength - 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) distance must be smaller than the adjacent arc length."
            )
        }
        let deltaAngle = CADExpression.multiply(
            .angle(1.0, .radian),
            .divide(distance, arc.radius)
        )
        if targetEndpoint.isStart {
            let splitAngle = CADExpression.add(arc.startAngle, deltaAngle)
            return ArcSplitResult(
                outer: SketchArc(
                    center: arc.center,
                    radius: arc.radius,
                    startAngle: splitAngle,
                    endAngle: arc.endAngle
                ),
                corner: SketchArc(
                    center: arc.center,
                    radius: arc.radius,
                    startAngle: arc.startAngle,
                    endAngle: splitAngle
                ),
                targetEndpointIsStart: true
            )
        }
        let splitAngle = CADExpression.subtract(arc.endAngle, deltaAngle)
        return ArcSplitResult(
            outer: SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: arc.startAngle,
                endAngle: splitAngle
            ),
            corner: SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: splitAngle,
                endAngle: arc.endAngle
            ),
            targetEndpointIsStart: false
        )
    }

    private func splitSketchCurve(
        _ entity: SketchEntity,
        targetEndpoint: SketchCurveEndpoint,
        distance: CADExpression,
        resolvedDistance: Double,
        owner: String
    ) throws -> SketchCurveSplitResult {
        switch (entity, targetEndpoint) {
        case (.line(let line), .line(let endpoint)):
            let splitPoint = try splitPoint(
                on: line,
                movingFrom: endpoint,
                distance: distance,
                resolvedDistance: resolvedDistance,
                owner: owner
            )
            let split = splitLine(
                line,
                targetEndpoint: endpoint,
                splitPoint: splitPoint
            )
            return SketchCurveSplitResult(
                outer: .line(split.outer),
                corner: .line(split.corner),
                targetEndpointIsStart: split.targetEndpointIsStart
            )
        case (.arc(let arc), .arc(let endpoint)):
            let split = try splitArc(
                arc,
                targetEndpoint: endpoint,
                distance: distance,
                resolvedDistance: resolvedDistance,
                owner: owner
            )
            return SketchCurveSplitResult(
                outer: .arc(split.outer),
                corner: .arc(split.corner),
                targetEndpointIsStart: split.targetEndpointIsStart
            )
        case (.point, _),
             (.circle, _),
             (.spline, _),
             (.line, .arc),
             (.arc, .line):
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line or arc endpoint that matches the selected curve."
            )
        }
    }

    private func splitReferences(
        endpoint: SketchCurveEndpoint,
        cornerID: SketchEntityID,
        split: SketchCurveSplitResult
    ) -> (
        outerSplit: SketchReference,
        cornerSplit: SketchReference,
        cornerVertex: SketchReference
    ) {
        switch endpoint {
        case .line(let lineEndpoint):
            if split.targetEndpointIsStart {
                return (
                    outerSplit: .lineStart(lineEndpoint.entityID),
                    cornerSplit: .lineEnd(cornerID),
                    cornerVertex: .lineStart(cornerID)
                )
            }
            return (
                outerSplit: .lineEnd(lineEndpoint.entityID),
                cornerSplit: .lineStart(cornerID),
                cornerVertex: .lineEnd(cornerID)
            )
        case .arc(let arcEndpoint):
            if split.targetEndpointIsStart {
                return (
                    outerSplit: .arcStart(arcEndpoint.entityID),
                    cornerSplit: .arcEnd(cornerID),
                    cornerVertex: .arcStart(cornerID)
                )
            }
            return (
                outerSplit: .arcEnd(arcEndpoint.entityID),
                cornerSplit: .arcStart(cornerID),
                cornerVertex: .arcEnd(cornerID)
            )
        }
    }

    private func offsetVertexConstraints(
        from constraints: [SketchConstraint],
        selectedReference: SketchReference,
        adjacentReference: SketchReference,
        selectedEndpoint: SketchCurveEndpoint,
        adjacentEndpoint: SketchCurveEndpoint,
        selectedCornerID: SketchEntityID,
        adjacentCornerID: SketchEntityID,
        selectedSplit: SketchCurveSplitResult,
        adjacentSplit: SketchCurveSplitResult
    ) -> [SketchConstraint] {
        var updated: [SketchConstraint] = []
        for constraint in constraints {
            switch constraint {
            case .coincident(let first, let second):
                if first == selectedReference ||
                    first == adjacentReference ||
                    second == selectedReference ||
                    second == adjacentReference {
                    continue
                }
                updated.append(constraint)
            case .horizontal(let entityID):
                updated.append(constraint)
                if entityID == selectedEndpoint.entityID,
                   case .line = selectedEndpoint {
                    updated.append(.horizontal(selectedCornerID))
                } else if entityID == adjacentEndpoint.entityID,
                          case .line = adjacentEndpoint {
                    updated.append(.horizontal(adjacentCornerID))
                }
            case .vertical(let entityID):
                updated.append(constraint)
                if entityID == selectedEndpoint.entityID,
                   case .line = selectedEndpoint {
                    updated.append(.vertical(selectedCornerID))
                } else if entityID == adjacentEndpoint.entityID,
                          case .line = adjacentEndpoint {
                    updated.append(.vertical(adjacentCornerID))
                }
            case .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                updated.append(constraint)
            }
        }

        let selectedReferences = splitReferences(
            endpoint: selectedEndpoint,
            cornerID: selectedCornerID,
            split: selectedSplit
        )
        let adjacentReferences = splitReferences(
            endpoint: adjacentEndpoint,
            cornerID: adjacentCornerID,
            split: adjacentSplit
        )
        updated.append(.coincident(selectedReferences.outerSplit, selectedReferences.cornerSplit))
        updated.append(.coincident(selectedReferences.cornerVertex, adjacentReferences.cornerVertex))
        updated.append(.coincident(adjacentReferences.cornerSplit, adjacentReferences.outerSplit))
        return updated
    }

    private func dimensionsAfterSketchVertexOffset(
        _ dimensions: [SketchDimension],
        affectedEntityIDs: Set<SketchEntityID>,
        selectedEndpoint: SketchCurveEndpoint,
        adjacentEndpoint: SketchCurveEndpoint,
        selectedCornerID: SketchEntityID,
        adjacentCornerID: SketchEntityID,
        selectedSplit: SketchCurveSplitResult,
        adjacentSplit: SketchCurveSplitResult,
        in sketch: Sketch
    ) throws -> [SketchDimension] {
        let selectedReferences = splitReferences(
            endpoint: selectedEndpoint,
            cornerID: selectedCornerID,
            split: selectedSplit
        )
        let adjacentReferences = splitReferences(
            endpoint: adjacentEndpoint,
            cornerID: adjacentCornerID,
            split: adjacentSplit
        )
        return try dimensions.map { dimension in
            guard dimensionReferencesAny(dimension, entityIDs: affectedEntityIDs) else {
                return dimension
            }
            let rewritten = try sketchDimensionAfterVertexOffset(
                dimension,
                selectedReference: selectedEndpoint.reference,
                selectedCornerVertex: selectedReferences.cornerVertex,
                adjacentReference: adjacentEndpoint.reference,
                adjacentCornerVertex: adjacentReferences.cornerVertex
            )
            try validateSketchVertexOffsetDimensionMigration(
                original: dimension,
                rewritten: rewritten,
                in: sketch
            )
            return try refreshedSketchDimension(
                rewritten,
                in: sketch,
                owner: "Sketch vertex offset dimension migration"
            )
        }
    }

    private func sketchDimensionAfterVertexOffset(
        _ dimension: SketchDimension,
        selectedReference: SketchReference,
        selectedCornerVertex: SketchReference,
        adjacentReference: SketchReference,
        adjacentCornerVertex: SketchReference
    ) throws -> SketchDimension {
        switch dimension {
        case .distance(let from, let to, let value):
            return .distance(
                from: sketchReferenceAfterVertexOffset(
                    from,
                    selectedReference: selectedReference,
                    selectedCornerVertex: selectedCornerVertex,
                    adjacentReference: adjacentReference,
                    adjacentCornerVertex: adjacentCornerVertex
                ),
                to: sketchReferenceAfterVertexOffset(
                    to,
                    selectedReference: selectedReference,
                    selectedCornerVertex: selectedCornerVertex,
                    adjacentReference: adjacentReference,
                    adjacentCornerVertex: adjacentCornerVertex
                ),
                value: value
            )
        case .angle(let from, let to, let value):
            let rewrittenFrom = sketchReferenceAfterVertexOffset(
                from,
                selectedReference: selectedReference,
                selectedCornerVertex: selectedCornerVertex,
                adjacentReference: adjacentReference,
                adjacentCornerVertex: adjacentCornerVertex
            )
            let rewrittenTo = sketchReferenceAfterVertexOffset(
                to,
                selectedReference: selectedReference,
                selectedCornerVertex: selectedCornerVertex,
                adjacentReference: adjacentReference,
                adjacentCornerVertex: adjacentCornerVertex
            )
            return .angle(from: rewrittenFrom, to: rewrittenTo, value: value)
        case .radius,
             .diameter:
            return dimension
        }
    }

    private func sketchReferenceAfterVertexOffset(
        _ reference: SketchReference,
        selectedReference: SketchReference,
        selectedCornerVertex: SketchReference,
        adjacentReference: SketchReference,
        adjacentCornerVertex: SketchReference
    ) -> SketchReference {
        if reference == selectedReference {
            return selectedCornerVertex
        }
        if reference == adjacentReference {
            return adjacentCornerVertex
        }
        return reference
    }

    private func validateSketchVertexOffsetDimensionMigration(
        original: SketchDimension,
        rewritten: SketchDimension,
        in sketch: Sketch
    ) throws {
        guard case .angle(let originalFrom, let originalTo, _) = original,
              case .angle(let rewrittenFrom, let rewrittenTo, _) = rewritten,
              sketchReferencesSingleArcSpan(originalFrom, originalTo),
              sketchReferencesSingleArcSpan(rewrittenFrom, rewrittenTo) == false else {
            return
        }
        guard try measuredSketchArcSpanAngle(
            from: rewrittenFrom,
            to: rewrittenTo,
            in: sketch,
            owner: "Sketch vertex offset dimension migration"
        ) != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch vertex offset cannot preserve arc span angle dimensions across disconnected split arcs."
            )
        }
    }

    private func sketchReferencesSingleArcSpan(
        _ first: SketchReference,
        _ second: SketchReference
    ) -> Bool {
        switch (first, second) {
        case (.arcStart(let firstID), .arcEnd(let secondID)),
             (.arcEnd(let firstID), .arcStart(let secondID)):
            return firstID == secondID
        default:
            return false
        }
    }

    private func validateSketchVertexOffsetConstraints(
        _ sketch: Sketch,
        affectedEntityIDs: Set<SketchEntityID>
    ) throws {
        for constraint in sketch.constraints {
            switch constraint {
            case .coincident,
                 .horizontal,
                 .vertical:
                continue
            case .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                if constraintReferencesAny(constraint, entityIDs: affectedEntityIDs) {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Sketch vertex offset currently preserves only coincident and horizontal/vertical line constraints on affected line/arc vertices."
                    )
                }
            }
        }
    }
}
