import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Edges and corners of a B-spline sheet shown straight from its source move its boundary
/// control points, exactly and without a new feature.
@Suite struct SurfaceBoundaryEditTests {
    /// A flat 3 × 3 quadratic sheet over x, y ∈ [0, 0.04].
    private func sheet() throws -> (DesignDocument, FeatureID) {
        var document = DesignDocument.empty()
        let values = [0.0, 0.02, 0.04]
        let featureID = try document.createBSplineSurface(name: "Sheet", surface: BSplineSurface3D(
            uDegree: 2, vDegree: 2, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 0, 1, 1, 1],
            controlPoints: values.map { y in values.map { Point3D(x: $0, y: y, z: 0) } }
        ))
        return (document, featureID)
    }

    private func entries(_ kind: TopologySummaryResult.Entry.Kind, of document: DesignDocument) throws -> [TopologySummaryResult.Entry] {
        try TopologySnapshotService().snapshot(document: document).entries.filter { $0.kind == kind }
    }

    private func net(_ document: DesignDocument, _ featureID: FeatureID) throws -> [[Point3D]] {
        guard case .bSplineSurface(let feature) = document.cadDocument.designGraph.nodes[featureID]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "No surface.")
        }
        return feature.surface.controlPoints
    }

    @Test func anEdgeLiftsItsBoundaryRowAndACornerItsPoint() throws {
        var (document, featureID) = try sheet()
        let order = document.cadDocument.designGraph.order
        let edge = try #require(try entries(.edge, of: document).first { abs(($0.midpoint?.x ?? -1) - 0.04) < 1e-9 })
        try document.moveBodyEdges(targets: [try #require(edge.selectionTarget())], direction: .unitZ, distance: .length(0.01, .meter))
        #expect(document.cadDocument.designGraph.order == order)
        var points = try net(document, featureID)
        #expect(points.allSatisfy { abs($0[2].z - 0.01) < 1e-12 && abs($0[0].z) < 1e-12 && abs($0[1].z) < 1e-12 })

        let corner = try #require(try entries(.vertex, of: document).first { entry in
            guard let p = entry.start else { return false }
            return abs(p.x) < 1e-9 && abs(p.y) < 1e-9
        })
        try document.moveBodyVertices(targets: [try #require(corner.selectionTarget())], direction: .unitZ, distance: .length(-0.005, .meter))
        points = try net(document, featureID)
        #expect(abs(points[0][0].z + 0.005) < 1e-12)
        #expect(abs(points[0][1].z) < 1e-12)
    }

    @Test func anEdgeTurnsAboutItsOppositeBoundary() throws {
        var (document, featureID) = try sheet()
        let edge = try #require(try entries(.edge, of: document).first { abs(($0.midpoint?.x ?? -1) - 0.04) < 1e-9 })
        try document.transformBodyTopology(
            .edges, targets: [try #require(edge.selectionTarget())],
            motion: .rotation(DirectRotation(origin: .origin, axis: .unitY, angle: .angle(-90, .degree)))
        )
        let points = try net(document, featureID)
        // The far row turns up: x = 0.04 becomes z = 0.04 above x = 0.
        #expect(points.allSatisfy { abs($0[2].x) < 1e-12 && abs($0[2].z - 0.04) < 1e-12 })
    }
}
