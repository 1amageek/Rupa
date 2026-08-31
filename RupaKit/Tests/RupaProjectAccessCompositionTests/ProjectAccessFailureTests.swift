import Foundation
import RupaAgentProtocol
import RupaAgentRuntime
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectAccess
import RupaProject
import RupaProjectModel
import RupaProjectPackage
import Synchronization
import Testing
@testable import RupaProjectAccessComposition
import RupaProjectAccessPlatform
@testable import RupaKit

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessInvalidBatchPreservesAuthorityAndInputBytes() async throws {
    let directory = try makeFailureAccessTemporaryDirectory()
    defer { removeFailureAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("invalid-input.rupa")
    let output = directory.appendingPathComponent("invalid-output.rupa")
    try await writeFailureAccessPackage(
        document: .empty(named: "Before Invalid Batch"),
        to: input
    )
    let inputHash = try failureAccessFileDigest(input)

    let opener = failureAccessOpener(in: directory)
    try await withFailureAccessSession(
        opener: opener,
        input: input,
        output: output
    ) { session in
        let before = try await failureAccessViewport(session)
        let response = try await session.send(
            .executeBatch(
                sessionID: session.sessionID,
                batch: AutomationBatch(
                    commands: [
                        .describeDocument,
                        .renameDocument(name: "Must Not Publish"),
                    ],
                    expectedGeneration: before.coordinates.documentGeneration,
                    expectedTransactionRevision: before.coordinates.transactionRevision,
                    expectedWorkspaceRevision: before.coordinates.workspaceRevision
                )
            )
        )

        guard case .failure(let error) = response else {
            Issue.record("An invalid batch must return a typed Agent failure.")
            return
        }
        #expect(error.code == .commandInvalid)
        let after = try await failureAccessViewport(session)
        #expect(after == before)
        #expect(try failureAccessFileDigest(input) == inputHash)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessStaleResponsePreservesExactAuthorityAndInputBytes() async throws {
    let directory = try makeFailureAccessTemporaryDirectory()
    defer { removeFailureAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("stale-input.rupa")
    let output = directory.appendingPathComponent("stale-output.rupa")
    try await writeFailureAccessPackage(
        document: .empty(named: "Before Stale Response"),
        to: input
    )
    let inputHash = try failureAccessFileDigest(input)

    let opener = failureAccessOpener(in: directory)
    try await withFailureAccessSession(
        opener: opener,
        input: input,
        output: output
    ) { session in
        let before = try await failureAccessViewport(session)
        let staleGeneration = DocumentGeneration(
            before.coordinates.documentGeneration.value + 1
        )
        let response = try await session.send(
            .execute(
                sessionID: session.sessionID,
                command: .renameDocument(name: "Must Remain Stale"),
                expectedGeneration: staleGeneration
            )
        )

        guard case .failure(let error) = response else {
            Issue.record("A stale generation must return a typed Agent failure.")
            return
        }
        #expect(error.code == .documentGenerationMismatch)
        let after = try await failureAccessViewport(session)
        #expect(after == before)
        #expect(try failureAccessFileDigest(input) == inputHash)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessSaveFailurePreservesInputAndLeavesSessionUsable() async throws {
    let directory = try makeFailureAccessTemporaryDirectory()
    defer { removeFailureAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("save-failure-input.rupa")
    let destinationDirectory = directory.appendingPathComponent(
        "published",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: destinationDirectory,
        withIntermediateDirectories: false
    )
    let output = destinationDirectory.appendingPathComponent("output.rupa")
    try await writeFailureAccessPackage(
        document: .empty(named: "Before Save Failure"),
        to: input
    )
    let inputBytes = try Data(contentsOf: input)

    let opener = failureAccessOpener(in: directory)
    try await withFailureAccessSession(
        opener: opener,
        input: input,
        output: output
    ) { session in
        let before = try await failureAccessViewport(session)
        try FileManager.default.removeItem(at: destinationDirectory)

        var observedSaveFailure = false
        do {
            _ = try await session.save(
                expectedGeneration: before.coordinates.documentGeneration
            )
        } catch let error as ProjectAccessError {
            if case .committedMutation = error {
                Issue.record("A pre-publication I/O failure must not report a committed mutation.")
            } else {
                Issue.record("The missing output parent returned an unexpected access error: \(error).")
            }
            observedSaveFailure = true
        } catch {
            observedSaveFailure = true
            #expect(error.localizedDescription.contains("Project package save failed"))
        }
        #expect(observedSaveFailure)
        #expect(try Data(contentsOf: input) == inputBytes)
        #expect(!FileManager.default.fileExists(atPath: output.path))

        let afterFailure = try await failureAccessViewport(session)
        #expect(afterFailure == before)

        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: false
        )
        let saved = try await session.save(
            expectedGeneration: before.coordinates.documentGeneration
        )
        #expect(saved.path == output.path)
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(try Data(contentsOf: input) == inputBytes)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessPostPublicationSaveFailureReturnsTerminalCommittedReceipt() async throws {
    let directory = try makeFailureAccessTemporaryDirectory()
    defer { removeFailureAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("committed-save-input.rupa")
    let output = directory.appendingPathComponent("committed-save-output.rupa")
    let document = DesignDocument.empty(named: "Committed Save")
    try await writeFailureAccessPackage(document: document, to: input)
    let inputBytes = try Data(contentsOf: input)
    let builder = FailureAccessFailingViewBuilder(
        failingBuildNumbers: [2, 3]
    )
    let handler = ProjectAgentCommandController()

    try await withConstructedFailureAccessSession(
        document: document,
        input: input,
        output: output,
        directory: directory,
        viewBuilder: builder,
        handler: handler
    ) { session in
        let before = try await failureAccessViewport(session)
        var receipt: AgentCommittedMutationOutcome?
        do {
            _ = try await session.save(
                expectedGeneration: before.coordinates.documentGeneration
            )
            Issue.record("Repeated view projection failure must return a committed receipt.")
        } catch let error as ProjectAccessError {
            guard case .committedMutation(let outcome) = error else {
                Issue.record("Post-publication failure returned the wrong access error: \(error).")
                return
            }
            receipt = outcome
        }

        let outcome = try #require(receipt)
        #expect(outcome.stage == .viewProjection)
        #expect(outcome.mutation == .save)
        #expect(outcome.requestMethod == "document.save")
        #expect(outcome.retryDisposition == .mustNotRetry)
        #expect(outcome.projectID == before.coordinates.projectID)
        #expect(outcome.documentGeneration == before.coordinates.documentGeneration)
        #expect(outcome.transactionRevision == before.coordinates.transactionRevision)
        #expect(outcome.publicationSequence == before.coordinates.publicationSequence + 1)
        #expect(outcome.workspaceRevision == before.coordinates.workspaceRevision)

        #expect(FileManager.default.fileExists(atPath: output.path))
        let committedBytes = try Data(contentsOf: output)
        #expect(!committedBytes.isEmpty)
        let committedPackage = try ProjectPackageStore().load(from: output)
        #expect(committedPackage.documentID == outcome.projectID)
        #expect(try Data(contentsOf: input) == inputBytes)

        let staleRead = try await session.send(
            .viewportSnapshot(
                sessionID: session.sessionID,
                expectedGeneration: outcome.documentGeneration
            )
        )
        guard case .failure(let staleError) = staleRead else {
            Issue.record("A failed committed-view recovery must not expose the stale view as current.")
            return
        }
        #expect(staleError.code == .projectPublicationMismatch)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessPreCancelledRequestPublishesAndSavesNothing() async throws {
    let directory = try makeFailureAccessTemporaryDirectory()
    defer { removeFailureAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("cancelled-input.rupa")
    let output = directory.appendingPathComponent("cancelled-output.rupa")
    try await writeFailureAccessPackage(
        document: .empty(named: "Before Cancellation"),
        to: input
    )
    let inputBytes = try Data(contentsOf: input)

    let opener = failureAccessOpener(in: directory)
    try await withFailureAccessSession(
        opener: opener,
        input: input,
        output: output
    ) { session in
        let before = try await failureAccessViewport(session)
        let request = Task { @MainActor in
            try await session.send(
                .execute(
                    sessionID: session.sessionID,
                    command: .renameDocument(name: "Cancelled Mutation"),
                    expectedGeneration: before.coordinates.documentGeneration
                )
            )
        }
        request.cancel()

        do {
            _ = try await request.value
            Issue.record("A pre-cancelled access request must not execute.")
        } catch is CancellationError {
            // Expected: the session sequencer checks cancellation before dispatch.
        } catch {
            Issue.record("A pre-cancelled access request returned an unexpected error: \(error).")
        }

        let after = try await failureAccessViewport(session)
        #expect(after == before)
        #expect(try Data(contentsOf: input) == inputBytes)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessQueuedAndInFlightCancellationPublishNothing() async throws {
    let directory = try makeFailureAccessTemporaryDirectory()
    defer { removeFailureAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("queued-cancellation-input.rupa")
    let output = directory.appendingPathComponent("queued-cancellation-output.rupa")
    let export = directory.appendingPathComponent("cancelled-export.stl")
    var document = DesignDocument.empty(named: "Queued Cancellation")
    _ = try document.createExtrudedRectangle(
        name: "Cancellation Body",
        plane: .xy,
        width: .length(20, .millimeter),
        height: .length(12, .millimeter),
        depth: .length(6, .millimeter),
        direction: .normal
    )
    try await writeFailureAccessPackage(document: document, to: input)
    let inputBytes = try Data(contentsOf: input)
    let exportGate = FailureAccessExportGate()
    defer { exportGate.release() }
    let exportService = DocumentExportService(
        preflightValidators: [
            FailureAccessBlockingExportValidator(gate: exportGate),
        ]
    )
    let handler = ProjectAgentCommandController(
        exportExecutor: ProjectAgentExportExecutor(exportService: exportService)
    )

    try await withConstructedFailureAccessSession(
        document: document,
        input: input,
        output: output,
        directory: directory,
        viewBuilder: ProjectViewSnapshotBuilder(),
        handler: handler
    ) { session in
        let before = try await failureAccessViewport(session)
        let inFlight = Task { @MainActor in
            try await session.send(
                .export(
                    sessionID: session.sessionID,
                    outputPath: export.path,
                    expectedGeneration: before.coordinates.documentGeneration,
                    options: ExportOptions(destinationPolicy: .overwrite),
                    dryRun: false
                )
            )
        }
        while !exportGate.didStart {
            try await Task.sleep(for: .milliseconds(1))
        }

        let queueEntry = FailureAccessQueueEntry()
        let queued = Task { @MainActor in
            queueEntry.markEntered()
            return try await session.send(
                .execute(
                    sessionID: session.sessionID,
                    command: .renameDocument(name: "Queued Mutation"),
                    expectedGeneration: before.coordinates.documentGeneration
                )
            )
        }
        while !queueEntry.didEnter {
            await Task.yield()
        }

        inFlight.cancel()
        queued.cancel()
        exportGate.release()

        do {
            let response = try await inFlight.value
            guard case .failure(let error) = response else {
                Issue.record("An in-flight cancelled export must not report success.")
                return
            }
            #expect(error.code == .commandInvalid)
            #expect(error.message.localizedCaseInsensitiveContains("cancel"))
        } catch is CancellationError {
            // Cancellation may surface at the access sequencer boundary.
        }
        do {
            _ = try await queued.value
            Issue.record("A queued cancelled mutation must not reach the handler.")
        } catch is CancellationError {
            // Expected after the predecessor drains.
        } catch {
            Issue.record("A queued cancelled mutation returned an unexpected error: \(error).")
        }

        let after = try await failureAccessViewport(session)
        #expect(after == before)
        #expect(try Data(contentsOf: input) == inputBytes)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(!FileManager.default.fileExists(atPath: export.path))
        let entries = try FileManager.default.contentsOfDirectory(
            atPath: directory.path
        )
        #expect(entries.allSatisfy { !$0.hasPrefix(".rupa-export-") })
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessExpiredOperationsPublishAndSaveNothing() async throws {
    let directory = try makeFailureAccessTemporaryDirectory()
    defer { removeFailureAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("expired-input.rupa")
    let output = directory.appendingPathComponent("expired-output.rupa")
    try await writeFailureAccessPackage(
        document: .empty(named: "Before Deadline"),
        to: input
    )
    let inputBytes = try Data(contentsOf: input)
    let opener = failureAccessOpener(in: directory)
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    try await withFailureAccessSession(
        opener: opener,
        input: input,
        output: output,
        deadline: deadline
    ) { session in
        let before = try await failureAccessViewport(session)
        try await Task.sleep(for: .milliseconds(1_100))

        do {
            _ = try await session.send(
                .execute(
                    sessionID: session.sessionID,
                    command: .renameDocument(name: "Expired Mutation"),
                    expectedGeneration: before.coordinates.documentGeneration
                )
            )
            Issue.record("An expired mutation must not execute.")
        } catch let error as ProjectAccessError {
            #expect(error == .deadlineExceeded)
        }
        do {
            _ = try await session.save(
                expectedGeneration: before.coordinates.documentGeneration
            )
            Issue.record("An expired save must not publish a package.")
        } catch let error as ProjectAccessError {
            #expect(error == .deadlineExceeded)
        }

        #expect(try Data(contentsOf: input) == inputBytes)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessExportDryRunDoesNotPublishProjectOrArtifact() async throws {
    let directory = try makeFailureAccessTemporaryDirectory()
    defer { removeFailureAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("dry-run-input.rupa")
    let output = directory.appendingPathComponent("dry-run-output.rupa")
    let export = directory.appendingPathComponent("dry-run.stl")
    var document = DesignDocument.empty(named: "Dry Run CAD")
    _ = try document.createExtrudedRectangle(
        name: "Dry Run Body",
        plane: .xy,
        width: .length(20, .millimeter),
        height: .length(12, .millimeter),
        depth: .length(6, .millimeter),
        direction: .normal
    )
    try await writeFailureAccessPackage(document: document, to: input)
    let inputBytes = try Data(contentsOf: input)

    let opener = failureAccessOpener(in: directory)
    try await withFailureAccessSession(
        opener: opener,
        input: input,
        output: output
    ) { session in
        let before = try await failureAccessViewport(session)
        let response = try await session.send(
            .export(
                sessionID: session.sessionID,
                outputPath: export.path,
                expectedGeneration: before.coordinates.documentGeneration,
                options: ExportOptions(destinationPolicy: .overwrite),
                dryRun: true
            )
        )
        guard case .export(let result) = response else {
            Issue.record("CAD-only export dry-run must return an export result.")
            return
        }
        #expect(result.dryRun)
        #expect(result.byteCount == 0)
        #expect(!FileManager.default.fileExists(atPath: export.path))

        let after = try await failureAccessViewport(session)
        #expect(after == before)
        #expect(try Data(contentsOf: input) == inputBytes)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessEvaluationFailureRollsBackAnAlreadyOpenSession() async throws {
    let directory = try makeFailureAccessTemporaryDirectory()
    defer { removeFailureAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("evaluation-rollback-input.rupa")
    let output = directory.appendingPathComponent("evaluation-rollback-output.rupa")
    try await writeFailureAccessPackage(
        document: .empty(named: "Before Evaluation Failure"),
        to: input
    )
    let inputBytes = try Data(contentsOf: input)

    let rejectedName = "Rejected During Evaluation"
    let opener = ClosedProjectAccessOpening(
        leaseStore: ProjectFileAuthorityLeaseStore(
            rootDirectory: directory.appendingPathComponent(
                "evaluation-failure-leases",
                isDirectory: true
            )
        ),
        workspaceMaker: FailureAccessNameRejectingWorkspaceMaker(
            rejectedName: rejectedName
        )
    )
    try await withFailureAccessSession(
        opener: opener,
        input: input,
        output: output
    ) { session in
        let before = try await failureAccessViewport(session)
        let response = try await session.send(
            .execute(
                sessionID: session.sessionID,
                command: .renameDocument(name: rejectedName),
                expectedGeneration: before.coordinates.documentGeneration
            )
        )

        guard case .failure(let error) = response else {
            Issue.record("Failed geometry evaluation must return a typed Agent failure.")
            return
        }
        #expect(error.code == .evaluationFailed)
        let after = try await failureAccessViewport(session)
        #expect(after == before)
        #expect(try Data(contentsOf: input) == inputBytes)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessRejectsPackageWhoseSelectedProviderCannotEvaluate() async throws {
    let directory = try makeFailureAccessTemporaryDirectory()
    defer { removeFailureAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("evaluation-failure.rupa")
    var document = DesignDocument.empty(named: "External Evaluation Failure")
    let representationID: GeometryRepresentationID = "representation.external.failure"
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "External Body",
        reference: nil,
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: GeometryRepresentationSet(
                representations: [
                    representationID: GeometryRepresentation(
                        id: representationID,
                        source: .external(
                            providerID: "unregistered-evaluation-provider",
                            sourceID: "external-source",
                            outputID: "external-output"
                        )
                    ),
                ],
                selection: GeometryRepresentationSelection(
                    modeling: representationID,
                    presentation: representationID
                )
            )
        )
    )
    _ = try document.validate()
    let productSource = try failureAccessProductSource(for: document)
    let package = try ProjectPackageDocument(
        documentID: document.projectID,
        productSource: productSource,
        cadSource: nil
    )
    _ = try ProjectPackageStore().save(package, to: input)
    let inputBytes = try Data(contentsOf: input)
    let opener = failureAccessOpener(in: directory)

    var observedEvaluationFailure = false
    do {
        _ = try await opener.open(
            .closedProject(input: input, output: nil),
            deadline: ContinuousClock.now.advanced(by: .seconds(30))
        )
        Issue.record("An unregistered selected geometry provider must fail evaluation during open.")
    } catch let error as ProjectAccessError {
        if case .fileAuthorityConflict = error {
            Issue.record("Evaluation failure must release its temporary file authority lease.")
        } else {
            Issue.record("Evaluation failure returned an unexpected access error: \(error).")
        }
    } catch {
        observedEvaluationFailure = true
        #expect(error.localizedDescription.localizedCaseInsensitiveContains("evaluat"))
        #expect(error.localizedDescription.contains("unregistered-evaluation-provider"))
    }
    #expect(observedEvaluationFailure)
    #expect(try Data(contentsOf: input) == inputBytes)
}

@MainActor
private func withConstructedFailureAccessSession<Result: Sendable>(
    document: DesignDocument,
    input: URL,
    output: URL?,
    directory: URL,
    viewBuilder: any ProjectViewSnapshotBuilding,
    handler: ProjectAgentCommandController,
    operation: @MainActor (ClosedProjectAccessSession) async throws -> Result
) async throws -> Result {
    let baseWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: document
    )
    let workspace = ProjectWorkspace(
        project: baseWorkspace.projectAuthorityOwner,
        viewBuilder: viewBuilder
    )
    _ = try await workspace.evaluate()
    let canonicalInput = input.standardizedFileURL
        .resolvingSymlinksInPath()
        .standardizedFileURL
    let canonicalOutput = output?.standardizedFileURL
        .resolvingSymlinksInPath()
        .standardizedFileURL
    let store = ProjectFileAuthorityLeaseStore(
        rootDirectory: directory.appendingPathComponent(
            "constructed-session-leases",
            isDirectory: true
        )
    )
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    let lease = try await store.acquire(
        paths: [canonicalInput] + (canonicalOutput.map { [$0] } ?? []),
        requiredPaths: [canonicalInput],
        deadline: deadline
    )
    let sessionID = UUID()
    do {
        try await handler.register(
            workspace: workspace,
            path: canonicalInput,
            id: sessionID
        )
        let session = ClosedProjectAccessSession(
            sessionID: sessionID,
            workspace: workspace,
            handler: handler,
            lease: lease,
            inputURL: canonicalInput,
            outputURL: canonicalOutput,
            deadline: deadline
        )
        do {
            let result = try await operation(session)
            await session.finish()
            return result
        } catch {
            await session.finish()
            throw error
        }
    } catch {
        await lease.release()
        throw error
    }
}

@MainActor
private func withFailureAccessSession<Result: Sendable>(
    opener: ClosedProjectAccessOpening,
    input: URL,
    output: URL?,
    deadline: ContinuousClock.Instant? = nil,
    operation: @MainActor (any ProjectAccessSession) async throws -> Result
) async throws -> Result {
    let session = try await opener.open(
        .closedProject(input: input, output: output),
        deadline: deadline ?? ContinuousClock.now.advanced(by: .seconds(30))
    )
    do {
        let result = try await operation(session)
        await session.finish()
        return result
    } catch {
        await session.finish()
        throw error
    }
}

@MainActor
private struct FailureAccessNameRejectingWorkspaceMaker: ProjectWorkspaceMaking {
    let rejectedName: String

    func makeWorkspace() throws -> ProjectWorkspace {
        let controller = try ProjectController(
            document: .empty(),
            evaluatorPreparer: FailureAccessNameRejectingEvaluatorPreparer(
                rejectedName: rejectedName
            ),
            projector: DesignDocumentProjectBridge()
        )
        return ProjectWorkspace(project: controller)
    }
}

private struct FailureAccessNameRejectingEvaluatorPreparer:
    ProjectEvaluatorPreparing {
    let rejectedName: String
    private let base = DefaultDesignDocumentProjectEvaluatorFactory()

    func makeEvaluator(
        for document: DesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        FailureAccessNameRejectingEvaluator(
            base: try base.makeEvaluator(
                for: document,
                reusing: currentEvaluation
            ),
            rejectedName: rejectedName
        )
    }
}

private struct FailureAccessNameRejectingEvaluator: ProjectEvaluating {
    let base: any ProjectEvaluating
    let rejectedName: String

    func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        guard project.name != rejectedName else {
            throw EvaluationError(
                code: .sourceUnavailable,
                message: "The access failure fixture rejected staged evaluation."
            )
        }
        return try base.evaluate(
            project: project,
            purpose: purpose,
            revision: revision
        )
    }
}

private final class FailureAccessFailingViewBuilder:
    ProjectViewSnapshotBuilding,
    Sendable {
    private let buildCount = Mutex(0)
    private let failingBuildNumbers: Set<Int>

    init(failingBuildNumbers: Set<Int>) {
        self.failingBuildNumbers = failingBuildNumbers
    }

    func build(from state: ProjectStateSnapshot) throws -> ProjectViewSnapshot {
        let currentBuild = buildCount.withLock { value in
            value += 1
            return value
        }
        guard !failingBuildNumbers.contains(currentBuild) else {
            throw FailureAccessViewError.projectionFailed
        }
        return try ProjectViewSnapshotBuilder().build(from: state)
    }
}

private enum FailureAccessViewError: Error {
    case projectionFailed
}

private final class FailureAccessExportGate: Sendable {
    private struct State: Sendable {
        var didStart = false
        var canFinish = false
    }

    private let state = Mutex(State())

    var didStart: Bool {
        state.withLock { $0.didStart }
    }

    func wait() {
        state.withLock { $0.didStart = true }
        while !state.withLock({ $0.canFinish }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func release() {
        state.withLock { $0.canFinish = true }
    }
}

private struct FailureAccessBlockingExportValidator:
    DocumentExportPreflightValidator,
    Sendable {
    let gate: FailureAccessExportGate

    func validateExport(
        context _: DocumentExportPreflightContext
    ) throws -> DocumentExportPreflightResult {
        gate.wait()
        return DocumentExportPreflightResult(
            policyEvaluation: ValidationPolicyEvaluation(
                policyID: "project-access.cancelled-export",
                decision: .allow,
                failures: []
            ),
            diagnostics: [],
            findings: [],
            blockingReasons: []
        )
    }
}

private final class FailureAccessQueueEntry: Sendable {
    private let entered = Mutex(false)

    var didEnter: Bool {
        entered.withLock { $0 }
    }

    func markEntered() {
        entered.withLock { $0 = true }
    }
}

@MainActor
private func writeFailureAccessPackage(
    document: DesignDocument,
    to url: URL
) async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(document: document)
    _ = try await workspace.evaluate()
    _ = try await workspace.save(to: url)
}

@MainActor
private func failureAccessViewport(
    _ session: any ProjectAccessSession
) async throws -> AgentProjectViewportSnapshot {
    let response = try await session.send(
        .viewportSnapshot(
            sessionID: session.sessionID,
            expectedGeneration: nil
        )
    )
    guard case .viewportSnapshot(let snapshot) = response else {
        throw EditorError(
            code: .commandFailed,
            message: "Closed access did not return a viewport snapshot."
        )
    }
    return snapshot
}

@MainActor
private func failureAccessOpener(in directory: URL) -> ClosedProjectAccessOpening {
    ClosedProjectAccessOpening(
        leaseStore: ProjectFileAuthorityLeaseStore(
            rootDirectory: directory.appendingPathComponent(
                "failure-leases",
                isDirectory: true
            )
        )
    )
}

private func failureAccessProductSource(
    for document: DesignDocument
) throws -> ProjectPackageProductSource {
    let name: Any
    if let documentName = document.cadDocument.metadata.name {
        name = documentName
    } else {
        name = NSNull()
    }
    let payload: [String: Any] = [
        "schemaVersion": 1,
        "documentID": try failureAccessJSONObject(document.id),
        "name": name,
        "units": try failureAccessJSONObject(document.cadDocument.units),
        "modelingSettings": try failureAccessJSONObject(document.modelingSettings),
        "productMetadata": try failureAccessJSONObject(document.productMetadata),
    ]
    let data = try JSONSerialization.data(
        withJSONObject: payload,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
    return try ProjectPackageProductSource(data: data)
}

private func failureAccessJSONObject<Value: Encodable>(
    _ value: Value
) throws -> Any {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(
        with: data,
        options: [.fragmentsAllowed]
    )
}

private func failureAccessFileDigest(_ url: URL) throws -> ContentFingerprint {
    try ContentFingerprint.sha256(
        algorithm: "sha256-project-access-failure-test-v1",
        data: Data(contentsOf: url)
    )
}

private func makeFailureAccessTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "RupaProjectAccessFailure-" + UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

private func removeFailureAccessTemporaryDirectory(_ directory: URL) {
    do {
        try FileManager.default.removeItem(at: directory)
    } catch {
        Issue.record("Failed to remove the access failure fixture: \(error).")
    }
}
