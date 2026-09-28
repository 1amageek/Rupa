import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD

public struct ViewportCurveCurvatureComb: Equatable {
    public var samples: [CurveEvaluationSample]
    public var maxAbsCurvature: Double
    public var modelBounds: CGRect

    /// The comb of `primitive`, or nil when the curve has no curvature to draw. A spline is
    /// sampled on its own degree and knots, densely enough that the tangent turns by at most
    /// `maximumTurn` between neighbouring teeth, so the comb follows a tight bend instead of
    /// joining distant teeth across it; lines have no comb, and circles and arcs keep one
    /// curvature, so uniform samples draw them exactly.
    public init?(
        primitive: ViewportSketchPrimitive,
        samplesPerSegment: Int = 14,
        maximumTurn: Double = Double.pi / 36,
        curvatureTolerance: Double = 1.0e-12
    ) throws {
        let sampler = SketchCurveSampler(samplesPerSegment: samplesPerSegment)
        let samples: [CurveEvaluationSample]
        switch primitive {
        case .point, .line:
            samples = []
        case .circle(_, let center, let radiusMeters, _):
            samples = sampler.circleSamples(
                center: Point2D(x: Double(center.x), y: Double(center.y)),
                radius: radiusMeters
            )
        case .arc(
            _,
            let center,
            let radiusMeters,
            let startAngleRadians,
            let endAngleRadians,
            _
        ):
            samples = sampler.arcSamples(
                center: Point2D(x: Double(center.x), y: Double(center.y)),
                radius: radiusMeters,
                startAngle: startAngleRadians,
                endAngle: endAngleRadians
            )
        case .spline(_, _, let controlPoints, let degree, let knots, _):
            let curve = try SketchSplineCurve(
                degree: degree,
                knots: knots,
                controlPoints: controlPoints.map { Point2D(x: Double($0.x), y: Double($0.y)) },
                tolerance: .standard
            )
            samples = try sampler.turnBoundedSplineSamples(for: curve, maximumTurn: maximumTurn)
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
