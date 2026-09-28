import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Project Body Body makes the curves where two bodies meet, joined into closed paths.
@MainActor
@Suite struct ProjectBodyBodyTests {
    private func box(_ document: inout DesignDocument, corner: Double, depth: Double, base: Double = 0) throws -> SceneNodeID {
        let id = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: base == 0 ? .xy : .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: base / 1000), normal: .unitZ)),
            firstCorner: SketchPoint(x: .length(corner, .millimeter), y: .length(corner, .millimeter)),
            oppositeCorner: SketchPoint(x: .length(corner + 20, .millimeter), y: .length(corner + 20, .millimeter)),
            depth: .length(depth, .millimeter), direction: .normal
        )
        return try #require(document.productMetadata.sceneNodes.first { $0.value.reference == .body(id) }?.key)
    }

    /// The second box, raised 5 mm, pierces the first box's corner: they meet along one closed
    /// loop on the first box's two walls, with six corners.
    @Test func aBoxPiercingAnotherMeetsItAlongAClosedLoop() throws {
        var document = DesignDocument.empty()
        let first = try box(&document, corner: 0, depth: 20)
        let second = try box(&document, corner: 10, depth: 10, base: 5)
        let ids = try document.projectBodyIntersection(
            first: SelectionTarget(sceneNodeID: first), second: SelectionTarget(sceneNodeID: second)
        )
        #expect(ids.count == 1)
        guard case .spatialPath(let path) = document.cadDocument.designGraph.nodes[try #require(ids.first)]?.operation else {
            Issue.record("The intersection is not a spatial path.")
            return
        }
        #expect(path.isClosed)
        let expected = [(20.0, 10.0, 5.0), (20, 20, 5), (10, 20, 5), (10, 20, 15), (20, 20, 15), (20, 10, 15)]
            .map { Point3D(x: $0.0 / 1000, y: $0.1 / 1000, z: $0.2 / 1000) }
        #expect(expected.allSatisfy { corner in path.knots.contains { ($0.position - corner).length < 1.0e-9 } })
        // Every knot lies on the first box's walls x = 20 mm or y = 20 mm.
        #expect(path.knots.allSatisfy { abs($0.position.x - 0.02) < 1.0e-9 || abs($0.position.y - 0.02) < 1.0e-9 })
    }

    @Test func boxesApartAreRefused() throws {
        var document = DesignDocument.empty()
        let first = try box(&document, corner: 0, depth: 5)
        let second = try box(&document, corner: 100, depth: 5)
        let before = document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            try document.projectBodyIntersection(first: SelectionTarget(sceneNodeID: first), second: SelectionTarget(sceneNodeID: second))
        }
        #expect(document.cadDocument.designGraph == before)
    }
}
