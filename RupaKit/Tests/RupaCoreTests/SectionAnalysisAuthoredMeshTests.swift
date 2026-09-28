import SwiftCAD
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import Testing
@testable import RupaCore

@Suite struct SectionAnalysisAuthoredMeshTests {
    private func meshDocument() throws -> (DesignDocument, SceneNodeID) {
        var builder = MeshSourceBuilder(identity: "section.mesh")
        let vertices = try (0..<8).map { i in
            try builder.addVertex(GeometryPoint3D(x: Double(i & 1), y: Double((i >> 1) & 1), z: Double((i >> 2) & 1)))
        }
        for face in [[0,2,3,1], [4,5,7,6], [0,1,5,4], [2,6,7,3], [0,4,6,2], [1,3,7,5]] {
            _ = try builder.addFace(vertexIDs: face.map { vertices[$0] })
        }
        let asset = try AuthoredMeshAsset(source: builder.build(), provenance: .created)
        var document = DesignDocument.empty()
        document.authoredMeshAssets[asset.id] = asset
        let id: GeometryRepresentationID = "section.mesh.representation"
        let node = try document.productMetadata.appendSceneNodeToFirstRoot(
            name: "Mesh box", reference: .authoredMesh(asset.id), object: ObjectDescriptor(
                category: .body, geometryRole: .mesh,
                geometryRepresentations: GeometryRepresentationSet(
                    representations: [id: GeometryRepresentation(id: id, source: .authoredMesh(asset.id))],
                    selection: GeometryRepresentationSelection(modeling: id, presentation: id)
                )
            )
        )
        return (document, node)
    }

    private func section(_ document: DesignDocument, limit: Int = 10000, payload: Bool = true) throws -> SectionAnalysisResult {
        try SectionAnalysisService().analyze(document: document,
            query: SectionAnalysisQuery(source: .sketchPlane(.plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.5), normal: .unitZ))),
                includesIntersectionSegments: payload, maximumIntersectionSegments: limit),
            activeConstructionPlaneID: nil, displayUnit: .meter)
    }

    @Test func meshOnlySceneHasAClosedSectionAndStableIdentity() throws {
        let (document, node) = try meshDocument()
        let result = try section(document)
        #expect(result.bodyCount == 1 && result.triangleCount == 12)
        #expect(result.bodies[0].bodyID == "mesh:section.mesh")
        #expect(result.bodies[0].sceneNodeID == node)
        #expect(result.bodies[0].sourceFeatureID == nil)
        #expect(result.closedIntersectionContourCount == 1)
        let contour = try #require(result.intersectionContours.first)
        #expect(abs(abs(contour.signedAreaSquareMeters) - 1) < 1e-8)
        #expect(contour.points.allSatisfy { abs($0.z - 0.5) < 1e-8 })
        #expect(try section(document).bodies == result.bodies)
    }

    @Test func occurrencesUseWorldPlacementAndVisibility() throws {
        var (document, node) = try meshDocument()
        let definition = try document.createComponentDefinition(name: "Part", rootSceneNodeIDs: [node])
        _ = try document.createComponentInstance(name: "High copy", definitionID: definition,
            localTransform: .translation(Vector3D(x: 0, y: 0, z: 3)))
        let result = try section(document)
        #expect(result.bodyCount == 2)
        #expect(Set(result.bodies.compactMap(\.occurrenceID)).count == 2)
        #expect(result.intersectingBodyCount == 1 && result.frontBodyCount == 1)
        document.productMetadata.sceneNodes[node]?.isVisible = false
        #expect(try section(document).bodyCount == 0)
    }

    @Test func meshesAndCADParticipateInTheSameInterferenceAnalysis() throws {
        var (document, _) = try meshDocument()
        let cad = try document.createExtrudedRectangle(name: "CAD box", plane: .xy,
            width: .length(1, .meter), height: .length(1, .meter), depth: .length(1, .meter), direction: .normal)
        let cadNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == cad })
        let result = try section(document)
        #expect(result.bodyCount == 2 && result.closedIntersectionContourCount == 2)
        #expect(result.interferences.count == 1)
        document.productMetadata.sceneNodes[cadNode.id]?.isVisible = false
        #expect(try section(document).bodyCount == 1)
    }

    @Test func retainedMeshIsNotCountedWhenCADIsTheSelectedPresentation() throws {
        var (document, meshNode) = try meshDocument()
        let cad = try document.createExtrudedRectangle(name: "CAD", plane: .xy,
            width: .length(1, .meter), height: .length(1, .meter), depth: .length(1, .meter), direction: .normal)
        let cadNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == cad })
        let meshSource = try #require(document.productMetadata.sceneNodes[meshNode]?.reference?.geometrySourceID)
        document.productMetadata.sceneNodes[meshNode]?.isVisible = false
        let rep: GeometryRepresentationID = "retained.mesh"
        document.productMetadata.sceneNodes[cadNode.id]?.object?.geometryRepresentations.representations[rep] =
            GeometryRepresentation(id: rep, source: .authoredMesh(meshSource))
        #expect(try section(document).bodyCount == 1)
        document.productMetadata.sceneNodes[cadNode.id]?.object?.geometryRepresentations.selection?.presentation = rep
        let switched = try section(document)
        #expect(switched.bodyCount == 1 && switched.bodies[0].bodyID == "mesh:section.mesh")
    }

    @Test func payloadLimitDoesNotSilentlyClaimCompleteContours() throws {
        let (document, _) = try meshDocument()
        let limited = try section(document, limit: 1)
        #expect(limited.intersectionSegments.count == 1 && limited.truncatedIntersectionSegments)
        #expect(limited.intersectionSegmentCount > 1)
        let omitted = try section(document, payload: false)
        #expect(omitted.intersectionSegments.isEmpty && omitted.intersectionSegmentCount > 0)
    }
}
