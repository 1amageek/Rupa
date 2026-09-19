import Foundation
import Testing
import SwiftCAD
@testable import RupaCore

@Suite("Spatial path source transactions")
struct SpatialPathEditingTests {
    @Test(.timeLimit(.minutes(1)))
    func conversionRetainsFeatureAndPlacementAndAllowsOutOfPlaneEditing() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(
            name: "Path", plane: .yz,
            start: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            end: SketchPoint(x: .length(2, .meter), y: .length(3, .meter))
        )
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.object?.sourceFeatureID == featureID })
        try document.convertSketchToSpatialPath(featureID: featureID)
        guard case let .spatialPath(path)? = document.cadDocument.designGraph.nodes[featureID]?.operation else {
            Issue.record("Conversion did not publish spatial source."); return
        }
        #expect(path.knots[1].position == Point3D(x: 0, y: 2, z: 3))
        #expect(document.productMetadata.sceneNodes[node.id]?.localTransform == node.localTransform)
        #expect(document.productMetadata.sceneNodes[node.id]?.object?.sourceFeatureID == featureID)
        try document.editSpatialPath(featureID: featureID,
            edit: .move(knotID: path.knots[1].id, handle: .position, point: Point3D(x: 4, y: 2, z: 3)))
        guard case let .spatialPath(edited)? = document.cadDocument.designGraph.nodes[featureID]?.operation else {
            Issue.record("Editing lost spatial source."); return
        }
        #expect(edited.knots[1].id == path.knots[1].id)
        #expect(edited.knots[1].position.x == 4)
        let before = document
        #expect(throws: (any Error).self) {
            try document.editSpatialPath(featureID: featureID, edit: .remove(knotID: path.knots[0].id))
        }
        #expect(document.cadDocument.designGraph == before.cadDocument.designGraph)
        #expect(document.productMetadata == before.productMetadata)
    }

    @Test(.timeLimit(.minutes(1)))
    func profileDependentConversionIsRejectedWithoutMutation() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createRectangleSketch(name: "Profile", plane: .xy,
            width: .length(2, .meter), height: .length(3, .meter))
        let extrusion = try FeatureNodeFactory.make(
            operation: .extrude(ExtrudeFeature(profile: .init(featureID: featureID), distance: .length(1, .meter))),
            in: document.cadDocument, tolerance: .standard)
        try document.appendFeature(extrusion)
        let before = document
        #expect(throws: (any Error).self) { try document.convertSketchToSpatialPath(featureID: featureID) }
        #expect(document.cadDocument.designGraph == before.cadDocument.designGraph)
        #expect(document.productMetadata == before.productMetadata)
    }
}
