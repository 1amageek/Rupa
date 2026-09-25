import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Suite @MainActor struct PlacedMeasurementTests {
    private func fixture() throws -> (DesignDocument, SceneNodeID) {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedRectangle(
            name: "Unit Box", plane: .xy, width: .length(1, .meter),
            height: .length(1, .meter), depth: .length(1, .meter), direction: .normal
        ))
        let node = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .body })
        return (session.document, node.id)
    }

    private func measure(_ document: DesignDocument, selecting ids: [SceneNodeID]) throws -> MeasurementResult {
        try MeasurementService().measure(
            document: document,
            selection: SelectionModel(selectedTargets: ids.map { SelectionTarget(sceneNodeID: $0) }),
            ruler: .standard(for: .meter)
        )
    }

    @Test func reflectedNonuniformPlacementMeasuresWorldGeometryAndRetainsIdentity() throws {
        var (document, nodeID) = try fixture()
        let transform = try Transform3D.translation(Vector3D(x: 10, y: 20, z: 30))
            .composed(with: .scale(Vector3D(x: -2, y: 3, z: 4), about: .origin))
        try document.setSceneNodeTransform(id: nodeID, localTransform: transform)
        let result = try measure(document, selecting: [nodeID])
        let solid = try #require(result.solids.first)
        let bounds = try #require(result.bounds)
        #expect(result.solids.count == 1)
        #expect(abs(solid.volumeCubicMeters - 24) < 1e-9)
        #expect(abs(try #require(solid.surfaceAreaSquareMeters) - 52) < 1e-9)
        #expect(abs(bounds.sizeX - 2) < 1e-9)
        #expect(abs(bounds.sizeY - 3) < 1e-9)
        #expect(abs(bounds.sizeZ - 4) < 1e-9)
        #expect(bounds.minX > 5 && bounds.minY > 15 && bounds.minZ > 25)
        #expect(abs(try #require(solid.linearDimensions.first).meters - 4) < 1e-9)
        #expect(solid.occurrenceID != nil)
        let decoded = try JSONDecoder().decode(MeasurementResult.self, from: JSONEncoder().encode(result))
        #expect(decoded == result)
    }

    @Test func repeatedComponentSelectionCountsEachOccurrenceOnce() throws {
        var (document, nodeID) = try fixture()
        let definitionID = try document.createComponentDefinition(name: "Part", rootSceneNodeIDs: [nodeID])
        let instanceA = try document.createComponentInstance(name: "A", definitionID: definitionID,
            localTransform: .translation(Vector3D(x: 5, y: 0, z: 0)))
        let instanceB = try document.createComponentInstance(name: "B", definitionID: definitionID,
            localTransform: .translation(Vector3D(x: 10, y: 0, z: 0)))
        let nodes = document.productMetadata.sceneNodes.values.filter {
            $0.reference?.componentInstanceID == instanceA || $0.reference?.componentInstanceID == instanceB
        }.map(\.id)
        let result = try measure(document, selecting: nodes)
        #expect(result.solids.count == 2)
        #expect(Set(result.solids.compactMap(\.occurrenceID)).count == 2)
        #expect(abs(result.totals.solidVolumeCubicMeters - 2) < 1e-9)
        #expect(try #require(result.bounds).minX > 4)
        let root = try #require(document.productMetadata.rootSceneNodeIDs.first)
        let grouped = try measure(document, selecting: [root, nodeID])
        #expect(grouped.solids.count == 3)
    }

    @Test func selectedProfileUsesItsAffinePlaneArea() throws {
        var (document, _) = try fixture()
        let sketchID = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .sketch }?.id)
        try document.setSceneNodeTransform(id: sketchID,
            localTransform: .scale(Vector3D(x: 2, y: 3, z: 4), about: .origin))
        let result = try measure(document, selecting: [sketchID])
        #expect(abs(result.totals.profileAreaSquareMeters - 6) < 1e-9)
        #expect(abs(try #require(result.bounds).sizeX - 2) < 1e-9)
        #expect(abs(try #require(result.bounds).sizeY - 3) < 1e-9)
    }

    @Test func staleSelectionIsRejected() throws {
        let (document, _) = try fixture()
        #expect(throws: EditorError.self) {
            try measure(document, selecting: [SceneNodeID()])
        }
    }

    @Test func invalidPlacementDoesNotPublishPartialChanges() throws {
        var (document, nodeID) = try fixture()
        let definitionID = try document.createComponentDefinition(name: "Part", rootSceneNodeIDs: [nodeID])
        var singular = Transform3D.identity
        singular.matrix.values[0] = 0
        let before = document.productMetadata
        #expect(throws: EditorError.self) {
            try document.setSceneNodeTransform(id: nodeID, localTransform: singular)
        }
        #expect(document.productMetadata == before)
        #expect(throws: EditorError.self) {
            try document.createComponentInstance(name: "Invalid", definitionID: definitionID, localTransform: singular)
        }
        #expect(document.productMetadata == before)
        let instanceID = try document.createComponentInstance(name: "Valid", definitionID: definitionID)
        let withInstance = document.productMetadata
        #expect(throws: EditorError.self) {
            try document.setComponentInstanceTransform(id: instanceID, localTransform: singular)
        }
        #expect(document.productMetadata == withInstance)
    }

    @Test func reversedPartialSweepUsesPlacedRetainedPathLength() throws {
        var document = DesignDocument.empty()
        let profile = try document.createRectangleSketch(name: "Profile", plane: .xy,
            width: .length(4, .millimeter), height: .length(2, .millimeter))
        let path = try document.createLineSketch(name: "Reversed Path", plane: .yz,
            start: SketchPoint(x: .length(0, .millimeter), y: .length(20, .millimeter)),
            end: SketchPoint(x: .length(0, .millimeter), y: .length(0, .millimeter)))
        let sweep = try document.createSweep(name: "Partial Sweep",
            sections: [.profile(ProfileReference(featureID: profile))],
            path: SweepPathReference(featureID: path),
            options: SweepOptions(distanceFraction: .constant(.scalar(0.75))))
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .body(sweep) })
        try document.setSceneNodeTransform(id: node.id,
            localTransform: .scale(Vector3D(x: 2, y: 3, z: 4), about: .origin))
        let result = try measure(document, selecting: [node.id])
        let solid = try #require(result.solids.first)
        let length = try #require(solid.linearDimensions.first { $0.kind == .sweepPathLength })
        #expect(abs(length.meters - 0.060) < 1e-8)
    }
}
