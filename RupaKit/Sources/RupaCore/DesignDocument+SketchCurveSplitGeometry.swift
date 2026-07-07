import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    enum SketchSplineSplitResolution {
        case interior(segmentCount: Int, segmentIndex: Int, segmentLocal: Double)
        case knot(segmentCount: Int, knotSegmentIndex: Int)
    }

    struct SketchCurveSegmentSplitResult {
        var originalEntityID: SketchEntityID
        var newEntityID: SketchEntityID
        var fraction: Double
        var retainedEntity: SketchEntity
        var newEntity: SketchEntity
        var insertedRetainedReference: SketchReference
        var insertedNewReference: SketchReference
        var originalEndReference: SketchReference
        var migratedEndReference: SketchReference
        var splineResolution: SketchSplineSplitResolution? = nil
    }

    func splitSketchCurveEntity(
        _ entity: SketchEntity,
        entityID: SketchEntityID,
        newEntityID: SketchEntityID,
        fraction: Double,
        owner: String
    ) throws -> SketchCurveSegmentSplitResult {
        switch entity {
        case .line(let line):
            let splitPoint = try splitPoint(on: line, fraction: fraction, owner: owner)
            let retainedLine = SketchLine(start: line.start, end: splitPoint)
            let newLine = SketchLine(start: splitPoint, end: line.end)
            _ = try resolvedLineMetrics(retainedLine, owner: owner)
            _ = try resolvedLineMetrics(newLine, owner: owner)
            return SketchCurveSegmentSplitResult(
                originalEntityID: entityID,
                newEntityID: newEntityID,
                fraction: fraction,
                retainedEntity: .line(retainedLine),
                newEntity: .line(newLine),
                insertedRetainedReference: .lineEnd(entityID),
                insertedNewReference: .lineStart(newEntityID),
                originalEndReference: .lineEnd(entityID),
                migratedEndReference: .lineEnd(newEntityID)
            )
        case .spline(let spline):
            let split = try splitSpline(
                spline,
                fraction: fraction,
                owner: owner
            )
            try validateSpline(split.retained, owner: owner)
            try validateSpline(split.new, owner: owner)
            return SketchCurveSegmentSplitResult(
                originalEntityID: entityID,
                newEntityID: newEntityID,
                fraction: fraction,
                retainedEntity: .spline(split.retained),
                newEntity: .spline(split.new),
                insertedRetainedReference: .splineControlPoint(
                    entity: entityID,
                    index: split.retained.controlPoints.count - 1
                ),
                insertedNewReference: .splineControlPoint(entity: newEntityID, index: 0),
                originalEndReference: .splineControlPoint(
                    entity: entityID,
                    index: spline.controlPoints.count - 1
                ),
                migratedEndReference: .splineControlPoint(
                    entity: newEntityID,
                    index: split.new.controlPoints.count - 1
                ),
                splineResolution: split.resolution
            )
        case .arc(let arc):
            let split = try splitArc(
                arc,
                fraction: fraction,
                owner: owner
            )
            try validateArc(split.retained, owner: owner)
            try validateArc(split.new, owner: owner)
            return SketchCurveSegmentSplitResult(
                originalEntityID: entityID,
                newEntityID: newEntityID,
                fraction: fraction,
                retainedEntity: .arc(split.retained),
                newEntity: .arc(split.new),
                insertedRetainedReference: .arcEnd(entityID),
                insertedNewReference: .arcStart(newEntityID),
                originalEndReference: .arcEnd(entityID),
                migratedEndReference: .arcEnd(newEntityID)
            )
        case .point,
             .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line, arc, or spline curve target."
            )
        }
    }

    func splitArc(
        _ arc: SketchArc,
        fraction: Double,
        owner: String
    ) throws -> (retained: SketchArc, new: SketchArc) {
        let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) arc start angle")
        let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) arc end angle")
        let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
        let splitAngle = startAngle + span * fraction
        let splitExpression = CADExpression.angle(splitAngle, .radian)
        return (
            retained: SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: arc.startAngle,
                endAngle: splitExpression
            ),
            new: SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: splitExpression,
                endAngle: arc.endAngle
            )
        )
    }

    func splitPoint(
        on line: SketchLine,
        fraction: Double,
        owner: String
    ) throws -> SketchPoint {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        guard hypot(deltaX, deltaY) > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        return sketchPoint(
            x: startX + deltaX * fraction,
            y: startY + deltaY * fraction
        )
    }

    func splitSpline(
        _ spline: SketchSpline,
        fraction: Double,
        owner: String
    ) throws -> (retained: SketchSpline, new: SketchSpline, resolution: SketchSplineSplitResolution) {
        let controlPoints = spline.controlPoints
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }
        let segmentCount = (controlPoints.count - 1) / 3
        let scaledParameter = fraction * Double(segmentCount)
        var segmentIndex = Int(floor(scaledParameter))
        let localFraction = scaledParameter - Double(segmentIndex)
        let tolerance = 1.0e-9

        if localFraction <= tolerance {
            guard segmentIndex > 0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) fraction must not resolve to the spline start."
                )
            }
            let knotSplit = splitSplineAtExistingKnot(
                spline,
                knotIndex: segmentIndex * 3,
                owner: owner
            )
            return (
                retained: knotSplit.retained,
                new: knotSplit.new,
                resolution: .knot(segmentCount: segmentCount, knotSegmentIndex: segmentIndex)
            )
        }
        if localFraction >= 1.0 - tolerance {
            segmentIndex += 1
            guard segmentIndex < segmentCount else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) fraction must not resolve to the spline end."
                )
            }
            let knotSplit = splitSplineAtExistingKnot(
                spline,
                knotIndex: segmentIndex * 3,
                owner: owner
            )
            return (
                retained: knotSplit.retained,
                new: knotSplit.new,
                resolution: .knot(segmentCount: segmentCount, knotSegmentIndex: segmentIndex)
            )
        }

        let segmentStart = segmentIndex * 3
        let p0 = controlPoints[segmentStart]
        let p1 = controlPoints[segmentStart + 1]
        let p2 = controlPoints[segmentStart + 2]
        let p3 = controlPoints[segmentStart + 3]
        let split = splitCubicBezier(
            p0,
            p1,
            p2,
            p3,
            fraction: .scalar(localFraction)
        )
        var retained = Array(controlPoints[0 ... segmentStart])
        retained.append(contentsOf: [split.left.1, split.left.2, split.left.3])
        var next = [split.right.0, split.right.1, split.right.2, split.right.3]
        if segmentStart + 4 < controlPoints.count {
            next.append(contentsOf: controlPoints[(segmentStart + 4)...])
        }
        guard retained.count >= 4,
              next.count >= 4 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) produced an invalid spline split."
            )
        }
        return (
            retained: SketchSpline(controlPoints: retained),
            new: SketchSpline(controlPoints: next),
            resolution: .interior(
                segmentCount: segmentCount,
                segmentIndex: segmentIndex,
                segmentLocal: localFraction
            )
        )
    }

    private func splitSplineAtExistingKnot(
        _ spline: SketchSpline,
        knotIndex: Int,
        owner: String
    ) -> (retained: SketchSpline, new: SketchSpline) {
        let controlPoints = spline.controlPoints
        precondition(knotIndex > 0 && knotIndex < controlPoints.count - 1)
        let retained = Array(controlPoints[0 ... knotIndex])
        let next = Array(controlPoints[knotIndex...])
        return (
            retained: SketchSpline(controlPoints: retained),
            new: SketchSpline(controlPoints: next)
        )
    }

    func splitCubicBezier(
        _ p0: SketchPoint,
        _ p1: SketchPoint,
        _ p2: SketchPoint,
        _ p3: SketchPoint,
        fraction: CADExpression
    ) -> (
        left: (SketchPoint, SketchPoint, SketchPoint, SketchPoint),
        right: (SketchPoint, SketchPoint, SketchPoint, SketchPoint)
    ) {
        let q0 = interpolatedSketchPoint(p0, p1, fraction: fraction)
        let q1 = interpolatedSketchPoint(p1, p2, fraction: fraction)
        let q2 = interpolatedSketchPoint(p2, p3, fraction: fraction)
        let r0 = interpolatedSketchPoint(q0, q1, fraction: fraction)
        let r1 = interpolatedSketchPoint(q1, q2, fraction: fraction)
        let s = interpolatedSketchPoint(r0, r1, fraction: fraction)
        return (
            left: (p0, q0, r0, s),
            right: (s, r1, q2, p3)
        )
    }

    private func interpolatedSketchPoint(
        _ first: SketchPoint,
        _ second: SketchPoint,
        fraction: CADExpression
    ) -> SketchPoint {
        SketchPoint(
            x: .add(first.x, .multiply(.subtract(second.x, first.x), fraction)),
            y: .add(first.y, .multiply(.subtract(second.y, first.y), fraction))
        )
    }
}
