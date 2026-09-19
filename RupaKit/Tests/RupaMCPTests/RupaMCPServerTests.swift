import Foundation
import MCP
import RupaAgentProtocol
import RupaCoreTypes
import Testing

@testable import RupaMCP

@Suite("Rupa MCP Server", .timeLimit(.minutes(1)))
struct RupaMCPServerTests {
    @Test("Legacy clients discover the fixed catalog and call status")
    func legacyCatalogAndStatus() async throws {
        let access = FakeRupaMCPAccess()
        let pair = await InMemoryTransport.createConnectedPair()
        let server = try await RupaMCPServer(access: access).start(transport: pair.server)
        let client = Client(name: "legacy-test", version: "1")
        try await client.connect(transport: pair.client)

        let listContext = try await client.send(ListTools.request(.init()))
        let list = try await listContext.value
        let statusContext = try await client.send(
            CallTool.request(.init(name: "rupa_agent_status"))
        )
        let status = try await statusContext.value
        let rejectedPageContext = try await client.send(
            CallTool.request(
                .init(name: "rupa_list_capabilities", arguments: ["limit": 51])
            )
        )
        let rejectedPage = try await rejectedPageContext.value

        #expect(list.tools.map(\.name) == expectedToolNames)
        let viewportTool = try #require(list.tools.first { $0.name == "rupa_execute_viewport" })
        let branches = try #require(
            viewportTool.inputSchema.objectValue?["properties"]?.objectValue?["operation"]?
                .objectValue?["oneOf"]?.arrayValue
        )
        let requiredFields: [String: Set<String>] = [
            "fitVisible": ["kind"], "fitSelected": ["kind"], "resetCamera": ["kind"],
            "orbit": ["kind", "yawDeltaDegrees", "elevationDeltaDegrees"],
            "pan": ["kind", "deltaXPoints", "deltaYPoints"], "zoom": ["kind", "factor"],
            "setOrientation": ["kind", "orientation"], "setDisplayMode": ["kind", "displayMode"],
            "setProjection": ["kind", "projection"],
        ]
        #expect(branches.count == requiredFields.count)
        for branch in branches {
            let object = try #require(branch.objectValue)
            let properties = try #require(object["properties"]?.objectValue)
            let kind = try #require(properties["kind"]?.objectValue?["const"]?.stringValue)
            #expect(Set(properties.keys) == requiredFields[kind])
            #expect(Set(object["required"]?.arrayValue?.compactMap(\.stringValue) ?? []) == requiredFields[kind])
            #expect(object["additionalProperties"]?.boolValue == false)
            if kind == "setProjection" {
                #expect(properties["projection"]?.objectValue?["enum"]?.arrayValue == ["parallel", "perspective"])
            }
        }
        #expect(status.isError == false)
        #expect(status.structuredContent?.objectValue?["running"]?.boolValue == true)
        #expect(status.structuredContent?.objectValue?["sessionCount"]?.intValue == 1)
        #expect(rejectedPage.isError == true)

