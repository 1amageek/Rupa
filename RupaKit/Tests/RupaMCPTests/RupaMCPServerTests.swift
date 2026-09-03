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
        #expect(failure.value.isError == true)
        #expect(
            failure.value.structuredContent?.objectValue?["error"]?
                .objectValue?["code"]?.stringValue == "invalidArguments"
        )
        #expect(await access.saveCount == 0)

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
    "rupa_invoke_capability",
    "rupa_execute_program",
    "rupa_save",
]

private actor FakeRupaMCPAccess: RupaMCPAccess {
    private(set) var invocationCount = 0
    private(set) var saveCount = 0
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
