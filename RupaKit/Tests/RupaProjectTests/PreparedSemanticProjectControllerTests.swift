import Synchronization
import SwiftCAD
import Testing
@testable import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProject
import RupaProjectModel

@Test(.timeLimit(.minutes(1)))
func preparedProgramCommitsAllStepsAsOneProjectPublicationAndUndoEntry() async throws {
    let controller = try makeController(
        document: .empty(named: "Prepared"),
        evaluator: PreparedProjectEvaluator()
    )
    let authority = await controller.currentAuthorityCoordinate()
    let result = try await controller.commit(
        ProjectSourceTransaction(
            name: "prepared.two-boxes",
            preparedProgram: try preparedBoxProgram(stepCount: 2),
            authority: authority,
            resultLimit: preparedResultLimit()
        )
    )
    let receipt = try #require(result.preparedProgramExecution)

    #expect(receipt.stepReceipts.count == 2)
    #expect(receipt.outputBindings.count == 2)
    #expect(receipt.telemetry.stepCount == 2)
    #expect(result.transactionRevision == DocumentTransactionRevision(1))
    #expect(result.state.publicationSequence == 1)
    #expect(result.state.canUndo)
    #expect(result.state.document.cadDocument.designGraph.nodes.count == 4)
    #expect(await controller.currentAuthorityCoordinate() == result.state.authorityCoordinate)

    let undone = try await controller.undo(
        expectedProjectID: result.state.document.projectID,
        expectedTransactionRevision: result.state.transactionRevision,
        expectedPublicationSequence: result.state.publicationSequence,
        operationGuard: {}
    )
    #expect(undone.document.cadDocument.designGraph.nodes.isEmpty)
    #expect(undone.transactionRevision == DocumentTransactionRevision(2))
}

@Test(.timeLimit(.minutes(1)))
func preparedProgramPreviewReturnsReceiptWithoutPublishingSourceOrAuthority() async throws {
    let controller = try makeController(
        document: .empty(named: "Preview"),
        evaluator: PreparedProjectEvaluator()
    )
    let authority = await controller.currentAuthorityCoordinate()
    let initialPackage = await controller.currentPackage()
    let preview = try await controller.previewSource(
        ProjectSourceTransaction(
            name: "prepared.preview",
            preparedProgram: try preparedBoxProgram(stepCount: 1),
            authority: authority,
            resultLimit: preparedResultLimit()
        )
    )

    #expect(preview.preparedProgramExecution?.stepReceipts.count == 1)
    #expect(preview.wouldMutate)
    #expect(await controller.currentDocument().cadDocument.designGraph.nodes.isEmpty)
    let retainedPackage = await controller.currentPackage()
    #expect(retainedPackage.documentID == initialPackage.documentID)
    #expect(retainedPackage.productSource == initialPackage.productSource)
    #expect(retainedPackage.cadSource == initialPackage.cadSource)
    #expect(retainedPackage.authoredMeshAssets == initialPackage.authoredMeshAssets)
    #expect(await controller.currentAuthorityCoordinate() == authority)
}

@Test(.timeLimit(.minutes(1)))
func preparedProgramRejectsStaleGenerationAndWorkspaceBeforeExecutorEntry() async throws {
    let executor = CountingPreparedProgramExecutor()
    let controller = try makeController(
        document: .empty(named: "Stale"),
        preparedProgramExecutor: executor
    )
    let authority = await controller.currentAuthorityCoordinate()
    let program = try preparedBoxProgram(stepCount: 1)

    let staleGeneration = ProjectAuthorityCoordinate(
        projectID: authority.projectID,
        documentGeneration: DocumentGeneration(authority.documentGeneration.value + 1),
        transactionRevision: authority.transactionRevision,
        publicationSequence: authority.publicationSequence,
        workspaceRevision: authority.workspaceRevision
    )
    var generationError: ProjectControllerError?
    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "prepared.stale-generation",
                preparedProgram: program,
                authority: staleGeneration,
                resultLimit: preparedResultLimit()
            )
        )
    } catch let caught as ProjectControllerError {
        generationError = caught
    }
    #expect(generationError?.code == .documentGenerationConflict)

    let staleWorkspace = ProjectAuthorityCoordinate(
        projectID: authority.projectID,
        documentGeneration: authority.documentGeneration,
        transactionRevision: authority.transactionRevision,
        publicationSequence: authority.publicationSequence,
        workspaceRevision: WorkspaceRevision(authority.workspaceRevision.value + 1)
    )
    var workspaceError: ProjectControllerError?
    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "prepared.stale-workspace",
                preparedProgram: program,
                authority: staleWorkspace,
                resultLimit: preparedResultLimit()
            )
        )
    } catch let caught as ProjectControllerError {
        workspaceError = caught
    }
    #expect(workspaceError?.code == .workspaceRevisionConflict)

    #expect(executor.executionCount == 0)
    #expect(await controller.currentAuthorityCoordinate() == authority)
}

