import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func sourceLineLength(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) throws -> Double {
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              case let .line(line) = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension application requires an existing source line."
            )
        }
        let start = try resolvedPoint(line.start, owner: "Selection dimension application line start")
        let end = try resolvedPoint(line.end, owner: "Selection dimension application line end")
        let dx = end.x - start.x
        let dy = end.y - start.y
        return (dx * dx + dy * dy).squareRoot()
    }

    func sourceLineDistanceGeometry(
        _ context: SelectionDimensionSourceLineDistanceLineContext
    ) throws -> SelectionDimensionSourceLineDistanceGeometry {
        guard let feature = cadDocument.designGraph.nodes[context.featureID],
              case let .sketch(sketch) = feature.operation,
              case let .line(line) = sketch.entities[context.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection point-line distance application requires an existing source line."
            )
        }
        let start = try resolvedPoint(line.start, owner: "Selection point-line distance line start")
        let end = try resolvedPoint(line.end, owner: "Selection point-line distance line end")
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > selectionDimensionEndpointTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point-line distance application requires a non-degenerate source line."
            )
        }
        return SelectionDimensionSourceLineDistanceGeometry(
            start: start,
            end: end,
            length: length
        )
    }

    func projectedPointOnSourceLine(
        _ point: Point2D,
        line: SelectionDimensionSourceLineDistanceGeometry
    ) throws -> SelectionDimensionSourceLineProjection {
        let unitX = (line.end.x - line.start.x) / line.length
        let unitY = (line.end.y - line.start.y) / line.length
        let rawParameter = (point.x - line.start.x) * unitX + (point.y - line.start.y) * unitY
        let clampedParameter = min(max(rawParameter, 0.0), line.length)
        let closest = Point2D(
            x: line.start.x + unitX * clampedParameter,
            y: line.start.y + unitY * clampedParameter
        )
        let deltaX = point.x - closest.x
        let deltaY = point.y - closest.y
        guard deltaX.isFinite, deltaY.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point-line distance application produced a non-finite projection."
            )
        }
        return SelectionDimensionSourceLineProjection(
            closest: closest,
            deltaX: deltaX,
            deltaY: deltaY,
            lineUnitX: unitX,
            lineUnitY: unitY
        )
    }

    func sourceLineAngleContext(
        curve: CurveOutputReference
    ) throws -> SourceLineAngleContext {
        let featureID = curve.featureID
        let entityID = try sourceCurveEntityID(
            featureID: featureID,
            curveIndex: curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              case let .line(line) = sketch.entities[entityID] else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection line angle application currently supports source line references only."
            )
        }
        let start = try resolvedPoint(line.start, owner: "Selection line angle application line start")
        let end = try resolvedPoint(line.end, owner: "Selection line angle application line end")
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx.isFinite, dy.isFinite, hypot(dx, dy) > selectionDimensionEndpointTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection line angle application requires non-degenerate source lines."
            )
        }
        return SourceLineAngleContext(
            featureID: featureID,
            entityID: entityID,
            plane: sketch.plane,
            target: try sourceSketchEntityTarget(featureID: featureID, entityID: entityID),
            angle: atan2(dy, dx)
        )
    }

    func sourcePoint(
        _ context: SelectionDimensionSourcePointContext
    ) throws -> Point2D {
        guard let feature = cadDocument.designGraph.nodes[context.featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[context.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection point distance application requires an existing source sketch point."
            )
        }
        switch context.role {
        case .handle(let handle):
            switch (handle, entity) {
            case (.lineStart, .line(let line)):
                return try resolvedPoint(line.start, owner: "Selection point distance line start")
            case (.lineEnd, .line(let line)):
                return try resolvedPoint(line.end, owner: "Selection point distance line end")
            case (.circleCenter, .circle(let circle)):
                return try resolvedPoint(circle.center, owner: "Selection point distance circle center")
            case (.arcCenter, .arc(let arc)):
                return try resolvedPoint(arc.center, owner: "Selection point distance arc center")
            case (.arcStart, .arc(let arc)):
                return try sourceArcEndpointPoint(
                    arc,
                    endpoint: .start,
                    owner: "Selection point distance arc start"
                )
            case (.arcEnd, .arc(let arc)):
                return try sourceArcEndpointPoint(
                    arc,
                    endpoint: .end,
                    owner: "Selection point distance arc end"
                )
            case (.point, .point(let point)):
                return try resolvedPoint(point, owner: "Selection point distance point")
            default:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection point distance application source point handle no longer matches the source entity."
                )
            }
        case .splineControlPoint(let index):
            guard case .spline(let spline) = entity,
                  spline.controlPoints.indices.contains(index) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection point distance application source spline control point no longer matches the source entity."
                )
            }
            return try resolvedPoint(
                spline.controlPoints[index],
                owner: "Selection point distance spline control point"
            )
        }
    }

    mutating func moveSourcePoint(
        _ context: SelectionDimensionSourcePointContext,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        switch context.role {
        case .handle(let handle):
            try moveSketchEntityPoint(
                target: context.target,
                handle: handle,
                deltaX: deltaX,
                deltaY: deltaY,
                objectRegistry: objectRegistry
            )
        case .splineControlPoint(let index):
            try moveSketchSplineControlPoint(
                target: context.target,
                controlPointIndex: index,
                deltaX: deltaX,
                deltaY: deltaY,
                objectRegistry: objectRegistry
            )
        }
    }

    func sourceArc(
        for context: SelectionDimensionSourcePointContext,
        owner: String
    ) throws -> SketchArc {
        switch context.role {
        case .handle(.arcStart), .handle(.arcEnd):
            break
        case .handle(.point),
             .handle(.lineStart),
             .handle(.lineEnd),
             .handle(.circleCenter),
             .handle(.arcCenter),
             .splineControlPoint:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires an arc endpoint source point."
            )
        }
        guard let feature = cadDocument.designGraph.nodes[context.featureID],
              case let .sketch(sketch) = feature.operation,
              case let .arc(arc) = sketch.entities[context.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires an existing source arc."
            )
        }
        return arc
    }

    func sourceArcEndpointPoint(
        _ arc: SketchArc,
        endpoint: SelectionDimensionCurveEndpointRole,
        owner: String
    ) throws -> Point2D {
        let center = try resolvedPoint(arc.center, owner: "\(owner) center")
        let radius = try resolvedLength(arc.radius, owner: "\(owner) radius")
        let angle: Double
        switch endpoint {
        case .start:
            angle = try resolvedAngle(arc.startAngle, owner: "\(owner) angle")
        case .end:
            angle = try resolvedAngle(arc.endAngle, owner: "\(owner) angle")
        }
        return Point2D(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    func sourceArcEndpointTargetPoint(
        center: Point2D,
        radius: Double,
        anchor: Point2D,
        targetDistance: Double,
        currentPoint: Point2D
    ) throws -> Point2D {
        guard radius > selectionDimensionEndpointTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc endpoint distance application requires a positive source arc radius."
            )
        }
        let centerToAnchorX = anchor.x - center.x
        let centerToAnchorY = anchor.y - center.y
        let centerToAnchorDistance = hypot(centerToAnchorX, centerToAnchorY)
        if centerToAnchorDistance <= selectionDimensionEndpointTolerance {
            guard abs(targetDistance - radius) <= selectionDimensionEndpointTolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection arc endpoint distance target has no solution on the source arc circle."
                )
            }
            return currentPoint
        }

        let maximumDistance = radius + centerToAnchorDistance
        let minimumDistance = abs(radius - centerToAnchorDistance)
        guard targetDistance <= maximumDistance + selectionDimensionEndpointTolerance,
              targetDistance + selectionDimensionEndpointTolerance >= minimumDistance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc endpoint distance target has no solution on the source arc circle."
            )
        }

        let unitX = centerToAnchorX / centerToAnchorDistance
        let unitY = centerToAnchorY / centerToAnchorDistance
        let along = (
            radius * radius -
                targetDistance * targetDistance +
                centerToAnchorDistance * centerToAnchorDistance
        ) / (2.0 * centerToAnchorDistance)
        let heightSquared = radius * radius - along * along
        guard heightSquared >= -selectionDimensionEndpointTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc endpoint distance target has no finite intersection solution."
            )
        }
        let height = sqrt(max(0.0, heightSquared))
        let base = Point2D(
            x: center.x + along * unitX,
            y: center.y + along * unitY
        )
        let first = Point2D(
            x: base.x - unitY * height,
            y: base.y + unitX * height
        )
        guard height > selectionDimensionEndpointTolerance else {
            return first
        }
        let second = Point2D(
            x: base.x + unitY * height,
            y: base.y - unitX * height
        )
        return squaredDistance(first, currentPoint) <= squaredDistance(second, currentPoint) ? first : second
    }

    func squaredDistance(_ lhs: Point2D, _ rhs: Point2D) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    func isArcEndpointRole(_ role: SelectionDimensionSourcePointRole) -> Bool {
        switch role {
        case .handle(.arcStart), .handle(.arcEnd):
            return true
        case .handle(.point),
             .handle(.lineStart),
             .handle(.lineEnd),
             .handle(.circleCenter),
             .handle(.arcCenter),
             .splineControlPoint:
            return false
        }
    }

    func sourceArcEndpointParameters(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) throws -> SketchArcEndpointParameterResolver.EndpointParameters {
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              case let .arc(arc) = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection arc span application requires an existing source arc."
            )
        }
        return try SketchArcEndpointParameterResolver().endpointParameters(
            for: arc,
            plane: sketch.plane,
            in: self,
            owner: "Selection arc span application"
        )
    }

    func resolvedPoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> Point2D {
        Point2D(
            x: try resolvedLength(point.x, owner: "\(owner) x"),
            y: try resolvedLength(point.y, owner: "\(owner) y")
        )
    }

    func resolvedLength(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let quantity = try cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .length else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a length."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite length."
            )
        }
        return quantity.value
    }

    func resolvedAngle(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let quantity = try cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to an angle."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite angle."
            )
        }
        return quantity.value
    }

    func lineEndpointRole(
        parameter: Double,
        lineLength: Double
    ) throws -> SelectionDimensionLineEndpointRole {
        guard parameter.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application requires finite line endpoint parameters."
            )
        }
        if abs(parameter) <= selectionDimensionEndpointTolerance {
            return .start
        }
        if abs(parameter - lineLength) <= selectionDimensionEndpointTolerance {
            return .end
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Selection dimension application requires current line start and line end references."
        )
    }

    func arcEndpointRole(
        parameter: Double,
        endpointParameters: SketchArcEndpointParameterResolver.EndpointParameters
    ) throws -> SelectionDimensionCurveEndpointRole {
        guard parameter.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc span application requires finite arc endpoint parameters."
            )
        }
        if abs(parameter - endpointParameters.start) <= selectionDimensionEndpointTolerance {
            return .start
        }
        if abs(parameter - endpointParameters.end) <= selectionDimensionEndpointTolerance {
            return .end
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Selection arc span application requires current arc start and arc end references."
        )
    }

    func selectionReference(
        curve: CurveOutputReference,
        role: SelectionDimensionLineEndpointRole,
        lineLength: Double
    ) -> SelectionReference {
        switch role {
        case .start:
            return .curve(.parameter(CurveParameterReference(
                curve: curve,
                parameter: 0.0
            )))
        case .end:
            return .curve(.parameter(CurveParameterReference(
                curve: curve,
                parameter: lineLength
            )))
        }
    }

    func selectionReference(
        curve: CurveOutputReference,
        role: SelectionDimensionCurveEndpointRole,
        arcEndpointParameters: SketchArcEndpointParameterResolver.EndpointParameters
    ) -> SelectionReference {
        switch role {
        case .start:
            return .curve(.parameter(CurveParameterReference(
                curve: curve,
                parameter: arcEndpointParameters.start
            )))
        case .end:
            return .curve(.parameter(CurveParameterReference(
                curve: curve,
                parameter: arcEndpointParameters.end
            )))
        }
    }

    func selectionReference(
        point context: SelectionDimensionSourcePointContext
    ) throws -> SelectionReference {
        switch context.role {
        case .handle(.lineStart):
            let curve = try sourceCurve(context, owner: "Selection point distance line start reference")
            return .curve(.parameter(CurveParameterReference(
                curve: curve,
                parameter: 0.0
            )))
        case .handle(.lineEnd):
            let curve = try sourceCurve(context, owner: "Selection point distance line end reference")
            return .curve(.parameter(CurveParameterReference(
                curve: curve,
                parameter: try sourceLineLength(
                    featureID: context.featureID,
                    entityID: context.entityID
                )
            )))
        case .handle(.circleCenter), .handle(.arcCenter):
            let curve = try sourceCurve(context, owner: "Selection point distance center reference")
            return .curve(.center(CurveCenterReference(curve: curve)))
        case .handle(.arcStart), .handle(.arcEnd):
            let curve = try sourceCurve(context, owner: "Selection point distance arc endpoint reference")
            let endpointParameters = try sourceArcEndpointParameters(
                featureID: context.featureID,
                entityID: context.entityID
            )
            return selectionReference(
                curve: curve,
                role: context.role == .handle(.arcStart) ? .start : .end,
                arcEndpointParameters: endpointParameters
            )
        case .splineControlPoint(let index):
            let curve = try sourceCurve(context, owner: "Selection point distance spline control point reference")
            return .curve(.controlPoint(CurveControlPointReference(
                curve: curve,
                controlPointIndex: index
            )))
        case .handle(.point):
            return .sketchPoint(SketchPointSelectionReference(
                featureID: context.featureID,
                entityID: context.entityID
            ))
        }
    }

    func sourceCurve(
        _ context: SelectionDimensionSourcePointContext,
        owner: String
    ) throws -> CurveOutputReference {
        guard let curve = context.curve else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a source curve reference."
            )
        }
        return curve
    }

    func lineAngleClosestToCurrent(
        referenceAngle: Double,
        targetAngle: Double,
        currentAngle: Double
    ) -> Double {
        let positive = referenceAngle + targetAngle
        let negative = referenceAngle - targetAngle
        if abs(normalizedSignedAngle(positive - currentAngle)) <=
            abs(normalizedSignedAngle(negative - currentAngle)) {
            return positive
        }
        return negative
    }

    func normalizedSignedAngle(_ angle: Double) -> Double {
        let period = Double.pi * 2.0
        var result = angle.truncatingRemainder(dividingBy: period)
        if result > Double.pi {
            result -= period
        } else if result < -Double.pi {
            result += period
        }
        return result
    }

    func persistentNameString(_ name: PersistentName) -> String {
        name.components.map { component in
            switch component {
            case .feature(let featureID):
                return "feature:\(featureID.description)"
            case .generated(let value):
                return "generated:\(value)"
            case .subshape(let value):
                return "subshape:\(value)"
            case .index(let index):
                return "index:\(index)"
            }
        }
        .joined(separator: "/")
    }
}
