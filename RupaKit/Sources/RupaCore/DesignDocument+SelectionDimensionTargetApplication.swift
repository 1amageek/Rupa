import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    mutating func applyObjectFaceDistanceDimension(
        dimension: SelectionDimension,
        context: SelectionDimensionObjectFaceDistanceContext,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let targetDistance = try resolvedLength(
            dimension.target,
            owner: "Selection face-distance application target"
        )
        guard targetDistance > selectionDimensionEndpointTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection face-distance application target must be positive."
            )
        }

        try setObjectDimension(
            target: context.target,
            kind: context.kind,
            value: dimension.target,
            objectRegistry: objectRegistry
        )
    }

    func sourceObjectFaceDistanceDimensionContextIfPresent(
        for dimension: SelectionDimension,
        objectRegistry: ObjectTypeRegistry
    ) throws -> SelectionDimensionObjectFaceDistanceContext? {
        guard case .topology(let firstName) = dimension.first,
              case .topology(let secondName) = dimension.second else {
            return nil
        }
        let topology = try TopologySummaryService().summarize(
            document: self,
            objectRegistry: objectRegistry
        )
        guard
            let firstTarget = try generatedFaceTargetIfPresent(
                for: firstName,
                in: topology,
                owner: "Selection face-distance application"
            ),
            let secondTarget = try generatedFaceTargetIfPresent(
                for: secondName,
                in: topology,
                owner: "Selection face-distance application"
            )
        else {
            return nil
        }
        guard let dimension = try ObjectFaceDimensionResolver().resolvePairIfPresent(
            first: firstTarget,
            second: secondTarget,
            in: self,
            objectRegistry: objectRegistry,
            topology: topology,
            operationName: "Selection face-distance application"
        ) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection face-distance application requires generated face targets."
            )
        }
        return SelectionDimensionObjectFaceDistanceContext(
            target: dimension.target,
            kind: dimension.kind
        )
    }

    func generatedFaceTargetIfPresent(
        for name: PersistentName,
        in topology: TopologySummaryResult,
        owner: String
    ) throws -> SelectionTarget? {
        let persistentName = persistentNameString(name)
        guard let entry = topology.entries.first(where: { $0.persistentName == persistentName }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) generated topology target was not found in the current topology."
            )
        }
        guard entry.kind == .face else {
            return nil
        }
        guard let target = entry.selectionTarget(),
              case .face = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires generated face selection targets."
            )
        }
        return target
    }

    mutating func applySourcePointDistanceDimension(
        id: SelectionDimensionID,
        dimension: SelectionDimension,
        context: SelectionDimensionSourcePointDistanceContext,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let targetDistance = try resolvedLength(
            dimension.target,
            owner: "Selection point distance application target"
        )
        guard targetDistance >= 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point distance application target must not be negative."
            )
        }

        let firstPoint = try sourcePoint(context.first)
        let secondPoint = try sourcePoint(context.second)
        let currentDeltaX = firstPoint.x - secondPoint.x
        let currentDeltaY = firstPoint.y - secondPoint.y
        let currentDistance = hypot(currentDeltaX, currentDeltaY)
        if currentDistance <= selectionDimensionEndpointTolerance {
            guard targetDistance <= selectionDimensionEndpointTolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection point distance application requires a non-zero current point distance to preserve direction."
                )
            }
            try refreshSourcePointDistanceReferences(id: id, context: context)
            return
        }

        let movePlan = try sourcePointDistanceMovePlan(for: context)
        if isArcEndpointRole(movePlan.moving.role) {
            try applySourceArcEndpointPointDistanceDimension(
                id: id,
                targetDistance: targetDistance,
                moving: movePlan.moving,
                anchor: movePlan.anchor,
                refreshContext: context,
                objectRegistry: objectRegistry
            )
            return
        }

        let movingPoint = try sourcePoint(movePlan.moving)
        let anchorPoint = try sourcePoint(movePlan.anchor)
        let movingDeltaX = movingPoint.x - anchorPoint.x
        let movingDeltaY = movingPoint.y - anchorPoint.y

        let scale = targetDistance / currentDistance
        let targetPoint = Point2D(
            x: anchorPoint.x + movingDeltaX * scale,
            y: anchorPoint.y + movingDeltaY * scale
        )
        let deltaX = targetPoint.x - movingPoint.x
        let deltaY = targetPoint.y - movingPoint.y
        guard deltaX.isFinite, deltaY.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point distance application produced a non-finite movement delta."
            )
        }

        if abs(deltaX) > selectionDimensionEndpointTolerance ||
            abs(deltaY) > selectionDimensionEndpointTolerance {
            try moveSourcePoint(
                movePlan.moving,
                deltaX: .length(deltaX, .meter),
                deltaY: .length(deltaY, .meter),
                objectRegistry: objectRegistry
            )
        }
        try refreshSourcePointDistanceReferences(id: id, context: context)
    }

    mutating func applySourcePointLineDistanceDimension(
        id: SelectionDimensionID,
        dimension: SelectionDimension,
        context: SelectionDimensionSourcePointLineDistanceContext,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let targetDistance = try resolvedLength(
            dimension.target,
            owner: "Selection point-line distance application target"
        )
        guard targetDistance >= 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point-line distance application target must not be negative."
            )
        }

        let point = try sourcePoint(context.point)
        let line = try sourceLineDistanceGeometry(context.line)
        let projection = try projectedPointOnSourceLine(point, line: line)
        let currentDistance = hypot(projection.deltaX, projection.deltaY)
        if abs(currentDistance - targetDistance) <= selectionDimensionEndpointTolerance {
            try refreshSourcePointLineDistanceReferences(id: id, context: context)
            return
        }
        let unitNormal: Point2D
        if currentDistance > selectionDimensionEndpointTolerance {
            unitNormal = Point2D(
                x: projection.deltaX / currentDistance,
                y: projection.deltaY / currentDistance
            )
        } else {
            unitNormal = Point2D(
                x: -projection.lineUnitY,
                y: projection.lineUnitX
            )
        }

        if try isSourcePointAnchored(context.point) == false {
            let targetPoint = Point2D(
                x: projection.closest.x + unitNormal.x * targetDistance,
                y: projection.closest.y + unitNormal.y * targetDistance
            )
            let deltaX = targetPoint.x - point.x
            let deltaY = targetPoint.y - point.y
            guard deltaX.isFinite, deltaY.isFinite else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection point-line distance application produced a non-finite movement delta."
                )
            }

            if abs(deltaX) > selectionDimensionEndpointTolerance ||
                abs(deltaY) > selectionDimensionEndpointTolerance {
                try moveSourcePoint(
                    context.point,
                    deltaX: .length(deltaX, .meter),
                    deltaY: .length(deltaY, .meter),
                    objectRegistry: objectRegistry
                )
            }
            try refreshSourcePointLineDistanceReferences(id: id, context: context)
            return
        }

        let lineDeltaX = unitNormal.x * (currentDistance - targetDistance)
        let lineDeltaY = unitNormal.y * (currentDistance - targetDistance)
        guard lineDeltaX.isFinite, lineDeltaY.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point-line distance application produced a non-finite line translation delta."
            )
        }
        if abs(lineDeltaX) > selectionDimensionEndpointTolerance ||
            abs(lineDeltaY) > selectionDimensionEndpointTolerance {
            try translateSketchLine(
                target: context.line.target,
                deltaX: .length(lineDeltaX, .meter),
                deltaY: .length(lineDeltaY, .meter),
                objectRegistry: objectRegistry
            )
        }
        try refreshSourcePointLineDistanceReferences(id: id, context: context)
    }

    mutating func refreshSourcePointDistanceReferences(
        id: SelectionDimensionID,
        context: SelectionDimensionSourcePointDistanceContext
    ) throws {
        guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection point distance application lost the source selection dimension."
            )
        }
        cadDocument.selectionDimensions[updatedDimensionIndex].first = try selectionReference(point: context.first)
        cadDocument.selectionDimensions[updatedDimensionIndex].second = try selectionReference(point: context.second)
    }

    mutating func refreshSourcePointLineDistanceReferences(
        id: SelectionDimensionID,
        context: SelectionDimensionSourcePointLineDistanceContext
    ) throws {
        guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection point-line distance application lost the source selection dimension."
            )
        }
        let pointReference = try selectionReference(point: context.point)
        let lineReference = SelectionReference.curve(.whole(context.line.curve))
        if context.pointIsFirst {
            cadDocument.selectionDimensions[updatedDimensionIndex].first = pointReference
            cadDocument.selectionDimensions[updatedDimensionIndex].second = lineReference
        } else {
            cadDocument.selectionDimensions[updatedDimensionIndex].first = lineReference
            cadDocument.selectionDimensions[updatedDimensionIndex].second = pointReference
        }
    }

    mutating func applySourceArcEndpointPointDistanceDimension(
        id: SelectionDimensionID,
        targetDistance: Double,
        moving: SelectionDimensionSourcePointContext,
        anchor: SelectionDimensionSourcePointContext,
        refreshContext: SelectionDimensionSourcePointDistanceContext,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let arc = try sourceArc(
            for: moving,
            owner: "Selection arc endpoint distance application"
        )
        let center = try resolvedPoint(
            arc.center,
            owner: "Selection arc endpoint distance application center"
        )
        let radius = try resolvedLength(
            arc.radius,
            owner: "Selection arc endpoint distance application radius"
        )
        let endpointRole: SelectionDimensionCurveEndpointRole
        switch moving.role {
        case .handle(.arcStart):
            endpointRole = .start
        case .handle(.arcEnd):
            endpointRole = .end
        case .handle(.point),
             .handle(.lineStart),
             .handle(.lineEnd),
             .handle(.circleCenter),
             .handle(.arcCenter),
             .splineControlPoint:
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc endpoint distance application requires an arc endpoint as the moving source point."
            )
        }
        let currentPoint = try sourceArcEndpointPoint(
            arc,
            endpoint: endpointRole,
            owner: "Selection arc endpoint distance application current endpoint"
        )
        let anchorPoint = try sourcePoint(anchor)
        let targetPoint = try sourceArcEndpointTargetPoint(
            center: center,
            radius: radius,
            anchor: anchorPoint,
            targetDistance: targetDistance,
            currentPoint: currentPoint
        )
        let deltaX = targetPoint.x - currentPoint.x
        let deltaY = targetPoint.y - currentPoint.y
        guard deltaX.isFinite, deltaY.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc endpoint distance application produced a non-finite movement delta."
            )
        }

        if abs(deltaX) > selectionDimensionEndpointTolerance ||
            abs(deltaY) > selectionDimensionEndpointTolerance {
            try moveSourcePoint(
                moving,
                deltaX: .length(deltaX, .meter),
                deltaY: .length(deltaY, .meter),
                objectRegistry: objectRegistry
            )
        }
        try refreshSourcePointDistanceReferences(id: id, context: refreshContext)
    }
}
