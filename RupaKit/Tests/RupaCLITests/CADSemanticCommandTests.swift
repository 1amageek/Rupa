import Foundation
import ArgumentParser
import RupaAgentProtocol
import RupaCore
import RupaCoreTypes
import RupaDomainFoundation
import Testing
@testable import RupaCLIKit

@Test(.timeLimit(.minutes(1)))
func cadInvokeForwardsOneRequestWithTheSessionAuthority() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/cad-invoke.rupa")
    let sessionID = UUID()
    let authority = testCADAuthority(projectID: "cad-invoke", generation: 7)
    let request = AgentSemanticDirectRequest(
        schemaVersion: AgentSemanticSchemaVersion(major: 1, minor: 0, patch: 0),
        operationID: DomainCapabilityID(rawValue: "architecture.createBox"),
        operationVersion: AgentSemanticOperationVersion(major: 2, minor: 1, patch: 0),
        arguments: [
            .init(
                name: "width",
                value: .literal(.number(0.25, unit: .meter))
            ),
        ],
        requestedOutputs: ["body"]
    )
    let expectedResult = AgentSemanticExecutionResult.prepublicationFailure(
        AgentSemanticPrepublicationFailure(
            stage: .executionRejected,
            code: DomainCapabilityErrorCode("fixture.rejected")
        )
    )
    let session = StubProjectAccessSession(
        sessionID: sessionID,
        initialAuthority: authority,
        steps: [.response(.capabilityExecution(expectedResult))]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()

    let result = try await withStubProjectAccess(opener: opener, observer: observer) {
        try await CLIService().invokeCapability(
            target: CLIDocumentTarget(fileURL: projectURL),
            request: request,
            dryRun: true
        )
    }

    #expect(result == expectedResult)
    #expect(await opener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await session.recordedSaveGenerations().isEmpty)
    #expect(await session.recordedFinishCount() == 1)
    let requests = await session.recordedRequests()
    #expect(requests.count == 1)
    guard case .invokeCapability(let outer) = requests[0] else {
        Issue.record("CAD invoke must send one semantic capability request.")
        return
    }
    #expect(outer.sessionID == sessionID)
    #expect(outer.authority == authority)
    #expect(outer.dryRun)
    #expect(outer.request == request)
}

@Test(.timeLimit(.minutes(1)))
func cadProgramForwardsOneBoundedDocumentWithoutCoordinateRead() async throws {
    let sessionID = UUID()
    let authority = testCADAuthority(projectID: "cad-program", generation: 11)
    let program = AgentSemanticProgramRequest(
        schemaVersion: AgentSemanticSchemaVersion(major: 1, minor: 0, patch: 0),
        nodes: [
            .init(
                symbol: "box",
                operationID: DomainCapabilityID(rawValue: "architecture.createBox"),
                operationVersion: AgentSemanticOperationVersion(major: 1, minor: 0, patch: 0),
                arguments: []
            ),
        ],
        requestedOutputs: []
    )
    let expectedResult = AgentSemanticExecutionResult.prepublicationFailure(
        AgentSemanticPrepublicationFailure(
            stage: .authorityRejected,
            code: DomainCapabilityErrorCode("fixture.authority")
        )
    )
    let session = StubProjectAccessSession(
        sessionID: sessionID,
        initialAuthority: authority,
        steps: [.response(.programExecution(expectedResult))]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()

    let result = try await withStubProjectAccess(opener: opener, observer: observer) {
        try await CLIService().executeProgram(
            target: CLIDocumentTarget(sessionID: sessionID),
            program: program
        )
    }

    #expect(result == expectedResult)
    #expect(await opener.recordedTargets() == [.liveSession(sessionID)])
    #expect(await session.recordedSaveGenerations().isEmpty)
    let requests = await session.recordedRequests()
    #expect(requests.count == 1)
    guard case .executeProgram(let outer) = requests[0] else {
        Issue.record("CAD program must send one structured semantic request.")
        return
    }
    #expect(outer.sessionID == sessionID)
    #expect(outer.authority == authority)
    #expect(!outer.dryRun)
    #expect(outer.program == program)
}

@Test(.timeLimit(.minutes(1)))
func cadServicesRejectMismatchedSemanticResponseDiscriminator() async throws {
    let session = StubProjectAccessSession(
        initialAuthority: testCADAuthority(projectID: "cad-mismatch", generation: 13),
        steps: [
            .response(
                .programExecution(
                    .prepublicationFailure(
                        AgentSemanticPrepublicationFailure(
                            stage: .authorityRejected,
                            code: DomainCapabilityErrorCode("fixture.mismatch")
                        )
                    )
                )
            ),
        ]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let request = AgentSemanticDirectRequest(
        schemaVersion: .init(major: 1, minor: 0, patch: 0),
        operationID: "architecture.createBox",
        operationVersion: .init(major: 1, minor: 0, patch: 0),
        arguments: [],
        requestedOutputs: []
    )

    await #expect(throws: EditorError.self) {
        try await withStubProjectAccess(opener: opener, observer: observer) {
            try await CLIService().invokeCapability(
                target: CLIDocumentTarget(sessionID: session.sessionID),
                request: request
            )
        }
    }
    #expect(await session.recordedRequests().count == 1)
    #expect(await session.recordedFinishCount() == 1)
}

@Test
func cadCommandsRequireExplicitVersionsAndSupportBothTargetForms() throws {
    let invocation = try CADInvokeCommand.parse([
        "/tmp/explicit.rupa",
        "architecture.createBox",
        "--schema-version", "1.0.0",
        "--version", "2.0.0",
        "--argument", #"{"name":"width","value":{"kind":"literal","literal":{"kind":"number","number":1.0,"unit":"meter"}}}"#,
        "--output", "body",
        "--json",
    ])
    #expect(invocation.positional == ["/tmp/explicit.rupa", "architecture.createBox"])
    #expect(invocation.schemaVersion == "1.0.0")
    #expect(invocation.operationVersion == "2.0.0")
    #expect(invocation.argumentPayloads.count == 1)
    #expect(invocation.requestedOutputs == ["body"])

    let sessionInvocation = try CADInvokeCommand.parse([
        "architecture.createBox",
        "--session-id", UUID().uuidString,
        "--schema-version", "1.0.0",
        "--version", "1.0.0",
    ])
    #expect(sessionInvocation.positional == ["architecture.createBox"])
}

@Test(.timeLimit(.minutes(1)))
func cadCommandsMapSemanticInputFailuresToUsageExit() async throws {
    let session = StubProjectAccessSession(steps: [])
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let invocation = try CADInvokeCommand.parse([
        "/tmp/project.rupa",
        "architecture.createBox",
        "--schema-version", "invalid",
        "--version", "1.0.0",
    ])
    let command = try CADProgramCommand.parse(["/tmp/project.rupa"])

    await withStubProjectAccess(opener: opener, observer: observer) {
        await #expect(throws: ExitCode(CLIExitCode.usage.rawValue)) {
            try await invocation.run()
        }
        await #expect(throws: ExitCode(CLIExitCode.usage.rawValue)) {
            try await command.run()
        }
    }
    #expect(await opener.recordedTargets().isEmpty)
}

private func testCADAuthority(
    projectID: String,
    generation: UInt64
) -> AgentProjectAuthorityCoordinate {
    AgentProjectAuthorityCoordinate(
        projectID: ProjectID(rawValue: projectID),
        documentGeneration: DocumentGeneration(generation),
        transactionRevision: DocumentTransactionRevision(generation + 1),
        publicationSequence: generation + 2,
        workspaceRevision: WorkspaceRevision(generation + 3)
    )
}
