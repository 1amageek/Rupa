import Foundation
import RupaAgentProtocol
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import Testing

@Test(.timeLimit(.minutes(1)))
func projectViewportSnapshotRoundTripsWithoutGeometryBuffers() throws {
    let sessionID = try #require(
        UUID(uuidString: "00000000-0000-0000-0000-000000000101")
    )
    let request = AgentRequest.viewportSnapshot(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(7)
    )
    let codec = AgentMessageCodec()
    let requestData = try codec.encode(request, id: "viewport-read")

    #expect(try codec.decodeRequest(from: requestData) == request)
    #expect(request.methodName == "project.viewportSnapshot")
    #expect(request.projectSessionID == sessionID)

    let projectID: ProjectID = "project.viewport.codec"
    let bounds = try GeometryBounds3D(
        minimum: GeometryPoint3D(x: -1, y: -2, z: -3),
        maximum: GeometryPoint3D(x: 4, y: 5, z: 6)
    )
    let item = AgentProjectViewportItem(
        occurrenceID: "occurrence.viewport.codec",
        sceneNodeID: SceneNodeID(),
        definitionID: "definition.viewport.codec",
        displayName: "Visible Body",
        representationID: "representation.viewport.codec",
        sourceReference: .cad(
            sourceID: "cad.viewport.codec",
            outputID: "body.viewport.codec"
        ),
        worldTransform: .identity,
        worldBounds: bounds,
        vertexCount: 8,
        faceCount: 6,
        cornerCount: 24,
        triangleCount: 12
    )
    let snapshot = AgentProjectViewportSnapshot(
        coordinates: AgentProjectViewCoordinates(
            sessionID: sessionID,
            projectID: projectID,
            documentGeneration: DocumentGeneration(7),
            transactionRevision: DocumentTransactionRevision(8),
            publicationSequence: 9,
            workspaceRevision: WorkspaceRevision(10),
            isDirty: true,
            canUndo: true,
            canRedo: false,
            diagnostics: []
        ),
        evaluationSnapshotID: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision(8)
        ),
        items: [item],
        worldBounds: bounds,
        triangleCount: 12,
        copyTelemetry: GeometryCopyTelemetry()
    )
    let response = AgentResponse.viewportSnapshot(snapshot)
    let responseData = try codec.encode(response, id: "viewport-read")
    let decoded = try codec.decodeResponse(from: responseData, expectedID: "viewport-read")

    #expect(decoded == response)
    let json = try #require(String(data: responseData, encoding: .utf8))
    #expect(json.contains("project.viewportSnapshot"))
    #expect(!json.contains("vertexIDs"))
    #expect(!json.contains("vertexPositions"))
    #expect(!json.contains("faceCornerRanges"))
    #expect(!json.contains("cornerVertexIDs"))
}
