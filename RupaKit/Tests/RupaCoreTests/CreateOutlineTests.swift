import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Create Outline leaves the silhouette on the body as joined 3D curves, the rim nearest the
/// viewer where two project onto one.
@MainActor
@Suite struct CreateOutlineTests {
    private func box(_ document: inout DesignDocument) throws -> SceneNodeID {
        let boxID = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(10, .millimeter), height: .length(10, .millimeter),
            depth: .length(10, .millimeter), direction: .normal
        )
        return try #require(document.productMetadata.sceneNodes.first { $0.value.reference == .body(boxID) }?.key)
    }

    private func path(_ document: DesignDocument, _ id: FeatureID) throws -> SpatialPathFeature {
        guard case .spatialPath(let path) = document.cadDocument.designGraph.nodes[id]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The outline path is missing.")
        }
        return path
    }

    @Test func aBoxSeenFromAboveOutlinesItsTopRim() throws {
        var document = DesignDocument.empty()
        let node = try box(&document)
        let ids = try document.createBodyOutlines(targets: [SelectionTarget(sceneNodeID: node)], plane: .xy)
        #expect(ids.count == 1)
        let outline = try path(document, try #require(ids.first))
        #expect(outline.isClosed && outline.knots.count == 4)
        // The top rim, z = 10 mm, not the bottom one.
        #expect(outline.knots.allSatisfy { abs($0.position.z - 0.01) < 1.0e-9 })
    }

    @Test func aBoxSeenAlongADiagonalOutlinesAClosedHexagon() throws {
        var document = DesignDocument.empty()
        let node = try box(&document)
        let plane = SketchPlane.plane(Plane3D(origin: .origin, normal: Vector3D(x: 1, y: 1, z: 1) * (1 / 3.0.squareRoot())))
        let ids = try document.createBodyOutlines(targets: [SelectionTarget(sceneNodeID: node)], plane: plane)
        #expect(ids.count == 1)
        let outline = try path(document, try #require(ids.first))
        #expect(outline.isClosed && outline.knots.count == 6)
    }
}
