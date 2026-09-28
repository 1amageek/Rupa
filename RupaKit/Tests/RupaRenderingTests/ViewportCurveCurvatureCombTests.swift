import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func viewportCurveCurvatureCombSkipsLinearCurves() throws {
    let comb = try ViewportCurveCurvatureComb(
        primitive: .line(
            entityID: SketchEntityID(),
            start: CGPoint(x: 0.0, y: 0.0),
            end: CGPoint(x: 0.010, y: 0.0)
        )
    )

    #expect(comb == nil)
}

@Test func viewportCurveCurvatureCombReportsCircleCurvature() throws {
    let comb = try #require(
        try ViewportCurveCurvatureComb(
            primitive: .circle(
                entityID: SketchEntityID(),
                center: CGPoint(x: 0.0, y: 0.0),
                radiusMeters: 0.004,
                segmentCount: 48
            )
        )
    )

    #expect(comb.samples.count >= 16)
    #expect(abs(comb.maxAbsCurvature - 250.0) < 1.0e-9)
    #expect(comb.displayScale() > 0.0)
    #expect(comb.samples.allSatisfy { sample in
        abs(sample.curvature - 250.0) < 1.0e-9
    })
}

@Test func viewportCurveCurvatureCombReportsArcCurvature() throws {
    let comb = try #require(
        try ViewportCurveCurvatureComb(
            primitive: .arc(
                entityID: SketchEntityID(),
                center: CGPoint(x: 0.0, y: 0.0),
                radiusMeters: 0.006,
                startAngleRadians: 0.0,
                endAngleRadians: Double.pi / 2.0,
                segmentCount: 24
            )
        )
    )

    #expect(comb.samples.count == 15)
    #expect(abs(comb.maxAbsCurvature - (1.0 / 0.006)) < 1.0e-9)
    #expect(comb.displayScale() > 0.0)
}

@Test func viewportCurveCurvatureCombReportsSplineCurvature() throws {
    let comb = try #require(
        try ViewportCurveCurvatureComb(
            primitive: .cubicSpline(
                entityID: SketchEntityID(),
                points: [],
                controlPoints: [
                    CGPoint(x: 0.000, y: 0.000),
                    CGPoint(x: 0.002, y: 0.004),
                    CGPoint(x: 0.006, y: 0.004),
                    CGPoint(x: 0.008, y: 0.000),
                ],
                sketchPlane: .xy
            )
        )
    )

    #expect(comb.samples.count > 8)
    #expect(comb.maxAbsCurvature > 1.0)
    #expect(comb.displayScale() > 0.0)
}

/// A quintic is combed on its own degree and knots.
@Test func viewportCurveCurvatureCombReadsAQuinticOnItsOwnKnots() throws {
    let controlPoints = [(0.0, 0.0), (0.004, 0.008), (0.008, -0.004), (0.012, 0.010), (0.016, -0.002), (0.020, 0.004)]
        .map { CGPoint(x: $0.0, y: $0.1) }
    let comb = try #require(
        try ViewportCurveCurvatureComb(
            primitive: .spline(
                entityID: SketchEntityID(),
                points: [],
                controlPoints: controlPoints,
                degree: 5,
                knots: [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1],
                sketchPlane: .xy
            )
        )
    )
    let curve = BSplineCurve2D(
        degree: 5,
        knots: [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1],
        controlPoints: controlPoints.map { Point2D(x: Double($0.x), y: Double($0.y)) }
    )
    for sample in comb.samples.enumerated().filter({ $0.offset.isMultiple(of: 4) }).map(\.element) {
        let onCurve = try curve.point(at: sample.parameter, tolerance: .standard)
        #expect(hypot(onCurve.x - sample.point.x, onCurve.y - sample.point.y) <= 1e-12)
    }
}

/// The Bridge Curve whose comb crossed itself: its teeth now turn by at most 5° from one to the
/// next around each hook instead of jumping across it.
@Test func viewportCurveCurvatureCombFollowsATightHook() throws {
    let controlPoints = [(0.0, 0.0), (-14.142, 0.0), (6.667, 6.667), (10.0, 10.0), (13.333, 13.333), (20.0, 34.142), (20.0, 20.0)]
        .map { CGPoint(x: $0.0 / 1000, y: $0.1 / 1000) }
    let comb = try #require(
        try ViewportCurveCurvatureComb(
            primitive: .cubicSpline(entityID: SketchEntityID(), points: [], controlPoints: controlPoints, sketchPlane: .xy)
        )
    )
    for (a, b) in zip(comb.samples, comb.samples.dropFirst()) {
        let turn = abs(atan2(a.tangent.x * b.tangent.y - a.tangent.y * b.tangent.x, a.tangent.x * b.tangent.x + a.tangent.y * b.tangent.y))
        #expect(turn <= Double.pi / 36 + 1e-12)
    }
}

/// Teeth point toward the center of curvature, so a tooth longer than the local radius crosses
/// its neighbours. On the tight hook the size-based scale would do that, so the scale is capped:
/// every tooth stays within its own radius, the longest reaching it, and the teeth remain in
/// proportion to the curvature.
@Test func viewportCurveCurvatureCombTeethStayWithinTheirRadius() throws {
    let controlPoints = [(0.0, 0.0), (-14.142, 0.0), (6.667, 6.667), (10.0, 10.0), (13.333, 13.333), (20.0, 34.142), (20.0, 20.0)]
        .map { CGPoint(x: $0.0 / 1000, y: $0.1 / 1000) }
    let comb = try #require(
        try ViewportCurveCurvatureComb(
            primitive: .cubicSpline(entityID: SketchEntityID(), points: [], controlPoints: controlPoints, sketchPlane: .xy)
        )
    )
    let scale = comb.displayScale()
    let diagonal = Double(hypot(comb.modelBounds.width, comb.modelBounds.height))
    #expect(scale < diagonal * CurveCurvatureDisplay.defaultCombScale / comb.maxAbsCurvature)
    for sample in comb.samples {
        #expect(abs(sample.curvature) * scale <= 1 / abs(sample.curvature) * (1 + 1e-12))
    }
    #expect(abs(comb.maxAbsCurvature * scale - 1 / comb.maxAbsCurvature) <= 1e-12)
}

/// A gentle curve keeps the size-based scale: its longest tooth is a tenth of its diagonal.
@Test func viewportCurveCurvatureCombKeepsTheSizeScaleOnAGentleCurve() throws {
    let comb = try #require(
        try ViewportCurveCurvatureComb(
            primitive: .arc(
                entityID: SketchEntityID(),
                center: CGPoint(x: 0.0, y: 0.0),
                radiusMeters: 0.006,
                startAngleRadians: 0.0,
                endAngleRadians: Double.pi / 2.0,
                segmentCount: 24
            )
        )
    )
    let diagonal = Double(hypot(comb.modelBounds.width, comb.modelBounds.height))
    #expect(abs(comb.displayScale() - diagonal * CurveCurvatureDisplay.defaultCombScale / comb.maxAbsCurvature) <= 1e-18)
}
