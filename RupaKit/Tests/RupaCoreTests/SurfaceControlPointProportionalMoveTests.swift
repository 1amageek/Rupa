import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Move Control Point's Proportional and Mirror options move a B-spline control net by hull
/// distance and across a construction-plane axis.
@Suite struct SurfaceControlPointProportionalMoveTests {
    typealias Index = SurfaceControlPointProportionalMove.NetIndex

    /// A flat 5 × 5 net symmetric about x = 0: control point (u, v) sits at ((u − 2) cm, (v − 2) cm, 0).
    private func net() -> [[Point3D]] {
        (0..<5).map { v in (0..<5).map { u in Point3D(x: Double(u - 2) * 0.01, y: Double(v - 2) * 0.01, z: 0) } }
    }

    private func move(_ options: SurfaceControlPointMoveOptions) -> SurfaceControlPointProportionalMove {
        SurfaceControlPointProportionalMove(options: options, distanceTolerance: 1.0e-9)
    }

    private let delta = Vector3D(x: 0.001, y: 0, z: 0.002)

    @Test func noneMovesExactlyTheSelectedControlPoints() throws {
        let result = try move(.init()).displacements(
            controlPoints: net(), selected: [Index(u: 3, v: 2), Index(u: 0, v: 0)], delta: delta, mirror: nil
        )
        #expect(result == [Index(u: 3, v: 2): delta, Index(u: 0, v: 0): delta])
    }

    @Test func allFallsOffAlongTheHullFromEverySelectedControlPoint() throws {
        let result = try move(.init(proportional: .all, falloffU: 2, falloffV: 1)).displacements(
            controlPoints: net(), selected: [Index(u: 2, v: 2)], delta: delta, mirror: nil
        )
        // One step along U is half the U reach: (1 − 0.25)² = 0.5625. One step along V reaches the
        // V limit and does not move.
        #expect(result[Index(u: 2, v: 2)] == delta)
        #expect(result[Index(u: 3, v: 2)] == delta * 0.5625)
        #expect(result[Index(u: 1, v: 2)] == delta * 0.5625)
        #expect(result[Index(u: 2, v: 3)] == nil)
        #expect(result[Index(u: 4, v: 2)] == nil)
        #expect(result.count == 3)
    }

    @Test func selectedWeighsOnlySelectedControlPointsFromTheActiveOne() throws {
        let result = try move(.init(proportional: .selected, falloffU: 2, falloffV: 2)).displacements(
            controlPoints: net(), selected: [Index(u: 1, v: 2), Index(u: 4, v: 4), Index(u: 2, v: 2)],
            delta: delta, mirror: nil
        )
        #expect(result[Index(u: 2, v: 2)] == delta)
        #expect(result[Index(u: 1, v: 2)] == delta * 0.5625)
        #expect(result[Index(u: 4, v: 4)] == nil, "Beyond the reach of the active control point.")
        #expect(result[Index(u: 3, v: 2)] == nil, "Unselected control points stay.")
    }

    @Test func mirrorMovesTheCounterpartByTheReflectedDeltaAndKeepsPlanePointsOnThePlane() throws {
        let plane = SurfaceControlPointProportionalMove.MirrorPlane(origin: .origin, normal: .unitX)
        let result = try move(.init(mirrorAxis: .x)).displacements(
            controlPoints: net(), selected: [Index(u: 3, v: 2), Index(u: 2, v: 4)], delta: delta, mirror: plane
        )
        #expect(result[Index(u: 3, v: 2)] == delta)
        #expect(result[Index(u: 1, v: 2)] == Vector3D(x: -0.001, y: 0, z: 0.002))
        #expect(result[Index(u: 2, v: 4)] == Vector3D(x: 0, y: 0, z: 0.002))
        #expect(result.count == 3)

        let proportional = try move(.init(proportional: .all, falloffU: 2, falloffV: 1, mirrorAxis: .x)).displacements(
            controlPoints: net(), selected: [Index(u: 4, v: 2)], delta: delta, mirror: plane
        )
        #expect(proportional[Index(u: 0, v: 2)] == Vector3D(x: -0.001, y: 0, z: 0.002))
        #expect(proportional[Index(u: 1, v: 2)] == Vector3D(x: -0.001, y: 0, z: 0.002) * 0.5625)
        #expect(proportional[Index(u: 3, v: 2)] == delta * 0.5625)
        #expect(proportional[Index(u: 2, v: 2)] == nil)
    }