@Test(.timeLimit(.minutes(1)))
func preparedProgramResultLimitFailureDiscardsTheStagedSource() async throws {
    let controller = try makeController(document: .empty(named: "Limited"))
    let authority = await controller.currentAuthorityCoordinate()
    let transaction = try ProjectSourceTransaction(
        name: "prepared.over-limit",
        preparedProgram: preparedBoxProgram(stepCount: 1),
        authority: authority,
        resultLimit: ProjectPreparedProgramResultLimit(
            maximumDiagnosticRecordCount: 0,
            maximumDiagnosticScalarCount: 0,
            maximumDiagnosticStringUTF8ByteCount: 0,
            maximumTelemetryRecordCount: 0,
            maximumTelemetryScalarCount: 0,
            maximumTelemetryStringUTF8ByteCount: 0
        )
    )

    var error: ProjectControllerError?
    do {
        _ = try await controller.commit(transaction)
    } catch let caught as ProjectControllerError {
        error = caught
    }

    #expect(error?.code == .resultLimitExceeded)
    #expect(await controller.currentDocument().cadDocument.designGraph.nodes.isEmpty)
    #expect(await controller.currentAuthorityCoordinate() == authority)
}

@Test(.timeLimit(.minutes(1)))
func preparedProgramMeasuresReceiptDiagnosticsAtExactBoundaries() async throws {
    let executor = DiagnosticPreparedProgramExecutor(message: "receipt")
    let accepted = try makeController(
        document: .empty(named: "Accepted Receipt"),
        evaluator: PreparedProjectEvaluator(),
        preparedProgramExecutor: executor
    )
    let acceptedAuthority = await accepted.currentAuthorityCoordinate()
    let result = try await accepted.commit(
        ProjectSourceTransaction(
            name: "prepared.accepted-receipt",
            preparedProgram: preparedBoxProgram(stepCount: 1),
            authority: acceptedAuthority,
            resultLimit: ProjectPreparedProgramResultLimit(
                maximumDiagnosticRecordCount: 1,
                maximumDiagnosticScalarCount: 3,
                maximumDiagnosticStringUTF8ByteCount: 7,
                maximumTelemetryRecordCount: 1,
                maximumTelemetryScalarCount: 6,
                maximumTelemetryStringUTF8ByteCount: 0
            )
        )
    )
    #expect(result.preparedProgramExecution?.diagnostics.count == 1)

    let rejected = try makeController(
        document: .empty(named: "Rejected Receipt"),
        evaluator: PreparedProjectEvaluator(),
        preparedProgramExecutor: executor
    )
    let rejectedAuthority = await rejected.currentAuthorityCoordinate()
    var error: ProjectControllerError?
    do {
        _ = try await rejected.commit(
            ProjectSourceTransaction(
                name: "prepared.rejected-receipt",
                preparedProgram: preparedBoxProgram(stepCount: 1),
                authority: rejectedAuthority,
                resultLimit: ProjectPreparedProgramResultLimit(
                    maximumDiagnosticRecordCount: 1,
                    maximumDiagnosticScalarCount: 2,
                    maximumDiagnosticStringUTF8ByteCount: 7,
                    maximumTelemetryRecordCount: 1,
                    maximumTelemetryScalarCount: 6,
                    maximumTelemetryStringUTF8ByteCount: 0
                )
            )
        )
    } catch let caught as ProjectControllerError {
        error = caught
    }
    #expect(error?.code == .resultLimitExceeded)
    #expect(await rejected.currentAuthorityCoordinate() == rejectedAuthority)
    #expect(await rejected.currentDocument().cadDocument.designGraph.nodes.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func preparedProgramEvaluationFailureAndCancellationPublishNothing() async throws {
    let failing = try makeController(
        document: .empty(named: "Rejected"),
        evaluator: RejectingPreparedProjectEvaluator()
    )
    let failingAuthority = await failing.currentAuthorityCoordinate()
    var evaluationError: ProjectControllerError?
    do {
        _ = try await failing.commit(
            ProjectSourceTransaction(
                name: "prepared.rejected",
                preparedProgram: preparedBoxProgram(stepCount: 1),
                authority: failingAuthority,
                resultLimit: preparedResultLimit()
            )
        )
    } catch let caught as ProjectControllerError {
        evaluationError = caught
    }
    #expect(evaluationError?.code == .evaluationFailed)
    #expect(await failing.currentAuthorityCoordinate() == failingAuthority)

    let gate = BlockingEvaluationGate(blockedSourceName: "Cancelled")
    defer { gate.releaseFirstEvaluation() }
    let cancelled = try makeController(
        document: .empty(named: "Cancelled"),
        evaluator: BlockingPreparedProjectEvaluator(gate: gate)
    )
    let cancelledAuthority = await cancelled.currentAuthorityCoordinate()
    let task = Task {
        try await cancelled.commit(
            ProjectSourceTransaction(
                name: "prepared.cancelled",
                preparedProgram: preparedBoxProgram(stepCount: 1),
                authority: cancelledAuthority,
                resultLimit: preparedResultLimit()
            )
        )
    }
    while !gate.didStartFirstEvaluation {
        try await Task.sleep(for: .milliseconds(1))
    }
    task.cancel()
    gate.releaseFirstEvaluation()
    await #expect(throws: CancellationError.self) {
        _ = try await task.value
    }
    #expect(await cancelled.currentAuthorityCoordinate() == cancelledAuthority)
}

