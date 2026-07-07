import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func moveSketchEntityPoint(
        target: SelectionTarget,
        handle: SketchEntityPointHandle,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let deltaXMeters = try resolvedLengthValue(deltaX, owner: "Sketch point move delta X")
        let deltaYMeters = try resolvedLengthValue(deltaY, owner: "Sketch point move delta Y")
        guard abs(deltaXMeters) > 1.0e-12 || abs(deltaYMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch point move delta must not be zero."
            )
        }

        let selection = try editableSketchEntity(for: target, operationName: "Sketch point move")
        var feature = selection.feature
        var sketch = selection.sketch
        let movedReference = try sketchPointReference(
            entityID: selection.entityID,
            entity: selection.entity,
            handle: handle,
            operationName: "Sketch point move"
        )
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        try pointPropagator.validateCanMove(
            movedReference,
            in: sketch,
            owner: "Sketch point move"
        )
        let updatedEntity: SketchEntity
        switch selection.entity {
        case .point(let point):
            guard handle == .point else {
                throw incompatibleSketchPointHandle(handle, entityKind: "point", operationName: "Sketch point move")
            }
            let movedPoint = translatedSketchPoint(
                point,
                deltaX: deltaX,
                deltaY: deltaY,
                deltaXMeters: deltaXMeters,
                deltaYMeters: deltaYMeters
            )
            _ = try resolvedLengthValue(movedPoint.x, owner: "Sketch point x")
            _ = try resolvedLengthValue(movedPoint.y, owner: "Sketch point y")
            updatedEntity = .point(movedPoint)
        case .line(var line):
            switch handle {
            case .lineStart:
                line.start = translatedSketchPoint(
                    line.start,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    deltaXMeters: deltaXMeters,
                    deltaYMeters: deltaYMeters
                )
            case .lineEnd:
                line.end = translatedSketchPoint(
                    line.end,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    deltaXMeters: deltaXMeters,
                    deltaYMeters: deltaYMeters
                )
            case .point, .circleCenter, .arcCenter, .arcStart, .arcEnd:
                throw incompatibleSketchPointHandle(handle, entityKind: "line", operationName: "Sketch point move")
            }
            _ = try resolvedLineMetrics(line, owner: "Sketch line")
            updatedEntity = .line(line)
        case .circle(var circle):
            guard handle == .circleCenter else {
                throw incompatibleSketchPointHandle(handle, entityKind: "circle", operationName: "Sketch point move")
            }
            circle.center = translatedSketchPoint(
                circle.center,
                deltaX: deltaX,
                deltaY: deltaY,
                deltaXMeters: deltaXMeters,
                deltaYMeters: deltaYMeters
            )
            _ = try resolvedLengthValue(circle.center.x, owner: "Sketch circle center x")
            _ = try resolvedLengthValue(circle.center.y, owner: "Sketch circle center y")
            _ = try resolvedPositiveLengthValue(circle.radius, owner: "Sketch circle radius")
            updatedEntity = .circle(circle)
        case .arc(var arc):
            switch handle {
            case .arcCenter:
                arc.center = translatedSketchPoint(
                    arc.center,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    deltaXMeters: deltaXMeters,
                    deltaYMeters: deltaYMeters
                )
            case .arcStart:
                arc.startAngle = try movedArcEndpointAngle(
                    arc,
                    endpointAngle: arc.startAngle,
                    deltaXMeters: deltaXMeters,
                    deltaYMeters: deltaYMeters,
                    owner: "Sketch arc start move"
                )
            case .arcEnd:
                arc.endAngle = try movedArcEndpointAngle(
                    arc,
                    endpointAngle: arc.endAngle,
                    deltaXMeters: deltaXMeters,
                    deltaYMeters: deltaYMeters,
                    owner: "Sketch arc end move"
                )
            case .point, .lineStart, .lineEnd, .circleCenter:
                throw incompatibleSketchPointHandle(handle, entityKind: "arc", operationName: "Sketch point move")
            }
            try validateArc(arc, owner: "Sketch arc")
            updatedEntity = .arc(arc)
        case .spline:
            throw incompatibleSketchPointHandle(handle, entityKind: "spline", operationName: "Sketch point move")
        }

        sketch.entities[selection.entityID] = updatedEntity
        try pointPropagator.propagate(
            from: movedReference,
            in: &sketch,
            owner: "Sketch point move"
        )
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch point move"
        )
    }

    mutating func translateSketchLine(
        target: SelectionTarget,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let deltaXMeters = try resolvedLengthValue(deltaX, owner: "Sketch line translation delta X")
        let deltaYMeters = try resolvedLengthValue(deltaY, owner: "Sketch line translation delta Y")
        guard abs(deltaXMeters) > 1.0e-12 || abs(deltaYMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line translation delta must not be zero."
            )
        }

        let selection = try editableSketchEntity(for: target, operationName: "Sketch line translation")
        guard case .line(var line) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line translation requires a line entity."
            )
        }
        var feature = selection.feature
        var sketch = selection.sketch
        let startReference = SketchReference.lineStart(selection.entityID)
        let endReference = SketchReference.lineEnd(selection.entityID)
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        try pointPropagator.validateCanMove(
            startReference,
            in: sketch,
            owner: "Sketch line translation"
        )
        try pointPropagator.validateCanMove(
            endReference,
            in: sketch,
            owner: "Sketch line translation"
        )

        line.start = translatedSketchPoint(
            line.start,
            deltaX: deltaX,
            deltaY: deltaY,
            deltaXMeters: deltaXMeters,
            deltaYMeters: deltaYMeters
        )
        line.end = translatedSketchPoint(
            line.end,
            deltaX: deltaX,
            deltaY: deltaY,
            deltaXMeters: deltaXMeters,
            deltaYMeters: deltaYMeters
        )
        _ = try resolvedLineMetrics(line, owner: "Sketch line")
        sketch.entities[selection.entityID] = .line(line)
        try pointPropagator.propagate(
            from: startReference,
            in: &sketch,
            owner: "Sketch line translation"
        )
        try pointPropagator.propagate(
            from: endReference,
            in: &sketch,
            owner: "Sketch line translation"
        )
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch line translation"
        )
    }

    public mutating func moveSketchSplineControlPoint(
        target: SelectionTarget,
        controlPointIndex: Int,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let deltaXMeters = try resolvedLengthValue(deltaX, owner: "Sketch spline control point move delta X")
        let deltaYMeters = try resolvedLengthValue(deltaY, owner: "Sketch spline control point move delta Y")
        guard abs(deltaXMeters) > 1.0e-12 || abs(deltaYMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point move delta must not be zero."
            )
        }
        guard controlPointIndex >= 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point index must not be negative."
            )
        }

        let selection = try editableSketchEntity(for: target, operationName: "Sketch spline control point move")
        guard case .spline(var spline) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point move requires a spline entity."
            )
        }
        guard spline.controlPoints.indices.contains(controlPointIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch spline control point move requires an existing control point."
            )
        }
        let movedReference = SketchReference.splineControlPoint(
            entity: selection.entityID,
            index: controlPointIndex
        )
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        try pointPropagator.validateCanMove(
            movedReference,
            in: selection.sketch,
            owner: "Sketch spline control point move"
        )

        var feature = selection.feature
        var sketch = selection.sketch
        spline.controlPoints[controlPointIndex] = translatedSketchPoint(
            spline.controlPoints[controlPointIndex],
            deltaX: deltaX,
            deltaY: deltaY,
            deltaXMeters: deltaXMeters,
            deltaYMeters: deltaYMeters
        )
        try validateSpline(spline, owner: "Sketch spline")
        sketch.entities[selection.entityID] = .spline(spline)
        try pointPropagator.propagate(
            from: movedReference,
            in: &sketch,
            owner: "Sketch spline control point move"
        )
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch spline control point move"
        )
    }

    public mutating func slideSketchSplineControlPoints(
        target: SelectionTarget,
        controlPointIndexes: [Int],
        direction: SplineControlPointSlideDirection,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let distanceMeters = try resolvedLengthValue(distance, owner: "Sketch spline control point slide distance")
        guard abs(distanceMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point slide distance must not be zero."
            )
        }
        guard controlPointIndexes.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point slide requires at least one control point index."
            )
        }
        guard controlPointIndexes.allSatisfy({ $0 >= 0 }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point indexes must not contain negative values."
            )
        }
        guard Set(controlPointIndexes).count == controlPointIndexes.count else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point slide requires unique control point indexes."
            )
        }

        let selection = try editableSketchEntity(for: target, operationName: "Sketch spline control point slide")
        guard case .spline(var spline) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point slide requires a spline entity."
            )
        }
        guard controlPointIndexes.allSatisfy({ spline.controlPoints.indices.contains($0) }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch spline control point slide requires existing control points."
            )
        }
        let slideDirections = try controlPointIndexes.map { index in
            try splineControlPointSlideDirection(
                in: spline,
                controlPointIndex: index,
                direction: direction,
                owner: "Sketch spline control point slide"
            )
        }
        let movedReferences = controlPointIndexes.map { index in
            SketchReference.splineControlPoint(
                entity: selection.entityID,
                index: index
            )
        }
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        for reference in movedReferences {
            try pointPropagator.validateCanMove(
                reference,
                in: selection.sketch,
                owner: "Sketch spline control point slide"
            )
        }

        var feature = selection.feature
        var sketch = selection.sketch
        for (index, slideDirection) in zip(controlPointIndexes, slideDirections) {
            spline.controlPoints[index] = translatedSketchPoint(
                spline.controlPoints[index],
                directionX: slideDirection.x,
                directionY: slideDirection.y,
                distance: distance
            )
        }
        try validateSpline(spline, owner: "Sketch spline")
        sketch.entities[selection.entityID] = .spline(spline)
        for reference in movedReferences {
            try pointPropagator.propagate(
                from: reference,
                in: &sketch,
                owner: "Sketch spline control point slide"
            )
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch spline control point slide"
        )
    }

    private func splineControlPointSlideDirection(
        in spline: SketchSpline,
        controlPointIndex: Int,
        direction: SplineControlPointSlideDirection,
        owner: String
    ) throws -> (x: Double, y: Double) {
        let positiveU = try splineControlPointPositiveUDirection(
            in: spline,
            controlPointIndex: controlPointIndex,
            owner: owner
        )
        switch direction {
        case .positiveU:
            return positiveU
        case .negativeU:
            return (x: -positiveU.x, y: -positiveU.y)
        case .normal:
            return (x: -positiveU.y, y: positiveU.x)
        }
    }

    private func splineControlPointPositiveUDirection(
        in spline: SketchSpline,
        controlPointIndex: Int,
        owner: String
    ) throws -> (x: Double, y: Double) {
        let controlPoints = spline.controlPoints
        guard controlPoints.count >= 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires at least two control points."
            )
        }
        if controlPointIndex == controlPoints.startIndex {
            return try normalizedDirection(
                from: controlPoints[controlPointIndex],
                to: controlPoints[controlPointIndex + 1],
                owner: "\(owner) control-cage U"
            )
        }
        if controlPointIndex == controlPoints.index(before: controlPoints.endIndex) {
            return try normalizedDirection(
                from: controlPoints[controlPointIndex - 1],
                to: controlPoints[controlPointIndex],
                owner: "\(owner) control-cage U"
            )
        }
        return try normalizedDirection(
            from: controlPoints[controlPointIndex - 1],
            to: controlPoints[controlPointIndex + 1],
            owner: "\(owner) control-cage U"
        )
    }

    func translatedSketchPoint(
        _ point: SketchPoint,
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaXMeters: Double,
        deltaYMeters: Double
    ) -> SketchPoint {
        SketchPoint(
            x: translatedExpression(point.x, delta: deltaX, resolvedDelta: deltaXMeters),
            y: translatedExpression(point.y, delta: deltaY, resolvedDelta: deltaYMeters)
        )
    }

    private func movedArcEndpointAngle(
        _ arc: SketchArc,
        endpointAngle: CADExpression,
        deltaXMeters: Double,
        deltaYMeters: Double,
        owner: String
    ) throws -> CADExpression {
        let center = try resolvedSketchMovementPoint(arc.center, owner: "\(owner) center")
        let endpoint = try pointOnArc(arc, angle: endpointAngle, owner: owner)
        let movedX = endpoint.x + deltaXMeters
        let movedY = endpoint.y + deltaYMeters
        let deltaFromCenterX = movedX - center.x
        let deltaFromCenterY = movedY - center.y
        guard sqrt(deltaFromCenterX * deltaFromCenterX + deltaFromCenterY * deltaFromCenterY) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot move an arc endpoint onto the arc center."
            )
        }
        return .angle(atan2(deltaFromCenterY, deltaFromCenterX), .radian)
    }

    func translatedExpression(
        _ expression: CADExpression,
        delta: CADExpression,
        resolvedDelta: Double
    ) -> CADExpression {
        guard abs(resolvedDelta) > 1.0e-12 else {
            return expression
        }
        return .add(expression, delta)
    }

    private func incompatibleSketchPointHandle(
        _ handle: SketchEntityPointHandle,
        entityKind: String,
        operationName: String
    ) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "\(operationName) handle \(handle.rawValue) is not compatible with a \(entityKind) entity."
        )
    }

    func sketchPointReference(
        entityID: SketchEntityID,
        entity: SketchEntity,
        handle: SketchEntityPointHandle,
        operationName: String
    ) throws -> SketchReference {
        switch entity {
        case .point:
            guard handle == .point else {
                throw incompatibleSketchPointHandle(handle, entityKind: "point", operationName: operationName)
            }
            return .entity(entityID)
        case .line:
            switch handle {
            case .lineStart:
                return .lineStart(entityID)
            case .lineEnd:
                return .lineEnd(entityID)
            case .point, .circleCenter, .arcCenter, .arcStart, .arcEnd:
                throw incompatibleSketchPointHandle(handle, entityKind: "line", operationName: operationName)
            }
        case .circle:
            guard handle == .circleCenter else {
                throw incompatibleSketchPointHandle(handle, entityKind: "circle", operationName: operationName)
            }
            return .circleCenter(entityID)
        case .arc:
            switch handle {
            case .arcCenter:
                return .arcCenter(entityID)
            case .arcStart:
                return .arcStart(entityID)
            case .arcEnd:
                return .arcEnd(entityID)
            case .point, .lineStart, .lineEnd, .circleCenter:
                throw incompatibleSketchPointHandle(handle, entityKind: "arc", operationName: operationName)
            }
        case .spline:
            throw incompatibleSketchPointHandle(handle, entityKind: "spline", operationName: operationName)
        }
    }

    private func resolvedSketchMovementPoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        (
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }
}
