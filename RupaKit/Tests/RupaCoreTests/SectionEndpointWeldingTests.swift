import SwiftCAD
import Testing
@testable import RupaCore

@Suite struct SectionEndpointWeldingTests {
    private func edge(_ a: Point2D, _ b: Point2D) -> SectionAnalysisResult.IntersectionSegment {
        .init(bodyID: "mesh", sceneNodeID: nil, start: Point3D(x: a.x, y: a.y, z: 0),
              end: Point3D(x: b.x, y: b.y, z: 0), start2D: a, end2D: b)
    }

    @Test func neighboringCellsWeldByDistanceAndNotInputOrder() throws {
        let tolerance = 1e-6
        let segments = [edge(Point2D(x: 0, y: 0), Point2D(x: 1.99 * tolerance, y: 1)),
                        edge(Point2D(x: 2.01 * tolerance, y: 1), Point2D(x: 2, y: 0))]
        let builder = SectionAnalysisContourBuilder(tolerance: tolerance)
        let expected = builder.build(segments: segments)
        #expect(expected.count == 1)
        #expect(try #require(expected.first).segmentCount == 2)
        for reverseOrder in [false, true] {
            for mask in 0..<4 {
                let oriented = segments.enumerated().map { index, segment in
                    mask & (1 << index) == 0 ? segment : edge(segment.end2D, segment.start2D)
                }
                let actual = builder.build(segments: reverseOrder ? Array(oriented.reversed()) : oriented)
                #expect(actual == expected)
            }
        }
    }

    @Test func diagonalEndpointsOutsideToleranceStaySeparate() {
        let tolerance = 1e-6
        let a = Point2D(x: -0.49 * tolerance, y: -0.49 * tolerance)
        let b = Point2D(x: 0.49 * tolerance, y: 0.49 * tolerance)
        let result = SectionAnalysisContourBuilder(tolerance: tolerance).build(segments: [
            edge(Point2D(x: -1, y: 0), a), edge(b, Point2D(x: 1, y: 0))])
        #expect(result.count == 2)
    }

    @Test func closedContoursSurviveLargeTranslationsAndCloseGaps() throws {
        for offset in [0.0, 1e15] {
            let a = Point2D(x: offset, y: offset), b = Point2D(x: offset + 1, y: offset)
            let c = Point2D(x: offset + 1, y: offset + 1), d = Point2D(x: offset, y: offset + 1)
            let nearA = Point2D(x: offset + (offset == 0 ? 2e-8 : 0), y: offset)
            let result = SectionAnalysisContourBuilder(tolerance: 1e-6).build(segments: [edge(b,c),edge(d,nearA),edge(a,b),edge(c,d)])
            let contour = try #require(result.first)
            #expect(result.count == 1 && contour.isClosed)
            #expect(abs(abs(contour.signedAreaSquareMeters) - 1) < 1e-10)
            #expect(abs(contour.lengthMeters - 4) < 1e-10)
        }
    }

    @Test func unindexableRangesDoNotSaturateAndSmallTolerancesAreHonored() {
        let huge = SectionAnalysisContourBuilder(tolerance: 1e-6).build(segments: [
            edge(Point2D(x: -1e14, y: 0), Point2D(x: 1e14, y: 0)),
            edge(Point2D(x: 1e14, y: 0), Point2D(x: 1e14, y: 1))])
        #expect(huge.count == 1 && huge.first?.segmentCount == 2)
        let mixed = SectionAnalysisContourBuilder(tolerance: 1e-6).build(segments: [
            edge(Point2D(x: -1e11, y: 0), Point2D(x: 0.49e-6, y: 0)),
            edge(Point2D(x: 0.51e-6, y: 0), Point2D(x: 1, y: 0))])
        #expect(mixed.count == 1)
        let tiny = SectionAnalysisContourBuilder(tolerance: 1e-15).build(segments: [
            edge(Point2D(x: -1, y: 0), Point2D(x: 0, y: 0)),
            edge(Point2D(x: 1e-14, y: 0), Point2D(x: 1, y: 0))])
        #expect(tiny.count == 2)
    }
}
