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

    /// Dependent Curve Extend: the target end extends in `shape` until it meets the curve
    /// `limit` names, at the crossing nearest the end. The extension is first made long enough to
    /// reach past `limit`, then split exactly at that crossing (Swift-CAD's intersector and the
    /// sketch split), so the new end lies on `limit`. A limit it never meets refuses the command.
    public mutating func extendSketchCurve(
        target: SelectionTarget,
        until limit: SelectionTarget,
        shape: ExtendCurveShape = .natural,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws {
        if limit.component == .object, productMetadata.sceneNodes[limit.sceneNodeID]?.reference?.kind == .body {
            try extendSketchCurve(
                target: target, untilBody: limit, shape: shape, objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
            )
            return
        }
        let owner = "Extend Curve to a curve"
        let selection = try editableSketchEntityBase(for: target, operationName: owner)
        let endpoint = try extendCurveEndpoint(for: target, selection: selection, operationName: owner)
        try validateSketchCurveCanExtend(selection: selection, endpoint: endpoint, shape: shape)
        let limitSelection = try editableSketchEntity(for: limit, operationName: owner)
        guard limitSelection.featureID == selection.featureID else {
            throw EditorError(code: .commandInvalid, message: "\(owner) needs the limit curve in the same sketch.")
        }
        guard limitSelection.entityID != selection.entityID else {
            throw EditorError(code: .commandInvalid, message: "\(owner) needs another curve as its limit.")
        }
        let limitGeometry = try cutCurveGeometry(limitSelection.entity, role: .cutter)
        guard let endPoint = try resolvedPoint(endpoint.reference, in: selection.sketch, owner: owner) else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) could not resolve the curve end.")
        }
        // Long enough to pass every point of the limit curve.
        let limitSamples = try sketchCurveSamplePoints(limitSelection.entity, owner: owner)
        var reach = 2 * (limitSamples.map { hypot($0.x - endPoint.x, $0.y - endPoint.y) }.max() ?? 0) + 1.0e-3
        if case .arc(let arc) = selection.entity {
            // An arc may grow only until it closes.
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: owner)
            let sweep = positiveArcSpan(
                startAngle: try resolvedAngleValue(arc.startAngle, owner: owner),
                endAngle: try resolvedAngleValue(arc.endAngle, owner: owner)
            )
            reach = min(reach, radius * (2 * Double.pi - sweep) * 0.999)
        }
        let probe = try extendedSketchCurveEntity(
            selection.entity,
            endpoint: endpoint,
            distance: .length(reach, .meter),
            resolvedDistance: reach,
            shape: shape,
            owner: owner
        )
        let probeGeometry = try cutCurveGeometry(probe, role: .target)
        let original = try sketchCurveSplitParameter(of: probe, nearestTo: Point2D(x: endPoint.x, y: endPoint.y))
        let hits: [SketchCurveIntersection2D]
        do {
            hits = try SketchCurveIntersector(tolerance: .standard).intersections(of: probeGeometry, with: limitGeometry)
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "\(owner): \(error.message)")
        }
        let margin = 1.0e-9
        let beyond = hits.map { splitParameter(ofNatural: $0.firstParameter, on: probeGeometry) }
            .filter { endpoint.isStart ? $0 < original - margin : $0 > original + margin }
        guard let crossing = endpoint.isStart ? beyond.max() : beyond.min() else {
            throw EditorError(code: .commandInvalid, message: "\(owner): the extension does not reach the limit curve.")
        }
        let split = try splitSketchCurveEntity(
            probe,
            entityID: selection.entityID,
            newEntityID: SketchEntityID(),
            fraction: crossing,
            owner: owner
        )
        let extendedEntity = endpoint.isStart ? split.newEntity : split.retainedEntity

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = extendedEntity
        if case .spline(let originalSpline) = selection.entity, endpoint.isStart,
           case .spline(let extended) = extendedEntity {
            let shift = extended.controlPoints.count - originalSpline.controlPoints.count
            sketch.remapSplineControlPoints(entity: selection.entityID) { $0 + shift }
        }
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        if selection.sketch.entities.count == 1 {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        try commitSketchEntityEdit(featureID: selection.featureID, feature: &feature, sketch: sketch, objectRegistry: objectRegistry, errorOwner: owner)
        didCommit = true
    }

    /// Points along a curve, to bound how far an extension must reach.
    private func sketchCurveSamplePoints(_ entity: SketchEntity, owner: String) throws -> [Point2D] {
        switch entity {
        case .line(let line):
            let start = try resolvedSketchPoint(line.start, owner: owner), end = try resolvedSketchPoint(line.end, owner: owner)
            return [Point2D(x: start.x, y: start.y), Point2D(x: end.x, y: end.y)]
        case .circle(let circle):
            let center = try resolvedSketchPoint(circle.center, owner: owner)
            let radius = try resolvedPositiveLengthValue(circle.radius, owner: owner)
            return [Point2D(x: center.x + radius, y: center.y + radius), Point2D(x: center.x - radius, y: center.y - radius)]
        case .arc(let arc):
            let center = try resolvedSketchPoint(arc.center, owner: owner)
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: owner)
            return [Point2D(x: center.x + radius, y: center.y + radius), Point2D(x: center.x - radius, y: center.y - radius)]
        case .spline(let spline):
            return try spline.controlPoints.map { point in
                let resolved = try resolvedSketchPoint(point, owner: owner)
                return Point2D(x: resolved.x, y: resolved.y)
            }
        case .point(let point):
            let resolved = try resolvedSketchPoint(point, owner: owner)
            return [Point2D(x: resolved.x, y: resolved.y)]
        }
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
        let origin = endpoint.isStart ? line.start : line.end
        let adjacent = endpoint.isStart ? line.end : line.start
        let extendedPoint = try pointExtendedLinearly(from: adjacent, through: origin, distance: distance, owner: owner)
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

        if shape == .soft || shape == .arc || shape == .reflective {
            // Built at the end: a start extension is the end extension of the reversed spline.
            let working = isStart ? reversedSketchSpline(spline) : spline
            let extended = try profileExtendedAtEnd(working, distance: distance, shape: shape, owner: owner)
            let result = isStart ? reversedSketchSpline(extended) : extended
            try validateSplineForm(result, owner: owner)
            return result
        }

        var updated = spline
        if shape == .natural {
            let segment = try expressionEndSegment(of: spline, isStart: isStart)
            let oriented = isStart ? Array(segment.reversed()) : segment
            let coordinates = oriented.flatMap { [$0.x, $0.y] }
            let continued = (0..<spline.degree).map { index in
                SketchPoint(
                    x: .bezierNaturalExtension(coordinates: coordinates, length: distance, coordinateIndex: 2 * index),
                    y: .bezierNaturalExtension(coordinates: coordinates, length: distance, coordinateIndex: 2 * index + 1)
                )
            }
            updated.controlPoints = isStart ? Array(continued.reversed()) + spline.controlPoints : spline.controlPoints + continued
        } else {
            let count = spline.controlPoints.count
            let origin = spline.controlPoints[isStart ? 0 : count - 1]
            let adjacent = spline.controlPoints[isStart ? 1 : count - 2]
            let added = try (1...spline.degree).map { index in
                let step = CADExpression.multiply(distance, .scalar(Double(index) / Double(spline.degree)))
                return try pointExtendedLinearly(from: adjacent, through: origin, distance: step, owner: owner)
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

    /// The same curve traversed backwards: points reversed, knots mirrored (u ↦ a + b − u).
    private func reversedSketchSpline(_ spline: SketchSpline) -> SketchSpline {
        var reversed = spline
        reversed.controlPoints = Array(spline.controlPoints.reversed())
        if let knots = spline.knots, let lower = knots.first, let upper = knots.last {
            reversed.knots = knots.reversed().map { lower + upper - $0 }
        }
        return reversed
    }

    /// Soft, Arc and Reflective at the spline's end, persisted as Swift-CAD's
    /// `bezierShapedExtension` expressions of the curve's own Bezier points and the distance, so
    /// the extension follows the curve and the distance when their parameters change. Arc and
    /// Soft follow the end's curvature held or fading to zero (G2 at the end, within the modeling
    /// distance) as cubic spans raised to the spline's degree, their span count fixed now;
    /// Reflective mirrors the curve's last `distance` (all of it if shorter) across the end's
    /// normal, storing the Bezier segments back to the one that length starts in. The new
    /// points join the end with a knot of multiplicity `degree`, one knot unit per new span.
    private func profileExtendedAtEnd(
        _ spline: SketchSpline,
        distance: CADExpression,
        shape: ExtendCurveShape,
        owner: String
    ) throws -> SketchSpline {
        let degree = spline.degree
        let length = try resolvedPositiveLengthValue(distance, owner: "\(owner) distance")
        let extender = BezierShapedExtension(tolerance: .standard)
        let stored: [SketchPoint]
        let persisted: BezierExtensionShape
        do {
            switch shape {
            case .soft, .arc:
                guard degree >= 3 else {
                    throw EditorError(code: .commandInvalid, message: "\(owner) \(shape.rawValue) needs a spline of degree 3 or more to keep the end's curvature.")
                }
                stored = try expressionEndSegment(of: spline, isStart: false)
                let profile: CurvatureProfileExtension.Profile = shape == .arc ? .arc : .soft
                let spanCount = try extender.profileSpanCount(segment: try resolvedPoints(stored, owner: owner), length: length, profile: profile)
                persisted = shape == .arc ? .arc(spanCount: spanCount) : .soft(spanCount: spanCount)
            case .reflective:
                let chain = try expressionBezierChain(of: spline)
                let span = try extender.reflectiveSegmentCount(segments: try resolvedPoints(chain, owner: owner), degree: degree, length: length)
                stored = Array(chain.suffix(span.count * degree + 1))
                persisted = .reflective(degree: degree, coversCurve: span.coversCurve)
            case .natural, .linear:
                throw EditorError(code: .commandInvalid, message: "\(owner) builds \(shape.rawValue) elsewhere.")
            }
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "\(owner): \(error.message)")
        }
        let coordinates = stored.flatMap { [$0.x, $0.y] }
        let newPointCount: Int
        do {
            newPointCount = try BezierShapedExtension.newPointCount(shape: persisted, controlPointCount: stored.count)
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "\(owner): \(error.message)")
        }
        let added = (0..<newPointCount).map { index in
            SketchPoint(
                x: .bezierShapedExtension(shape: persisted, coordinates: coordinates, length: distance, coordinateIndex: 2 * index),
                y: .bezierShapedExtension(shape: persisted, coordinates: coordinates, length: distance, coordinateIndex: 2 * index + 1)
            )
        }
        let pieceCount = newPointCount / degree
        guard let knots = spline.knotVector, let joint = knots.last else {
            throw EditorError(code: .commandInvalid, message: "\(owner): the spline's knots could not be resolved.")
        }
        let combinedKnots = Array(knots.dropLast())
            + (1..<max(pieceCount, 1)).flatMap { Array(repeating: joint + Double($0), count: degree) }
            + Array(repeating: joint + Double(pieceCount), count: degree + 1)
        var extended = spline
        extended.controlPoints = spline.controlPoints + added
        let chain = SketchSpline(controlPoints: extended.controlPoints, isClosed: false, degree: degree)
        extended.knots = chain.knotVector == combinedKnots ? nil : combinedKnots
        return extended
    }

    private func resolvedPoints(_ points: [SketchPoint], owner: String) throws -> [Point2D] {
        try points.map {
            Point2D(
                x: try resolvedLengthValue($0.x, owner: owner),
                y: try resolvedLengthValue($0.y, owner: owner)
            )
        }
    }

    private func pointExtendedLinearly(
        from adjacent: SketchPoint, through origin: SketchPoint, distance: CADExpression, owner: String
    ) throws -> SketchPoint {
        _ = try normalizedDirection(from: adjacent, to: origin, owner: "\(owner) tangent")
        let dx = CADExpression.subtract(origin.x, adjacent.x)
        let dy = CADExpression.subtract(origin.y, adjacent.y)
        let magnitude = CADExpression.hypot(dx, dy)
        return SketchPoint(
            x: .add(origin.x, .multiply(distance, .divide(dx, magnitude))),
            y: .add(origin.y, .multiply(distance, .divide(dy, magnitude)))
        )
    }

    /// Isolate the end Bezier span by raising its adjacent knot to degree multiplicity.
    /// Boehm's affine combinations retain the original coordinate expressions.
    private func expressionEndSegment(of spline: SketchSpline, isStart: Bool) throws -> [SketchPoint] {
        let degree = spline.degree
        var points = spline.controlPoints
        if let knots = spline.knots {
            let interior = knots.dropFirst(degree + 1).dropLast(degree + 1)
            if let boundary = isStart ? interior.first : interior.last {
                points = try raisedToFullMultiplicity(points: points, knots: knots, at: boundary, degree: degree).points
            }
        }
        return isStart ? Array(points.prefix(degree + 1)) : Array(points.suffix(degree + 1))
    }

    /// The spline's Bezier segments in curve order, sharing their joints: every interior knot
    /// raised to multiplicity `degree`, the points expressions of the original points.
    private func expressionBezierChain(of spline: SketchSpline) throws -> [SketchPoint] {
        let degree = spline.degree
        guard var knots = spline.knots else { return spline.controlPoints }
        var points = spline.controlPoints
        var boundaries: [Double] = []
        for knot in knots.dropFirst(degree + 1).dropLast(degree + 1) where boundaries.last != knot {
            boundaries.append(knot)
        }
        for boundary in boundaries {
            (points, knots) = try raisedToFullMultiplicity(points: points, knots: knots, at: boundary, degree: degree)
        }
        return points
    }

    /// Boehm insertion of `boundary` until its multiplicity is `degree`, with the new points
    /// interpolated as expressions of the old.
    private func raisedToFullMultiplicity(
        points: [SketchPoint], knots: [Double], at boundary: Double, degree: Int
    ) throws -> (points: [SketchPoint], knots: [Double]) {
        var points = points, knots = knots
        let multiplicity = knots.filter { $0 == boundary }.count
        guard multiplicity < degree else { return (points, knots) }
        for count in multiplicity..<degree {
            guard let span = knots.lastIndex(where: { $0 <= boundary }) else {
                throw EditorError(code: .commandInvalid, message: "The extension cannot resolve its end span.")
            }
            var next = Array(points.prefix(span - degree + 1))
            for index in (span - degree + 1)...(span - count) {
                let denominator = knots[index + degree] - knots[index]
                guard denominator > 0 else {
                    throw EditorError(code: .commandInvalid, message: "The extension has a degenerate knot interval.")
                }
                next.append(interpolatedSketchPoint(points[index - 1], points[index],
                    fraction: .scalar((boundary - knots[index]) / denominator)))
            }
            next.append(contentsOf: points[(span - count)...])
            knots.insert(boundary, at: span + 1)
            points = next
        }
        return (points, knots)
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

extension DesignDocument {
    /// Dependent Curve Extend to a sheet or solid: the end extends by `shape` until it meets the
    /// body. A probe extension long enough to pass the whole body is crossed with each of the
    /// body's faces in world space (`faceCrossingFractions`), and the extended curve ends at the
    /// first crossing past the original end; an extension that meets no face is refused.
    mutating func extendSketchCurve(
        target: SelectionTarget, untilBody body: SelectionTarget, shape: ExtendCurveShape, objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?, currentGeneration: DocumentGeneration?
    ) throws {
        let owner = "Extend Curve to a body"
        let selection = try editableSketchEntityBase(for: target, operationName: owner)
        let endpoint = try extendCurveEndpoint(for: target, selection: selection, operationName: owner)
        try validateSketchCurveCanExtend(selection: selection, endpoint: endpoint, shape: shape)
        guard let endPoint = try resolvedPoint(endpoint.reference, in: selection.sketch, owner: owner) else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) could not resolve the curve end.")
        }
        let system = try placedSketchSystem(for: target, plane: selection.sketch.plane)
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        guard let evaluated = topology.evaluatedDocument else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) needs the evaluated document.")
        }
        let placement = try worldPlacement(of: body.sceneNodeID)
        let entries = topology.entries.filter { $0.sceneNodeID == body.sceneNodeID.description }
        let faces = try entries.filter { $0.kind == .face }.map { entry in
            guard let reference = entry.stableReference else {
                throw EditorError(code: .referenceUnresolved, message: "\(owner) body face has no stable reference.")
            }
            return SurfaceReference(subshape: reference)
        }
        // Long enough to pass every vertex of the body.
        let worldEnd = system.point(from: Point2D(x: endPoint.x, y: endPoint.y))
        let corners = try entries.filter { $0.kind == .edge }.flatMap { [$0.start, $0.end].compactMap { $0 } }
            .map { try placement.applied(to: Point3D(x: $0.x, y: $0.y, z: $0.z)) }
        guard !faces.isEmpty, !corners.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "\(owner) needs a body with faces.")
        }
        let reach = 2 * (corners.map { ($0 - worldEnd).length }.max() ?? 0) + 1.0e-3
        let probe = try extendedSketchCurveEntity(
            selection.entity, endpoint: endpoint, distance: .length(reach, .meter), resolvedDistance: reach, shape: shape, owner: owner
        )
        let original = try sketchCurveSplitParameter(of: probe, nearestTo: Point2D(x: endPoint.x, y: endPoint.y))
        var crossings: [Double] = []
        for face in faces {
            crossings += try faceCrossingFractions(of: probe, system: system, face: face, facePlacement: placement, in: evaluated, owner: owner)
        }
        let margin = 1.0e-9
        let beyond = crossings.filter { endpoint.isStart ? $0 < original - margin : $0 > original + margin }
        guard let crossing = endpoint.isStart ? beyond.max() : beyond.min() else {
            throw EditorError(code: .commandInvalid, message: "\(owner): the extension does not reach the body.")
        }
        let split = try splitSketchCurveEntity(
            probe, entityID: selection.entityID, newEntityID: SketchEntityID(), fraction: crossing, owner: owner
        )
        let extendedEntity = endpoint.isStart ? split.newEntity : split.retainedEntity
        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = extendedEntity
        if case .spline(let originalSpline) = selection.entity, endpoint.isStart, case .spline(let extended) = extendedEntity {
            let shift = extended.controlPoints.count - originalSpline.controlPoints.count
            sketch.remapSplineControlPoints(entity: selection.entityID) { $0 + shift }
        }
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        if selection.sketch.entities.count == 1 {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        try commitSketchEntityEdit(featureID: selection.featureID, feature: &feature, sketch: sketch, objectRegistry: objectRegistry, errorOwner: owner)
        didCommit = true
    }
}
