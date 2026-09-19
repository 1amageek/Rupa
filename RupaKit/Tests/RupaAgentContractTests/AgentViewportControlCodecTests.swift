import Foundation
import RupaAgentProtocol
import RupaCore
import Testing

@Test(.timeLimit(.minutes(1)))
func viewportControlRequestsAndResponsesRoundTripWithExactMethods() throws {
    let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    let viewportID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    let requests: [AgentRequest] = [
        .listViewports(sessionID: sessionID),
        .viewportState(sessionID: sessionID, viewportID: viewportID),
        .executeViewport(
            sessionID: sessionID,
            viewportID: viewportID,
            expectedViewportRevision: 12,
            operation: .orbit(yawDeltaDegrees: 15, elevationDeltaDegrees: -5)
        ),
    ]
    let codec = AgentMessageCodec()

    for request in requests {
        let data = try codec.encode(request, id: request.methodName)
        let envelope = try codec.decodeRequestEnvelope(from: data)
        #expect(envelope.method == request.methodName)
        #expect(envelope.params == request)
        #expect(envelope.params.projectSessionID == sessionID)
    }
    let executeData = try codec.encode(requests[2], id: "viewport.execute")
    let executeJSON = try #require(String(data: executeData, encoding: .utf8))
    #expect(executeJSON.contains("expectedViewportRevision"))
    #expect(executeJSON.contains("yawDeltaDegrees"))
    #expect(executeJSON.contains(viewportID.uuidString))

    let state = fixtureViewportState(viewportID: viewportID)
    let responses: [(AgentResponse, String)] = [
        (.viewportList([state]), "viewport.list"),
        (.viewportState(state), "viewport.state"),
        (.viewportExecution(state), "viewport.execute"),
    ]
    for (response, method) in responses {
        let data = try codec.encode(response, id: method, method: method)
        let envelope = try codec.decodeResponseEnvelope(from: data)
        #expect(envelope.method == method)
        #expect(envelope.result == response)
        if method == "viewport.state" {
            #expect(String(data: data, encoding: .utf8)?.contains("viewportWidthPoints") == true)
            #expect(String(data: data, encoding: .utf8)?.contains("xDirection") == true)
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func viewportOperationRejectsUnknownFieldsAndInvalidNumbers() throws {
    let decoder = JSONDecoder()
    let mixedAction = Data(
        #"{"kind":"fitVisible","factor":1.5}"#.utf8
    )
    #expect(throws: Error.self) {
        _ = try decoder.decode(AgentViewportOperation.self, from: mixedAction)
    }

    let unknownAction = Data(
        #"{"kind":"zoom","factor":1.5,"unexpected":true}"#.utf8
    )
    #expect(throws: Error.self) {
        _ = try decoder.decode(AgentViewportOperation.self, from: unknownAction)
    }

    #expect(throws: EditorError.self) {
        try AgentViewportOperation.zoom(factor: 0).validate()
    }
    #expect(throws: EditorError.self) {
        try AgentViewportOperation.orbit(yawDeltaDegrees: .infinity, elevationDeltaDegrees: 0).validate()
    }
    #expect(throws: EditorError.self) {
        try AgentViewportOperation.setOrientation(.custom).validate()
    }
}

@Test(.timeLimit(.minutes(1)))
func viewportStateRejectsInvalidShapeAndMismatchedResponseMethod() throws {
    let invalid = AgentViewportState(
        viewportID: UUID(),
        revision: 1,
        viewportWidthPoints: -1,
        viewportHeightPoints: 480,
        canFitVisible: true,
        canFitSelected: false,
        orientation: .custom,
        yawDegrees: 0,
        elevationDegrees: 0,
        panXPoints: 0,
        panYPoints: 0,
        zoomFactor: 1,
        xDirection: .init(dx: 1, dy: 0),
        yDirection: .init(dx: 0, dy: 1),
        zDirection: .init(dx: 0, dy: 0),
        displayMode: .solid
    )
    #expect(throws: Error.self) {
        _ = try JSONEncoder().encode(invalid)
    }

    let valid = fixtureViewportState(viewportID: UUID())
    let codec = AgentMessageCodec()
    _ = try codec.encode(
        .viewportList(Array(repeating: valid, count: AgentViewportState.maximumListCount)),
        id: "viewport-limit", method: "viewport.list"
    )
    #expect(throws: EditorError.self) {
        _ = try codec.encode(
            .viewportList(Array(repeating: valid, count: AgentViewportState.maximumListCount + 1)),
            id: "viewport-limit", method: "viewport.list"
        )
    }
    #expect(throws: EditorError.self) {
        _ = try AgentMessageCodec().encode(
            .viewportState(valid),
            id: "viewport-state",
            method: "viewport.execute"
        )
    }
}

