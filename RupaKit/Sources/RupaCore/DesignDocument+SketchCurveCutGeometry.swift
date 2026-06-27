import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
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

    func cutFractionsForLineTarget(
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

    func cutFractionsForSplineTarget(
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

    func cutFractionsForArcTarget(
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
}
