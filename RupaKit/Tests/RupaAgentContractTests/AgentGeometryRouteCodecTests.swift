import Foundation
import RupaAgentProtocol
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaKit
import RupaProject
import RupaProjectModel
import Testing

@Test(.timeLimit(.minutes(1)))
func agentGeometryRouteMessagesRoundTripThroughTheWireCodec() throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let coordinate = ProjectAuthorityCoordinate(
        projectID: ProjectID(rawValue: "project.agent.route"),
        transactionRevision: DocumentTransactionRevision(2),
        publicationSequence: 3
    )
    let handle = try agentGeometryRouteHandle(coordinate: coordinate)
    let plan = try agentGeometryRoutePlan()
    let requests: [AgentRequest] = [
        .meshCatalog(
            AgentMeshCatalogRequest(
                sessionID: sessionID,
                expectedGeneration: DocumentGeneration(4)
            )
        ),
        .meshPage(
            AgentMeshPageRequest(
                sessionID: sessionID,
                expectedGeneration: DocumentGeneration(4),
                handle: handle,
                domain: .vertex,
                cursor: ProjectMeshElementCursor(
                    sourceID: handle.sourceID,
                    contentIdentity: handle.contentIdentity,
                    domain: .vertex,
                    nextIndex: 1
                )
            )
        ),
        .meshNeighborhood(
            AgentMeshNeighborhoodRequest(
                sessionID: sessionID,
                expectedGeneration: DocumentGeneration(4),
                handle: handle,
                origin: .vertex(MeshVertexID(0)),
                depth: 1
            )
        ),
        .meshEdit(
            AgentMeshEditRequest(
                sessionID: sessionID,
                expectedGeneration: DocumentGeneration(4),
                handle: handle,
                plan: plan,
                mode: .preview,
                name: "agent.codec.preview"
            )
        ),
        .meshEdit(
            AgentMeshEditRequest(
                sessionID: sessionID,
                expectedGeneration: DocumentGeneration(4),
                handle: handle,
                plan: plan,
                mode: .commit,
                name: "agent.codec.commit"
            )
        ),
        .makeEditable(
            AgentMakeEditableRequest(
                sessionID: sessionID,
                expectedGeneration: DocumentGeneration(4),
                sceneNodeID: SceneNodeID(),
                authoredMeshSourceID: "mesh.agent.codec",
                authoredMeshRepresentationID: "representation.agent.codec"
            )
        ),
    ]

    for request in requests {
        let encoded = try codec.encode(request, id: request.methodName)
        let decoded = try codec.decodeRequest(from: encoded)
        #expect(decoded == request)
    }

    let coordinates = AgentProjectViewCoordinates(
        sessionID: sessionID,
        projectID: coordinate.projectID,
        documentGeneration: DocumentGeneration(4),
        transactionRevision: coordinate.transactionRevision,
        publicationSequence: coordinate.publicationSequence,
        workspaceRevision: WorkspaceRevision(5),
        isDirty: true,
        canUndo: true,
        canRedo: false,
        diagnostics: []
    )
    let catalog = AgentResponse.meshCatalog(
        AgentMeshCatalogResult(
            coordinates: coordinates,
            catalog: ProjectMeshCatalog(
                projectAuthorityCoordinate: coordinate,
                sources: []
            )
        )
    )
    let page = AgentResponse.meshPage(
        AgentMeshPageResult(
            coordinates: coordinates,
            page: AgentMeshPage(
                handle: handle,
                domain: .vertex,
                records: [],
                nextCursor: nil
            )
        )
    )
    let neighborhood = AgentResponse.meshNeighborhood(
        AgentMeshNeighborhoodResult(
            coordinates: coordinates,
            neighborhood: AgentMeshNeighborhood(handle: handle, records: [])
        )
    )
    let receipt = try MeshEditReceipt(
        stepReceipts: [],
        didChange: false,
        telemetry: GeometryCopyTelemetry()
    )
    let preview = AgentResponse.meshEditPreview(
        AgentMeshEditPreviewResult(
            coordinates: coordinates,
            sourceID: handle.sourceID,
            previousContentIdentity: handle.contentIdentity,
            proposedContentIdentity: handle.contentIdentity,
            receipt: receipt,
            didMutate: false,
            proposedTransactionRevision: coordinate.transactionRevision,
            proposedDocumentGeneration: coordinates.documentGeneration
        )
    )
    let commit = AgentResponse.meshEditCommit(
        AgentMeshEditCommitResult(
            coordinates: coordinates,
            handle: handle,
            sourceID: handle.sourceID,
            previousContentIdentity: handle.contentIdentity,
            contentIdentity: handle.contentIdentity,
            receipt: receipt,
            didMutate: false
        )
    )
    let makeEditable = AgentResponse.makeEditable(
        AgentMakeEditableResult(
            coordinates: coordinates,
            handle: handle,
            sceneNodeID: SceneNodeID(),
            sourceRepresentationID: "cad.agent.codec",
            authoredMeshSourceID: handle.sourceID,
            authoredMeshRepresentationID: "representation.agent.codec",
            evaluationSnapshotID: EvaluationSnapshotID(
                projectID: coordinate.projectID,
                purpose: .modeling,
                sourceRevision: coordinate.transactionRevision
            ),
            cadSourceIdentity: handle.contentIdentity,
            authoredMeshContentIdentity: handle.contentIdentity,
            provenance: .created,
            switchedPresentationSelection: true,
            copyTelemetry: GeometryCopyTelemetry()
        )
    )

    for response in [catalog, page, neighborhood, preview, commit, makeEditable] {
        let encoded = try codec.encode(response)
        #expect(try codec.decodeResponse(from: encoded) == response)
    }
}

