import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// A Bridge Curve between curves that do not share a sketch, or between body edges, is solved in
/// world space: kept as a sketch spline when it lies in one plane, a spatial path otherwise.
@MainActor
@Suite struct SpatialBridgeCurveTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }

    private func line(_ document: inout DesignDocument, _ plane: SketchPlane, _ a: (Double, Double), _ b: (Double, Double)) throws -> SelectionTarget {
        let id = try document.createLineSketch(name: "Line", plane: plane,
                                               start: SketchPoint(x: mm(a.0), y: mm(a.1)), end: SketchPoint(x: mm(b.0), y: mm(b.1)))
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[id]?.operation,
              let entity = sketch.entities.keys.first else { throw EditorError(code: .referenceUnresolved, message: "missing") }
        let node = try #require(document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == id }?.key)
        return SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: id, entityID: entity)))
    }

    private let g1 = BridgeCurveContinuity(first: .g1, second: .g1)

    @Test func twoSketchesOnOnePlaneBridgeAsASketchSpline() throws {
        var document = DesignDocument.empty()
        let first = try line(&document, .xy, (0, 0), (10, 0))
        let second = try line(&document, .xy, (20, 5), (30, 5))
        let ends = try document.spatialBridgeEnds(joining: [first, second])
        #expect(ends.0.fraction == 1 && ends.1.fraction == 0)
        let id = try document.createSpatialBridgeCurve(first: ends.0, second: ends.1, continuity: g1)
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[id]?.operation,
              case .spline(let spline) = try #require(sketch.entities.values.first) else {
            Issue.record("A planar bridge should be a sketch spline.")
            return
        }
        let system = try SketchPlaneCoordinateSystem(plane: sketch.plane)
        let points = try spline.controlPoints.map { point in
            system.point(from: Point2D(
                x: try document.cadDocument.parameters.resolvedValue(for: point.x).value,
                y: try document.cadDocument.parameters.resolvedValue(for: point.y).value
            ))
        }
        #expect(spline.degree == 3 && points.count == 4)
        #expect((points[0] - Point3D(x: 0.01, y: 0, z: 0)).length < 1.0e-9)
        #expect((points[3] - Point3D(x: 0.02, y: 0.005, z: 0)).length < 1.0e-9)
        // Leaving the first line along +x and arriving on the second along +x.
        #expect(abs((points[1] - points[0]).y) < 1.0e-12 && (points[1] - points[0]).x > 0)
        #expect(abs((points[3] - points[2]).y) < 1.0e-12 && (points[3] - points[2]).x > 0)
    }

    @Test func skewLinesBridgeAsAPathAndRefuseCurvatureContinuity() throws {
        var document = DesignDocument.empty()
        let first = try line(&document, .xy, (0, 0), (10, 0))
        let raised = SketchPlane.plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.01), normal: .unitZ))
        let second = try line(&document, raised, (20, 5), (20, 15))
        let ends = (SpatialBridgeEnd(target: first, fraction: 1), SpatialBridgeEnd(target: second, fraction: 0))
        let id = try document.createSpatialBridgeCurve(first: ends.0, second: ends.1, continuity: g1)
        guard case .spatialPath(let path) = document.cadDocument.designGraph.nodes[id]?.operation else {
            Issue.record("A bridge off one plane should be a spatial path.")
            return
        }
        #expect((path.knots.first!.position - Point3D(x: 0.01, y: 0, z: 0)).length < 1.0e-9)
        #expect((path.knots.last!.position - Point3D(x: 0.02, y: 0.005, z: 0.01)).length < 1.0e-9)
        let before = document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            try document.createSpatialBridgeCurve(first: ends.0, second: ends.1, continuity: BridgeCurveContinuity(first: .g2, second: .g2))
        }
        #expect(document.cadDocument.designGraph == before)
    }

    @Test func twoBodyEdgesBridgeAtTheirNearestEnds() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        var document = session.document
        let edges = try TopologySnapshotService().snapshot(document: document).entries.filter { $0.kind == .edge }
        // Two parallel top edges, opposite each other.
        let top = edges.filter { ($0.start?.z ?? 0) > 1.0e-6 && ($0.end?.z ?? 0) > 1.0e-6 }
        let first = try #require(top.first)
        let second = try #require(top.first { candidate in
            guard let a = first.start, let b = first.end, let c = candidate.start, let d = candidate.end else { return false }
            let u = (b.x - a.x, b.y - a.y), w = (d.x - c.x, d.y - c.y)
            return candidate.subshapeID != first.subshapeID && abs(u.0 * w.1 - u.1 * w.0) < 1.0e-12
        })
        let ends = try document.spatialBridgeEnds(joining: [try #require(first.selectionTarget()), try #require(second.selectionTarget())])
        let id = try document.createSpatialBridgeCurve(first: ends.0, second: ends.1, continuity: g1)
        #expect(document.cadDocument.designGraph.nodes[id] != nil)
    }

    /// Clicked ends: a ray down onto a line lands at its fraction; ends on one sketch make an
    /// associative sketch Bridge Curve, ends on two sketches a spatial one.
    @Test func clickedEndsBridgeInOrAcrossSketches() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Pair", plane: .xy,
                                                      start: SketchPoint(x: mm(0), y: mm(0)), end: SketchPoint(x: mm(10), y: mm(0)))
        guard var feature = document.cadDocument.designGraph.nodes[featureID], case var .sketch(sketch) = feature.operation,
              let firstID = sketch.entities.keys.first else { throw EditorError(code: .referenceUnresolved, message: "missing") }
        let secondID = SketchEntityID()
        sketch.entities[secondID] = .line(SketchLine(start: SketchPoint(x: mm(20), y: mm(10)), end: SketchPoint(x: mm(30), y: mm(10))))
        feature.operation = .sketch(sketch)
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        let node = try #require(document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == featureID }?.key)
        func curve(_ id: SketchEntityID) -> SelectionTarget {
            SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: id)))
        }
        let fraction = try document.sketchCurveFraction(
            alongRay: Point3D(x: 0.0075, y: 0.001, z: 1), direction: Vector3D(x: 0, y: 0, z: -1), on: curve(firstID)
        )
        #expect(abs(fraction - 0.75) < 1.0e-9)

        let sources = document.productMetadata.bridgeCurveSources.count
        try document.createBridgeCurve(
            clicked: SpatialBridgeEnd(target: curve(firstID), fraction: 0.75), SpatialBridgeEnd(target: curve(secondID), fraction: 0.2),
            continuity: g1
        )
        #expect(document.productMetadata.bridgeCurveSources.count == sources + 1)

        let other = try line(&document, .xy, (0, 30), (10, 30))
        let id = try document.createBridgeCurve(
            clicked: SpatialBridgeEnd(target: curve(firstID), fraction: 1), SpatialBridgeEnd(target: other, fraction: 0.5),
            continuity: g1
        )
        #expect(id != featureID)
        #expect(document.productMetadata.bridgeCurveSources.count == sources + 1)
    }

    /// A tension scales its end's speed: doubling it doubles the first handle's length.
    @Test func tensionScalesTheEndHandle() throws {
        func handle(_ tension: Double) throws -> Double {
            var document = DesignDocument.empty()
            let first = try line(&document, .xy, (0, 0), (10, 0))
            let second = try line(&document, .xy, (20, 5), (30, 5))
            let id = try document.createSpatialBridgeCurve(
                first: SpatialBridgeEnd(target: first, fraction: 1), second: SpatialBridgeEnd(target: second, fraction: 0),
                continuity: g1, tensions: (tension, 1)
            )
            guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[id]?.operation,
                  case .spline(let spline) = try #require(sketch.entities.values.first) else { throw EditorError(code: .referenceUnresolved, message: "missing") }
            let x = try spline.controlPoints.prefix(2).map { try document.cadDocument.parameters.resolvedValue(for: $0.x).value }
            return x[1] - x[0]
        }
        #expect(abs(try handle(2) - 2 * (try handle(1))) < 1.0e-12)
    }
}