        await client.disconnect()
        await server.stop()
    }

    @Test("Modern clients use the same catalog and receive structured failures")
    func modernCatalogAndFailure() async throws {
        let access = FakeRupaMCPAccess()
        let pair = await InMemoryTransport.createConnectedPair()
        let server = try await RupaMCPServer(access: access).start(transport: pair.server)
        let client = Client(name: "modern-test", version: "1")
        let connection = try await client.connect(
            transport: pair.client,
            preference: .modernOnly,
            delivery: .byteStream
        )

        let list = try await client.sendModern(ListTools.request(.init()))
        let viewportID = fixtureViewportID
        let viewport = try await client.sendModern(
            CallTool.request(
                .init(
                    name: "rupa_get_viewport_state",
                    arguments: [
                        "sessionID": .string(UUID().uuidString),
                        "viewportID": .string(viewportID.uuidString),
                    ]
                )
            )
        )
        let failure = try await client.sendModern(
            CallTool.request(
                .init(
                    name: "rupa_save",
                    arguments: [
                        "projectPath": .string("/tmp/project.rupa"),
                        "sessionID": .string(UUID().uuidString),
                    ]
                )
            )
        )

        #expect(connection.era == .modern)
        #expect(list.value.tools.map(\.name) == expectedToolNames)
        #expect(viewport.value.isError == false)
        #expect(await access.viewportStateCount == 1)
        #expect(await access.saveCount == 0)
        #expect(failure.value.isError == true)
        #expect(
            failure.value.structuredContent?.objectValue?["error"]?
                .objectValue?["code"]?.stringValue == "invalidArguments"
        )
        #expect(await access.saveCount == 0)

        await client.disconnect()
        await server.stop()
    }

    @Test("Viewport tools forward one explicit operation without saving", arguments: [
        AgentViewportOperation.zoom(factor: 1.25),
        .setProjection(.parallel), .setProjection(.perspective),
    ])
    func viewportToolsForwardOnceWithoutSave(operation: AgentViewportOperation) async throws {
        let access = FakeRupaMCPAccess()
        let pair = await InMemoryTransport.createConnectedPair()
        let server = try await RupaMCPServer(access: access).start(transport: pair.server)
        let client = Client(name: "viewport-test", version: "1")
        try await client.connect(transport: pair.client)
        let sessionID = UUID()
        let viewportID = fixtureViewportID

        let listContext = try await client.send(
            CallTool.request(
                .init(
                    name: "rupa_list_viewports",
                    arguments: ["sessionID": .string(sessionID.uuidString)]
                )
            )
        )
        let list = try await listContext.value
        let executeContext = try await client.send(
            CallTool.request(
                .init(
                    name: "rupa_execute_viewport",
                    arguments: [
                        "sessionID": .string(sessionID.uuidString),
                        "viewportID": .string(viewportID.uuidString),
                        "expectedViewportRevision": 7,
                        "operation": try Value(operation),
                    ]
                )
            )
        )
        let execute = try await executeContext.value

        #expect(list.isError == false)
        #expect(execute.isError == false)
        #expect(await access.viewportListCount == 1)
        #expect(await access.viewportExecutionCount == 1)
        #expect(await access.lastViewportID == viewportID)
        #expect(await access.lastViewportOperation == operation)
        #expect(await access.saveCount == 0)

        await client.disconnect()
        await server.stop()
    }

    @Test("Viewport tools preserve stale failures and reject malformed numbers")
    func viewportFailureBoundaries() async throws {
        let access = FakeRupaMCPAccess()
        await access.rejectNextViewportExecution()
        let pair = await InMemoryTransport.createConnectedPair()
        let server = try await RupaMCPServer(access: access).start(transport: pair.server)
        let client = Client(name: "viewport-failure-test", version: "1")
        try await client.connect(transport: pair.client)
        let sessionID = UUID()
        let viewportID = fixtureViewportID

        let staleContext = try await client.send(
            CallTool.request(
                .init(
                    name: "rupa_execute_viewport",
                    arguments: [
                        "sessionID": .string(sessionID.uuidString),
                        "viewportID": .string(viewportID.uuidString),
                        "expectedViewportRevision": 6,
                        "operation": .object(["kind": .string("resetCamera")]),
                    ]
                )
            )
        )
        let stale = try await staleContext.value
        #expect(stale.isError == true)
        #expect(
            stale.structuredContent?.objectValue?["error"]?
                .objectValue?["message"]?.stringValue == "Viewport revision is stale."
        )
        #expect(await access.viewportExecutionCount == 1)
        #expect(await access.saveCount == 0)

        let malformedContext = try await client.send(
            CallTool.request(
                .init(
                    name: "rupa_execute_viewport",
                    arguments: [
                        "sessionID": .string(sessionID.uuidString),
                        "viewportID": .string(viewportID.uuidString),
                        "operation": .object([
                            "kind": .string("zoom"),
                            "factor": .string("nan"),
                        ]),
                    ]
                )
            )
        )
        let malformed = try await malformedContext.value
        #expect(malformed.isError == true)
        #expect(await access.viewportExecutionCount == 1)

        await client.disconnect()
        await server.stop()
    }

    @Test("Mutation forwards once and save remains explicit")
    func mutationAndExplicitSave() async throws {
        let access = FakeRupaMCPAccess()
        let pair = await InMemoryTransport.createConnectedPair()
        let server = try await RupaMCPServer(access: access).start(transport: pair.server)
        let client = Client(name: "mutation-test", version: "1")
        try await client.connect(transport: pair.client)
        let sessionID = UUID()
        let request = AgentSemanticDirectRequest(
            schemaVersion: .init(major: 1, minor: 0, patch: 0),
            operationID: "architecture.createBox",
            operationVersion: .init(major: 1, minor: 0, patch: 0),
            arguments: [],
            requestedOutputs: []
        )

        let invocationContext = try await client.send(
            CallTool.request(
                .init(
                    name: "rupa_invoke_capability",
                    arguments: [
                        "sessionID": .string(sessionID.uuidString),
                        "request": try Value(request),
                        "dryRun": true,
                    ]
                )
            )
        )
        let invocation = try await invocationContext.value

        #expect(invocation.isError == true)
        #expect(await access.invocationCount == 1)
        #expect(await access.saveCount == 0)
        #expect(await access.lastTarget == .session(sessionID))
        #expect(await access.lastRequest == request)
        #expect(await access.lastDryRun == true)

        let saveContext = try await client.send(
            CallTool.request(
                .init(
                    name: "rupa_save",
                    arguments: ["sessionID": .string(sessionID.uuidString)]
                )
            )
        )
        let save = try await saveContext.value

        #expect(save.isError == false)
        #expect(await access.saveCount == 1)

        await client.disconnect()
        await server.stop()
    }
}

