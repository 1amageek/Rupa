import CoreGraphics
import Foundation
import RupaCore
import Testing
@testable import RupaRendering

@Test func viewportSplineControlPointSlideAffordanceProjectsPositiveUDistance() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.004, y: -0.004, width: 0.012, height: 0.008),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let controlPoints = [
        CGPoint(x: 0.000, y: 0.000),
        CGPoint(x: 0.002, y: 0.000),
        CGPoint(x: 0.004, y: 0.000),
    ]
    let geometry = try #require(
        ViewportSplineControlPointSlideAffordanceGeometry(
            controlPoints: controlPoints,
            selectedIndexes: [1],
            direction: .positiveU,
            layout: layout
        )
    )

    let start = layout.project(geometry.baseModelPoint)
    let current = layout.project(
        CGPoint(
            x: geometry.baseModelPoint.x + 0.002,
            y: geometry.baseModelPoint.y
        )
    )

    #expect(abs(geometry.slideDistance(start: start, current: current, layout: layout) - 0.002) < 1.0e-12)
}

@Test func viewportSplineControlPointSlideAffordanceKeepsSignedNegativeUDistance() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.004, y: -0.004, width: 0.012, height: 0.008),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let controlPoints = [
        CGPoint(x: 0.000, y: 0.000),
        CGPoint(x: 0.002, y: 0.000),
        CGPoint(x: 0.004, y: 0.000),
    ]
    let geometry = try #require(
        ViewportSplineControlPointSlideAffordanceGeometry(
            controlPoints: controlPoints,
            selectedIndexes: [1],
            direction: .negativeU,
            layout: layout
        )
    )

    let start = layout.project(geometry.baseModelPoint)
    let current = layout.project(
        CGPoint(
            x: geometry.baseModelPoint.x + 0.001,
            y: geometry.baseModelPoint.y
        )
    )

    #expect(abs(geometry.slideDistance(start: start, current: current, layout: layout) + 0.001) < 1.0e-12)
}

@Test func viewportSplineControlPointSlideAffordanceNormalIsPerpendicularToPositiveU() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.004, y: -0.004, width: 0.012, height: 0.008),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let controlPoints = [
        CGPoint(x: 0.000, y: 0.000),
        CGPoint(x: 0.002, y: 0.000),
        CGPoint(x: 0.004, y: 0.000),
    ]
    let geometry = try #require(
        ViewportSplineControlPointSlideAffordanceGeometry(
            controlPoints: controlPoints,
            selectedIndexes: [1],
            direction: .normal,
            layout: layout
        )
    )
    let positiveU = CGPoint(x: 1.0, y: 0.0)
    let dot = geometry.modelDirection.x * positiveU.x + geometry.modelDirection.y * positiveU.y

    #expect(abs(dot) < 1.0e-12)
}

@Test func viewportSplineControlPointSlideAffordanceKeepsHandleWhenSelectedUDirectionsCancel() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.004, y: -0.004, width: 0.012, height: 0.008),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let controlPoints = [
        CGPoint(x: 0.000, y: 0.000),
        CGPoint(x: 0.002, y: 0.000),
        CGPoint(x: 0.000, y: 0.000),
    ]
    let geometry = try #require(
        ViewportSplineControlPointSlideAffordanceGeometry(
            controlPoints: controlPoints,
            selectedIndexes: [0, 2],
            direction: .positiveU,
            layout: layout
        )
    )

    #expect(abs(geometry.modelDirection.x - 1.0) < 1.0e-12)
    #expect(abs(geometry.modelDirection.y) < 1.0e-12)
}

@Test func viewportSplineControlPointSlidePreviewUsesEachControlPointLocalUDirection() throws {
    let controlPoints = [
        CGPoint(x: 0.000, y: 0.000),
        CGPoint(x: 0.002, y: 0.000),
        CGPoint(x: 0.004, y: 0.000),
        CGPoint(x: 0.004, y: 0.002),
    ]
    let preview = try #require(
        ViewportSplineControlPointSlideAffordanceGeometry.previewControlPoints(
            controlPoints: controlPoints,
            selectedIndexes: [1, 2],
            direction: .positiveU,
            distanceMeters: 0.001
        )
    )
    let diagonalDistance = CGFloat(0.001 / sqrt(2.0))

    #expect(preview[0] == controlPoints[0])
    #expect(abs(preview[1].x - 0.003) < 1.0e-12)
    #expect(abs(preview[1].y) < 1.0e-12)
    #expect(abs(preview[2].x - (0.004 + diagonalDistance)) < 1.0e-12)
    #expect(abs(preview[2].y - diagonalDistance) < 1.0e-12)
    #expect(preview[3] == controlPoints[3])
}
