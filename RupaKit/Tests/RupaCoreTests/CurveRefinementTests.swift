import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Complete Edge extends curves to the curves their extensions meet; Subdivide doubles a spline's
/// control points and raises a B-spline surface.
@Suite struct CurveRefinementTests {
    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: .length(x, .meter), y: .length(y, .meter))
    }

    /// The selection target of the only curve in `featureID`'s sketch.
    private func curve(_ featureID: FeatureID, in document: DesignDocument) throws -> (SelectionTarget, SketchEntityID) {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "Expected a sketch.")
        }
        let entityID = try #require(sketch.entityOrder.first)
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID })
        return (SelectionTarget(sceneNodeID: node.id, component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: entityID))), entityID)
    }

    private func entity(_ featureID: FeatureID, _ entityID: SketchEntityID, in document: DesignDocument) -> SketchEntity? {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation else { return nil }
        return sketch.entities[entityID]
    }

    private func value(_ expression: CADExpression, in document: DesignDocument) throws -> Double {
        try document.cadDocument.parameters.resolvedValue(for: expression).value
    }

    /// A vertical wall at x = 2 from y = -1 to 1, drawn as its own sketch on the same plane.
    private func documentWithWall() throws -> DesignDocument {
        var document = DesignDocument.empty()
        _ = try document.createLineSketch(name: "Wall", plane: .xy, start: point(2, -1), end: point(2, 1))
        return document
    }

    @Test func aLineExtendsOnlyTheEndWhoseExtensionMeetsAnotherCurve() throws {
        var document = try documentWithWall()
        let featureID = try document.createLineSketch(name: "Line", plane: .xy, start: point(0, 0), end: point(1, 0))
        let (target, entityID) = try curve(featureID, in: document)

        #expect(try document.completeSketchCurve(target: target) == [.end])
        guard case .line(let line) = entity(featureID, entityID, in: document) else {
            Issue.record("Expected the line.")
            return
        }
        #expect(abs(try value(line.end.x, in: document) - 2) < 1e-9)
        #expect(abs(try value(line.end.y, in: document)) < 1e-9)
        #expect(abs(try value(line.start.x, in: document)) < 1e-12)

        #expect(throws: EditorError.self, "Both ends now rest on or reach nothing further.") {
            try document.completeSketchCurve(target: target)
        }
    }

    @Test func anArcExtendsAroundItsCircle() throws {
        var document = DesignDocument.empty()
        _ = try document.createLineSketch(name: "Wall", plane: .xy, start: point(-0.5, 0), end: point(-0.5, 2))
        let featureID = try document.createArcSketch(
            name: "Arc", plane: .xy, center: point(0, 0), radius: .length(1, .meter),
            startAngle: .angle(0, .radian), endAngle: .angle(.pi / 2, .radian)
        )
        let (target, entityID) = try curve(featureID, in: document)

        #expect(try document.completeSketchCurve(target: target) == [.end])
        guard case .arc(let arc) = entity(featureID, entityID, in: document) else {
            Issue.record("Expected the arc.")
            return
        }
        #expect(abs(try value(arc.endAngle, in: document) - 2 * .pi / 3) < 1e-9)
        #expect(abs(try value(arc.startAngle, in: document)) < 1e-12)
    }

    @Test func aSplineExtendsStraightAlongItsEndTangent() throws {
        var document = try documentWithWall()
        let featureID = try document.createSplineSketch(name: "Spline", plane: .xy, spline: SketchSpline(
            controlPoints: [point(0, 0.5), point(0.3, -0.2), point(0.6, 0), point(1, 0)], isClosed: false
        ))
        let (target, entityID) = try curve(featureID, in: document)

        #expect(try document.completeSketchCurve(target: target) == [.end])
        guard case .spline(let spline) = entity(featureID, entityID, in: document) else {
            Issue.record("Expected the spline.")
            return
        }
        #expect(spline.controlPoints.count == 7)
        let last = try #require(spline.controlPoints.last)
        #expect(abs(try value(last.x, in: document) - 2) < 1e-9)
        #expect(abs(try value(last.y, in: document)) < 1e-9)
    }

    @Test func nothingChangesWhenNoCurveIsReached() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Line", plane: .xy, start: point(0, 0), end: point(1, 0))
        _ = try document.createLineSketch(name: "Parallel", plane: .xy, start: point(0, 1), end: point(1, 1))
        _ = try document.createLineSketch(name: "Elsewhere", plane: .yz, start: point(-1, -1), end: point(1, 1))
        let before = document
        let (target, _) = try curve(featureID, in: document)
        #expect(throws: EditorError.self) { try document.completeSketchCurve(target: target) }
        #expect(document.cadDocument.designGraph == before.cadDocument.designGraph)
        #expect(document.productMetadata == before.productMetadata)
    }

    @Test func subdivideSplitsEverySpanAtItsMiddleAndReportsTheNewControlPoints() throws {
        var document = DesignDocument.empty()
        let points = [point(0, 0), point(1, 2), point(2, 2), point(3, 0), point(4, -2), point(5, -2), point(6, 0)]
        let featureID = try document.createSplineSketch(
            name: "Spline", plane: .xy, spline: SketchSpline(controlPoints: points, isClosed: false)
        )
        let (target, entityID) = try curve(featureID, in: document)

        #expect(try document.subdivideSketchSpline(target: target) == [2, 3, 4, 8, 9, 10])
        guard case .spline(let spline) = entity(featureID, entityID, in: document) else {
            Issue.record("Expected the spline.")
            return
        }
        #expect(spline.controlPoints.count == 13)
        // The middle of the first span of (0,0) (1,2) (2,2) (3,0) is (1.5, 1.5).
        #expect(abs(try value(spline.controlPoints[3].x, in: document) - 1.5) < 1e-9)
        #expect(abs(try value(spline.controlPoints[3].y, in: document) - 1.5) < 1e-9)
        // The original joint moves to index 6 unchanged.
        #expect(abs(try value(spline.controlPoints[6].x, in: document) - 3) < 1e-12)
        #expect(abs(try value(spline.controlPoints[12].x, in: document) - 6) < 1e-12)
    }

    @Test func subdivideRaisesASurfaceAndAddsASpanKeepingItsShape() throws {
        var document = DesignDocument.empty()
        let original = BSplineSurface3D(
            uDegree: 3, vDegree: 3, uKnots: [0, 0, 0, 0, 1, 1, 1, 1], vKnots: [0, 0, 0, 0, 1, 1, 1, 1],
            controlPoints: (0..<4).map { v in
                (0..<4).map { u in Point3D(x: Double(u), y: Double(v), z: Double((u * v) % 3) * 0.3) }
            }
        )
        let featureID = try document.createBSplineSurface(name: "Surface", surface: original)
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID })

        try document.subdivideSurface(target: SelectionTarget(sceneNodeID: node.id))
        guard case .bSplineSurface(let feature) = document.cadDocument.designGraph.nodes[featureID]?.operation else {
            Issue.record("Expected the surface.")
            return
        }
        let raised = feature.surface
        #expect(raised.uDegree == 4 && raised.vDegree == 4)
        #expect(raised.uControlPointCount == 6 && raised.vControlPointCount == 6)
        #expect(raised.uKnots == [0, 0, 0, 0, 0, 0.5, 1, 1, 1, 1, 1])
        for (u, v) in [(0.3, 0.7), (0.5, 0.5), (0.9, 0.1)] {
            let before = try original.point(u: u, v: v, tolerance: .standard)
            let after = try raised.point(u: u, v: v, tolerance: .standard)
            #expect((after - before).length < 1e-10)
        }
        let properties = document.productMetadata.sceneNodes[node.id]?.object?.properties
        #expect(properties?["surface.degree.u"] == .integer(4))
        #expect(properties?["control.point.v"] == .integer(6))
    }
}
