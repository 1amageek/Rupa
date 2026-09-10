import CoreGraphics
import Testing
@testable import RupaRendering

@Test
func inputMathPreservesRadialSignedDeltaAndRefusesCollinearBasis() throws {
    let projection = ViewportSpatialMaterializedInteractionTarget.RadialProjection(
        center: .zero,
        radialVector: CGVector(dx: 10, dy: 0),
        tangentVector: CGVector(dx: 0, dy: 10),
        baseAngleRadians: 0.1,
        minimumAngleRadians: 0.05
    )
    let angle = try #require(try projection.angle(
        start: CGPoint(x: 10, y: 0),
        current: CGPoint(x: 0, y: 10)
    ))
    #expect(abs(angle - (0.1 + .pi / 2.0)) < 1.0e-12)

    // A pointer on the projected centre carries no direction, so the caller
    // keeps the value it already holds instead of receiving a substitute.
    #expect(try projection.angle(start: CGPoint(x: 10, y: 0), current: .zero) == nil)
    #expect(try projection.angle(start: .zero, current: CGPoint(x: 0, y: 10)) == nil)

    let collinear = ViewportSpatialMaterializedInteractionTarget.RadialProjection(
        center: .zero,
        radialVector: CGVector(dx: 10, dy: 0),
        tangentVector: CGVector(dx: 20, dy: 0),
        baseAngleRadians: 0.1,
        minimumAngleRadians: 0.05
    )
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try collinear.angle(start: CGPoint(x: 10, y: 0), current: CGPoint(x: 0, y: 10))
    }
}

@Test
func inputMathUsesProjectedDirectionForLinearAndDensityCounts() throws {
    let linear = ViewportSpatialMaterializedInteractionTarget.LinearCopyCountProjection(
        basePoint: .zero,
        projectedDirection: CGVector(dx: 1, dy: 0),
        baseCopyCount: 3,
        pointsPerCopy: 10
    )
    #expect(try linear.count(start: .zero, current: CGPoint(x: 15, y: 4)) == 5)

    let density = ViewportSpatialMaterializedInteractionTarget.LinearDensityProjection(
        basePoint: .zero,
        extentPoint: CGPoint(x: 10, y: 0),
        anchorPoint: CGPoint(x: 10, y: 24),
        projectedDirection: CGVector(dx: 0, dy: 1),
        baseCopyCount: 4,
        pointsPerCopy: 28
    )
    #expect(try density.count(start: .zero, current: CGPoint(x: 2, y: 13)) == 4)
    #expect(try density.count(start: .zero, current: CGPoint(x: 2, y: 31)) == 5)
}

@Test
func inputMathUsesSignedAngularDeltaAndDensityDirection() throws {
    let angular = ViewportSpatialMaterializedInteractionTarget.AngularCopyCountProjection(
        center: .zero,
        radialVector: CGVector(dx: 10, dy: 0),
        tangentVector: CGVector(dx: 0, dy: 10),
        baseCopyCount: 2,
        stepAngleRadians: 0.5,
        minimumAngleRadians: 0.05
    )
    #expect(try angular.count(start: CGPoint(x: 10, y: 0), current: CGPoint(x: 0, y: 10)) == 5)
    #expect(try angular.count(start: CGPoint(x: 10, y: 0), current: .zero) == nil)

    let density = ViewportSpatialMaterializedInteractionTarget.AngularDensityProjection(
        anchorPoint: .zero,
        projectedDirection: CGVector(dx: 0, dy: 1),
        baseCopyCount: 3,
        pointsPerCopy: 28
    )
    #expect(try density.count(start: .zero, current: CGPoint(x: 2, y: 31)) == 4)
}

@Test
func inputMathUsesFullCurveSamplesForNearestPhysicalDistanceAndCurveCount() throws {
    let extent = ViewportSpatialMaterializedInteractionTarget.CurveExtentProjection(
        projectedPathPoints: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10)
        ],
        distanceSamplesMeters: [0, 2, 5],
        baseDistanceMeters: 2,
        totalLengthMeters: 5,
        minimumDistanceMeters: 1
    )
    let nearest = try extent.distance(current: CGPoint(x: 9, y: 5))
    #expect(abs(nearest - 3.5) < 1.0e-12)
    #expect(try extent.distance(current: CGPoint(x: -20, y: 0)) == 1)
    #expect(try extent.distance(current: CGPoint(x: 10, y: 30)) == 5)

    let curve = ViewportSpatialMaterializedInteractionTarget.CurveCopyCountProjection(
        anchorPoint: .zero,
        projectedDirection: CGVector(dx: 0, dy: 1),
        baseCopyCount: 2,
        pointsPerCopy: 28
    )
    #expect(try curve.count(start: .zero, current: CGPoint(x: 0, y: 29)) == 3)
}

@Test
func inputMathRejectsNonfiniteAndIntegerOverflow() throws {
    let linear = ViewportSpatialMaterializedInteractionTarget.LinearCopyCountProjection(
        basePoint: .zero,
        projectedDirection: CGVector(dx: 1, dy: 0),
        baseCopyCount: Int.max,
        pointsPerCopy: 1
    )
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try linear.count(start: .zero, current: CGPoint(x: 1, y: 0))
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try linear.count(start: .zero, current: CGPoint(x: CGFloat.nan, y: 0))
    }

    let malformedCurve = ViewportSpatialMaterializedInteractionTarget.CurveExtentProjection(
        projectedPathPoints: [CGPoint.zero, CGPoint(x: 1, y: 0)],
        distanceSamplesMeters: [0],
        baseDistanceMeters: 0.1,
        totalLengthMeters: 1,
        minimumDistanceMeters: 0.1
    )
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try malformedCurve.distance(current: .zero)
    }
    let collapsedCurve = ViewportSpatialMaterializedInteractionTarget.CurveExtentProjection(
        projectedPathPoints: [.zero, .zero, .zero],
        distanceSamplesMeters: [0, 1, 2],
        baseDistanceMeters: 1,
        totalLengthMeters: 2,
        minimumDistanceMeters: 0.1
    )
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try collapsedCurve.distance(current: .zero)
    }
}
