import SwiftCAD
import Testing
@testable import RupaCore

/// Duplicate, Place and Paste copy objects through one scene-fragment component.
@Suite struct SceneCloningTests {
    private let tolerance = 1.0e-9

    /// A 0.1 x 0.08 x 0.06 m box under a translated, rotated parent group.
    @MainActor
    private func boxUnderMovedParent() throws -> (EditorSession, box: SceneNodeID, parent: SceneNodeID) {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.08, .meter),
            depth: .length(0.06, .meter), direction: .normal
        ))
        let box = try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.kind == .body
        }).id
        let group = try session.execute(.groupSceneNodes(name: "Parent", memberIDs: [box], origin: nil))
        let parent = try #require(group.generatedIdentities.sceneNodeIDs.first)
        let placement = try Transform3D.rotation(axis: .unitZ, angleRadians: 0.3)
        _ = try session.execute(.setSceneNodeTransform(
            id: parent,
            localTransform: try Transform3D.translation(Vector3D(x: 1, y: -2, z: 0.5)).composed(with: placement)
        ))
        return (session, box, parent)
    }

    private func world(_ id: SceneNodeID, in document: DesignDocument) throws -> Transform3D {
        try SceneNodeHierarchy(metadata: document.productMetadata).worldTransform(of: id)
    }

    private func solidVolume(_ document: DesignDocument) throws -> Double {
        try MeasurementService().measure(document: document, ruler: .standard(for: .meter))
            .totals.solidVolumeCubicMeters
    }

    @MainActor
    @Test func duplicateCopiesInPlaceBesideTheSourceAndIsOneUndoStep() throws {
        let (session, box, parent) = try boxUnderMovedParent()
        let before = session.document
        let sourceFeatures = Set(before.cadDocument.designGraph.nodes.keys)

        let result = try session.execute(.duplicateSceneNodes(ids: [box]))
        let document = session.document
        let copy = try #require(document.productMetadata.sceneNodes[parent]?.childIDs.last)
        #expect(document.productMetadata.sceneNodes[parent]?.childIDs == [box, copy])
        #expect(result.generatedIdentities.sceneNodeIDs.contains(copy))
        #expect(try world(copy, in: document).isApproximately(world(box, in: document)))

        let copiedFeature = try #require(document.productMetadata.sceneNodes[copy]?.reference?.featureID)
        #expect(!sourceFeatures.contains(copiedFeature))
        #expect(document.cadDocument.designGraph.nodes.count == 2 * sourceFeatures.count)
        #expect(document.productMetadata.sceneNodes[copy]?.name == "Box 2")
        #expect(abs(try solidVolume(document) - 2 * 0.1 * 0.08 * 0.06) < tolerance)

        _ = try session.undo()
        #expect(session.document.cadDocument.designGraph.order == before.cadDocument.designGraph.order)
        #expect(session.document.productMetadata == before.productMetadata)
    }

    @MainActor
    @Test func aCopyIsIndependentOfItsSource() throws {
        let (session, box, parent) = try boxUnderMovedParent()
        let sourceGraph = session.document.cadDocument.designGraph.nodes
        _ = try session.execute(.duplicateSceneNodes(ids: [box]))
        let copy = try #require(session.document.productMetadata.sceneNodes[parent]?.childIDs.last)

        _ = try session.execute(.setSceneNodeObjectProperty(
            id: copy, propertyID: .init(rawValue: "corner.radius"), value: .length(0.01)
        ))

        for (id, node) in sourceGraph {
            #expect(session.document.cadDocument.designGraph.nodes[id] == node)
        }
        let copyFeatures = session.document.cadDocument.designGraph.nodes.values.filter { sourceGraph[$0.id] == nil }
        #expect(copyFeatures.contains { if case .fillet = $0.operation { true } else { false } })
    }

    @MainActor
    @Test func placeInsertsOneCopyPerWorldPlacement() throws {
        let (session, box, parent) = try boxUnderMovedParent()
        let first = try Transform3D.translation(Vector3D(x: 0.5, y: 0, z: 0))
        let second = try Transform3D.rotation(axis: .unitZ, angleRadians: .pi / 2)

        _ = try session.execute(.placeSceneNodes(ids: [box], placements: [first, second], output: .independentCopy))
        let document = session.document
        let children = try #require(document.productMetadata.sceneNodes[parent]?.childIDs)
        #expect(children.count == 3 && children[0] == box)
        let sourceWorld = try world(box, in: document)
        #expect(try world(children[1], in: document).isApproximately(first.composed(with: sourceWorld)))
        #expect(try world(children[2], in: document).isApproximately(second.composed(with: sourceWorld)))
        #expect(abs(try solidVolume(document) - 3 * 0.1 * 0.08 * 0.06) < tolerance)
    }

    @MainActor
    @Test func aFeaturePresentedOutsideTheSelectionIsCarriedHiddenWithTheCopy() throws {
        let (session, box, parent) = try boxUnderMovedParent()
        let sketchNode = try #require(session.document.productMetadata.sceneNodes[box]?.childIDs.first)
        _ = try session.execute(.moveSceneNodes(ids: [sketchNode], parentID: parent, beforeSiblingID: nil))
        let sketchWorld = try world(sketchNode, in: session.document)

        _ = try session.execute(.duplicateSceneNodes(ids: [box]))
        let document = session.document
        let copy = try #require(document.productMetadata.sceneNodes[parent]?.childIDs.last {
            document.productMetadata.sceneNodes[$0]?.reference?.kind == .body && $0 != box
        })
        let carried = try #require(document.productMetadata.sceneNodes[copy]?.childIDs.first)
        let carriedNode = try #require(document.productMetadata.sceneNodes[carried])
        #expect(carriedNode.isVisible == false)
        #expect(carriedNode.reference?.kind == .sketch)
        #expect(carriedNode.reference?.featureID != document.productMetadata.sceneNodes[sketchNode]?.reference?.featureID)
        #expect(try world(carried, in: document).isApproximately(sketchWorld))
    }

    @MainActor
    @Test func faceMaterialBindingsFollowTheCopiedFaces() throws {
        let (session, box, parent) = try boxUnderMovedParent()
        let material = Material(
            name: "PETG", baseColor: ColorRGBA(r: 0.1, g: 0.5, b: 0.8, a: 1.0),
            metallic: 0, roughness: 0.45, opacity: 1
        )
        var metadata = session.document.productMetadata
        metadata.materialLibrary.materials[material.id] = material
        _ = try session.execute(.replaceProductMetadata(metadata))
        let topology = try TopologySnapshotService().snapshot(document: session.document)
        let face = try #require(topology.entries.first { $0.kind == .face }?.selectionTarget())
        _ = try session.execute(.setTopologyMaterialBinding(target: face, materialID: material.id, process: nil))

        _ = try session.execute(.duplicateSceneNodes(ids: [box]))
        let document = session.document
        let copy = try #require(document.productMetadata.sceneNodes[parent]?.childIDs.last)
        let copiedFeature = try #require(document.productMetadata.sceneNodes[copy]?.reference?.featureID)
        let bindings = document.productMetadata.topologyMaterialBindings.values
        #expect(bindings.count == 2)
        let copied = try #require(bindings.first { $0.target.sceneNodeID == copy })
        guard case .face(let componentID) = copied.target.component,
              let subshape = componentID.generatedTopologySubshapeID,
              case .face(let sourceComponent) = face.component,
              let sourceSubshape = sourceComponent.generatedTopologySubshapeID else {
            Issue.record("The copied binding must name a generated face.")
            return
        }
        #expect(copied.materialID == material.id)
        #expect(subshape.role == sourceSubshape.role && subshape.ordinal == sourceSubshape.ordinal)
        #expect(document.cadDocument.designGraph.nodes[subshape.featureID] != nil)
        #expect(subshape.featureID != sourceSubshape.featureID)
        #expect(subshape.featureID == copiedFeature || document.cadDocument.designGraph.nodes[copiedFeature] != nil)
    }

    @MainActor
    @Test func pastingIntoAnotherDocumentBringsParametersAndRefusesAConflict() throws {
        let source = EditorSession()
        _ = try source.execute(.upsertParameter(name: "depth", expression: .length(0.05, .meter), kind: .length))
        let depthID = try #require(source.document.cadDocument.parameters.parameters.values.first { $0.name == "depth" }?.id)
        _ = try source.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .reference(depthID), direction: .normal
        ))
        let box = try #require(source.document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .body }).id
        let fragment = try source.document.sceneFragment(copying: [box])
        #expect(fragment.parameters.map(\.id) == [depthID])

        let target = EditorSession()
        let offset = try Transform3D.translation(Vector3D(x: 1, y: 0, z: 0))
        _ = try target.execute(.pasteSceneFragment(fragment, placements: [offset]))
        #expect(target.document.cadDocument.parameters.parameters[depthID]?.name == "depth")
        #expect(abs(try solidVolume(target.document) - 0.1 * 0.1 * 0.05) < tolerance)

        let conflicting = EditorSession()
        var parameters = conflicting.document.cadDocument
        parameters.parameters.parameters[depthID] = Parameter(
            id: depthID, name: "depth", expression: .length(0.2, .meter), kind: .length
        )
        var document = conflicting.document
        document.cadDocument = parameters
        let before = document
        #expect(throws: EditorError.self) {
            try document.pasteSceneFragment(fragment, placements: [offset])
        }
        #expect(document.cadDocument.designGraph.order == before.cadDocument.designGraph.order)
    }

    @MainActor
    @Test func componentInstancesAndPatternOutputsAreRefused() throws {
        let (session, box, _) = try boxUnderMovedParent()
        let definition = try session.execute(.createComponentDefinition(name: "Part", rootSceneNodeIDs: [box]))
        let definitionID = try #require(definition.generatedIdentities.componentDefinitionIDs.first)
        let instance = try session.execute(.createComponentInstance(
            name: "Instance", definitionID: definitionID, localTransform: .identity
        ))
        let instanceNode = try #require(instance.generatedIdentities.sceneNodeIDs.first)
        let before = session.document

        #expect(throws: (any Error).self) {
            _ = try session.execute(.duplicateSceneNodes(ids: [instanceNode]))
        }
        #expect(session.document.productMetadata == before.productMetadata)
    }
}

private extension Transform3D {
    func isApproximately(_ other: Transform3D, tolerance: Double = 1.0e-12) -> Bool {
        zip(matrix.values, other.matrix.values).allSatisfy { abs($0 - $1) <= tolerance }
    }
}
