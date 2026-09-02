import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaProjectAccess
import Testing
@testable import RupaCLIKit

@Test(.timeLimit(.minutes(1)))
func typedMutationUsesOneSessionWithoutSaving() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/source.rupa")
    let generation = DocumentGeneration(3)
    let changedGeneration = DocumentGeneration(4)
    let session = StubProjectAccessSession(
        steps: [
            .response(.parameterExpression(stubAutomationResult(
                message: "Parameter updated.",
                generation: changedGeneration
            )))
        ]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()

    try await withStubProjectAccess(opener: opener, observer: observer) {
        let response = try await CLIService().executeTypedMutationRequest(
            target: CLIDocumentTarget(fileURL: projectURL)
        ) { sessionID in
            .setParameterExpression(
                sessionID: sessionID,
                name: "Result",
                expression: "10 mm",
                kind: .length,
                defaults: nil,
                expectedGeneration: generation
            )
        }
        #expect(!response.saved)
        #expect(response.dirty)
        #expect(response.generation == changedGeneration.value)
    }

    #expect(await opener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await opener.recordedDeadlines().count == 1)
    #expect(await session.recordedSaveGenerations().isEmpty)
    #expect(await session.recordedFinishCount() == 1)

    let requests = await session.recordedRequests()
    #expect(requests.count == 1)
    guard case .setParameterExpression(
        _,
        let name,
        let expression,
        let kind,
        let defaults,
        let expectedGeneration
    ) = requests[0] else {
        Issue.record("The mutation request was not projected through the typed Agent API.")
        return
    }
    #expect(name == "Result")
    #expect(expression == "10 mm")
    #expect(kind == .length)
    #expect(defaults == nil)
    #expect(expectedGeneration == generation)
}

@Test(.timeLimit(.minutes(1)))
func typedMutationFailureNeverSavesOrFallsBack() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/no-save.rupa")
    let commandFailure = EditorError(
        code: .commandFailed,
        message: "Rejected."
    )
    let session = StubProjectAccessSession(
        steps: [
            .response(.failure(commandFailure))
        ]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let target = CLIDocumentTarget(fileURL: projectURL)

    _ = await withStubProjectAccess(opener: opener, observer: observer) {
        await #expect(throws: EditorError.self) {
            _ = try await CLIService().executeTypedMutationRequest(target: target) { sessionID in
                .setParameterExpression(
                    sessionID: sessionID,
                    name: "Failure",
                    expression: "1 mm",
                    kind: .length,
                    defaults: nil,
                    expectedGeneration: DocumentGeneration(2)
                )
            }
        }
    }

    #expect(await session.recordedSaveGenerations().isEmpty)
    #expect(await opener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await session.recordedRequests().count == 1)
    #expect(await session.recordedFinishCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func typedMutationDoesNotSaveUntilExplicitSave() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/live-save.rupa")
    let generation = DocumentGeneration(9)
    let session = StubProjectAccessSession(
        steps: [
            .response(.parameterExpression(stubAutomationResult(
                message: "Changed in memory.",
                generation: generation
            )))
        ]
    )
    let mutationOpener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let target = CLIDocumentTarget(fileURL: projectURL)

    try await withStubProjectAccess(opener: mutationOpener, observer: observer) {
        let mutation = try await CLIService().executeTypedMutationRequest(target: target) { sessionID in
            .setParameterExpression(
                sessionID: sessionID,
                name: "Live",
                expression: "2 mm",
                kind: .length,
                defaults: nil,
                expectedGeneration: DocumentGeneration(8)
            )
        }
        #expect(!mutation.saved)
        #expect(mutation.dirty)
        #expect(await session.recordedSaveGenerations().isEmpty)
    }

    let saveSession = StubProjectAccessSession(steps: [])
    let saveOpener = StubProjectAccessOpener(session: saveSession)
    try await withStubProjectAccess(opener: saveOpener, observer: observer) {
        let save = try await CLIService().saveDocument(
            target: target,
            expectedGeneration: generation
        )
        #expect(save.generation == generation.value)
    }

    #expect(await session.recordedSaveGenerations().isEmpty)
    #expect(await saveSession.recordedSaveGenerations() == [generation])
    #expect(await mutationOpener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await saveOpener.recordedTargets() == [.liveProject(projectURL)])
}

@Test(.timeLimit(.minutes(1)))
func unknownAndCommittedTypedMutationOutcomesAreNeverRetried() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/no-retry.rupa")
    let requestID = UUID()
    let unknownSession = StubProjectAccessSession(
        steps: [.error(.outcomeUnknown(requestID: requestID))]
    )
    let unknownOpener = StubProjectAccessOpener(session: unknownSession)
    let observer = await makeStubProjectAccessObserver()

    await #expect(throws: ProjectAccessError.outcomeUnknown(requestID: requestID)) {
        try await withStubProjectAccess(opener: unknownOpener, observer: observer) {
            _ = try await CLIService().executeTypedMutationRequest(
                target: CLIDocumentTarget(fileURL: projectURL)
            ) { sessionID in
                .setParameterExpression(
                    sessionID: sessionID,
                    name: "Unknown",
                    expression: "1 mm",
                    kind: .length,
                    defaults: nil,
                    expectedGeneration: DocumentGeneration(1)
                )
            }
        }
    }
    #expect(await unknownOpener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await unknownSession.recordedRequests().count == 1)
    #expect(await unknownSession.recordedSaveGenerations().isEmpty)

    let outcome = AgentCommittedMutationOutcome(
        stage: .viewProjection,
        mutation: .source,
        requestMethod: "parameter.setExpression",
        projectID: ProjectID(rawValue: "project.no-retry"),
        documentGeneration: DocumentGeneration(2),
        transactionRevision: DocumentTransactionRevision(2),
        publicationSequence: 2,
        workspaceRevision: WorkspaceRevision(2),
        message: "Committed but response projection failed."
    )
    let committedSession = StubProjectAccessSession(
        steps: [.response(.committedMutation(outcome))]
    )
    let committedOpener = StubProjectAccessOpener(session: committedSession)

    await #expect(throws: CLICommittedMutationError.self) {
        try await withStubProjectAccess(opener: committedOpener, observer: observer) {
            _ = try await CLIService().executeTypedMutationRequest(
                target: CLIDocumentTarget(fileURL: projectURL)
            ) { sessionID in
                .setParameterExpression(
                    sessionID: sessionID,
                    name: "Committed",
                    expression: "1 mm",
                    kind: .length,
                    defaults: nil,
                    expectedGeneration: DocumentGeneration(1)
                )
            }
        }
    }
    #expect(await committedOpener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await committedSession.recordedRequests().count == 1)
    #expect(await committedSession.recordedSaveGenerations().isEmpty)
}
