import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func adjacentSketchCurveEndpoint(
        to reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> (reference: SketchReference, endpoint: SketchCurveEndpoint, entity: SketchEntity) {
        let matches = sketch.constraints.compactMap { constraint -> SketchReference? in
            guard case .coincident(let first, let second) = constraint else {
                return nil
            }
            if first == reference {
                return second
            }
            if second == reference {
                return first
            }
            return nil
        }
        let curveEndpointMatches = matches.compactMap { candidate -> (SketchReference, SketchCurveEndpoint, SketchEntity)? in
            guard let endpoint = sketchCurveEndpoint(for: candidate),
                  let entity = sketch.entities[endpoint.entityID],
                  isSupportedOffsetVertexCurveEntity(entity, endpoint: endpoint) else {
                return nil
            }
            return (candidate, endpoint, entity)
        }
        guard curveEndpointMatches.count == 1,
              let match = curveEndpointMatches.first else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires exactly one adjacent line or arc endpoint at the selected vertex."
            )
        }
        return match
    }

    func isSupportedOffsetVertexCurveEntity(
        _ entity: SketchEntity,
        endpoint: SketchCurveEndpoint
    ) -> Bool {
        switch (entity, endpoint) {
        case (.line, .line),
             (.arc, .arc):
            return true
        case (.point, _),
             (.circle, _),
             (.spline, _),
             (.line, .arc),
             (.arc, .line):
            return false
        }
    }

    func translatedSketchPoint(
        _ point: SketchPoint,
        directionX: Double,
        directionY: Double,
        distance: CADExpression,
        scale: Double = 1.0
    ) -> SketchPoint {
        SketchPoint(
            x: .add(point.x, .multiply(distance, .scalar(directionX * scale))),
            y: .add(point.y, .multiply(distance, .scalar(directionY * scale)))
        )
    }

    func normalizedDirection(
        from start: SketchPoint,
        to end: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        let startX = try resolvedLengthValue(start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) direction must not collapse to zero."
            )
        }
        return (x: deltaX / length, y: deltaY / length)
    }

    func resolvedLineMetrics(
        _ line: SketchLine,
        owner: String
    ) throws -> (length: Double, angleRadians: Double, angleDegrees: Double) {
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
                message: "\(owner) length must be greater than zero."
            )
        }
        let angleRadians = atan2(deltaY, deltaX)
        return (
            length: length,
            angleRadians: angleRadians,
            angleDegrees: angleRadians * 180.0 / .pi
        )
    }

    func resizedLine(
        _ line: SketchLine,
        length: Double,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let currentLength = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard currentLength > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        return SketchLine(
            start: line.start,
            end: sketchPoint(
                x: startX + deltaX / currentLength * length,
                y: startY + deltaY / currentLength * length
            )
        )
    }

    func resizedLinePreservingEnd(
        _ line: SketchLine,
        length: Double,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let currentLength = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard currentLength > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        return SketchLine(
            start: sketchPoint(
                x: endX - deltaX / currentLength * length,
                y: endY - deltaY / currentLength * length
            ),
            end: line.end
        )
    }

    func angledLinePreservingStart(
        _ line: SketchLine,
        angleRadians: Double,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let length = try resolvedLineMetrics(line, owner: owner).length
        return SketchLine(
            start: line.start,
            end: sketchPoint(
                x: startX + cos(angleRadians) * length,
                y: startY + sin(angleRadians) * length
            )
        )
    }

    func angledLinePreservingEnd(
        _ line: SketchLine,
        angleRadians: Double,
        owner: String
    ) throws -> SketchLine {
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let length = try resolvedLineMetrics(line, owner: owner).length
        return SketchLine(
            start: sketchPoint(
                x: endX - cos(angleRadians) * length,
                y: endY - sin(angleRadians) * length
            ),
            end: line.end
        )
    }

    func angularDistance(_ first: Double, _ second: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        var delta = (first - second).truncatingRemainder(dividingBy: fullCircle)
        if delta > Double.pi {
            delta -= fullCircle
        }
        if delta < -Double.pi {
            delta += fullCircle
        }
        return abs(delta)
    }

    func validateLineAngleDimensionAgainstDirectOrientationConstraints(
        _ angleRadians: Double,
        lineID: SketchEntityID,
        sketch: Sketch,
        owner: String
    ) throws {
        for constraint in sketch.constraints {
            switch constraint {
            case .horizontal(let constrainedLineID) where constrainedLineID == lineID:
                guard lineOrientationDistance(angleRadians, 0.0) <= 1.0e-12 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) conflicts with a horizontal sketch constraint."
                    )
                }
            case .vertical(let constrainedLineID) where constrainedLineID == lineID:
                guard lineOrientationDistance(angleRadians, Double.pi / 2.0) <= 1.0e-12 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) conflicts with a vertical sketch constraint."
                    )
                }
            default:
                continue
            }
        }
    }

    func positiveArcSpan(
        startAngle: Double,
        endAngle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        // Remainder-based normalization stays O(1) for arbitrarily large angle
        // expressions; +/- 2*pi loops hang on huge-but-finite values.
        var span = (endAngle - startAngle).truncatingRemainder(dividingBy: fullCircle)
        if span <= 0.0 {
            span += fullCircle
        }
        return span
    }

    func squaredDistance(
        _ first: (x: Double, y: Double),
        _ second: (x: Double, y: Double)
    ) -> Double {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return deltaX * deltaX + deltaY * deltaY
    }

    func validateArc(
        _ arc: SketchArc,
        owner: String
    ) throws {
        _ = try resolvedLengthValue(arc.center.x, owner: "\(owner) center x")
        _ = try resolvedLengthValue(arc.center.y, owner: "\(owner) center y")
        _ = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius")
        let resolvedStartAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
        let resolvedEndAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
        _ = try normalizedPartialArcSpan(
            startAngle: resolvedStartAngle,
            endAngle: resolvedEndAngle
        )
    }

    func validateSpline(
        _ spline: SketchSpline,
        owner: String
    ) throws {
        let count = spline.controlPoints.count
        guard count >= 4, (count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) control point count must be 3n + 1 and at least 4."
            )
        }
        let resolvedPoints = try spline.controlPoints.enumerated().map { index, point in
            (
                x: try resolvedLengthValue(point.x, owner: "\(owner) control point \(index) x"),
                y: try resolvedLengthValue(point.y, owner: "\(owner) control point \(index) y")
            )
        }
        for segmentIndex in stride(from: 0, to: resolvedPoints.count - 1, by: 3) {
            let start = resolvedPoints[segmentIndex]
            let end = resolvedPoints[segmentIndex + 3]
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y
            guard sqrt(deltaX * deltaX + deltaY * deltaY) > ModelingTolerance.standard.distance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) cubic segment \(segmentIndex / 3) must not collapse to a point."
                )
            }
        }
    }

    func normalizedPartialArcSpan(
        startAngle: Double,
        endAngle: Double
    ) throws -> Double {
        let fullCircle = Double.pi * 2.0
        // Remainder-based normalization stays O(1) for arbitrarily large angle
        // expressions; +/- 2*pi loops hang on huge-but-finite values.
        var span = (endAngle - startAngle - ModelingTolerance.standard.angle)
            .truncatingRemainder(dividingBy: fullCircle)
        if span <= 0.0 {
            span += fullCircle
        }
        span += ModelingTolerance.standard.angle
        guard span > ModelingTolerance.standard.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Arc sketch angle span must be greater than zero."
            )
        }
        guard span < fullCircle - ModelingTolerance.standard.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Arc sketch must be partial; use a circle sketch for full circles."
            )
        }
        return span
    }

    func sketchPoint(x: Double, y: Double) -> SketchPoint {
        SketchPoint(
            x: .length(x, .meter),
            y: .length(y, .meter)
        )
    }

    func sketchCoordinate(
        from point: TopologySummaryResult.Entry.Point,
        on plane: SketchPlane
    ) throws -> (x: Double, y: Double, depth: Double) {
        switch plane {
        case .xy:
            return (x: point.x, y: point.y, depth: point.z)
        case .yz:
            return (x: point.y, y: point.z, depth: point.x)
        case .zx:
            return (x: point.z, y: point.x, depth: point.y)
        case .plane(let plane):
            let normal = try plane.normal.normalized(tolerance: 1.0e-12)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: 1.0e-12)
            let v = normal.cross(u)
            let delta = Point3D(x: point.x, y: point.y, z: point.z) - plane.origin
            return (
                x: delta.dot(u),
                y: delta.dot(v),
                depth: delta.dot(normal)
            )
        }
    }

    func updateRectangleSketch(
        _ sketch: inout Sketch,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint
    ) throws {
        guard let lineIDs = try rectangleLineIDs(in: sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cube dimensions require an axis-aligned rectangle profile."
            )
        }
        let bottomLeft = firstCorner
        let bottomRight = SketchPoint(x: oppositeCorner.x, y: firstCorner.y)
        let topRight = oppositeCorner
        let topLeft = SketchPoint(x: firstCorner.x, y: oppositeCorner.y)
        sketch.entities[lineIDs.bottom] = .line(SketchLine(start: bottomLeft, end: bottomRight))
        sketch.entities[lineIDs.right] = .line(SketchLine(start: bottomRight, end: topRight))
        sketch.entities[lineIDs.top] = .line(SketchLine(start: topRight, end: topLeft))
        sketch.entities[lineIDs.left] = .line(SketchLine(start: topLeft, end: bottomLeft))
    }

    func resolvedPoint(
        _ reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> (x: Double, y: Double)? {
        switch reference {
        case let .entity(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .point(point) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedSketchPoint(point, owner: owner)
        case let .lineStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedSketchPoint(line.start, owner: owner)
        case let .lineEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedSketchPoint(line.end, owner: owner)
        case let .circleCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .circle(circle) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedSketchPoint(circle.center, owner: owner)
        case let .arcCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedSketchPoint(arc.center, owner: owner)
        case let .arcStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try pointOnArc(arc, angle: arc.startAngle, owner: owner)
        case let .arcEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try pointOnArc(arc, angle: arc.endAngle, owner: owner)
        case let .splineControlPoint(entityID, index):
            guard let entity = sketch.entities[entityID],
                  case let .spline(spline) = entity,
                  spline.controlPoints.indices.contains(index) else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedSketchPoint(spline.controlPoints[index], owner: owner)
        case .circleRadius, .arcRadius:
            return nil
        }
    }

    func resolvedSketchPoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        (
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }

    func pointOnArc(
        _ arc: SketchArc,
        angle: CADExpression,
        owner: String
    ) throws -> (x: Double, y: Double) {
        let center = try resolvedSketchPoint(arc.center, owner: owner)
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        let resolvedAngle = try resolvedAngleValue(angle, owner: "\(owner) arc angle")
        return (
            x: center.x + cos(resolvedAngle) * radius,
            y: center.y + sin(resolvedAngle) * radius
        )
    }

    func rectangleLineIDs(
        in sketch: Sketch
    ) throws -> (bottom: SketchEntityID, right: SketchEntityID, top: SketchEntityID, left: SketchEntityID)? {
        guard let bounds = try resolvedSketchBounds2D(sketch),
              sketch.entities.count == 4 else {
            return nil
        }
        var bottom: SketchEntityID?
        var right: SketchEntityID?
        var top: SketchEntityID?
        var left: SketchEntityID?
        let tolerance = 1.0e-9

        for (id, entity) in sketch.entities {
            guard case .line(let line) = entity else {
                return nil
            }
            let startX = try resolvedLengthValue(line.start.x, owner: "Rectangle line start x")
            let startY = try resolvedLengthValue(line.start.y, owner: "Rectangle line start y")
            let endX = try resolvedLengthValue(line.end.x, owner: "Rectangle line end x")
            let endY = try resolvedLengthValue(line.end.y, owner: "Rectangle line end y")
            if nearlyEqual(startY, bounds.minY, tolerance: tolerance),
               nearlyEqual(endY, bounds.minY, tolerance: tolerance) {
                bottom = id
            } else if nearlyEqual(startY, bounds.maxY, tolerance: tolerance),
                      nearlyEqual(endY, bounds.maxY, tolerance: tolerance) {
                top = id
            } else if nearlyEqual(startX, bounds.minX, tolerance: tolerance),
                      nearlyEqual(endX, bounds.minX, tolerance: tolerance) {
                left = id
            } else if nearlyEqual(startX, bounds.maxX, tolerance: tolerance),
                      nearlyEqual(endX, bounds.maxX, tolerance: tolerance) {
                right = id
            } else {
                return nil
            }
        }

        guard let bottom,
              let right,
              let top,
              let left else {
            return nil
        }
        return (bottom, right, top, left)
    }

    func nearlyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    func resolvedSketchBounds2D(
        _ sketch: Sketch
    ) throws -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        var points: [(x: Double, y: Double)] = []
        for entity in sketch.entities.values {
            for point in sketchPoints(in: entity) {
                points.append(
                    (
                        x: try resolvedLengthValue(point.x, owner: "Sketch point x"),
                        y: try resolvedLengthValue(point.y, owner: "Sketch point y")
                    )
                )
            }
        }
        guard let first = points.first else {
            return nil
        }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return (minX, minY, maxX, maxY)
    }

    func isRectangleProfile(_ sketch: Sketch) -> Bool {
        guard sketch.entities.count == 4 else {
            return false
        }
        return sketch.entities.values.allSatisfy { entity in
            if case .line(_) = entity {
                return true
            }
            return false
        }
    }

    func singleCircleEntry(in sketch: Sketch) -> (id: SketchEntityID, circle: SketchCircle)? {
        var circleEntry: (id: SketchEntityID, circle: SketchCircle)?
        for (id, entity) in sketch.entities {
            guard case .circle(let circle) = entity else {
                return nil
            }
            guard circleEntry == nil else {
                return nil
            }
            circleEntry = (id, circle)
        }
        return circleEntry
    }

    private func lineOrientationDistance(_ first: Double, _ second: Double) -> Double {
        let period = Double.pi
        var delta = (first - second).truncatingRemainder(dividingBy: period)
        if delta > period / 2.0 {
            delta -= period
        }
        if delta < -period / 2.0 {
            delta += period
        }
        return abs(delta)
    }

    private func invalidSketchPointReference(_ owner: String) -> EditorError {
        EditorError(
            code: .referenceUnresolved,
            message: "\(owner) references an unsupported sketch point."
        )
    }

    private func sketchPoints(in entity: SketchEntity) -> [SketchPoint] {
        switch entity {
        case .point(let point):
            [point]
        case .line(let line):
            [line.start, line.end]
        case .circle(let circle):
            [circle.center]
        case .arc(let arc):
            [arc.center]
        case .spline(let spline):
            spline.controlPoints
        }
    }
}
