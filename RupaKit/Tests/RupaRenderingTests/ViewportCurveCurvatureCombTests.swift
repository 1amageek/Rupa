import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func viewportCurveCurvatureCombSkipsLinearCurves() throws {
    let comb = ViewportCurveCurvatureComb(
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
        ViewportCurveCurvatureComb(
            primitive: .circle(
                entityID: SketchEntityID(),
                center: CGPoint(x: 0.0, y: 0.0),
                radiusMeters: 0.004
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
        ViewportCurveCurvatureComb(
            primitive: .arc(
                entityID: SketchEntityID(),
                center: CGPoint(x: 0.0, y: 0.0),
                radiusMeters: 0.006,
                startAngleRadians: 0.0,
                endAngleRadians: Double.pi / 2.0
            )
        )
    )

    #expect(comb.samples.count == 15)
    #expect(abs(comb.maxAbsCurvature - (1.0 / 0.006)) < 1.0e-9)
    #expect(comb.displayScale() > 0.0)
}

@Test func viewportCurveCurvatureCombReportsSplineCurvature() throws {
    let comb = try #require(
        ViewportCurveCurvatureComb(
            primitive: .spline(
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
