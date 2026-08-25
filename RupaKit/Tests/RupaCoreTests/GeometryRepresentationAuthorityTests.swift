import SwiftCAD
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import Testing
@testable import RupaCore

@Test(.timeLimit(.minutes(1)))
func meshOnlyDocumentRetainsExplicitSourceAuthority() throws {
    let mesh = try triangleMesh(identity: "mesh.only")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let representationID: GeometryRepresentationID = "representation.mesh-only"
    var document = DesignDocument.empty(named: "Mesh Only")
    document.authoredMeshAssets[asset.id] = asset
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Imported Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: representationSet(
                representationID: representationID,
                source: .authoredMesh(asset.id)
            )
        )
    )

    _ = try document.validate()

    #expect(document.hasAuthoritativeCADSource == false)
    #expect(document.authoredMeshAssets[asset.id]?.source == mesh)
}

@Test(.timeLimit(.minutes(1)))
func cadAndAuthoredMeshCanRemainIndependentOnOneObject() throws {
    var document = DesignDocument.empty(named: "Hybrid")
    let bodyFeatureID = try document.createExtrudedRectangle(
        name: "Body",
        plane: .xy,
        width: .length(1, .meter),
        height: .length(1, .meter),
        depth: .length(1, .meter),
        direction: .normal
    )
    let bodyNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference == .body(bodyFeatureID)
    }?.key)
    var bodyObject = try #require(document.productMetadata.sceneNodes[bodyNodeID]?.object)
    let cadRepresentationID = try #require(bodyObject.geometryRepresentations.selection?.modeling)
    let mesh = try triangleMesh(identity: "mesh.presentation")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let meshRepresentationID: GeometryRepresentationID = "representation.presentation"
    document.authoredMeshAssets[asset.id] = asset
    bodyObject.geometryRepresentations.representations[meshRepresentationID] = GeometryRepresentation(
        id: meshRepresentationID,
        source: .authoredMesh(asset.id)
    )
    bodyObject.geometryRepresentations.selection = GeometryRepresentationSelection(
        modeling: cadRepresentationID,
        presentation: meshRepresentationID
    )
    document.productMetadata.sceneNodes[bodyNodeID]?.object = bodyObject

    _ = try document.validate()

    #expect(bodyObject.sourceFeatureID == bodyFeatureID)
    #expect(bodyObject.geometryRepresentations.source(for: .presentation) == .authoredMesh(asset.id))
    #expect(document.hasAuthoritativeCADSource)
}

@Test(.timeLimit(.minutes(1)))
func geometryRepresentationSetRejectsMissingOrDanglingSelections() throws {
    let representationID: GeometryRepresentationID = "representation.valid"
    let representation = GeometryRepresentation(
        id: representationID,
        source: .external(providerID: "provider", sourceID: "source", outputID: nil)
    )

    #expect(throws: ProjectModelError.self) {
        try GeometryRepresentationSet(
            representations: [representationID: representation]
        ).validate(requiresSelection: true)
    }
    #expect(throws: ProjectModelError.self) {
        try GeometryRepresentationSet(
            representations: [representationID: representation],
            selection: GeometryRepresentationSelection(
                modeling: "representation.missing",
                presentation: representationID
            )
        ).validate(requiresSelection: true)
    }
}

@Test(.timeLimit(.minutes(1)))
func geometryRepresentationSetRejectsDuplicateSources() throws {
    let firstID: GeometryRepresentationID = "representation.first"
    let secondID: GeometryRepresentationID = "representation.second"
    let source = GeometrySourceReference.external(
        providerID: "provider",
        sourceID: "source",
        outputID: "output"
    )
    let set = GeometryRepresentationSet(
        representations: [
            firstID: GeometryRepresentation(id: firstID, source: source),
            secondID: GeometryRepresentation(id: secondID, source: source),
        ],
        selection: GeometryRepresentationSelection(
            modeling: firstID,
            presentation: secondID
        )
    )

    #expect(throws: ProjectModelError.self) {
        try set.validate(requiresSelection: true)
    }
}