@Test(.timeLimit(.minutes(1)))
func preparedProgramFinalAuthorityGuardRejectsAConcurrentPublication() async throws {
    let gate = BlockingEvaluationGate(blockedSourceName: "Before")
    defer { gate.releaseFirstEvaluation() }
    let controller = try makeController(
        document: .empty(named: "Before"),
        evaluator: BlockingPreparedProjectEvaluator(gate: gate)
    )
    let authority = await controller.currentAuthorityCoordinate()
    let first = Task {
        try await controller.commit(
            ProjectSourceTransaction(
                name: "prepared.late",
                preparedProgram: preparedBoxProgram(stepCount: 1),
                authority: authority,
                resultLimit: preparedResultLimit()
            )
        )
    }
    while !gate.didStartFirstEvaluation {
        try await Task.sleep(for: .milliseconds(1))
    }

    let winner = try await controller.commit(
        ProjectSourceTransaction(
            name: "winner",
            commands: [.renameDocument(name: "Winner")],
            expectedProjectID: authority.projectID,
            expectedTransactionRevision: authority.transactionRevision,
            expectedPublicationSequence: authority.publicationSequence
        )
    )
    gate.releaseFirstEvaluation()

    var conflict: ProjectControllerError?
    do {
        _ = try await first.value
    } catch let caught as ProjectControllerError {
        conflict = caught
    }
    #expect(conflict?.code == .revisionConflict)
    #expect(winner.state.document.cadDocument.metadata.name == "Winner")
    #expect(await controller.currentDocument().cadDocument.designGraph.nodes.isEmpty)
    #expect(await controller.currentAuthorityCoordinate() == winner.state.authorityCoordinate)
}

