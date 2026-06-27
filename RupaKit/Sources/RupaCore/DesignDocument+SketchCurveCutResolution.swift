import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func resolvedCutCurveLineSegment(
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

    func resolvedCutCurveArc(
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

    func resolvedCutCurveSplineSamples(
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

    func resolvedCutCurvePoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> Point2D {
        Point2D(
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }
}
