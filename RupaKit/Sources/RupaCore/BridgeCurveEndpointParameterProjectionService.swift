import Foundation
import SwiftCAD

public struct BridgeCurveEndpointParameterProjection: Equatable, Sendable {
    public var endpoint: BridgeCurveEndpoint
    public var parameter: Double
    public var point: Point2D
    public var outgoingTangent: Point2D

    public init(
        endpoint: BridgeCurveEndpoint,
        parameter: Double,
        point: Point2D,
        outgoingTangent: Point2D
    ) {
        self.endpoint = endpoint
        self.parameter = parameter
        self.point = point
        self.outgoingTangent = outgoingTangent
    }
}

public struct BridgeCurveEndpointParameterProjectionService: Sendable {
    public init() {}

    public func parameter(
        for endpoint: BridgeCurveEndpoint,
        featureID: FeatureID,
        in document: DesignDocument
    ) throws -> Double {
        let entity = try sourceEntity(
            for: endpoint.reference,
            featureID: featureID,
            in: document
        ).entity
        if let expression = endpoint.parameter {
            return try resolvedParameter(
                expression,
                document: document,
                owner: "Bridge curve endpoint parameter"
            )
        }
        switch (endpoint.reference, entity) {
        case (.lineStart, .line),
             (.arcStart, .arc):
            return 0.0
        case (.lineEnd, .line),
             (.arcEnd, .arc):
            return 1.0
        case let (.splineControlPoint(_, index), .spline(spline)):
            if index == 0 {
                return 0.0
            }
            if index == spline.controlPoints.count - 1 {
                return 1.0
            }
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve endpoint parameter requires a spline endpoint or explicit scalar parameter."
            )
        case (.entity, .line),
             (.entity, .arc),
             (.entity, .spline):
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve entity endpoints require an explicit scalar parameter."
            )
        case (.lineStart, _),
             (.lineEnd, _),
             (.arcStart, _),
             (.arcEnd, _),
             (.splineControlPoint, _),
             (.entity, _):
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve endpoint reference does not match an editable curve."
            )
        case (.circleCenter, _),
             (.circleRadius, _),
             (.arcCenter, _),
             (.arcRadius, _):
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve endpoint parameter requires a line, arc, or spline curve."
            )
        }
    }

    public func projection(
        for endpoint: BridgeCurveEndpoint,
        featureID: FeatureID,
        near point: Point2D,
        in document: DesignDocument
    ) throws -> BridgeCurveEndpointParameterProjection {
        guard point.x.isFinite,
              point.y.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve endpoint parameter projection requires a finite point."
            )
        }
        let source = try sourceEntity(
            for: endpoint.reference,
            featureID: featureID,
            in: document
        )
        let sketch = source.sketch
        let entity = source.entity
        guard supportsProjection(entity) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve endpoint parameter projection requires a line, arc, or spline curve."
            )
        }
        let parameter: Double
        switch entity {
        case .line(let line):
            parameter = try lineParameter(line, near: point, document: document)
        case .arc(let arc):
            parameter = try arcParameter(arc, near: point, document: document)
        case .spline(let spline):
            parameter = try splineParameter(spline, near: point, document: document)
        case .point,
             .circle:
            throw EditorError(code: .commandInvalid, message: "Unsupported bridge curve endpoint projection target.")
        }
        let nextEndpoint = BridgeCurveEndpoint(
            reference: endpoint.reference,
            parameter: .scalar(parameter),
            reversesSense: endpoint.reversesSense,
            trimSide: endpoint.trimSide,
            tension: endpoint.tension
        )
        guard let sample = try SketchCurveEndpointResolver().sample(
            for: nextEndpoint,
            sketch: sketch,
            document: document
        ) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve projected endpoint could not be resolved."
            )
        }
        return BridgeCurveEndpointParameterProjection(
            endpoint: nextEndpoint,
            parameter: parameter,
            point: sample.sample.point,
            outgoingTangent: sample.outgoingTangent
        )
    }

    private func lineParameter(
        _ line: SketchLine,
        near point: Point2D,
        document: DesignDocument
    ) throws -> Double {
        let start = try resolvedPoint(line.start, document: document)
        let end = try resolvedPoint(line.end, document: document)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1.0e-24 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve endpoint parameter projection cannot use a collapsed line."
            )
        }
        return clampedUnit(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
    }

    private func arcParameter(
        _ arc: SketchArc,
        near point: Point2D,
        document: DesignDocument
    ) throws -> Double {
        let center = try resolvedPoint(arc.center, document: document)
        let radius = try resolvedValue(arc.radius, kind: .length, document: document)
        guard radius > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve endpoint parameter projection cannot use a collapsed arc."
            )
        }
        let dx = point.x - center.x
        let dy = point.y - center.y
        guard dx * dx + dy * dy > 1.0e-24 else {
            return 0.0
        }
        let startAngle = try resolvedValue(arc.startAngle, kind: .angle, document: document)
        let endAngle = try resolvedValue(arc.endAngle, kind: .angle, document: document)
        let span = normalizedAngleSpan(startAngle: startAngle, endAngle: endAngle)
        let angle = atan2(dy, dx)
        let delta = normalizedAngleDelta(from: startAngle, to: angle)
        if delta <= span || abs(span - Double.pi * 2.0) <= 1.0e-12 {
            return clampedUnit(delta / max(span, 1.0e-12))
        }
        let startPoint = Point2D(
            x: center.x + cos(startAngle) * radius,
            y: center.y + sin(startAngle) * radius
        )
        let endPoint = Point2D(
            x: center.x + cos(startAngle + span) * radius,
            y: center.y + sin(startAngle + span) * radius
        )
        return distanceSquared(from: point, to: startPoint) <= distanceSquared(from: point, to: endPoint)
            ? 0.0
            : 1.0
    }

    private func splineParameter(
        _ spline: SketchSpline,
        near point: Point2D,
        document: DesignDocument
    ) throws -> Double {
        let controlPoints = try spline.controlPoints.map { try resolvedPoint($0, document: document) }
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve endpoint parameter projection requires a cubic Bezier spline."
            )
        }
        let segmentCount = (controlPoints.count - 1) / 3
        var best: (segment: Int, t: Double, distanceSquared: Double)?
        let coarseSteps = 12
        for segment in 0 ..< segmentCount {
            var previousT = 0.0
            var previousDistance = distanceSquared(
                from: point,
                to: splinePoint(controlPoints: controlPoints, segment: segment, t: previousT)
            )
            for step in 1 ... coarseSteps {
                let currentT = Double(step) / Double(coarseSteps)
                let currentDistance = distanceSquared(
                    from: point,
                    to: splinePoint(controlPoints: controlPoints, segment: segment, t: currentT)
                )
                let localBest = refinedSplineParameter(
                    controlPoints: controlPoints,
                    segment: segment,
                    lower: previousT,
                    upper: currentT,
                    near: point
                )
                if best.map({ localBest.distanceSquared < $0.distanceSquared }) ?? true {
                    best = (segment, localBest.t, localBest.distanceSquared)
                }
                if previousDistance < currentDistance,
                   (best.map({ previousDistance < $0.distanceSquared }) ?? true) {
                    best = (segment, previousT, previousDistance)
                }
                previousT = currentT
                previousDistance = currentDistance
            }
        }
        guard let best else {
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve endpoint parameter projection could not sample the spline."
            )
        }
        return clampedUnit((Double(best.segment) + best.t) / Double(segmentCount))
    }

    private func refinedSplineParameter(
        controlPoints: [Point2D],
        segment: Int,
        lower: Double,
        upper: Double,
        near point: Point2D
    ) -> (t: Double, distanceSquared: Double) {
        var low = lower
        var high = upper
        for _ in 0 ..< 32 {
            let first = low + (high - low) / 3.0
            let second = high - (high - low) / 3.0
            let firstDistance = distanceSquared(
                from: point,
                to: splinePoint(controlPoints: controlPoints, segment: segment, t: first)
            )
            let secondDistance = distanceSquared(
                from: point,
                to: splinePoint(controlPoints: controlPoints, segment: segment, t: second)
            )
            if firstDistance < secondDistance {
                high = second
            } else {
                low = first
            }
        }
        let t = (low + high) / 2.0
        return (
            t,
            distanceSquared(from: point, to: splinePoint(controlPoints: controlPoints, segment: segment, t: t))
        )
    }

    private func splinePoint(
        controlPoints: [Point2D],
        segment: Int,
        t: Double
    ) -> Point2D {
        let start = segment * 3
        return cubicBezierPoint(
            controlPoints[start],
            controlPoints[start + 1],
            controlPoints[start + 2],
            controlPoints[start + 3],
            t: clampedUnit(t)
        )
    }

    private func cubicBezierPoint(
        _ p0: Point2D,
        _ p1: Point2D,
        _ p2: Point2D,
        _ p3: Point2D,
        t: Double
    ) -> Point2D {
        let inverse = 1.0 - t
        let b0 = inverse * inverse * inverse
        let b1 = 3.0 * inverse * inverse * t
        let b2 = 3.0 * inverse * t * t
        let b3 = t * t * t
        return Point2D(
            x: p0.x * b0 + p1.x * b1 + p2.x * b2 + p3.x * b3,
            y: p0.y * b0 + p1.y * b1 + p2.y * b2 + p3.y * b3
        )
    }

    private func distanceSquared(from first: Point2D, to second: Point2D) -> Double {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return dx * dx + dy * dy
    }

    private func entityID(for reference: SketchReference) -> SketchEntityID? {
        switch reference {
        case let .entity(entityID),
             let .lineStart(entityID),
             let .lineEnd(entityID),
             let .arcStart(entityID),
             let .arcEnd(entityID),
             let .splineControlPoint(entityID, _):
            return entityID
        case .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius:
            return nil
        }
    }

    private func resolvedPoint(
        _ point: SketchPoint,
        document: DesignDocument
    ) throws -> Point2D {
        Point2D(
            x: try document.resolvedLengthValue(point.x, owner: "Bridge curve endpoint x"),
            y: try document.resolvedLengthValue(point.y, owner: "Bridge curve endpoint y")
        )
    }

    private func resolvedValue(
        _ expression: CADExpression,
        kind: QuantityKind,
        document: DesignDocument
    ) throws -> Double {
        switch kind {
        case .length:
            return try document.resolvedLengthValue(expression, owner: "Bridge curve endpoint length")
        case .angle:
            return try document.resolvedAngleValue(expression, owner: "Bridge curve endpoint angle")
        case .scalar:
            return try document.resolvedScalarValue(expression, owner: "Bridge curve endpoint scalar")
        }
    }

    private func resolvedParameter(
        _ expression: CADExpression,
        document: DesignDocument,
        owner: String
    ) throws -> Double {
        let value = try document.resolvedScalarValue(expression, owner: owner)
        guard value >= 0.0,
              value <= 1.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a scalar from 0 through 1."
            )
        }
        return value
    }

    private func sourceEntity(
        for reference: SketchReference,
        featureID: FeatureID,
        in document: DesignDocument
    ) throws -> (sketch: Sketch, entity: SketchEntity) {
        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              case .sketch(let sketch) = feature.operation,
              let entityID = entityID(for: reference),
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve endpoint parameter projection requires an editable source curve."
            )
        }
        return (sketch: sketch, entity: entity)
    }

    private func supportsProjection(_ entity: SketchEntity) -> Bool {
        switch entity {
        case .line,
             .arc,
             .spline:
            return true
        case .point,
             .circle:
            return false
        }
    }

    private func normalizedAngleSpan(startAngle: Double, endAngle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        let tolerance = 1.0e-12
        var span = endAngle - startAngle
        while span <= tolerance {
            span += fullCircle
        }
        while span > fullCircle + tolerance {
            span -= fullCircle
        }
        return min(span, fullCircle)
    }

    private func normalizedAngleDelta(from startAngle: Double, to angle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        var delta = angle - startAngle
        while delta < 0.0 {
            delta += fullCircle
        }
        while delta > fullCircle {
            delta -= fullCircle
        }
        return delta
    }

    private func clampedUnit(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }
}
