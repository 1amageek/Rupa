import Foundation
import SwiftCAD
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import Testing
@testable import RupaCore

/// Copying a mesh object or a component instance gives it new identities and shares nothing.
@Suite struct SceneCloningMeshAndInstanceTests {
    private func triangle(identity: GeometrySourceID) throws -> MeshSource {
        var builder = MeshSourceBuilder(identity: identity)
        let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
        let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
        let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
        _ = try builder.addFace(vertexIDs: [first, second, third])
        return try builder.build()
    }

    private func meshDocument() throws -> (DesignDocument, SceneNodeID, GeometrySourceID) {
        let asset = try AuthoredMeshAsset(source: try triangle(identity: "mesh.source"), provenance: .created)
        let representationID: GeometryRepresentationID = "representation.mesh"
        var document = DesignDocument.empty(named: "Mesh")
        document.authoredMeshAssets[asset.id] = asset
        let node = try document.productMetadata.appendSceneNodeToFirstRoot(
            name: "Mesh",
            reference: .authoredMesh(asset.id),
            object: ObjectDescriptor(
                category: .body,
                geometryRole: .mesh,
                geometryRepresentations: GeometryRepresentationSet(
                    representations: [representationID: GeometryRepresentation(id: representationID, source: .authoredMesh(asset.id))],
                    selection: GeometryRepresentationSelection(modeling: representationID, presentation: representationID)
                )
            )
        )
        _ = try document.validate()
        return (document, node, asset.id)
    }

    @Test func mirrorCopiesAMeshAtTheWorldReflectionWithIndependentAsset() throws {
        var (document, node, source) = try meshDocument()
        let plane = try SceneMirrorPlane(origin: Point3D(x: 2, y: 0, z: 0), normal: .unitX)
        let copyID = try #require(try document.mirrorSceneNodes(ids: [node], plane: plane, options: .init()).first)
        let copy = try #require(document.productMetadata.sceneNodes[copyID])
        #expect(copy.reference?.geometrySourceID != source)
        let world = try SceneNodeHierarchy(metadata: document.productMetadata).worldTransform(of: copyID)
        #expect(try world.applied(to: Point3D(x: 1, y: 0, z: 0)) == Point3D(x: 3, y: 0, z: 0))
        #expect(document.authoredMeshAssets[source]?.source.vertexPositions == document.authoredMeshAssets[try #require(copy.reference?.geometrySourceID)]?.source.vertexPositions)
        _ = try document.validate()
    }

    @Test func placingAMeshCopiesItsAssetUnderANewIdentity() throws {
        var (document, node, source) = try meshDocument()
        #expect(document.productMetadata.sceneCopyRefusal(for: [node]) == nil)
        let copies = try document.placeSceneNodes(
            ids: [node], placements: [try Transform3D.translation(Vector3D(x: 2, y: 0, z: 0))]
        )
        let copy = try #require(copies.first.flatMap { document.productMetadata.sceneNodes[$0] })
        let copiedSource = try #require(copy.reference?.geometrySourceID)
        #expect(copiedSource != source)
        #expect(document.authoredMeshAssets.count == 2)
        #expect(document.authoredMeshAssets[copiedSource]?.id == copiedSource)
        #expect(document.authoredMeshAssets[copiedSource]?.source.vertexPositions == document.authoredMeshAssets[source]?.source.vertexPositions)
        let representations = try #require(copy.object?.geometryRepresentations)
        #expect(representations.representations.values.allSatisfy { $0.source == .authoredMesh(copiedSource) })
        #expect(representations.representations["representation.mesh"] == nil, "The copy's representation has its own identity.")
        let selection = try #require(representations.selection)
        #expect(representations.representations[selection.presentation] != nil)
        #expect(try SceneNodeHierarchy(metadata: document.productMetadata).worldTransform(of: copy.id).applied(to: .origin)
            == Point3D(x: 2, y: 0, z: 0))
        _ = try document.validate()
    }

    @Test func duplicatingAnInstanceMakesAnotherInstanceOfTheSameDefinition() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        )
        let box = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID }).id
        let instances = try document.placeSceneNodes(
            ids: [box], placements: [try Transform3D.translation(Vector3D(x: 1, y: 0, z: 0))], output: .componentInstance
        )
        let instanceNode = try #require(instances.first)
        let copies = try document.duplicateSceneNodes(ids: [instanceNode])
        let copyNode = try #require(copies.first.flatMap { document.productMetadata.sceneNodes[$0] })
        let sourceInstance = try #require(document.productMetadata.sceneNodes[instanceNode]?.reference?.componentInstanceID)
        let copiedInstance = try #require(copyNode.reference?.componentInstanceID)
        #expect(copiedInstance != sourceInstance)
        #expect(copyNode.object?.componentInstanceID == copiedInstance)
        let original = try #require(document.productMetadata.componentInstances[sourceInstance])
        let copied = try #require(document.productMetadata.componentInstances[copiedInstance])
        #expect(copied.definitionID == original.definitionID)
        #expect(copied.localTransform == original.localTransform)
        #expect(copied.name != original.name)
        _ = try document.validate()

        // Another document has no such definition, so the paste brings it along.
        let fragment = try document.sceneFragment(copying: [instanceNode])
        var other = DesignDocument.empty()
        _ = try other.pasteSceneFragment(fragment, placements: [.identity])
        #expect(other.productMetadata.componentDefinitions.count == 1)
    }

    @Test func pasteboardFragmentsWrittenBeforeMeshesAndInstancesStillDecode() throws {
        var (document, node, _) = try meshDocument()
        _ = document
        let fragment = try document.sceneFragment(copying: [node])
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(fragment)) as? [String: Any])
        object.removeValue(forKey: "authoredMeshes")
        object.removeValue(forKey: "componentInstances")
        let decoded = try JSONDecoder().decode(SceneFragment.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.authoredMeshes.isEmpty)
        #expect(decoded.componentInstances.isEmpty)
        #expect(decoded.roots == fragment.roots)
        document = DesignDocument.empty()
    }
}