    @Test func missingCounterpartAndInvalidFalloffAreTypedFailures() {
        var asymmetric = net()
        asymmetric[2][1] = Point3D(x: -0.012, y: 0, z: 0)
        let plane = SurfaceControlPointProportionalMove.MirrorPlane(origin: .origin, normal: .unitX)
        #expect(throws: EditorError.self) {
            _ = try move(.init(mirrorAxis: .x)).displacements(
                controlPoints: asymmetric, selected: [Index(u: 3, v: 2)], delta: delta, mirror: plane
            )
        }
        #expect(throws: EditorError.self) {
            _ = try move(.init(proportional: .all, falloffU: 0)).displacements(
                controlPoints: net(), selected: [Index(u: 3, v: 2)], delta: delta, mirror: nil
            )
        }
        #expect(throws: EditorError.self) {
            _ = try move(.init()).displacements(controlPoints: net(), selected: [Index(u: 5, v: 0)], delta: delta, mirror: nil)
        }
    }

    @Test func commandMovesThePlacedSurfaceAcrossTheWorldMirrorPlaneAtomically() throws {
        var document = DesignDocument.empty()
        let knots = [0, 0, 0, 1.0 / 3, 2.0 / 3, 1, 1, 1]
        let featureID = try document.createBSplineSurface(name: "Net", surface: BSplineSurface3D(
            uDegree: 2, vDegree: 2, uKnots: knots, vKnots: knots,
            controlPoints: net(), weights: Array(repeating: Array(repeating: 1, count: 5), count: 5)
        ))
        // The surface is placed 5 cm along world X, so the world plane x = 5 cm is its own x = 0.
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID })
        document.productMetadata.sceneNodes[node.id]?.localTransform = try Transform3D.translation(Vector3D(x: 0.05, y: 0, z: 0))
        let plane = SketchPlane.plane(Plane3D(origin: Point3D(x: 0.05, y: 0, z: 0), normal: .unitX))
        let polySplineID = try document.createPolySplineSurface(name: "Quad", sourceMesh: Mesh(
            positions: [
                Point3D(x: 0, y: 0.1, z: 0), Point3D(x: 0.02, y: 0.1, z: 0),
                Point3D(x: 0.02, y: 0.12, z: 0.004), Point3D(x: 0, y: 0.12, z: 0),
            ],
            indices: [0, 1, 2, 0, 2, 3]
        ))
        let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
        let points = try #require(summary.sources.first { $0.featureID == featureID.description }?.patches.first?.controlPoints)
        let polySplinePoint = try #require(
            summary.sources.first { $0.featureID == polySplineID.description }?.patches.first?.controlPoints.first?.selectionReference
        )
        let selected = try #require(points.first { $0.uIndex == 3 && $0.vIndex == 2 }?.selectionReference)

        // The plane's normal is its own z, so Mirror Z reflects across world x = 5 cm.
        try document.moveSurfaceControlPointsProportionally(
            targets: [selected], deltaX: .length(1, .millimeter), deltaY: .length(0, .millimeter),
            deltaZ: .length(2, .millimeter), options: .init(mirrorAxis: .z, mirrorPlane: plane)
        )
        guard case .bSplineSurface(let moved) = document.cadDocument.designGraph.nodes[featureID]?.operation else {
            Issue.record("Expected the B-spline surface feature.")
            return
        }
        #expect((moved.surface.controlPoints[2][3] - Point3D(x: 0.011, y: 0, z: 0.002)).length < 1e-12)
        #expect((moved.surface.controlPoints[2][1] - Point3D(x: -0.011, y: 0, z: 0.002)).length < 1e-12)
        #expect(moved.surface.controlPoints[2][2] == Point3D(x: 0, y: 0, z: 0))

        // A target that is not a B-spline control point refuses the whole move and changes nothing.
        let before = document.cadDocument.designGraph.nodes[featureID]
        #expect(throws: EditorError.self) {
            try document.moveSurfaceControlPointsProportionally(
                targets: [selected, polySplinePoint], deltaX: .length(1, .millimeter),
                deltaY: .length(0, .millimeter), deltaZ: .length(0, .millimeter), options: .init(proportional: .all)
            )
        }
        #expect(document.cadDocument.designGraph.nodes[featureID] == before)
    }
}
