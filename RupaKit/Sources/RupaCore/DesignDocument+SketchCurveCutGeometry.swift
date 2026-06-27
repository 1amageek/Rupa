import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    private struct CutCurveLineSegment {
        var startX: Double
        var startY: Double
        var endX: Double
        var endY: Double
    }

    struct CutCurveCircle {
        var centerX: Double
        var centerY: Double
        var radius: Double
    }

    private struct CutCurveArc {
        var circle: CutCurveCircle
        var startAngle: Double
        var endAngle: Double
    }

    private static let cutCurveSplineSamplesPerSegment = 64
    private typealias CutCurveSplineSampleSegment = (
        start: CurveEvaluationSample,
        end: CurveEvaluationSample
    )

    func cutSketchCurveFractions(
        targetSelection: EditableSketchEntitySelection,
        cutterSelection: EditableSketchEntitySelection,
        options: CutCurveOptions
    ) throws -> [Double] {
        try validateCutSketchCurveSelections(
            targetSelection: targetSelection,
            cutterSelection: cutterSelection,
            options: options
        )
        let fractions: [Double]
        switch targetSelection.entity {
        case .line(let targetLine):
            let target = try resolvedCutCurveLineSegment(targetLine, owner: "Cut Curve target")
            fractions = try cutFractionsForLineTarget(
                target: target,
                cutterSelection: cutterSelection,
                extendsCutter: options.extendsCutter
            )
        case .arc(let targetArc):
            let target = try resolvedCutCurveArc(targetArc, owner: "Cut Curve target")
            fractions = try cutFractionsForArcTarget(
                target: target,
                cutterSelection: cutterSelection,
                extendsCutter: options.extendsCutter
            )
        case .spline(let targetSpline):
            let samples = try resolvedCutCurveSplineSamples(
                targetSpline,
                owner: "Cut Curve target"
            )
            fractions = try cutFractionsForSplineTarget(
                samples: samples,
                cutterSelection: cutterSelection,
                extendsCutter: options.extendsCutter
            )
        case .point, .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, arc, or open spline target curve."
            )
        }
        let uniqueFractions = uniqueInteriorCutFractions(fractions)
        guard uniqueFractions.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cutter does not intersect the target curve inside the supported target segment."
            )
        }
        return uniqueFractions
    }

    private func cutFractionsForLineTarget(
        target: CutCurveLineSegment,
        cutterSelection: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            feature: FeatureNode,
            sketch: Sketch,
            entity: SketchEntity
        ),
        extendsCutter: Bool
    ) throws -> [Double] {
        switch cutterSelection.entity {
        case .line(let cutterLine):
            let cutter = try resolvedCutCurveLineSegment(cutterLine, owner: "Cut Curve cutter")
            return try cutFractionsForLineLineIntersection(
                target: target,
                cutter: cutter,
                extendsCutter: extendsCutter
            )
        case .circle(let circle):
            let cutter = try resolvedCutCurveCircle(circle, owner: "Cut Curve cutter")
            return cutFractionsForLineCircleIntersection(
                target: target,
                circle: cutter,
                restrictToArc: nil
            )
        case .arc(let arc):
            let cutter = try resolvedCutCurveArc(arc, owner: "Cut Curve cutter")
            return cutFractionsForLineCircleIntersection(
                target: target,
                circle: cutter.circle,
                restrictToArc: extendsCutter ? nil : cutter
            )
        case .spline(let spline):
            guard extendsCutter == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve spline cutter extension is not represented in the current source subset."
                )
            }
            let cutterSamples = try resolvedCutCurveSplineSamples(
                spline,
                owner: "Cut Curve cutter"
            )
            return cutFractionsForLineSplineIntersection(
                target: target,
                cutterSamples: cutterSamples
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, circle, arc, or open spline cutter curve."
            )
        }
    }

    private func cutFractionsForSplineTarget(
        samples: [CurveEvaluationSample],
        cutterSelection: EditableSketchEntitySelection,
        extendsCutter: Bool
    ) throws -> [Double] {
        switch cutterSelection.entity {
        case .line(let cutterLine):
            let cutter = try resolvedCutCurveLineSegment(cutterLine, owner: "Cut Curve cutter")
            var rejectedByCutterReach = false
            var fractions: [Double] = []
            for segment in cutCurveSplineSampleSegments(samples) {
                let result = cutFractionsForSplineSegmentLineIntersection(
                    segment: segment,
                    cutter: cutter,
                    extendsCutter: extendsCutter
                )
                rejectedByCutterReach = rejectedByCutterReach || result.rejectedByCutterReach
                fractions.append(contentsOf: result.fractions)
            }
            if fractions.isEmpty && rejectedByCutterReach {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
                )
            }
            return fractions
        case .circle(let circle):
            let cutter = try resolvedCutCurveCircle(circle, owner: "Cut Curve cutter")
            return cutCurveSplineSampleSegments(samples).flatMap { segment in
                cutFractionsForSplineSegmentCircleIntersection(
                    segment: segment,
                    circle: cutter,
                    restrictToArc: nil
                )
            }
        case .arc(let arc):
            let cutter = try resolvedCutCurveArc(arc, owner: "Cut Curve cutter")
            return cutCurveSplineSampleSegments(samples).flatMap { segment in
                cutFractionsForSplineSegmentCircleIntersection(
                    segment: segment,
                    circle: cutter.circle,
                    restrictToArc: extendsCutter ? nil : cutter
                )
            }
        case .spline(let spline):
            guard extendsCutter == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve spline cutter extension is not represented in the current source subset."
                )
            }
            let cutterSamples = try resolvedCutCurveSplineSamples(
                spline,
                owner: "Cut Curve cutter"
            )
            return cutFractionsForSplineSplineIntersection(
                targetSamples: samples,
                cutterSamples: cutterSamples
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, circle, arc, or open spline cutter curve."
            )
        }
    }

    func validateCutSketchCurveSelections(
        targetSelection: EditableSketchEntitySelection,
        cutterSelection: EditableSketchEntitySelection,
        options: CutCurveOptions
    ) throws {
        guard options.usesScreenSpaceDirection == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve screen-space direction requires a 3D cutter context that is not represented yet."
            )
        }
        guard targetSelection.featureID != cutterSelection.featureID ||
            targetSelection.entityID != cutterSelection.entityID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve requires distinct target and cutter curves."
            )
        }
        guard targetSelection.sketch.plane == cutterSelection.sketch.plane else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source curve cutter requires target and cutter to share a sketch plane."
            )
        }
    }

    func cutAnglesForCircleTarget(
        target: CutCurveCircle,
        cutterSelection: EditableSketchEntitySelection,
        extendsCutter: Bool
    ) throws -> [Double] {
        let angles: [Double]
        switch cutterSelection.entity {
        case .line(let cutterLine):
            let cutter = try resolvedCutCurveLineSegment(cutterLine, owner: "Cut Curve cutter")
            angles = try cutAnglesForCircleLineIntersection(
                target: target,
                cutter: cutter,
                extendsCutter: extendsCutter
            )
        case .circle(let circle):
            let cutter = try resolvedCutCurveCircle(circle, owner: "Cut Curve cutter")
            angles = try cutAnglesForCircleCircleIntersection(
                target: target,
                circle: cutter,
                restrictToArc: nil
            )
        case .arc(let arc):
            let cutter = try resolvedCutCurveArc(arc, owner: "Cut Curve cutter")
            angles = try cutAnglesForCircleCircleIntersection(
                target: target,
                circle: cutter.circle,
                restrictToArc: extendsCutter ? nil : cutter
            )
        case .spline(let spline):
            guard extendsCutter == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve spline cutter extension is not represented in the current source subset."
                )
            }
            let cutterSamples = try resolvedCutCurveSplineSamples(
                spline,
                owner: "Cut Curve cutter"
            )
            angles = cutAnglesForCircleSplineIntersection(
                target: target,
                cutterSamples: cutterSamples
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, circle, arc, or open spline cutter curve."
            )
        }
        let uniqueAngles = uniqueCutAngles(angles)
        guard uniqueAngles.count == 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve circle target requires two distinct cutter intersections to create two arc segments."
            )
        }
        return uniqueAngles
    }

    private func cutFractionsForArcTarget(
        target: CutCurveArc,
        cutterSelection: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            feature: FeatureNode,
            sketch: Sketch,
            entity: SketchEntity
        ),
        extendsCutter: Bool
    ) throws -> [Double] {
        switch cutterSelection.entity {
        case .line(let cutterLine):
            let cutter = try resolvedCutCurveLineSegment(cutterLine, owner: "Cut Curve cutter")
            return try cutFractionsForArcLineIntersection(
                target: target,
                cutter: cutter,
                extendsCutter: extendsCutter
            )
        case .circle(let circle):
            let cutter = try resolvedCutCurveCircle(circle, owner: "Cut Curve cutter")
            return try cutFractionsForArcCircleIntersection(
                target: target,
                circle: cutter,
                restrictToArc: nil
            )
        case .arc(let arc):
            let cutter = try resolvedCutCurveArc(arc, owner: "Cut Curve cutter")
            return try cutFractionsForArcCircleIntersection(
                target: target,
                circle: cutter.circle,
                restrictToArc: extendsCutter ? nil : cutter
            )
        case .spline(let spline):
            guard extendsCutter == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve spline cutter extension is not represented in the current source subset."
                )
            }
            let cutterSamples = try resolvedCutCurveSplineSamples(
                spline,
                owner: "Cut Curve cutter"
            )
            return cutFractionsForArcSplineIntersection(
                target: target,
                cutterSamples: cutterSamples
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, circle, arc, or open spline cutter curve."
            )
        }
    }

    private func resolvedCutCurveLineSegment(
        _ line: SketchLine,
        owner: String
    ) throws -> CutCurveLineSegment {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        guard hypot(deltaX, deltaY) > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) length must be greater than zero."
            )
        }
        return CutCurveLineSegment(
            startX: startX,
            startY: startY,
            endX: endX,
            endY: endY
        )
    }

    func resolvedCutCurveCircle(
        _ circle: SketchCircle,
        owner: String
    ) throws -> CutCurveCircle {
        let centerX = try resolvedLengthValue(circle.center.x, owner: "\(owner) center x")
        let centerY = try resolvedLengthValue(circle.center.y, owner: "\(owner) center y")
        let radius = try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) radius")
        return CutCurveCircle(centerX: centerX, centerY: centerY, radius: radius)
    }

    private func resolvedCutCurveArc(
        _ arc: SketchArc,
        owner: String
    ) throws -> CutCurveArc {
        let circle = try resolvedCutCurveCircle(
            SketchCircle(center: arc.center, radius: arc.radius),
            owner: owner
        )
        let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
        let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
        return CutCurveArc(circle: circle, startAngle: startAngle, endAngle: endAngle)
    }

    private func resolvedCutCurveSplineSamples(
        _ spline: SketchSpline,
        owner: String
    ) throws -> [CurveEvaluationSample] {
        guard spline.isClosed == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires an open spline curve."
            )
        }
        let controlPoints = try spline.controlPoints.map { point in
            try resolvedCutCurvePoint(point, owner: owner)
        }
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }
        let samples = SketchCurveSampler(
            samplesPerSegment: Self.cutCurveSplineSamplesPerSegment
        )
        .splineSamples(for: controlPoints)
        guard samples.count >= 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a spline with non-zero sampled length."
            )
        }
        return samples
    }

    private func resolvedCutCurvePoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> Point2D {
        Point2D(
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }

    private func cutFractionsForLineLineIntersection(
        target: CutCurveLineSegment,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) throws -> [Double] {
        let targetX = target.endX - target.startX
        let targetY = target.endY - target.startY
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let denominator = targetX * cutterY - targetY * cutterX
        guard abs(denominator) > 1.0e-14 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve line cutter must intersect the target line; parallel or overlapping lines are unsupported."
            )
        }

        let deltaX = cutter.startX - target.startX
        let deltaY = cutter.startY - target.startY
        let targetFraction = (deltaX * cutterY - deltaY * cutterX) / denominator
        let cutterFraction = (deltaX * targetY - deltaY * targetX) / denominator
        let tolerance = 1.0e-10
        guard targetFraction > tolerance,
              targetFraction < 1.0 - tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve intersection must fall inside the target curve segment, not on its endpoint."
            )
        }
        if extendsCutter == false {
            guard cutterFraction >= -tolerance,
                  cutterFraction <= 1.0 + tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
                )
            }
        }
        return [targetFraction]
    }

    private func cutCurveSplineSampleSegments(
        _ samples: [CurveEvaluationSample]
    ) -> [CutCurveSplineSampleSegment] {
        zip(samples, samples.dropFirst()).compactMap { start, end in
            let length = hypot(end.point.x - start.point.x, end.point.y - start.point.y)
            guard length > ModelingTolerance.standard.distance else {
                return nil
            }
            return (start: start, end: end)
        }
    }

    private func cutFractionsForLineSplineIntersection(
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

    private func cutFractionsForArcSplineIntersection(
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

    private func cutAnglesForCircleSplineIntersection(
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

    private func cutFractionsForSplineSplineIntersection(
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

    private func cutFractionsForLineTargetSplineSegmentIntersection(
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

    private func cutFractionsForArcTargetSplineSegmentIntersection(
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

    private func cutAnglesForCircleTargetSplineSegmentIntersection(
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

    private func cutFractionsForSplineSegmentSplineSegmentIntersection(
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

    private func cutCurveLineIntersectionFractions(
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

    private func cutCurveSampleSegmentsMayIntersect(
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

    private func cutFractionsForSplineSegmentLineIntersection(
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

    private func cutFractionsForSplineSegmentCircleIntersection(
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

    private func cutCurveSplineSegmentParameter(
        segment: CutCurveSplineSampleSegment,
        localFraction: Double
    ) -> Double {
        let clampedFraction = min(max(localFraction, 0.0), 1.0)
        return segment.start.parameter +
            (segment.end.parameter - segment.start.parameter) * clampedFraction
    }

    private func cutFractionsForLineCircleIntersection(
        target: CutCurveLineSegment,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) -> [Double] {
        let targetX = target.endX - target.startX
        let targetY = target.endY - target.startY
        let lengthSquared = targetX * targetX + targetY * targetY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = target.startX - circle.centerX
        let offsetY = target.startY - circle.centerY
        let b = 2.0 * (offsetX * targetX + offsetY * targetY)
        let c = offsetX * offsetX + offsetY * offsetY - circle.radius * circle.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let rawFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            rawFractions = [-b / (2.0 * lengthSquared)]
        } else {
            rawFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        return rawFractions.filter { fraction in
            guard fraction > tolerance,
                  fraction < 1.0 - tolerance else {
                return false
            }
            guard let arc else {
                return true
            }
            let pointX = target.startX + targetX * fraction
            let pointY = target.startY + targetY * fraction
            let angle = atan2(pointY - arc.circle.centerY, pointX - arc.circle.centerX)
            return cutCurveAngleIsOnArc(angle, startAngle: arc.startAngle, endAngle: arc.endAngle)
        }
    }

    private func cutFractionsForArcLineIntersection(
        target: CutCurveArc,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) throws -> [Double] {
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let lengthSquared = cutterX * cutterX + cutterY * cutterY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = cutter.startX - target.circle.centerX
        let offsetY = cutter.startY - target.circle.centerY
        let b = 2.0 * (offsetX * cutterX + offsetY * cutterY)
        let c = offsetX * offsetX + offsetY * offsetY - target.circle.radius * target.circle.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let rawCutterFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            rawCutterFractions = [-b / (2.0 * lengthSquared)]
        } else {
            rawCutterFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        var rejectedByCutterReach = false
        let targetFractions = rawCutterFractions.compactMap { cutterFraction -> Double? in
            let pointX = cutter.startX + cutterX * cutterFraction
            let pointY = cutter.startY + cutterY * cutterFraction
            let angle = atan2(pointY - target.circle.centerY, pointX - target.circle.centerX)
            guard cutCurveAngleIsOnArc(
                angle,
                startAngle: target.startAngle,
                endAngle: target.endAngle
            ) else {
                return nil
            }
            if extendsCutter == false &&
                (cutterFraction < -tolerance || cutterFraction > 1.0 + tolerance) {
                rejectedByCutterReach = true
                return nil
            }
            return cutCurveArcFraction(for: angle, on: target)
        }
        if targetFractions.isEmpty && rejectedByCutterReach {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
            )
        }
        return targetFractions
    }

    private func cutFractionsForArcCircleIntersection(
        target: CutCurveArc,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) throws -> [Double] {
        let points = try cutCurveCircleCircleIntersections(
            target.circle,
            circle
        )
        return points.compactMap { point -> Double? in
            let targetAngle = atan2(
                point.y - target.circle.centerY,
                point.x - target.circle.centerX
            )
            guard cutCurveAngleIsOnArc(
                targetAngle,
                startAngle: target.startAngle,
                endAngle: target.endAngle
            ) else {
                return nil
            }
            if let arc {
                let cutterAngle = atan2(
                    point.y - arc.circle.centerY,
                    point.x - arc.circle.centerX
                )
                guard cutCurveAngleIsOnArc(
                    cutterAngle,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle
                ) else {
                    return nil
                }
            }
            return cutCurveArcFraction(for: targetAngle, on: target)
        }
    }

    private func cutAnglesForCircleLineIntersection(
        target: CutCurveCircle,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) throws -> [Double] {
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let lengthSquared = cutterX * cutterX + cutterY * cutterY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = cutter.startX - target.centerX
        let offsetY = cutter.startY - target.centerY
        let b = 2.0 * (offsetX * cutterX + offsetY * cutterY)
        let c = offsetX * offsetX + offsetY * offsetY - target.radius * target.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let rawCutterFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            rawCutterFractions = [-b / (2.0 * lengthSquared)]
        } else {
            rawCutterFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        var rejectedByCutterReach = false
        let angles = rawCutterFractions.compactMap { cutterFraction -> Double? in
            if extendsCutter == false &&
                (cutterFraction < -tolerance || cutterFraction > 1.0 + tolerance) {
                rejectedByCutterReach = true
                return nil
            }
            let pointX = cutter.startX + cutterX * cutterFraction
            let pointY = cutter.startY + cutterY * cutterFraction
            return atan2(pointY - target.centerY, pointX - target.centerX)
        }
        if angles.isEmpty && rejectedByCutterReach {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
            )
        }
        return angles
    }

    private func cutAnglesForCircleCircleIntersection(
        target: CutCurveCircle,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) throws -> [Double] {
        let points = try cutCurveCircleCircleIntersections(
            target,
            circle
        )
        return points.compactMap { point -> Double? in
            if let arc {
                let cutterAngle = atan2(
                    point.y - arc.circle.centerY,
                    point.x - arc.circle.centerX
                )
                guard cutCurveAngleIsOnArc(
                    cutterAngle,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle
                ) else {
                    return nil
                }
            }
            return atan2(point.y - target.centerY, point.x - target.centerX)
        }
    }

    private func cutCurveCircleCircleIntersections(
        _ first: CutCurveCircle,
        _ second: CutCurveCircle
    ) throws -> [(x: Double, y: Double)] {
        let deltaX = second.centerX - first.centerX
        let deltaY = second.centerY - first.centerY
        let distance = hypot(deltaX, deltaY)
        let tolerance = 1.0e-10
        guard distance > tolerance else {
            if abs(first.radius - second.radius) <= tolerance {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve coincident circular curves do not create discrete intersections in the current source subset."
                )
            }
            return []
        }
        guard distance <= first.radius + second.radius + tolerance,
              distance >= abs(first.radius - second.radius) - tolerance else {
            return []
        }

        let firstRadiusSquared = first.radius * first.radius
        let secondRadiusSquared = second.radius * second.radius
        let distanceSquared = distance * distance
        let centerOffset = (firstRadiusSquared - secondRadiusSquared + distanceSquared) /
            (2.0 * distance)
        let heightSquared = firstRadiusSquared - centerOffset * centerOffset
        guard heightSquared >= -1.0e-14 else {
            return []
        }

        let unitX = deltaX / distance
        let unitY = deltaY / distance
        let baseX = first.centerX + centerOffset * unitX
        let baseY = first.centerY + centerOffset * unitY
        let height = sqrt(max(heightSquared, 0.0))
        if height <= tolerance {
            return [(x: baseX, y: baseY)]
        }
        let perpendicularX = -unitY * height
        let perpendicularY = unitX * height
        return [
            (x: baseX + perpendicularX, y: baseY + perpendicularY),
            (x: baseX - perpendicularX, y: baseY - perpendicularY),
        ]
    }

    private func uniqueInteriorCutFractions(_ fractions: [Double]) -> [Double] {
        let tolerance = 1.0e-10
        return fractions
            .filter { fraction in
                fraction > tolerance && fraction < 1.0 - tolerance
            }
            .sorted()
            .reduce(into: [Double]()) { uniqueFractions, fraction in
                guard uniqueFractions.contains(where: { abs($0 - fraction) <= tolerance }) == false else {
                    return
                }
                uniqueFractions.append(fraction)
            }
    }

    private func uniqueCutAngles(_ angles: [Double]) -> [Double] {
        let tolerance = 1.0e-10
        let fullCircle = Double.pi * 2.0
        var uniqueAngles = angles
            .map(normalizedCutAngle)
            .sorted()
            .reduce(into: [Double]()) { uniqueAngles, angle in
                guard uniqueAngles.contains(where: { abs($0 - angle) <= tolerance }) == false else {
                    return
                }
                uniqueAngles.append(angle)
            }
        if let first = uniqueAngles.first,
           let last = uniqueAngles.last,
           uniqueAngles.count > 1,
           fullCircle - last + first <= tolerance {
            uniqueAngles.removeLast()
        }
        return uniqueAngles
    }

    private func normalizedCutAngle(_ angle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        var normalized = angle
        while normalized < 0.0 {
            normalized += fullCircle
        }
        while normalized >= fullCircle {
            normalized -= fullCircle
        }
        if fullCircle - normalized <= 1.0e-10 {
            return 0.0
        }
        return normalized
    }

    private func cutCurveAngleIsOnArc(
        _ angle: Double,
        startAngle: Double,
        endAngle: Double
    ) -> Bool {
        normalizedAngleDelta(from: startAngle, to: angle) <=
            positiveArcSpan(startAngle: startAngle, endAngle: endAngle) + 1.0e-10
    }

    private func cutCurveArcFraction(
        for angle: Double,
        on arc: CutCurveArc
    ) -> Double {
        normalizedAngleDelta(from: arc.startAngle, to: angle) /
            positiveArcSpan(startAngle: arc.startAngle, endAngle: arc.endAngle)
    }

    private func normalizedAngleDelta(
        from startAngle: Double,
        to angle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        var delta = angle - startAngle
        while delta < 0.0 {
            delta += fullCircle
        }
        while delta >= fullCircle {
            delta -= fullCircle
        }
        return delta
    }
}
