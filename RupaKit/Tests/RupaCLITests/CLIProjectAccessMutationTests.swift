import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaProjectAccess
import Testing
@testable import RupaCLIKit

@Test(.timeLimit(.minutes(1)))
func implicitUnitAndFileOutputShareOneClosedSessionAndSaveOnce() async throws {
    let inputURL = URL(fileURLWithPath: "/tmp/source.rupa")
    let outputURL = URL(fileURLWithPath: "/tmp/result.rupa")
    let generation = DocumentGeneration(3)
    let savedGeneration = DocumentGeneration(4)
    let session = StubProjectAccessSession(
        steps: [
            .response(.command(stubAutomationResult(
                message: "Described.",
                effect: .readOnly,
                generation: generation,
                sourceDirty: false,
                didMutate: false,
                workspaceScale: stubWorkspaceScale(displayUnit: .millimeter)
            ))),
            .response(.command(stubAutomationResult(
                message: "Renamed.",
                generation: savedGeneration
            ))),
        ]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await MainActor.run { StubProjectAccessObserver() }
    let options = try CLIWriteDocumentOptions.parse([
        inputURL.path,
        "--mode", "file",
        "--expected-generation", String(generation.value),
        "--output", outputURL.path,
    ])

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await CLIProjectAccessRunner.withCommandScope {
            let unit = try await CLILengthUnitResolver.resolve(
                unitName: nil,
                document: options,
                sessionID: nil
            )
            #expect(unit == .millimeter)

            let response = try await CLIService().applyAutomationCommand(
                target: try options.target(sessionID: nil),
                command: .renameDocument(name: "Result"),
                mode: options.mode,
                expectedGeneration: options.generation(),
                dryRun: false,
                writePolicy: try options.writePolicy(sessionID: nil)
            )
            #expect(response.saved)
            #expect(!response.dirty)
            #expect(response.generation == savedGeneration.value)
        }
    }

    #expect(await opener.recordedTargets() == [
        .closedProject(input: inputURL, output: outputURL),
    ])
    #expect(await opener.recordedDeadlines().count == 1)
    #expect(await session.recordedSaveGenerations() == [savedGeneration])
    #expect(await session.recordedFinishCount() == 1)

    let requests = await session.recordedRequests()
    #expect(requests.count == 2)
    guard case .execute(_, .describeDocument, generation, _) = requests[0] else {
        Issue.record("Implicit unit resolution must describe the document first.")
        return
    }
    #expect(generation == DocumentGeneration(3))
    guard case .execute(_, .renameDocument(name: "Result"), generation, _) = requests[1] else {
        Issue.record("The mutation request was not projected through the shared access session.")
        return
    }
    #expect(generation == DocumentGeneration(3))
}

@Test(.timeLimit(.minutes(1)))
func fileDryRunAndCommandFailureNeverSave() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/no-save.rupa")
    let commandFailure = EditorError(
        code: .commandFailed,
        message: "Rejected."
    )
    let session = StubProjectAccessSession(
        steps: [
            .response(.command(stubAutomationResult(
                message: "Previewed.",
                generation: DocumentGeneration(2),
                sourceDirty: false,
                didMutate: false
            ))),
            .response(.failure(commandFailure)),
        ]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await MainActor.run { StubProjectAccessObserver() }
    let target = CLIDocumentTarget(fileURL: projectURL)

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await CLIProjectAccessRunner.withCommandScope {
            let preview = try await CLIService().applyAutomationCommand(
                target: target,
                command: .renameDocument(name: "Preview"),
                mode: .file,
                expectedGeneration: DocumentGeneration(1),
                dryRun: true
            )
            #expect(!preview.saved)

            await #expect(throws: EditorError.self) {
                _ = try await CLIService().applyAutomationCommand(
                    target: target,
                    command: .renameDocument(name: "Failure"),
                    mode: .file,
                    expectedGeneration: DocumentGeneration(2),
                    dryRun: false
                )
            }
        }
    }

    #expect(await session.recordedSaveGenerations().isEmpty)
    #expect(await opener.recordedTargets() == [
        .closedProject(input: projectURL, output: nil),
    ])
    #expect(await session.recordedFinishCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func liveMutationDoesNotSaveUntilExplicitSave() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/live-save.rupa")
    let generation = DocumentGeneration(9)
    let session = StubProjectAccessSession(
        steps: [
            .response(.command(stubAutomationResult(
                message: "Changed in memory.",
                generation: generation
            ))),
        ]
    )
    let mutationOpener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let target = CLIDocumentTarget(fileURL: projectURL)

    try await withStubProjectAccess(opener: mutationOpener, observer: observer) {
        let mutation = try await CLIService().applyAutomationCommand(
            target: target,
            command: .renameDocument(name: "Live"),
            mode: .live,
            expectedGeneration: DocumentGeneration(8)
        )
        #expect(!mutation.saved)
        #expect(mutation.dirty)
        #expect(await session.recordedSaveGenerations().isEmpty)
    }

    let saveSession = StubProjectAccessSession(steps: [])
    let saveOpener = StubProjectAccessOpener(session: saveSession)
    try await withStubProjectAccess(opener: saveOpener, observer: observer) {
        let save = try await CLIService().saveDocument(
            target: target,
            mode: .live,
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
func unknownAndCommittedMutationOutcomesAreNeverRetried() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/no-retry.rupa")
    let requestID = UUID()
    let unknownSession = StubProjectAccessSession(
        steps: [.error(.outcomeUnknown(requestID: requestID))]
    )
    let unknownOpener = StubProjectAccessOpener(session: unknownSession)
    let observer = await makeStubProjectAccessObserver()

    await #expect(throws: ProjectAccessError.outcomeUnknown(requestID: requestID)) {
        try await withStubProjectAccess(opener: unknownOpener, observer: observer) {
            _ = try await CLIService().applyAutomationCommand(
                target: CLIDocumentTarget(fileURL: projectURL),
                command: .renameDocument(name: "Unknown"),
                mode: .live,
                expectedGeneration: DocumentGeneration(1)
            )
        }
    }
    #expect(await unknownOpener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await unknownSession.recordedRequests().count == 1)
    #expect(await unknownSession.recordedSaveGenerations().isEmpty)

    let outcome = AgentCommittedMutationOutcome(
        stage: .viewProjection,
        mutation: .source,
        requestMethod: "command.apply",
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
            _ = try await CLIService().applyAutomationCommand(
                target: CLIDocumentTarget(fileURL: projectURL),
                command: .renameDocument(name: "Committed"),
                mode: .live,
                expectedGeneration: DocumentGeneration(1)
            )
        }
    }
    #expect(await committedOpener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await committedSession.recordedRequests().count == 1)
    #expect(await committedSession.recordedSaveGenerations().isEmpty)
}
