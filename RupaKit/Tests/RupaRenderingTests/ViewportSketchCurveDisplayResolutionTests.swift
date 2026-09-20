import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene
import Testing
@testable import RupaRendering

/// The frame divides a sketch curve at the count its primitive carries.
///
/// The rule is owned by `RupaCore/DESIGN.md`; this checks that the producer that
/// draws the polyline, and therefore the query measured against it, reads it.

@Test func theFrameDividesACircleAtTheCountItsPrimitiveCarries() throws {
    for segmentCount in [8, 16, 64] {
        let points = try ViewportSpatialOverlayProducer.sketchPrimitiveWorldPoints(
            .circle(
                entityID: SketchEntityID(),
                center: CGPoint(x: 0, y: 0),
                radiusMeters: 0.01,
                segmentCount: segmentCount
            )
        )

        // One sample per segment, plus the close back onto the first.
        #expect(points.count == segmentCount + 1)
    }
}

@Test func theFrameDividesAnArcAtTheCountItsPrimitiveCarries() throws {
    for segmentCount in [2, 6, 24] {
        let points = try ViewportSpatialOverlayProducer.sketchPrimitiveWorldPoints(
            .arc(
                entityID: SketchEntityID(),
                center: CGPoint(x: 0, y: 0),
                radiusMeters: 0.01,
                startAngleRadians: 0.0,
                endAngleRadians: .pi / 2.0,
                segmentCount: segmentCount
            )
        )

        #expect(points.count == segmentCount + 1)
    }
}

@Test func aCurveCarryingNoUsableCountIsRefusedRatherThanRedrawnAtOneOfOurOwn() {
    #expect(throws: (any Error).self) {
        _ = try ViewportSpatialOverlayProducer.sketchPrimitiveWorldPoints(
            .circle(
                entityID: SketchEntityID(),
                center: CGPoint(x: 0, y: 0),
                radiusMeters: 0.01,
                segmentCount: 2
            )
        )
    }
    #expect(throws: (any Error).self) {
        _ = try ViewportSpatialOverlayProducer.sketchPrimitiveWorldPoints(
            .arc(
                entityID: SketchEntityID(),
                center: CGPoint(x: 0, y: 0),
                radiusMeters: 0.01,
                startAngleRadians: 0.0,
                endAngleRadians: .pi / 2.0,
                segmentCount: 1
            )
        )
    }
}
