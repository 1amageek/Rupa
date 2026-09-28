import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Project Curve Curve makes the curve whose projections onto the two sketch planes are the two
/// selected curves.
@MainActor
@Suite struct ProjectCurveCurveTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }

    private func curveTarget(_ document: DesignDocument, _ featureID: FeatureID) throws -> SelectionTarget {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              let entityID = sketch.entities.keys.first else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        let node = try #require(document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == featureID }?.key)
        return SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: entityID)))
    }

    @Test func aTopLineAndASideSplineMeetAlongTheLiftedSpline() throws {
        var document = DesignDocument.empty()
        // Seen from above, a line along x; seen from the side (the zx plane), a spline.
        let top = try document.createLineSketch(
            name: "Top", plane: .xy,
            start: SketchPoint(x: mm(0), y: mm(5)), end: SketchPoint(x: mm(10), y: mm(5))
        )
        let sideSystem = try SketchPlaneCoordinateSystem(plane: .zx)
        // Spline control points given in 3D (x, 0, z), read in the zx sketch's own coordinates.
        let sidePoints = [(-2.0, 0.0), (3.0, 6.0), (8.0, -2.0), (12.0, 4.0)].map { (x: Double, z: Double) -> SketchPoint in
            let local = sideSystem.project(Point3D(x: x / 1000, y: 0, z: z / 1000)).point
            return SketchPoint(x: .length(local.x, .meter), y: .length(local.y, .meter))
        }
        let side = try document.createSplineSketch(name: "Side", plane: .zx, spline: SketchSpline(controlPoints: sidePoints))
        let splineCurve: SketchSplineCurve = try {
            guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[side]?.operation,
                  case .spline(let spline) = sketch.entities.values.first else {
                throw EditorError(code: .referenceUnresolved, message: "The spline is missing.")
            }
            return try document.resolvedSketchSplineCurve(spline, owner: "Test")
        }()

        let id = try document.projectCurveIntersection(
            first: try curveTarget(document, top), second: try curveTarget(document, side)
        )
        guard case .spatialPath(let path) = document.cadDocument.designGraph.nodes[id]?.operation else {
            Issue.record("The projection is not a spatial path.")
            return
        }
        let curve = try path.exactCurve(tolerance: .standard)
        let domain = curve.knots.last! - curve.knots.first!
        for i in 0...30 {
            let p = try curve.point(at: curve.knots.first! + domain * Double(i) / 30, tolerance: .standard)
            // Above the top line: y = 5 mm, x within it.
            #expect(abs(p.y - 0.005) < 1.0e-5 && p.x > -1.0e-5 && p.x < 0.01 + 1.0e-5)
            // Beside the side spline: its zx projection is on the spline.
            let local = sideSystem.project(p).point
            var nearest = Double.infinity
            for j in 0...2000 {
                let q = try splineCurve.bSpline.point(at: Double(j) / 2000, tolerance: .standard)
                nearest = min(nearest, hypot(q.x - local.x, q.y - local.y))
            }
            #expect(nearest < 2.0e-5)
        }
    }

    @Test func curvesOnParallelPlanesAreRefused() throws {
        var document = DesignDocument.empty()
        let first = try document.createLineSketch(name: "A", plane: .xy, start: SketchPoint(x: mm(0), y: mm(0)), end: SketchPoint(x: mm(10), y: mm(0)))
        let second = try document.createLineSketch(name: "B", plane: .xy, start: SketchPoint(x: mm(0), y: mm(5)), end: SketchPoint(x: mm(10), y: mm(-5)))
        let before = document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            try document.projectCurveIntersection(first: try curveTarget(document, first), second: try curveTarget(document, second))
        }
        #expect(document.cadDocument.designGraph == before)
    }
}
