import CoreGraphics
import RupaCore
import SwiftCAD

public struct ViewportCurveCurvatureComb: Equatable {
    public var samples: [CurveEvaluationSample]
    public var maxAbsCurvature: Double
    public var modelBounds: CGRect

    public init?(
        primitive: ViewportSketchPrimitive,
        samplesPerSegment: Int = 14,
        curvatureTolerance: Double = 1.0e-12
    ) {
        let evaluator = SketchCurveEvaluator(samplesPerSegment: samplesPerSegment)
        let samples: [CurveEvaluationSample]
        switch primitive {
        case .point, .line:
            samples = []
        case .circle(_, let center, let radiusMeters):
            samples = evaluator.circleSamples(
                center: CADCore.Point2D(x: Double(center.x), y: Double(center.y)),
                radius: radiusMeters
            )
        case .arc(_, let center, let radiusMeters, let startAngleRadians, let endAngleRadians):
            samples = evaluator.arcSamples(
                center: CADCore.Point2D(x: Double(center.x), y: Double(center.y)),
                radius: radiusMeters,
                startAngle: startAngleRadians,
                endAngle: endAngleRadians
            )
        case .spline(_, _, let controlPoints, _):
            let points = controlPoints.map { point in
                CADCore.Point2D(x: Double(point.x), y: Double(point.y))
            }
            samples = evaluator.splineSamples(for: points)
        }

        let drawableSamples = samples.filter { sample in
            sample.curvature.isFinite && abs(sample.curvature) > curvatureTolerance
        }
        guard drawableSamples.isEmpty == false else {
            return nil
        }

        self.samples = drawableSamples
        self.maxAbsCurvature = drawableSamples.map { abs($0.curvature) }.max() ?? 0.0
        self.modelBounds = Self.bounds(for: drawableSamples)
    }

    public func displayScale(scaleFactor: Double = CurveCurvatureDisplay.defaultCombScale) -> Double {
        guard maxAbsCurvature > 1.0e-12 else {
            return 0.0
        }
        let diagonal = max(Double(hypot(modelBounds.width, modelBounds.height)), 1.0e-6)
        return diagonal * scaleFactor / maxAbsCurvature
    }

    private static func bounds(for samples: [CurveEvaluationSample]) -> CGRect {
        let xs = samples.map(\.point.x)
        let ys = samples.map(\.point.y)
        let minX = xs.min() ?? 0.0
        let minY = ys.min() ?? 0.0
        let maxX = xs.max() ?? minX
        let maxY = ys.max() ?? minY
        return CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 1.0e-9),
            height: max(maxY - minY, 1.0e-9)
        )
    }
}
