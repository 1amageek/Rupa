import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Outline pieces are the same curve only when their identifying points agree: the two halves of
/// one circle differ, a curve drawn the other way round matches, and no coordinate is too large.
@MainActor
@Suite struct OutlineCurveIdentityTests {
    private func mm(_ v: Double) -> CADExpression { .length(v, .millimeter) }
    private let document = DesignDocument.empty()

    private func arc(_ start: Double, _ end: Double) -> SketchEntity {
        .arc(SketchArc(center: SketchPoint(x: mm(0), y: mm(0)), radius: mm(5), startAngle: .angle(start, .radian), endAngle: .angle(end, .radian)))
    }

    @Test func theTwoHalvesOfACircleDiffer() throws {
        let upper = try document.outlineCurveIdentity(arc(0, .pi)), lower = try document.outlineCurveIdentity(arc(.pi, 2 * .pi))
        #expect(!upper.matches(lower, tolerance: 1.0e-9))
        #expect(upper.matches(try document.outlineCurveIdentity(arc(0, .pi)), tolerance: 1.0e-9))
    }

    @Test func aCurveDrawnTheOtherWayMatches() throws {
        let line = try document.outlineCurveIdentity(.line(SketchLine(start: SketchPoint(x: mm(0), y: mm(0)), end: SketchPoint(x: mm(10), y: mm(2)))))
        let back = try document.outlineCurveIdentity(.line(SketchLine(start: SketchPoint(x: mm(10), y: mm(2)), end: SketchPoint(x: mm(0), y: mm(0)))))
        #expect(line.matches(back, tolerance: 1.0e-9))
        let points = [(0.0, 0.0), (3.0, 4.0), (7.0, 5.0), (10.0, 3.0)]
        let spline = try document.outlineCurveIdentity(.spline(SketchSpline(controlPoints: points.map { SketchPoint(x: mm($0.0), y: mm($0.1)) })))
        let reversed = try document.outlineCurveIdentity(.spline(SketchSpline(controlPoints: points.reversed().map { SketchPoint(x: mm($0.0), y: mm($0.1)) })))
        #expect(spline.matches(reversed, tolerance: 1.0e-9))
    }

    @Test func coordinatesFarFromTheOriginCompareWithoutTrapping() throws {
        let far = SketchPoint(x: .length(1.0e12, .meter), y: .length(-1.0e12, .meter))
        let line = try document.outlineCurveIdentity(.line(SketchLine(start: far, end: SketchPoint(x: mm(0), y: mm(0)))))
        #expect(line.matches(line, tolerance: 1.0e-9))
    }
}
