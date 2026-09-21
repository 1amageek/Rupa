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

    /// Repositions a rectangle profile between two opposite corners, keeping the corners it carries.
    ///
    /// A square profile stores the corner expressions the caller supplies, so a side driven by a
    /// named dimension stays driven by it. A rounded profile is placed from resolved lengths, and a
    /// size that no longer admits its radius is refused rather than silently squared off. Neither
    /// branch changes the entity set, so the constraints the sketch already declares stay valid.
    func updateRectangleSketch(
        _ sketch: inout Sketch,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint
    ) throws {
        guard let profile = try recognizedRectangleProfile(in: sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cube dimensions require an axis-aligned rectangle profile."
            )
        }
        let rebuilt: RectangleProfileBuilder.Result
        if profile.cornerRadius > 0 {
            let firstX = try resolvedLengthValue(firstCorner.x, owner: "Rectangle corner x")
            let firstY = try resolvedLengthValue(firstCorner.y, owner: "Rectangle corner y")
            let oppositeX = try resolvedLengthValue(oppositeCorner.x, owner: "Rectangle corner x")
            let oppositeY = try resolvedLengthValue(oppositeCorner.y, owner: "Rectangle corner y")
            let sizeX = abs(oppositeX - firstX)
            let sizeY = abs(oppositeY - firstY)
            try validateRectangleCornerRadius(profile.cornerRadius, sizeX: sizeX, sizeY: sizeY)
            rebuilt = RectangleProfileBuilder.build(
                centerX: (firstX + oppositeX) / 2.0,
                centerY: (firstY + oppositeY) / 2.0,
                sizeX: sizeX,
                sizeY: sizeY,
                cornerRadius: profile.cornerRadius,
                reusing: profile.ids
            )
        } else {
            rebuilt = RectangleProfileBuilder.build(
                bottomLeft: firstCorner,
                bottomRight: SketchPoint(x: oppositeCorner.x, y: firstCorner.y),
                topRight: oppositeCorner,
                topLeft: SketchPoint(x: firstCorner.x, y: oppositeCorner.y),
                reusing: profile.ids
            )
        }
        for (id, entity) in rebuilt.entities {
            sketch.entities[id] = entity
        }
    }

    /// Refuses a corner radius the rectangle cannot hold.
    ///
    /// At the upper equality two of the four lines have zero length and the profile is a stadium,
    /// which is the slot type's shape and not a rectangle's. This is the tolerance idiom
    /// `validateAllEdgeCorner` uses for the body fillet a cube's corner declares.
    func validateRectangleCornerRadius(_ radius: Double, sizeX: Double, sizeY: Double) throws {
        let tolerance = modelingSettings.tolerance.distance
        guard radius.isFinite, radius == 0 ||
                (radius > tolerance && min(sizeX, sizeY) - 2 * radius > tolerance) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Rectangle corner must be zero or a positive radius below half the shorter side."
            )
        }
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

    /// Names the four sides of a square rectangle profile.
    ///
    /// A rounded profile is deliberately not recognized here. The callers are the direct
    /// manipulation and dimension-handle paths, which map a 3D vertex or edge onto a rectangle
    /// corner, and a corner a rounded profile replaced with an arc is not a point they can name.
    func rectangleLineIDs(
        in sketch: Sketch
    ) throws -> (bottom: SketchEntityID, right: SketchEntityID, top: SketchEntityID, left: SketchEntityID)? {
        guard let profile = try recognizedRectangleProfile(in: sketch),
              profile.cornerRadius == 0 else {
            return nil
        }
        return (profile.ids.bottom, profile.ids.right, profile.ids.top, profile.ids.left)
    }

    /// Reads a rectangle profile back out of a sketch, square or rounded.
    ///
    /// The family is four axis-aligned lines, optionally followed by four equal corner arcs whose
    /// centers sit at the inset corners the radius describes. Anything else is not a rectangle
    /// profile and the caller decides what to do about that.
    func recognizedRectangleProfile(
        in sketch: Sketch
    ) throws -> RectangleProfileBuilder.Recognized? {
        guard let bounds = try resolvedSketchBounds2D(sketch) else {
            return nil
        }
        let tolerance = 1.0e-9
        var bottom: SketchEntityID?
        var right: SketchEntityID?
        var top: SketchEntityID?
        var left: SketchEntityID?
        var arcs: [(id: SketchEntityID, centerX: Double, centerY: Double, radius: Double)] = []

        for (id, entity) in sketch.entities {
            switch entity {
            case .line(let line):
                let startX = try resolvedLengthValue(line.start.x, owner: "Rectangle line start x")
                let startY = try resolvedLengthValue(line.start.y, owner: "Rectangle line start y")
                let endX = try resolvedLengthValue(line.end.x, owner: "Rectangle line end x")
                let endY = try resolvedLengthValue(line.end.y, owner: "Rectangle line end y")
                if nearlyEqual(startY, bounds.minY, tolerance: tolerance),
                   nearlyEqual(endY, bounds.minY, tolerance: tolerance) {
                    guard bottom == nil else { return nil }
                    bottom = id
                } else if nearlyEqual(startY, bounds.maxY, tolerance: tolerance),
                          nearlyEqual(endY, bounds.maxY, tolerance: tolerance) {
                    guard top == nil else { return nil }
                    top = id
                } else if nearlyEqual(startX, bounds.minX, tolerance: tolerance),
                          nearlyEqual(endX, bounds.minX, tolerance: tolerance) {
                    guard left == nil else { return nil }
                    left = id
                } else if nearlyEqual(startX, bounds.maxX, tolerance: tolerance),
                          nearlyEqual(endX, bounds.maxX, tolerance: tolerance) {
                    guard right == nil else { return nil }
                    right = id
                } else {
                    return nil
                }
            case .arc(let arc):
                let center = try resolvedSketchPoint(arc.center, owner: "Rectangle corner arc center")
                let radius = try resolvedLengthValue(arc.radius, owner: "Rectangle corner arc radius")
                arcs.append((id, center.x, center.y, radius))
            default:
                return nil
            }
        }

        guard let bottom, let right, let top, let left else {
            return nil
        }
        var ids = RectangleProfileBuilder.EntityIDs(
            bottom: bottom, right: right, top: top, left: left)

        guard arcs.isEmpty == false else {
            return RectangleProfileBuilder.Recognized(
                ids: ids,
                cornerRadius: 0,
                minX: bounds.minX,
                minY: bounds.minY,
                maxX: bounds.maxX,
                maxY: bounds.maxY
            )
        }
        guard arcs.count == 4 else {
            return nil
        }
        let radius = arcs[0].radius
        guard radius > tolerance,
              arcs.allSatisfy({ nearlyEqual($0.radius, radius, tolerance: tolerance) }) else {
            return nil
        }
        for arc in arcs {
            let isRight = nearlyEqual(arc.centerX, bounds.maxX - radius, tolerance: tolerance)
            let isLeft = nearlyEqual(arc.centerX, bounds.minX + radius, tolerance: tolerance)
            let isTop = nearlyEqual(arc.centerY, bounds.maxY - radius, tolerance: tolerance)
            let isBottom = nearlyEqual(arc.centerY, bounds.minY + radius, tolerance: tolerance)
            switch (isRight, isLeft, isTop, isBottom) {
            case (true, false, false, true):
                guard ids.bottomRight == nil else { return nil }
                ids.bottomRight = arc.id
            case (true, false, true, false):
                guard ids.topRight == nil else { return nil }
                ids.topRight = arc.id
            case (false, true, true, false):
                guard ids.topLeft == nil else { return nil }
                ids.topLeft = arc.id
            case (false, true, false, true):
                guard ids.bottomLeft == nil else { return nil }
                ids.bottomLeft = arc.id
            default:
                return nil
            }
        }
        guard ids.isRounded else {
            return nil
        }
        return RectangleProfileBuilder.Recognized(
            ids: ids,
            cornerRadius: radius,
            minX: bounds.minX,
            minY: bounds.minY,
            maxX: bounds.maxX,
            maxY: bounds.maxY
        )
    }

    /// Names the cap profile family the kernel's all-edge fillet rounds, or `nil` for a sketch
    /// outside every one of them.
    ///
    /// The order is the contract: a circle, then a rectangle, then a regular polygon, then a
    /// stadium. `AllEdgeFilletProfile` owns why an axis-aligned square stops at the rectangle.
    func recognizedAllEdgeFilletProfile(in sketch: Sketch) throws -> AllEdgeFilletProfile? {
        if let cylinder = try recognizedCylinderCircleProfile(in: sketch) {
            // A tube is none of the four prisms the kernel's all-edge fillet accepts, so a hollow
            // cylinder names no profile here rather than falling through to a recognizer that
            // would read its two circles as some other shape.
            guard cylinder.inner == nil, cylinder.outer.radius > 0 else {
                return nil
            }
            return .circle(radius: cylinder.outer.radius)
        }
        if let rectangle = try recognizedRectangleProfile(in: sketch) {
            return .rectangle(
                sizeX: rectangle.sizeX,
                sizeY: rectangle.sizeY,
                cornerRadius: rectangle.cornerRadius
            )
        }
        if let polygon = try recognizedRegularPolygonProfile(in: sketch) {
            return .regularPolygon(
                sideLength: polygon.sideLength,
                sideCount: polygon.sideCount
            )
        }
        if let capRadius = try recognizedStadiumProfile(in: sketch) {
            return .stadium(capRadius: capRadius)
        }
        return nil
    }

    /// Reads a regular polygon profile back out of a sketch.
    ///
    /// The family is a closed chain of three or more equal straight sides whose vertices all turn
    /// by the same signed exterior angle. A closed chain of equal sides alone would also admit a
    /// star polygon, which winds more than once and corners reflexly, so the turn is measured at
    /// every vertex rather than inferred from the side count.
    func recognizedRegularPolygonProfile(
        in sketch: Sketch
    ) throws -> (sideCount: Int, sideLength: Double)? {
        let tolerance = 1.0e-9
        var sides: [(start: (x: Double, y: Double), end: (x: Double, y: Double))] = []
        for entity in sketch.entities.values {
            guard case .line(let line) = entity else {
                return nil
            }
            sides.append(
                (
                    start: try resolvedSketchPoint(line.start, owner: "Polygon side start"),
                    end: try resolvedSketchPoint(line.end, owner: "Polygon side end")
                )
            )
        }
        guard sides.count >= 3 else {
            return nil
        }

        var directions: [(x: Double, y: Double)] = []
        var lengths: [Double] = []
        for side in sides {
            let deltaX = side.end.x - side.start.x
            let deltaY = side.end.y - side.start.y
            let length = (deltaX * deltaX + deltaY * deltaY).squareRoot()
            guard length > tolerance else {
                return nil
            }
            directions.append((x: deltaX / length, y: deltaY / length))
            lengths.append(length)
        }
        guard let shortestSide = lengths.min(),
              let longestSide = lengths.max(),
              longestSide - shortestSide <= tolerance else {
            return nil
        }

        var successors: [Int] = []
        for side in sides {
            var successor: Int?
            for (candidateIndex, candidate) in sides.enumerated() {
                guard nearlyEqual(candidate.start.x, side.end.x, tolerance: tolerance),
                      nearlyEqual(candidate.start.y, side.end.y, tolerance: tolerance) else {
                    continue
                }
                guard successor == nil else {
                    return nil
                }
                successor = candidateIndex
            }
            guard let successor else {
                return nil
            }
            successors.append(successor)
        }

        // One cycle through every side and back to its start. Two sides sharing a successor, or a
        // chain that closes early, leaves the loop somewhere other than where it began.
        var visited: Set<Int> = []
        var sideIndex = 0
        for _ in sides.indices {
            guard visited.insert(sideIndex).inserted else {
                return nil
            }
            sideIndex = successors[sideIndex]
        }
        guard sideIndex == 0 else {
            return nil
        }

        let expectedTurn = 2.0 * Double.pi / Double(sides.count)
        var firstTurn: Double?
        for index in sides.indices {
            let incoming = directions[index]
            let outgoing = directions[successors[index]]
            let turn = atan2(
                incoming.x * outgoing.y - incoming.y * outgoing.x,
                incoming.x * outgoing.x + incoming.y * outgoing.y
            )
            guard nearlyEqual(abs(turn), expectedTurn, tolerance: tolerance) else {
                return nil
            }
            if let firstTurn {
                guard turn.sign == firstTurn.sign else {
                    return nil
                }
            } else {
                firstTurn = turn
            }
        }
        return (sideCount: sides.count, sideLength: shortestSide)
    }

    /// Reads a stadium profile back out of a sketch and names the radius of its caps.
    ///
    /// The family is two parallel straight sides of one length closed by two half-turn arcs of one
    /// radius, which is the outline a slot takes when its path is a single straight segment. The
    /// outline is rebuilt from the two cap centers and compared against the sketch rather than
    /// checked feature by feature, so a figure whose caps join the wrong ends is refused.
    func recognizedStadiumProfile(in sketch: Sketch) throws -> Double? {
        let tolerance = 1.0e-9
        var sides: [(start: (x: Double, y: Double), end: (x: Double, y: Double))] = []
        var caps: [(center: (x: Double, y: Double), radius: Double, start: Double, end: Double)] = []
        for entity in sketch.entities.values {
            switch entity {
            case .line(let line):
                sides.append(
                    (
                        start: try resolvedSketchPoint(line.start, owner: "Slot side start"),
                        end: try resolvedSketchPoint(line.end, owner: "Slot side end")
                    )
                )
            case .arc(let arc):
                caps.append(
                    (
                        center: try resolvedSketchPoint(arc.center, owner: "Slot cap center"),
                        radius: try resolvedLengthValue(arc.radius, owner: "Slot cap radius"),
                        start: try resolvedAngleValue(arc.startAngle, owner: "Slot cap start angle"),
                        end: try resolvedAngleValue(arc.endAngle, owner: "Slot cap end angle")
                    )
                )
            default:
                return nil
            }
        }
        guard sides.count == 2, caps.count == 2 else {
            return nil
        }

        let capRadius = caps[0].radius
        guard capRadius > tolerance,
              nearlyEqual(caps[1].radius, capRadius, tolerance: tolerance) else {
            return nil
        }
        for cap in caps {
            guard nearlyEqual(abs(cap.end - cap.start), .pi, tolerance: tolerance) else {
                return nil
            }
        }

        let axisX = caps[1].center.x - caps[0].center.x
        let axisY = caps[1].center.y - caps[0].center.y
        let straightLength = (axisX * axisX + axisY * axisY).squareRoot()
        guard straightLength > tolerance else {
            return nil
        }
        let offsetX = -axisY / straightLength * capRadius
        let offsetY = axisX / straightLength * capRadius

        for cap in caps {
            let capStart = (
                x: cap.center.x + cos(cap.start) * capRadius,
                y: cap.center.y + sin(cap.start) * capRadius
            )
            guard coincides(capStart, with: (x: cap.center.x + offsetX, y: cap.center.y + offsetY), tolerance: tolerance)
                || coincides(capStart, with: (x: cap.center.x - offsetX, y: cap.center.y - offsetY), tolerance: tolerance) else {
                return nil
            }
        }

        let nearSide = (
            (x: caps[0].center.x + offsetX, y: caps[0].center.y + offsetY),
            (x: caps[1].center.x + offsetX, y: caps[1].center.y + offsetY)
        )
        let farSide = (
            (x: caps[0].center.x - offsetX, y: caps[0].center.y - offsetY),
            (x: caps[1].center.x - offsetX, y: caps[1].center.y - offsetY)
        )
        let firstSpansNear = spans(sides[0], nearSide, tolerance: tolerance)
        let firstSpansFar = spans(sides[0], farSide, tolerance: tolerance)
        let secondSpansNear = spans(sides[1], nearSide, tolerance: tolerance)
        let secondSpansFar = spans(sides[1], farSide, tolerance: tolerance)
        guard (firstSpansNear && secondSpansFar) || (firstSpansFar && secondSpansNear) else {
            return nil
        }
        return capRadius
    }

    private func coincides(
        _ point: (x: Double, y: Double),
        with other: (x: Double, y: Double),
        tolerance: Double
    ) -> Bool {
        nearlyEqual(point.x, other.x, tolerance: tolerance)
            && nearlyEqual(point.y, other.y, tolerance: tolerance)
    }

    private func spans(
        _ side: (start: (x: Double, y: Double), end: (x: Double, y: Double)),
        _ endpoints: ((x: Double, y: Double), (x: Double, y: Double)),
        tolerance: Double
    ) -> Bool {
        (coincides(side.start, with: endpoints.0, tolerance: tolerance)
            && coincides(side.end, with: endpoints.1, tolerance: tolerance))
            || (coincides(side.start, with: endpoints.1, tolerance: tolerance)
                && coincides(side.end, with: endpoints.0, tolerance: tolerance))
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

    func singleLineEntry(in sketch: Sketch) -> (id: SketchEntityID, line: SketchLine)? {
        var lineEntry: (id: SketchEntityID, line: SketchLine)?
        for (id, entity) in sketch.entities {
            guard case .line(let line) = entity else {
                return nil
            }
            guard lineEntry == nil else {
                return nil
            }
            lineEntry = (id, line)
        }
        return lineEntry
    }

    func singleArcEntry(in sketch: Sketch) -> (id: SketchEntityID, arc: SketchArc)? {
        var arcEntry: (id: SketchEntityID, arc: SketchArc)?
        for (id, entity) in sketch.entities {
            guard case .arc(let arc) = entity else {
                return nil
            }
            guard arcEntry == nil else {
                return nil
            }
            arcEntry = (id, arc)
        }
        return arcEntry
    }

    /// Names the circle profile family a cylinder extrudes, or `nil` for a sketch outside it.
    ///
    /// `CylinderCircleProfile` owns what the family is. Two circles are one profile only when the
    /// inner one is concentric with the outer one and strictly inside it, which is what makes the
    /// extrusion one tube rather than two bodies. Anything else — a third circle, an entity that is
    /// not a circle, two circles side by side — is a sketch no cylinder edit names, and each caller
    /// keeps the behaviour it already has for a profile it cannot name.
    ///
    /// The recognizer resolves radii but judges no bound beyond the containment that makes the
    /// family well formed. A caller that requires a positive radius, or one the current hollow
    /// leaves room for, states that itself.
    func recognizedCylinderCircleProfile(in sketch: Sketch) throws -> CylinderCircleProfile? {
        var entries: [CylinderCircleProfile.Entry] = []
        for (id, entity) in sketch.entities {
            guard case .circle(let circle) = entity, entries.count < 2 else {
                return nil
            }
            let radius = try resolvedLengthValue(circle.radius, owner: "Cylinder radius")
            entries.append(CylinderCircleProfile.Entry(id: id, circle: circle, radius: radius))
        }
        let tolerance = modelingSettings.tolerance.distance
        switch entries.count {
        case 1:
            return CylinderCircleProfile(outer: entries[0], inner: nil)
        case 2:
            let sorted = entries.sorted { $0.radius > $1.radius }
            let outer = sorted[0]
            let inner = sorted[1]
            let centerOffset = try sketchPointDistance(outer.circle.center, inner.circle.center)
            guard inner.radius > tolerance,
                  outer.radius - inner.radius > tolerance,
                  centerOffset <= tolerance else {
                return nil
            }
            return CylinderCircleProfile(outer: outer, inner: inner)
        default:
            return nil
        }
    }

    private func sketchPointDistance(_ first: SketchPoint, _ second: SketchPoint) throws -> Double {
        let owner = "Circle center"
        let deltaX = try resolvedLengthValue(first.x, owner: owner)
            - resolvedLengthValue(second.x, owner: owner)
        let deltaY = try resolvedLengthValue(first.y, owner: owner)
            - resolvedLengthValue(second.y, owner: owner)
        return (deltaX * deltaX + deltaY * deltaY).squareRoot()
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
