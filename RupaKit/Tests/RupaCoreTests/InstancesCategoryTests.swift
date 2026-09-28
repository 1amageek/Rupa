import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// An instance of a group sits outside the group, under the document root's Instances category;
/// an instance of a single object stays beside it.
@MainActor
@Suite struct InstancesCategoryTests {
    private func box(_ document: inout DesignDocument) throws -> SceneNodeID {
        let id = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(10, .millimeter), height: .length(10, .millimeter),
            depth: .length(10, .millimeter), direction: .normal
        )
        return try #require(document.productMetadata.sceneNodes.first { $0.value.reference == .body(id) }?.key)
    }

    private func parent(of id: SceneNodeID, in document: DesignDocument) -> SceneNodeID? {
        document.productMetadata.sceneNodes.first { $0.value.childIDs.contains(id) }?.key
    }

    @Test func instancesOfAGroupGoUnderOneInstancesCategory() throws {
        var document = DesignDocument.empty()
        let group = try document.groupSceneNodes(name: "Group", memberIDs: [try box(&document)])
        let root = try #require(document.productMetadata.rootSceneNodeIDs.first)
        let first = try #require(try document.placeSceneNodes(ids: [group], placements: [.identity], output: .componentInstance).first)
        let second = try #require(try document.placeSceneNodes(
            ids: [group], placements: [.translation(Vector3D(x: 0.1, y: 0, z: 0))], output: .componentInstance
        ).first)
        let category = try #require(parent(of: first, in: document))
        #expect(parent(of: second, in: document) == category)
        #expect(parent(of: category, in: document) == root)
        let node = try #require(document.productMetadata.sceneNodes[category])
        #expect(node.isGroupingNode && node.name == "Instances")
        // The category is transparent: the instance's world placement is its placement from the root.
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        let local = try #require(document.productMetadata.sceneNodes[second]?.localTransform)
        #expect(try hierarchy.worldTransform(of: second) == (try hierarchy.worldTransform(of: root)).composed(with: local))
        try document.productMetadata.validate(against: document.cadDocument, objectRegistry: .builtIn)
    }

    @Test func anInstanceOfOneObjectStaysBesideIt() throws {
        var document = DesignDocument.empty()
        let body = try box(&document)
        let root = try #require(document.productMetadata.rootSceneNodeIDs.first)
        let instance = try #require(try document.placeSceneNodes(ids: [body], placements: [.identity], output: .componentInstance).first)
        #expect(parent(of: instance, in: document) == root)
        #expect(!document.productMetadata.sceneNodes.values.contains { $0.name == "Instances" })
    }
}
