import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Readers that evaluate a sketch spline (display, analysis, snapping, bridge parameters) read
/// a spline of any degree or knots on its own B-spline, not as a cubic chain.
@MainActor
@Suite struct GeneralSplineReadersTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }

    /// A quintic chain of two spans (11 control points, joint at index 5).
    private let quinticPoints: [(Double, Double)] = [
        (0, 0), (4, 8), (8, -4), (12, 10), (16, -2), (20, 4), (24, 10), (28, -6), (32, 8), (36, 0), (40, 4),
    ]
    /// A cubic B-spline with one simple interior knot: smooth at 0.4, no joint there.
    private let explicitPoints: [(Double, Double)] = [(0, 0), (10, 10), (20, 15), (30, 2), (40, 10)]
    private let explicitKnots: [Double] = [0, 0, 0, 0, 0.4, 1, 1, 1, 1]

    private func document(_ spline: SketchSpline) throws -> (DesignDocument, FeatureID) {
        var document = DesignDocument.empty()
        let featureID = try document.createSplineSketch(name: "General", plane: .xy, spline: spline)
        return (document, featureID)
    }

    private func quintic() -> SketchSpline {
        SketchSpline(controlPoints: quinticPoints.map { SketchPoint(x: mm($0.0), y: mm($0.1)) }, degree: 5)
    }

    private func explicit() -> SketchSpline {
        SketchSpline(controlPoints: explicitPoints.map { SketchPoint(x: mm($0.0), y: mm($0.1)) }, knots: explicitKnots)
    }

    /// The kernel's B-spline of `points` (millimeters) in meters.
    private func bSpline(_ points: [(Double, Double)], degree: Int, knots: [Double]) -> BSplineCurve2D {
        BSplineCurve2D(degree: degree, knots: knots, controlPoints: points.map { Point2D(x: $0.0 / 1000, y: $0.1 / 1000) })
    }

    @Test func aQuinticIsDisplayedOnItsOwnCurve() throws {
        let (document, featureID) = try document(quintic())
        let snapshot = try #require(SketchDisplaySnapshotService().snapshots(document: document, ruler: .standard(for: .millimeter))[featureID])
        guard case let .spline(_, points, controlPoints, degree, knots, _) = try #require(snapshot.primitives.first) else {
            Issue.record("A spline displays as a spline primitive.")
            return
        }
        #expect(degree == 5 && controlPoints.count == 11)
        #expect(knots == [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2])
        let curve = bSpline(quinticPoints, degree: 5, knots: knots)
        // Display samples are 32 per segment: sample i is the curve at u = i / 32.
        #expect(points.count == 65)
        for (index, point) in points.enumerated() where index.isMultiple(of: 5) {
            let expected = try curve.point(at: Double(index) / 32, tolerance: .standard)
            #expect(hypot(expected.x - point.x, expected.y - point.y) <= 1e-12)
        }
    }

    @Test func analysisReadsCurvatureAndJointsOfEitherForm() throws {
        let (quinticDocument, _) = try document(quintic())
        let quinticResult = try CurveAnalysisService(samplesPerSegment: 8).analyze(document: quinticDocument, displayUnit: .millimeter)
        let quinticEntry = try #require(quinticResult.curves.first)
        let curve = bSpline(quinticPoints, degree: 5, knots: [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2])
        for sample in quinticEntry.samples.enumerated().filter({ $0.offset.isMultiple(of: 5) }).map(\.element) {
            let geometry = try curve.differentialGeometry(at: sample.parameter * 2, tolerance: .standard)
            let d1 = geometry.firstDerivative, d2 = geometry.secondDerivative
            let expected = (d1.x * d2.y - d1.y * d2.x) / pow(d1.x * d1.x + d1.y * d1.y, 1.5)
            #expect(abs(sample.curvature - expected) <= 1e-6 * max(1, abs(expected)))
        }
        let quinticJoins = quinticResult.continuityJoins.filter { $0.constraintKinds == ["splineKnot"] }
        #expect(quinticJoins.count == 1)
        #expect(quinticJoins.first?.firstReference.hasSuffix(":5") == true)

        let (explicitDocument, _) = try document(explicit())
        let explicitResult = try CurveAnalysisService(samplesPerSegment: 8).analyze(document: explicitDocument, displayUnit: .millimeter)
        #expect(explicitResult.curves.first?.samples.isEmpty == false)
        // A simple interior knot is smooth by construction: no joint is reported there.
        #expect(explicitResult.continuityJoins.filter { $0.constraintKinds == ["splineKnot"] }.isEmpty)
    }

    @Test func snappingFindsTheNearestPointOnAGeneralSpline() throws {
        let (document, _) = try document(explicit())
        let curve = bSpline(explicitPoints, degree: 3, knots: explicitKnots)
        let onCurve = try curve.point(at: 0.63, tolerance: .standard)
        let result = try SnapResolver().resolve(
            point: Point2D(x: onCurve.x, y: onCurve.y),
            in: document,
            ruler: .standard(for: .millimeter),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0005,
                maximumCandidateCount: 32
            )
        )
        // A point on the curve snaps to itself: the projection is exact, not onto a chord.
        let candidate = try #require(result.candidates.first { $0.kind == .splineClosest })
        #expect(hypot(candidate.point.x - onCurve.x, candidate.point.y - onCurve.y) <= 1e-10)
    }

    @Test func aBridgeParameterIsTheFractionOverTheKnotDomain() throws {
        let (document, featureID) = try document(explicit())
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              let entityID = sketch.entities.keys.first else {
            Issue.record("The spline sketch is missing.")
            return
        }
        let curve = bSpline(explicitPoints, degree: 3, knots: explicitKnots)
        let onCurve = try curve.point(at: 0.63, tolerance: .standard)
        let parameter = try document.sketchCurveSplitParameter(
            of: .spline(explicit()),
            nearestTo: Point2D(x: onCurve.x, y: onCurve.y)
        )
        #expect(abs(parameter - 0.63) <= 1e-6)
        _ = entityID
    }
}