@Test(.timeLimit(.minutes(1)))
func viewportProjectionRoundTripsAndRejectsInconsistentLens() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for projection in [AgentViewportProjection.parallel, .perspective] {
        let operation = AgentViewportOperation.setProjection(projection)
        #expect(try decoder.decode(AgentViewportOperation.self, from: encoder.encode(operation)) == operation)
        let state = fixtureViewportState(
            viewportID: UUID(), projection: projection,
            fieldOfViewRadians: projection == .perspective ? 0.9 : nil
        )
        #expect(try decoder.decode(AgentViewportState.self, from: encoder.encode(state)) == state)
    }
    for json in [
        #"{"kind":"setProjection","projection":"unknown"}"#,
        #"{"kind":"setProjection"}"#,
        #"{"kind":"setProjection","projection":"perspective","fieldOfViewRadians":0.9}"#,
    ] {
        #expect(throws: Error.self) {
            _ = try decoder.decode(AgentViewportOperation.self, from: Data(json.utf8))
        }
    }
    for fieldOfView in [nil, 0, -1, Double.pi, .infinity] as [Double?] {
        #expect(throws: Error.self) {
            _ = try encoder.encode(fixtureViewportState(
                viewportID: UUID(), projection: .perspective, fieldOfViewRadians: fieldOfView
            ))
        }
    }
    #expect(throws: Error.self) {
        _ = try encoder.encode(fixtureViewportState(
            viewportID: UUID(), projection: .parallel, fieldOfViewRadians: 0.9
        ))
    }
}

private func fixtureViewportState(
    viewportID: UUID,
    projection: AgentViewportProjection = .parallel,
    fieldOfViewRadians: Double? = nil,
    focusX: Double = 12.5
) -> AgentViewportState {
    AgentViewportState(
        viewportID: viewportID,
        revision: 12,
        projection: projection,
        fieldOfViewRadians: fieldOfViewRadians,
        viewportWidthPoints: 640,
        viewportHeightPoints: 480,
        canFitVisible: true,
        canFitSelected: true,
        orientation: .isometric,
        yawDegrees: 45,
        elevationDegrees: 35.2643897,
        panXPoints: 0,
        panYPoints: 0,
        zoomFactor: 1,
        xDirection: .init(dx: 1, dy: 0),
        yDirection: .init(dx: 0, dy: 1),
        zDirection: .init(dx: -1, dy: -1),
        displayMode: .solidWithEdges,
        focusXMeters: focusX, focusYMeters: -4, focusZMeters: 7
    )
}

@Test func viewportFocusCodecRequiresFiniteWorldCoordinates() throws {
    let state = fixtureViewportState(viewportID: UUID())
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(AgentViewportState.self, from: data)
    #expect(decoded.focusXMeters == 12.5)
    #expect(decoded.focusYMeters == -4)
    #expect(decoded.focusZMeters == 7)
    #expect(throws: Error.self) {
        _ = try JSONEncoder().encode(fixtureViewportState(viewportID: UUID(), focusX: .infinity))
    }
    for key in ["focusXMeters", "focusYMeters", "focusZMeters"] {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: key)
        let missing = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: Error.self) { _ = try JSONDecoder().decode(AgentViewportState.self, from: missing) }
    }
}
