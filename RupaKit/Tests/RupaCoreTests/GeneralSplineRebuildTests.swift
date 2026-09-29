import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Rebuild's Refit and Explicit Control take splines of any degree and knots and build every
/// degree a sketch spline stores, through Swift-CAD's fits.
@MainActor
@Suite struct GeneralSplineRebuildTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }

    private func document(_ spline: SketchSpline) throws -> (DesignDocument, FeatureID, SketchEntityID) {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Curves", plane: .xy, start: point(-20, -20), end: point(-19, -20))
        guard var feature = document.cadDocument.designGraph.nodes[featureID],
              case var .sketch(sketch) = feature.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        let entityID = SketchEntityID()
        sketch.entities[entityID] = .spline(spline)
        feature.operation = .sketch(sketch)
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        return (document, featureID, entityID)
    }

    private func target(_ document: DesignDocument, _ featureID: FeatureID, _ entityID: SketchEntityID) throws -> SelectionTarget {
        let sceneNodeID = try #require(document.productMetadata.sceneNodes.first { _, node in
            node.reference?.kind == .sketch && node.reference?.featureID == featureID
        }?.key)
        return SelectionTarget(sceneNodeID: sceneNodeID, component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: entityID)))
    }

    private func spline(_ document: DesignDocument, _ featureID: FeatureID, _ entityID: SketchEntityID) throws -> SketchSpline {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              case .spline(let spline) = sketch.entities[entityID] else {
            throw EditorError(code: .referenceUnresolved, message: "The spline is missing.")
        }
        return spline
    }

    private func samplesDeviation(_ document: DesignDocument, from original: SketchSpline, to rebuilt: SketchSpline) throws -> Double {
        let before = try document.resolvedSketchSplineCurve(original, owner: "Test")
        let after = SketchCurveGeometry2D.sketchSpline(try document.resolvedSketchSplineCurve(rebuilt, owner: "Test"))
        let projector = SketchCurveProjector(tolerance: .standard)
        let lower = before.bSpline.knots[0], upper = before.bSpline.knots[before.bSpline.knots.count - 1]
        var maximum = 0.0
        for i in 0...400 {
            let p = try before.bSpline.point(at: lower + (upper - lower) * Double(i) / 400, tolerance: .standard)
            let foot = try projector.nearest(on: after, to: p).point
            maximum = max(maximum, hypot(foot.x - p.x, foot.y - p.y))
        }
        return maximum
    }

    @Test func explicitControlBuildsTheChosenDegreeFromAQuintic() throws {
        let quintic = SketchSpline(
            controlPoints: [(0, 0), (2, 4), (4, -2), (6, 5), (8, -1), (10, 2), (12, 5), (14, -3), (16, 4), (18, 0), (20, 2)].map { point($0.0, $0.1) },
            degree: 5
        )
        var (document, featureID, entityID) = try document(quintic)
        let report = try document.rebuildSketchCurve(
            target: target(document, featureID, entityID),
            options: .explicitControl(degree: 4, spanCount: 6, weight: 1)
        )
        let rebuilt = try spline(document, featureID, entityID)
        #expect(rebuilt.degree == 4)
        #expect(rebuilt.controlPoints.count == 10)
        #expect(report.rebuiltControlPointCount == 10 && report.rebuiltSpanCount == 6)
        #expect(report.deviationMeasurement == .sampledProjection)
        let measured = try samplesDeviation(document, from: quintic, to: rebuilt)
        #expect(abs(measured - report.maximumDeviationMeters) <= 1e-6)
        #expect(report.maximumDeviationMeters < 1e-3)
    }

    @Test func refitKeepsTheCornerOfAQuadraticWithKnots() throws {
        let quadratic = SketchSpline(
            controlPoints: [point(0, 0), point(1, 2), point(2, 2), point(3, 1), point(4, -1)],
            degree: 2,
            knots: [0, 0, 0, 0.5, 0.5, 1, 1, 1]
        )
        var (document, featureID, entityID) = try document(quadratic)
        let report = try document.rebuildSketchCurve(
            target: target(document, featureID, entityID),
            options: .refit(tolerance: .length(1e-4, .millimeter), keepsCorners: true)
        )
        let rebuilt = try spline(document, featureID, entityID)
        #expect(rebuilt.degree == 3)
        #expect(report.maximumDeviationMeters <= 1e-7)
        #expect(try samplesDeviation(document, from: quadratic, to: rebuilt) <= 1e-7 + 1e-9)
        let corner = try rebuilt.controlPoints.map {
            (try document.cadDocument.parameters.resolvedValue(for: $0.x).value, try document.cadDocument.parameters.resolvedValue(for: $0.y).value)
        }.contains { hypot($0.0 - 0.002, $0.1 - 0.002) < 1e-12 }
        #expect(corner)
    }

    @Test func explicitControlRefusesADegreeOutsideTheCoreRangeBeforeMutation() throws {
        let quintic = SketchSpline(controlPoints: [point(0, 0), point(1, 2), point(2, -1), point(3, 3), point(4, 1), point(5, 2)], degree: 5)
        var (document, featureID, entityID) = try document(quintic)
        let revision = document.cadDocument.designGraph.revision
        #expect(CurveRebuildOptions.explicitControlDegrees == 1...SketchSpline.maximumDegree)
        #expect(throws: EditorError.self) {
            try document.rebuildSketchCurve(
                target: target(document, featureID, entityID),
                options: .explicitControl(degree: SketchSpline.maximumDegree + 1, spanCount: 2, weight: 1)
            )
        }
        #expect(document.cadDocument.designGraph.revision == revision)
        #expect(try spline(document, featureID, entityID) == quintic)
    }

    /// Counts outside what a rebuild takes are refused before they are used, whoever sends them:
    /// the largest integers neither overflow nor allocate, and the document stays as it was.
    @Test func countsOutsideTheCoreRangesAreRefusedBeforeMutation() throws {
        let quintic = SketchSpline(controlPoints: [point(0, 0), point(1, 2), point(2, -1), point(3, 3), point(4, 1), point(5, 2)], degree: 5)
        var (document, featureID, entityID) = try document(quintic)
        let revision = document.cadDocument.designGraph.revision
        #expect(CurveRebuildOptions.explicitControlSpanCounts(degree: 3) == 1...(SketchSplineLeastSquaresFit.maximumControlPointCount - 3))
        for options in [
            CurveRebuildOptions.explicitControl(degree: 3, spanCount: .max, weight: 1),
            .explicitControl(degree: 3, spanCount: SketchSplineLeastSquaresFit.maximumControlPointCount - 2, weight: 1),
            .explicitControl(degree: 3, spanCount: 0, weight: 1),
            .points(controlPointCount: .max),
            .points(controlPointCount: SketchSplineLeastSquaresFit.maximumControlPointCount + 1),
        ] {
            #expect(throws: EditorError.self) {
                try document.rebuildSketchCurve(target: target(document, featureID, entityID), options: options)
            }
        }
        #expect(document.cadDocument.designGraph.revision == revision)
        #expect(try spline(document, featureID, entityID) == quintic)
    }
}
