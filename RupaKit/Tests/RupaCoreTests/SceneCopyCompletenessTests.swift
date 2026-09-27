import Foundation
import SwiftCAD
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import Testing
@testable import RupaCore

/// Copies carry saved measurements, construction planes, meshes in arrays and instance definitions.
@Suite struct SceneCopyCompletenessTests {
    private func box(_ document: inout DesignDocument) throws -> (FeatureID, SceneNodeID) {
        let featureID = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        )
        return (featureID, try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID }).id)
    }

    @Test func aMeasurementCopiedWithItsGeometryFollowsTheCopy() throws {
        var document = DesignDocument.empty()
        let (featureID, boxNode) = try box(&document)
        let topology = try TopologySnapshotService().snapshot(document: document)
        let face = try #require(topology.entries.first { $0.kind == .face && $0.sceneNodeID == boxNode.description })
        let faceTarget = try #require(face.selectionTarget())
        let boxOccurrence = try #require(try SceneNodeHierarchy(metadata: document.productMetadata).resolvedOccurrences()
            .first { $0.sceneNodeID == boxNode })
        let faceAnchor = MeasurementAnchor(
            kind: .topologyReference, role: .start, sceneNodeID: boxNode,
            occurrenceID: boxOccurrence.id,
            topologyReference: MeasurementTopologyAnchor(
                sceneNodeID: boxNode, component: faceTarget.component, kind: .face, subshapeID: face.subshapeID
            )
        )
        let measurementID = try document.addMeasurementAnnotation(MeasurementAnnotation(
            name: "Gap", kind: .distance,
            anchors: [faceAnchor, .worldPoint(Point3D(x: 1, y: 0, z: 0), role: .end)]
        ))
        let annotationNode = try #require(document.productMetadata.measurements[measurementID]?.sceneNodeID)

        let offset = try Transform3D.translation(Vector3D(x: 2, y: 0, z: 0))
        let copies = try document.placeSceneNodes(ids: [boxNode, annotationNode], placements: [offset])
        #expect(copies.count == 2)
        let copied = try #require(document.productMetadata.measurements.values.first { $0.id != measurementID })
        #expect(copied.sceneNodeID.map(copies.contains) == true)
        let copiedBox = try #require(copies.first { document.productMetadata.sceneNodes[$0]?.reference?.kind == .body })
        let copiedFeature = try #require(document.productMetadata.sceneNodes[copiedBox]?.reference?.featureID)
        #expect(copiedFeature != featureID)
        let copiedFace = try #require(copied.anchors[0].topologyReference)
        #expect(copiedFace.sceneNodeID == copiedBox)
        #expect(GeneratedSubshapeIdentity.subshapeID(from: copiedFace.subshapeID)?.featureID == copiedFeature)
        let copiedOccurrence = try SceneNodeHierarchy(metadata: document.productMetadata).resolvedOccurrences()
            .first { $0.sceneNodeID == copiedBox }
        #expect(copied.anchors[0].occurrenceID == copiedOccurrence?.id)
        #expect(copied.anchors[1].worldPoint == Point3D(x: 3, y: 0, z: 0), "A world anchor moves with the copy.")

        let resolution = MeasurementAnnotationResolver().resolve(
            copied, in: document, topology: try TopologySnapshotService().snapshot(document: document)
        )
        guard case .resolved = resolution.outcome else {
            Issue.record("The copied measurement resolves on the copied geometry: \(resolution.outcome)")
            return
        }
        _ = try document.validate()
    }

    @Test func aConstructionPlaneCopiesAsANewPlane() throws {
        var document = DesignDocument.empty()
        let planeID = try document.createConstructionPlane(name: "Datum", plane: .yz)
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.constructionPlaneID == planeID }).id
        #expect(document.productMetadata.sceneCopyRefusal(for: [node]) == nil)
        let copies = try document.duplicateSceneNodes(ids: [node])
        let copiedPlane = try #require(copies.first.flatMap { document.productMetadata.sceneNodes[$0]?.reference?.constructionPlaneID })
        #expect(copiedPlane != planeID)
        #expect(document.productMetadata.constructionPlanes[copiedPlane]?.name == "Datum Copy")
        #expect(document.productMetadata.constructionPlanes[copiedPlane]?.plane == .yz)
        _ = try document.validate()
    }

    @Test func anIndependentCopyArrayOfAMeshCopiesTheMeshEachTime() throws {
        var builder = MeshSourceBuilder(identity: "mesh.source")
        let a = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
        let b = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
        let c = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
        _ = try builder.addFace(vertexIDs: [a, b, c])
        let asset = try AuthoredMeshAsset(source: try builder.build(), provenance: .created)
        var document = DesignDocument.empty()
        document.authoredMeshAssets[asset.id] = asset
        let representationID: GeometryRepresentationID = "representation.mesh"
        let node = try document.productMetadata.appendSceneNodeToFirstRoot(
            name: "Mesh", reference: .authoredMesh(asset.id),
            object: ObjectDescriptor(
                category: .body, geometryRole: .mesh,
                geometryRepresentations: GeometryRepresentationSet(
                    representations: [representationID: GeometryRepresentation(id: representationID, source: .authoredMesh(asset.id))],
                    selection: GeometryRepresentationSelection(modeling: representationID, presentation: representationID)
                )
            )
        )
        let arrayID = try document.createPatternArray(
            name: "Meshes", copying: [node],
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(direction: .unitX, distance: .length(2, .meter), copyCount: 3)
            )),
            outputMode: .independentCopy
        )
        let outputs = try #require(document.productMetadata.patternArrays[arrayID]?.outputSceneNodeIDs)
        #expect(outputs.count == 3)
        #expect(document.authoredMeshAssets.count == 4, "The source mesh and one copy per output.")
        _ = try document.validate()
        let summary = PatternArraySummaryService().summarize(document: document, generation: DocumentGeneration(1), dirty: false)
        #expect(summary.patternArrays.first?.diagnostics.isEmpty == true, "\(summary.patternArrays.first?.diagnostics ?? [])")

        // Fewer copies drop the meshes only those outputs presented.
        try document.updatePatternArray(id: arrayID, distribution: .rectangular(RectangularPatternArray(
            firstAxis: PatternArrayLinearAxis(direction: .unitX, distance: .length(2, .meter), copyCount: 1)
        )))
        #expect(document.authoredMeshAssets.count == 2)
    }

    @Test func anInstancePastedIntoAnotherDocumentBringsItsDefinition() throws {
        var document = DesignDocument.empty()
        let (_, boxNode) = try box(&document)
        let instances = try document.placeSceneNodes(
            ids: [boxNode], placements: [try Transform3D.translation(Vector3D(x: 1, y: 0, z: 0))], output: .componentInstance
        )
        let fragment = try document.sceneFragment(copying: [try #require(instances.first)])
        #expect(fragment.componentDefinitions.count == 1)

        var other = DesignDocument.empty()
        let pasted = try other.pasteSceneFragment(fragment, placements: [.identity])
        let instanceID = try #require(pasted.first.flatMap { other.productMetadata.sceneNodes[$0]?.reference?.componentInstanceID })
        let definitionID = try #require(other.productMetadata.componentInstances[instanceID]?.definitionID)
        let definition = try #require(other.productMetadata.componentDefinitions[definitionID])
        #expect(!definition.rootSceneNodeIDs.isEmpty)
        #expect(definition.rootSceneNodeIDs.allSatisfy { other.productMetadata.sceneNodes[$0]?.isVisible == false },
                "The definition content is kept hidden; the instance shows it.")
        _ = try other.validate()

        // Pasting again reuses nothing across documents but keeps one definition per paste.
        _ = try other.pasteSceneFragment(fragment, placements: [.identity])
        _ = try other.validate()
    }
}