private let expectedToolNames = [
    "rupa_agent_status",
    "rupa_list_sessions",
    "rupa_list_capabilities",
    "rupa_list_viewports",
    "rupa_get_viewport_state",
    "rupa_execute_viewport",
    "rupa_invoke_capability",
    "rupa_execute_program",
    "rupa_save",
]

private let fixtureViewportID = UUID(uuidString: "D4E8A1A0-4AB1-4A92-8A93-2E1C5A1C3A7A")!

private func fixtureViewportState() -> AgentViewportState {
    AgentViewportState(
        viewportID: fixtureViewportID,
        revision: 7,
        viewportWidthPoints: 640,
        viewportHeightPoints: 480,
        canFitVisible: true,
        canFitSelected: false,
        orientation: .isometric,
        yawDegrees: 45,
        elevationDegrees: 35.2643897,
        panXPoints: 0,
        panYPoints: 0,
        zoomFactor: 1,
        xDirection: AgentViewportDirection2D(dx: 1, dy: 0),
        yDirection: AgentViewportDirection2D(dx: 0, dy: 1),
        zDirection: AgentViewportDirection2D(dx: -1, dy: -1),
        displayMode: .solid
    )
}

private actor FakeRupaMCPAccess: RupaMCPAccess {
    private(set) var invocationCount = 0
    private(set) var saveCount = 0
    private(set) var viewportListCount = 0
    private(set) var viewportStateCount = 0
    private(set) var viewportExecutionCount = 0
    private(set) var lastViewportID: UUID?
    private(set) var lastViewportOperation: AgentViewportOperation?
    private var shouldRejectNextViewportExecution = false
    private(set) var lastTarget: RupaMCPProjectTarget?
    private(set) var lastRequest: AgentSemanticDirectRequest?
    private(set) var lastDryRun: Bool?

    func status() -> AgentStatus {
        AgentStatus(running: true, sessionCount: 1)
    }

    func sessions() -> [WorkspaceSessionSummary] {
        []
    }

    func capabilities() -> [AgentCapabilityDescriptor] {
        []
    }

    func listViewports(target: RupaMCPProjectTarget) -> [AgentViewportState] {
        viewportListCount += 1
        return [fixtureViewportState()]
    }

    func viewportState(
        target: RupaMCPProjectTarget,
        viewportID: UUID
    ) -> AgentViewportState {
        viewportStateCount += 1
        lastViewportID = viewportID
        return fixtureViewportState()
    }

    func executeViewport(
        target: RupaMCPProjectTarget,
        viewportID: UUID,
        expectedViewportRevision: UInt64?,
        operation: AgentViewportOperation
    ) throws -> AgentViewportState {
        viewportExecutionCount += 1
        lastViewportID = viewportID
        lastViewportOperation = operation
        if shouldRejectNextViewportExecution {
            shouldRejectNextViewportExecution = false
            // The application maps an expected-revision mismatch to this typed MCP failure.
            throw RupaMCPError.invalidArguments("Viewport revision is stale.")
        }
        return fixtureViewportState()
    }

    func rejectNextViewportExecution() {
        shouldRejectNextViewportExecution = true
    }

    func invokeCapability(
        target: RupaMCPProjectTarget,
        request: AgentSemanticDirectRequest,
        dryRun: Bool
    ) -> AgentSemanticExecutionResult {
        invocationCount += 1
        lastTarget = target
        lastRequest = request
        lastDryRun = dryRun
        return .prepublicationFailure(
            AgentSemanticPrepublicationFailure(
                stage: .executionRejected,
                code: "fixtureRejected"
            )
        )
    }

    func executeProgram(
        target: RupaMCPProjectTarget,
        program: AgentSemanticProgramRequest,
        dryRun: Bool
    ) -> AgentSemanticExecutionResult {
        .prepublicationFailure(
            AgentSemanticPrepublicationFailure(
                stage: .executionRejected,
                code: "fixtureRejected"
            )
        )
    }

    func save(
        target: RupaMCPProjectTarget,
        expectedGeneration: DocumentGeneration?
    ) -> SaveResult {
        saveCount += 1
        return SaveResult(
            message: "Saved.",
            path: "/tmp/project.rupa",
            generation: expectedGeneration ?? DocumentGeneration(1),
            dirty: false,
            diagnostics: []
        )
    }
}