@Test(.timeLimit(.minutes(1)))
func nonGeometryObjectRejectsRepresentations() throws {
    let representationID: GeometryRepresentationID = "representation.invalid-group"
    let object = ObjectDescriptor(
        category: .group,
        geometryRepresentations: representationSet(
            representationID: representationID,
            source: .external(providerID: "provider", sourceID: "source", outputID: nil)
        )
    )

    #expect(throws: DocumentValidationError.self) {
        try object.validate()
    }
}

@Test(.timeLimit(.minutes(1)))
func documentRejectsMissingAuthoredMeshAsset() throws {
    let sourceID: GeometrySourceID = "mesh.missing"
    var document = DesignDocument.empty()
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Missing Mesh",
        reference: .authoredMesh(sourceID),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: representationSet(
                representationID: "representation.missing-mesh",
                source: .authoredMesh(sourceID)
            )
        )
    )

    #expect(throws: DocumentValidationError.self) {
        try document.validate()
    }
}

@Test(.timeLimit(.minutes(1)))
func documentRejectsCADRepresentationFromAnotherDocument() throws {
    var document = DesignDocument.empty()
    let bodyFeatureID = try document.createExtrudedRectangle(
        name: "Body",
        plane: .xy,
        width: .length(1, .meter),
        height: .length(1, .meter),
        depth: .length(1, .meter),
        direction: .normal
    )
    let bodyNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference == .body(bodyFeatureID)
    }?.key)
    var bodyObject = try #require(document.productMetadata.sceneNodes[bodyNodeID]?.object)
    let representationID = try #require(bodyObject.geometryRepresentations.selection?.modeling)
    bodyObject.geometryRepresentations.representations[representationID]?.source = .cad(
        sourceID: DocumentID().description,
        outputID: bodyFeatureID.description
    )
    document.productMetadata.sceneNodes[bodyNodeID]?.object = bodyObject

    #expect(throws: DocumentValidationError.self) {
        try document.validate()
    }
}

@Test(.timeLimit(.minutes(1)))
func cadDerivedMeshProvenanceRequiresRetainedCADRepresentation() throws {
    let mesh = try triangleMesh(identity: "mesh.derived")
    let fingerprint = try ContentFingerprint(
        algorithm: "source-revision",
        value: "revision-1"
    )
    let identity = try ContentIdentity(domain: "rupa.cad-source", fingerprint: fingerprint)
    let asset = try AuthoredMeshAsset(
        source: mesh,
        provenance: .derivedFromCAD(
            representationID: "representation.missing-cad",
            sourceIdentity: identity
        )
    )
    var document = DesignDocument.empty()
    document.authoredMeshAssets[asset.id] = asset

    #expect(throws: DocumentValidationError.self) {
        try document.validate()
    }
}

@Test(.timeLimit(.minutes(1)))
func patternCopyRemapsCADRepresentationInsteadOfStoredFeatureID() throws {
    let sourceFeatureID = FeatureID()
    let copiedFeatureID = FeatureID()
    let documentID = DocumentID()
    var object = ObjectDescriptor.body(
        featureID: sourceFeatureID,
        documentID: documentID,
        sourceSection: nil,
        typeID: nil
    )

    try object.remapCADRepresentations(using: [sourceFeatureID: copiedFeatureID])

    #expect(object.sourceFeatureID == copiedFeatureID)
    #expect(object.geometryRepresentations.source(for: .modeling) == .cad(
        sourceID: documentID.description,
        outputID: copiedFeatureID.description
    ))
}

private func representationSet(
    representationID: GeometryRepresentationID,
    source: GeometrySourceReference
) -> GeometryRepresentationSet {
    GeometryRepresentationSet(
        representations: [
            representationID: GeometryRepresentation(
                id: representationID,
                source: source
            ),
        ],
        selection: GeometryRepresentationSelection(
            modeling: representationID,
            presentation: representationID
        )
    )
}

private func triangleMesh(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}
