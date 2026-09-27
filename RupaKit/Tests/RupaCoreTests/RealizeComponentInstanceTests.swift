import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Realize Instances turns a component instance into an independent, editable copy where the
/// instance shows its definition, and leaves the definition and its other instances alone.
@Suite struct RealizeComponentInstanceTests {
    private func boxWithInstances() throws -> (DesignDocument, box: SceneNodeID, instances: [SceneNodeID]) {
        var document = DesignDocument.empty()
        let featureID = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        )
        let box = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID }).id
        let instances = try document.placeSceneNodes(
            ids: [box],
            placements: [
                try Transform3D.translation(Vector3D(x: 1, y: 0, z: 0)),
                try Transform3D.translation(Vector3D(x: 0, y: 2, z: 0)),
            ],
            output: .componentInstance
        )
        return (document, box, instances)
    }

    /// Where an occurrence of the box shows its origin, for the occurrences under `node`.
    private func shownOrigins(under node: SceneNodeID, box: SceneNodeID, in document: DesignDocument) throws -> [Point3D] {
        try SceneNodeHierarchy(metadata: document.productMetadata).resolvedOccurrences().filter {
            $0.sceneNodeID == node && $0.sourceSceneNodeID == box
        }.map { try $0.worldTransform.applied(to: .origin) }
    }

    @Test func anInstanceBecomesAnIndependentCopyWhereItWasShown() throws {
        var (document, box, instances) = try boxWithInstances()
        let shown = try #require(try shownOrigins(under: instances[0], box: box, in: document).first)
        let definitionCount = document.productMetadata.componentDefinitions.count
        let featureCount = document.cadDocument.designGraph.nodes.count

        let copies = try document.realizeComponentInstances(sceneNodeIDs: [instances[0]])

        let copy = try #require(copies.first.flatMap { document.productMetadata.sceneNodes[$0] })
        #expect(copy.reference?.kind == .body)
        #expect(copy.reference?.featureID != document.productMetadata.sceneNodes[box]?.reference?.featureID)
        let copied = try SceneNodeHierarchy(metadata: document.productMetadata).worldTransform(of: copy.id).applied(to: .origin)
        #expect((copied - shown).length < 1e-12)
        #expect(document.productMetadata.sceneNodes[instances[0]] == nil)
        #expect(document.productMetadata.sceneNodes[instances[1]] != nil)
        #expect(document.productMetadata.componentDefinitions.count == definitionCount)
        #expect(document.cadDocument.designGraph.nodes.count > featureCount)
        _ = try document.validate()
    }

    @Test func aNodeThatIsNotAnInstanceIsRefusedAndNothingChanges() throws {
        var (document, box, _) = try boxWithInstances()
        let before = document.productMetadata
        #expect(throws: EditorError.self) {
            _ = try document.realizeComponentInstances(sceneNodeIDs: [box])
        }
        #expect(document.productMetadata == before)
    }
}