private func preparedBoxProgram(stepCount: Int) throws -> PreparedAutomationProgram {
    let steps = (0..<stepCount).map { index in
        PreparedAutomationStep(
            outputs: [
                PreparedAutomationOutputSlot(
                    id: PreparedAutomationSlotID("body-\(index)"),
                    selector: .sourceBody(role: .body, index: 0)
                ),
            ],
            estimatedGeneratedSourceWork: 5,
            commandBuilder: PreparedAutomationCommandBuilder(name: "box-\(index)") { _ in
                try ContextResolvedEditorCommand(validating: .createExtrudedRectangle(
                    name: "Prepared Box \(index)",
                    plane: .xy,
                    width: .length(Double(index + 1), .meter),
                    height: .length(1, .meter),
                    depth: .length(1, .meter),
                    direction: .normal
                ))
            }
        )
    }
    return try PreparedAutomationProgram(
        steps: steps,
        limits: PreparedAutomationLimitPolicy(
            maximumStepCount: stepCount,
            maximumInputSlotCount: 0,
            maximumOutputSlotCount: stepCount,
            maximumCommandCount: stepCount,
            maximumGeneratedSourceWork: UInt64(stepCount * 5)
        )
    )
}

private func preparedResultLimit() -> ProjectPreparedProgramResultLimit {
    ProjectPreparedProgramResultLimit(
        maximumDiagnosticRecordCount: 0,
        maximumDiagnosticScalarCount: 0,
        maximumDiagnosticStringUTF8ByteCount: 0,
        maximumTelemetryRecordCount: 1,
        maximumTelemetryScalarCount: 6,
        maximumTelemetryStringUTF8ByteCount: 0
    )
}

private final class CountingPreparedProgramExecutor: PreparedAutomationProgramExecuting, Sendable {
    private let count = Mutex(0)
    private let executor = DefaultPreparedAutomationProgramExecutor()

    var executionCount: Int {
        count.withLock { $0 }
    }

    func execute(
        _ program: PreparedAutomationProgram,
        in stagedSession: EditorSession
    ) throws -> PreparedAutomationExecutionReceipt {
        count.withLock { $0 += 1 }
        return try executor.execute(program, in: stagedSession)
    }
}

private struct DiagnosticPreparedProgramExecutor: PreparedAutomationProgramExecuting {
    let message: String

    func execute(
        _ program: PreparedAutomationProgram,
        in stagedSession: EditorSession
    ) throws -> PreparedAutomationExecutionReceipt {
        let receipt = try DefaultPreparedAutomationProgramExecutor().execute(
            program,
            in: stagedSession
        )
        return PreparedAutomationExecutionReceipt(
            stepReceipts: receipt.stepReceipts,
            outputBindings: receipt.outputBindings,
            diagnostics: [
                EditorDiagnostic(
                    severity: .warning,
                    code: .workspacePrecisionWarning,
                    message: message
                ),
            ],
            telemetry: receipt.telemetry
        )
    }
}

private struct RejectingPreparedProjectEvaluator: ProjectEvaluating {
    func evaluate(
        project _: ProjectSourceModel,
        purpose _: GeometryRepresentationPurpose,
        revision _: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        throw EvaluationError(
            code: .invalidResult,
            message: "Fixture rejected prepared evaluation."
        )
    }
}

private struct PreparedProjectEvaluator: ProjectEvaluating {
    func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        EvaluatedProjectSnapshot(
            id: EvaluationSnapshotID(
                projectID: project.id,
                purpose: purpose,
                sourceRevision: revision
            ),
            projectID: project.id,
            occurrences: [:],
            copyTelemetry: GeometryCopyTelemetry()
        )
    }
}

private struct BlockingPreparedProjectEvaluator: ProjectEvaluating {
    let gate: BlockingEvaluationGate

    func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        gate.waitIfNeeded(for: project.name)
        return try PreparedProjectEvaluator().evaluate(
            project: project,
            purpose: purpose,
            revision: revision
        )
    }
}
