import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func cutCurveSplineSampleSegments(
        _ samples: [CurveEvaluationSample]
    ) -> [CutCurveSplineSampleSegment] {
        // Drop only truly degenerate chords (near-duplicate samples). The
        // previous CAD-tolerance floor (1e-6 m) made every Bezier segment
        // shorter than ~64x tolerance invisible to Cut, silently skipping
        // intersections on small features while others succeeded. The floor is
        // relative to the sampled polyline length, so it scales with the curve.
        var totalLength = 0.0
        for (start, end) in zip(samples, samples.dropFirst()) {
            totalLength += hypot(end.point.x - start.point.x, end.point.y - start.point.y)
        }
        let degenerateChordFloor = max(totalLength * 1.0e-12, 1.0e-15)
        return zip(samples, samples.dropFirst()).compactMap { start, end in
            let length = hypot(end.point.x - start.point.x, end.point.y - start.point.y)
            guard length > degenerateChordFloor else {
                return nil
            }
            return (start: start, end: end)
        }
    }

    func cutFractionsForLineSplineIntersection(
        target: CutCurveLineSegment,
        cutterSamples: [CurveEvaluationSample]
    ) -> [Double] {
        cutCurveSplineSampleSegments(cutterSamples).flatMap { segment in
            cutFractionsForLineTargetSplineSegmentIntersection(
                target: target,
                cutterSegment: segment
            )
        }
    }

    func cutFractionsForArcSplineIntersection(
        target: CutCurveArc,
        cutterSamples: [CurveEvaluationSample]
    ) -> [Double] {
        cutCurveSplineSampleSegments(cutterSamples).flatMap { segment in
            cutFractionsForArcTargetSplineSegmentIntersection(
                target: target,
                cutterSegment: segment
            )
        }
    }

    func cutAnglesForCircleSplineIntersection(
        target: CutCurveCircle,
        cutterSamples: [CurveEvaluationSample]
    ) -> [Double] {
        cutCurveSplineSampleSegments(cutterSamples).flatMap { segment in
            cutAnglesForCircleTargetSplineSegmentIntersection(
                target: target,
                cutterSegment: segment
            )
        }
    }

    func cutFractionsForSplineSplineIntersection(
        targetSamples: [CurveEvaluationSample],
        cutterSamples: [CurveEvaluationSample]
    ) -> [Double] {
        let targetSegments = cutCurveSplineSampleSegments(targetSamples)
        let cutterSegments = cutCurveSplineSampleSegments(cutterSamples)
        var fractions: [Double] = []
        for targetSegment in targetSegments {
            for cutterSegment in cutterSegments where cutCurveSampleSegmentsMayIntersect(
                targetSegment,
                cutterSegment
            ) {
                fractions.append(
                    contentsOf: cutFractionsForSplineSegmentSplineSegmentIntersection(
                        targetSegment: targetSegment,
                        cutterSegment: cutterSegment
                    )
                )
            }
        }
        return fractions
    }

    func cutFractionsForLineTargetSplineSegmentIntersection(
        target: CutCurveLineSegment,
        cutterSegment: CutCurveSplineSampleSegment
    ) -> [Double] {
        guard let fractions = cutCurveLineIntersectionFractions(
            firstStartX: target.startX,
            firstStartY: target.startY,
            firstEndX: target.endX,
            firstEndY: target.endY,
            secondStartX: cutterSegment.start.point.x,
            secondStartY: cutterSegment.start.point.y,
            secondEndX: cutterSegment.end.point.x,
            secondEndY: cutterSegment.end.point.y
        ) else {
            return []
        }
        let tolerance = 1.0e-10
        guard fractions.first > tolerance,
              fractions.first < 1.0 - tolerance else {
            return []
        }
        return [fractions.first]
    }

    func cutFractionsForArcTargetSplineSegmentIntersection(
        target: CutCurveArc,
        cutterSegment: CutCurveSplineSampleSegment
    ) -> [Double] {
        let cutterX = cutterSegment.end.point.x - cutterSegment.start.point.x
        let cutterY = cutterSegment.end.point.y - cutterSegment.start.point.y
        let lengthSquared = cutterX * cutterX + cutterY * cutterY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = cutterSegment.start.point.x - target.circle.centerX
        let offsetY = cutterSegment.start.point.y - target.circle.centerY
        let b = 2.0 * (offsetX * cutterX + offsetY * cutterY)
        let c = offsetX * offsetX + offsetY * offsetY - target.circle.radius * target.circle.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let cutterFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            cutterFractions = [-b / (2.0 * lengthSquared)]
        } else {
            cutterFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        return cutterFractions.compactMap { cutterFraction -> Double? in
            guard cutterFraction >= -tolerance,
                  cutterFraction <= 1.0 + tolerance else {
                return nil
            }
            let pointX = cutterSegment.start.point.x + cutterX * cutterFraction
            let pointY = cutterSegment.start.point.y + cutterY * cutterFraction
            let angle = atan2(pointY - target.circle.centerY, pointX - target.circle.centerX)
            guard cutCurveAngleIsOnArc(
                angle,
                startAngle: target.startAngle,
                endAngle: target.endAngle
            ) else {
                return nil
            }
            return cutCurveArcFraction(for: angle, on: target)
        }
    }

    func cutAnglesForCircleTargetSplineSegmentIntersection(
        target: CutCurveCircle,
        cutterSegment: CutCurveSplineSampleSegment
    ) -> [Double] {
        let cutterX = cutterSegment.end.point.x - cutterSegment.start.point.x
        let cutterY = cutterSegment.end.point.y - cutterSegment.start.point.y
        let lengthSquared = cutterX * cutterX + cutterY * cutterY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = cutterSegment.start.point.x - target.centerX
        let offsetY = cutterSegment.start.point.y - target.centerY
        let b = 2.0 * (offsetX * cutterX + offsetY * cutterY)
        let c = offsetX * offsetX + offsetY * offsetY - target.radius * target.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let cutterFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            cutterFractions = [-b / (2.0 * lengthSquared)]
        } else {
            cutterFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        return cutterFractions.compactMap { cutterFraction -> Double? in
            guard cutterFraction >= -tolerance,
                  cutterFraction <= 1.0 + tolerance else {
                return nil
            }
            let pointX = cutterSegment.start.point.x + cutterX * cutterFraction
            let pointY = cutterSegment.start.point.y + cutterY * cutterFraction
            return atan2(pointY - target.centerY, pointX - target.centerX)
        }
    }

    func cutFractionsForSplineSegmentSplineSegmentIntersection(
        targetSegment: CutCurveSplineSampleSegment,
        cutterSegment: CutCurveSplineSampleSegment
    ) -> [Double] {
        guard let fractions = cutCurveLineIntersectionFractions(
            firstStartX: targetSegment.start.point.x,
            firstStartY: targetSegment.start.point.y,
            firstEndX: targetSegment.end.point.x,
            firstEndY: targetSegment.end.point.y,
            secondStartX: cutterSegment.start.point.x,
            secondStartY: cutterSegment.start.point.y,
            secondEndX: cutterSegment.end.point.x,
            secondEndY: cutterSegment.end.point.y
        ) else {
            return []
        }
        return [
            cutCurveSplineSegmentParameter(
                segment: targetSegment,
                localFraction: fractions.first
            ),
        ]
    }

    func cutCurveLineIntersectionFractions(
        firstStartX: Double,
        firstStartY: Double,
        firstEndX: Double,
        firstEndY: Double,
        secondStartX: Double,
        secondStartY: Double,
        secondEndX: Double,
        secondEndY: Double
    ) -> (first: Double, second: Double)? {
        let firstX = firstEndX - firstStartX
        let firstY = firstEndY - firstStartY
        let secondX = secondEndX - secondStartX
        let secondY = secondEndY - secondStartY
        let denominator = firstX * secondY - firstY * secondX
        guard abs(denominator) > 1.0e-14 else {
            return nil
        }

        let deltaX = secondStartX - firstStartX
        let deltaY = secondStartY - firstStartY
        let firstFraction = (deltaX * secondY - deltaY * secondX) / denominator
        let secondFraction = (deltaX * firstY - deltaY * firstX) / denominator
        let tolerance = 1.0e-10
        guard firstFraction >= -tolerance,
              firstFraction <= 1.0 + tolerance,
              secondFraction >= -tolerance,
              secondFraction <= 1.0 + tolerance else {
            return nil
        }
        return (
            first: min(max(firstFraction, 0.0), 1.0),
            second: min(max(secondFraction, 0.0), 1.0)
        )
    }

    func cutCurveSampleSegmentsMayIntersect(
        _ first: CutCurveSplineSampleSegment,
        _ second: CutCurveSplineSampleSegment
    ) -> Bool {
        let tolerance = 1.0e-10
        let firstMinX = min(first.start.point.x, first.end.point.x) - tolerance
        let firstMaxX = max(first.start.point.x, first.end.point.x) + tolerance
        let firstMinY = min(first.start.point.y, first.end.point.y) - tolerance
        let firstMaxY = max(first.start.point.y, first.end.point.y) + tolerance
        let secondMinX = min(second.start.point.x, second.end.point.x) - tolerance
        let secondMaxX = max(second.start.point.x, second.end.point.x) + tolerance
        let secondMinY = min(second.start.point.y, second.end.point.y) - tolerance
        let secondMaxY = max(second.start.point.y, second.end.point.y) + tolerance
        return firstMaxX >= secondMinX &&
            secondMaxX >= firstMinX &&
            firstMaxY >= secondMinY &&
            secondMaxY >= firstMinY
    }

    func cutFractionsForSplineSegmentLineIntersection(
        segment: CutCurveSplineSampleSegment,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) -> (fractions: [Double], rejectedByCutterReach: Bool) {
        let targetX = segment.end.point.x - segment.start.point.x
        let targetY = segment.end.point.y - segment.start.point.y
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let denominator = targetX * cutterY - targetY * cutterX
        guard abs(denominator) > 1.0e-14 else {
            return (fractions: [], rejectedByCutterReach: false)
        }

        let deltaX = cutter.startX - segment.start.point.x
        let deltaY = cutter.startY - segment.start.point.y
        let targetFraction = (deltaX * cutterY - deltaY * cutterX) / denominator
        let cutterFraction = (deltaX * targetY - deltaY * targetX) / denominator
        let tolerance = 1.0e-10
        guard targetFraction >= -tolerance,
              targetFraction <= 1.0 + tolerance else {
            return (fractions: [], rejectedByCutterReach: false)
        }
        if extendsCutter == false &&
            (cutterFraction < -tolerance || cutterFraction > 1.0 + tolerance) {
            return (fractions: [], rejectedByCutterReach: true)
        }
        return (
            fractions: [
                cutCurveSplineSegmentParameter(
                    segment: segment,
                    localFraction: targetFraction
                ),
            ],
            rejectedByCutterReach: false
        )
    }

    func cutFractionsForSplineSegmentCircleIntersection(
        segment: CutCurveSplineSampleSegment,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) -> [Double] {
        let targetX = segment.end.point.x - segment.start.point.x
        let targetY = segment.end.point.y - segment.start.point.y
        let lengthSquared = targetX * targetX + targetY * targetY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = segment.start.point.x - circle.centerX
        let offsetY = segment.start.point.y - circle.centerY
        let b = 2.0 * (offsetX * targetX + offsetY * targetY)
        let c = offsetX * offsetX + offsetY * offsetY - circle.radius * circle.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }

        let root = sqrt(max(discriminant, 0.0))
        let localFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            localFractions = [-b / (2.0 * lengthSquared)]
        } else {
            localFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        return localFractions.compactMap { localFraction -> Double? in
            guard localFraction >= -tolerance,
                  localFraction <= 1.0 + tolerance else {
                return nil
            }
            let pointX = segment.start.point.x + targetX * localFraction
            let pointY = segment.start.point.y + targetY * localFraction
            if let arc {
                let angle = atan2(pointY - arc.circle.centerY, pointX - arc.circle.centerX)
                guard cutCurveAngleIsOnArc(
                    angle,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle
                ) else {
                    return nil
                }
            }
            return cutCurveSplineSegmentParameter(
                segment: segment,
                localFraction: localFraction
            )
        }
    }

    func cutCurveSplineSegmentParameter(
        segment: CutCurveSplineSampleSegment,
        localFraction: Double
    ) -> Double {
        let clampedFraction = min(max(localFraction, 0.0), 1.0)
        return segment.start.parameter +
            (segment.end.parameter - segment.start.parameter) * clampedFraction
    }
}