@Test(.timeLimit(.minutes(1)))
func agentGeometryRouteCodecRejectsOverLimitPayloadsWithoutFallback() throws {
    let codec = AgentMessageCodec()
    let request = AgentRequest.meshCatalog(
        AgentMeshCatalogRequest(
            sessionID: UUID(),
            expectedGeneration: DocumentGeneration(1),
            limits: ProjectMeshReadLimits(
                maxSources: ProjectMeshReadLimits.hard.maxSources + 1
            )
        )
    )

    #expect(throws: EditorError.self) {
        try codec.encode(request)
    }

    let valid = try codec.encode(
        .meshCatalog(
            AgentMeshCatalogRequest(
                sessionID: UUID(),
                expectedGeneration: DocumentGeneration(1)
            )
        )
    )
    var object = try #require(
        JSONSerialization.jsonObject(with: valid) as? [String: Any]
    )
    var params = try #require(object["params"] as? [String: Any])
    var limits = try #require(params["limits"] as? [String: Any])
    limits["maxSources"] = ProjectMeshReadLimits.hard.maxSources + 1
    params["limits"] = limits
    object["params"] = params
    let malformed = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: EditorError.self) {
        try codec.decodeRequest(from: malformed)
    }
}

private func agentGeometryRouteHandle(
    coordinate: ProjectAuthorityCoordinate
) throws -> ProjectMeshSourceHandle {
    let identity = try ContentIdentity(
        domain: "rupa.agent.route",
        fingerprint: try ContentFingerprint.sha256(
            algorithm: "agent-route-test",
            data: Data("geometry-route".utf8)
        )
    )
    return ProjectMeshSourceHandle(
        projectAuthorityCoordinate: coordinate,
        sourceID: "mesh.agent.route",
        contentIdentity: identity
    )
}

private func agentGeometryRoutePlan() throws -> MeshEditPlan {
    try MeshEditPlan(
        steps: [
            MeshEditStep(
                id: MeshEditStepID("agent-route-position"),
                operation: .primitive(
                    .setVertexPositions([
                        try MeshVertexPositionEdit(
                            vertexID: MeshVertexID(0),
                            position: GeometryPoint3D(x: 0, y: 0, z: 0.5)
                        ),
                    ])
                )
            ),
        ]
    )
}
