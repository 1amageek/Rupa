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

@Test(.timeLimit(.minutes(1)), arguments: [0, 1, 2])
func topologyEditsPreserveIndependentPresentationAndProvenance(operation: Int) throws {
    var document = DesignDocument.empty(named: "Mixed topology edit")
    let featureID: FeatureID
    if operation == 0 {
        featureID = try document.createExtrudedRectangle(name: "Body", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal)
    } else {
        featureID = try document.createBSplineSurface(name: "Patch", surface: .bilinearPatch(
            bottomLeft: .origin, bottomRight: Point3D(x: 0.1, y: 0, z: 0),
            topRight: Point3D(x: 0.1, y: 0.1, z: 0), topLeft: Point3D(x: 0, y: 0.1, z: 0)))
    }
    let nodeID = try #require(document.productMetadata.sceneNodes.first { $0.value.reference == .body(featureID) }?.key)
    var object = try #require(document.productMetadata.sceneNodes[nodeID]?.object)
    let cadID = try #require(object.geometryRepresentations.selection?.modeling)
    let meshID: GeometryRepresentationID = "presentation.mesh"
    let identity = try ContentIdentity(domain: "rupa.cad-source",
        fingerprint: ContentFingerprint(algorithm: "source-revision", value: "before-edit"))
    let asset = try AuthoredMeshAsset(source: triangleMesh(identity: "mesh.retained"),
        provenance: .derivedFromCAD(representationID: cadID, sourceIdentity: identity))
    document.authoredMeshAssets[asset.id] = asset
    object.geometryRepresentations.representations[meshID] = .init(id: meshID, source: .authoredMesh(asset.id))
    object.geometryRepresentations.selection = .init(modeling: cadID, presentation: meshID)
    document.productMetadata.sceneNodes[nodeID]?.object = object
    _ = try document.validate()
    let session = EditorSession(document: document)
    if operation == 2 {
        let source = try #require(SurfaceSourceSummaryService().summarize(document: document,
            displayUnit: .millimeter).sources.first)
        let face = try #require(source.patches.first?.faceSelectionReference)
        let points = [SurfaceParameter(u: 0.2, v: 0.2), SurfaceParameter(u: 0.8, v: 0.2),
            SurfaceParameter(u: 0.8, v: 0.8), SurfaceParameter(u: 0.2, v: 0.8)]
        let loop = SurfaceTrimLoop(role: .outer, parameterCurves: (0..<4).map {
            .polyline([points[$0], points[($0 + 1) % 4]])
        })
        _ = try session.execute(.setSurfaceTrimLoops(target: face, trimLoops: [loop]))
        #expect(session.document.productMetadata.sceneNodes[nodeID]?.object?.geometryRepresentations.selection == object.geometryRepresentations.selection)
        _ = try session.execute(.setSurfaceTrimLoops(target: face, trimLoops: []))
    } else {
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let target = try #require(topology.entries.first { $0.kind == (operation == 0 ? .edge : .face) }?.selectionTarget())
        let command: EditorCommand = operation == 0
            ? .createBodyEdgeTreatment(name: "Fillet", target: target, treatment: .fillet(radius: .length(0.001, .meter)))
            : .createSheetSurfaceEdit(name: "Offset", target: target, edit: .offset(distance: .length(0.002, .meter)))
        _ = try session.execute(command)
    }
    _ = try session.document.validate()
    let edited = try #require(session.document.productMetadata.sceneNodes[nodeID]?.object)
    #expect(edited.geometryRepresentations.selection == object.geometryRepresentations.selection)
    #expect(edited.geometryRepresentations.representations.count == 2)
    #expect(edited.geometryRepresentations.representations[meshID] == object.geometryRepresentations.representations[meshID])
    #expect(session.document.authoredMeshAssets == document.authoredMeshAssets)
    _ = try session.undo()
    #expect(session.document.authoredMeshAssets == document.authoredMeshAssets)
    #expect(session.document.productMetadata.sceneNodes[nodeID]?.object?.geometryRepresentations.selection == object.geometryRepresentations.selection)
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
