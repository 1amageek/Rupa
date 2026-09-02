import Foundation
import RupaAutomation
import RupaCADIntegration
import RupaCore
import RupaCoreTypes
@testable import RupaDomainFoundation
import RupaEvaluation
@testable import RupaKit
import RupaProject
import RupaProjectModel
import SwiftCAD
import Synchronization
import Testing

@Test(.timeLimit(.minutes(1)))
func semanticDirectOneNodeAndMultiNodeProgramsUseOneWorkspaceAuthorityAction() async throws {
    let compiler = try semanticBoxCompiler()
    let invocation = semanticBoxInvocation()
    let direct = try compiler.compile(
        SemanticDirectRequest(
            schemaVersion: .current,
            invocation: invocation,
            requestedOutputs: [SemanticOutputID("body")]
        ),
        context: SemanticCompilationContext(),
        limits: semanticBoxLimits()
    )
    let oneNode = try compiler.compile(
        semanticBoxProgram(nodeCount: 1),
        context: SemanticCompilationContext(),
        limits: semanticBoxLimits()
    )
    let multiNode = try compiler.compile(
        semanticBoxProgram(nodeCount: 2),
        context: SemanticCompilationContext(),
        limits: semanticBoxLimits()
    )

    for fixture in [
        (name: "direct", compilation: direct, stepCount: 1),
        (name: "one-node", compilation: oneNode, stepCount: 1),
        (name: "multi-node", compilation: multiNode, stepCount: 2),
    ] {
        let controller = try makeSemanticProjectController(
            document: .empty(named: "Semantic \(fixture.name)")
        )
        let workspace = await ProjectWorkspace(project: controller)
        let base = await controller.currentAuthorityCoordinate()

        let result = try await workspace.executeSemanticProgram(
            ProjectSemanticProgramRequest(
                compilation: fixture.compilation,
                authority: base,
                dryRun: false,
                resultBudget: semanticResultBudget()
            )
        )
        let commit = try requireSemanticCommit(result)

        #expect(commit.authority.projectID == base.projectID)
        #expect(
            commit.authority.documentGeneration.value
                == base.documentGeneration.value + UInt64(fixture.stepCount)
        )
        #expect(commit.authority.transactionRevision.value == base.transactionRevision.value + 1)
        #expect(commit.authority.publicationSequence == base.publicationSequence + 1)
        #expect(commit.authority.workspaceRevision == base.workspaceRevision)
        #expect(commit.view.authorityCoordinate == commit.authority)
        #expect(commit.telemetry.execution.stepCount == fixture.stepCount)
        #expect(commit.telemetry.execution.commandCount == fixture.stepCount)
        #expect(commit.outputs.count == fixture.compilation.requestedOutputs.count)
        try expectRequestedSourceBodies(
            commit.outputs,
            requested: fixture.compilation.requestedOutputs,
            view: commit.view
        )
    }
}

@Test(.timeLimit(.minutes(1)))
func semanticDryRunReturnsNoPersistentOrEvaluatedIdentity() async throws {
    let compilation = try semanticBoxCompiler().compile(
        SemanticDirectRequest(
            schemaVersion: .current,
            invocation: semanticBoxInvocation(),
            requestedOutputs: [SemanticOutputID("body")]
        ),
        context: SemanticCompilationContext(),
        limits: semanticBoxLimits()
    )
    let controller = try makeSemanticProjectController(
        document: .empty(named: "Semantic Dry Run")
    )
    let workspace = await ProjectWorkspace(project: controller)
    let base = await controller.currentAuthorityCoordinate()

    let result = try await workspace.executeSemanticProgram(
        ProjectSemanticProgramRequest(
            compilation: compilation,
            authority: base,
            dryRun: true,
            resultBudget: semanticResultBudget()
        )
    )
    guard case .preview(let preview) = result else {
        Issue.record("Expected a semantic preview without persistent output bindings.")
        return
    }

    #expect(preview.authority == base)
    #expect(preview.proposedDocumentGeneration.value == base.documentGeneration.value + 1)
    #expect(preview.proposedTransactionRevision.value == base.transactionRevision.value + 1)
    #expect(await controller.currentAuthorityCoordinate() == base)
    #expect(await controller.currentDocument().cadDocument.designGraph.nodes.isEmpty)
    #expect(await workspace.view == nil)
    var evaluationError: ProjectControllerError?
    do {
        _ = try await controller.currentEvaluation()
    } catch let error as ProjectControllerError {
        evaluationError = error
    }
    #expect(evaluationError?.code == .snapshotUnavailable)
}

@Test(.timeLimit(.minutes(1)))
func semanticDryRunDoesNotContaminateTheFollowingCommitCADEvaluation() async throws {
    let compilation = try semanticBoxCompilation()
    let controller = try makeSemanticProjectController(
        document: .empty(named: "Semantic Dry Run Then Commit")
    )
    let workspace = await ProjectWorkspace(project: controller)
    let base = await controller.currentAuthorityCoordinate()

    _ = try await workspace.executeSemanticProgram(
        ProjectSemanticProgramRequest(
            compilation: compilation,
            authority: base,
            dryRun: true,
            resultBudget: semanticResultBudget()
        )
    )
    let result = try await workspace.executeSemanticProgram(
        ProjectSemanticProgramRequest(
            compilation: compilation,
            authority: base,
            dryRun: false,
            resultBudget: semanticResultBudget()
        )
    )
    let commit = try requireSemanticCommit(result)

    #expect(commit.authority.transactionRevision == DocumentTransactionRevision(1))
    #expect(commit.authority.publicationSequence == 1)
    #expect(await controller.currentDocument().cadDocument.designGraph.nodes.isEmpty == false)
}

@Test(.timeLimit(.minutes(1)))
func semanticResultBudgetRejectsCompilerChargeBeforeProjectStaging() async throws {
    let compilation = try semanticBoxCompiler().compile(
        SemanticDirectRequest(
            schemaVersion: .current,
            invocation: semanticBoxInvocation(),
            requestedOutputs: [SemanticOutputID("body")]
        ),
        context: SemanticCompilationContext(),
        limits: semanticBoxLimits()
    )
    let executionProbe = SemanticPreparedExecutionProbe()
    let controller = try makeSemanticProjectController(
        document: .empty(named: "Semantic Budget Rejection"),
        preparedProgramExecutor: ProbedSemanticPreparedProgramExecutor(probe: executionProbe)
    )
    let workspace = await ProjectWorkspace(project: controller)
    let base = await controller.currentAuthorityCoordinate()
    var caught: ProjectSemanticProgramError?

    do {
        _ = try await workspace.executeSemanticProgram(
            ProjectSemanticProgramRequest(
                compilation: compilation,
                authority: base,
                dryRun: false,
                resultBudget: semanticResultBudget(maximumRequestedOutputCount: 0)
            )
        )
    } catch let error as ProjectSemanticProgramError {
        caught = error
    }

    #expect(caught?.code == .resultBudgetExceeded)
    #expect(executionProbe.executionCount == 0)
    #expect(await controller.currentAuthorityCoordinate() == base)
    #expect(await controller.currentDocument().cadDocument.designGraph.nodes.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func semanticViewProjectionFailureReturnsExactCommittedAuthorityAndMustNotRetry() async throws {
    let compilation = try semanticBoxCompilation()
    let controller = try makeSemanticProjectController(
        document: .empty(named: "Semantic View Failure")
    )
    let workspace = await ProjectWorkspace(
        project: controller,
        viewBuilder: RejectingSemanticViewBuilder()
    )
    let base = await controller.currentAuthorityCoordinate()

    let result = try await workspace.executeSemanticProgram(
        ProjectSemanticProgramRequest(
            compilation: compilation,
            authority: base,
            dryRun: false,
            resultBudget: semanticResultBudget()
        )
    )
    let failure = try requireSemanticCommittedFailure(result)
    let committed = await controller.currentAuthorityCoordinate()

    #expect(failure.code == .viewProjectionFailed)
    #expect(failure.retryDisposition == .mustNotRetry)
    #expect(failure.authority == committed)
    #expect(committed.projectID == base.projectID)
    #expect(committed.documentGeneration.value == base.documentGeneration.value + 1)
    #expect(committed.transactionRevision.value == base.transactionRevision.value + 1)
    #expect(committed.publicationSequence == base.publicationSequence + 1)
    #expect(committed.workspaceRevision == base.workspaceRevision)
    #expect(await controller.currentDocument().cadDocument.designGraph.nodes.isEmpty == false)
    #expect(await workspace.view == nil)
}

@Test(.timeLimit(.minutes(1)))
func semanticResultProjectionFailureReturnsExactCommittedAuthorityAndMustNotRetry() async throws {
    let compilation = try semanticBoxCompilation()
    let controller = try makeSemanticProjectController(
        document: .empty(named: "Semantic Result Failure")
    )
    let workspace = await ProjectWorkspace(
        project: controller,
        semanticResultProjector: RejectingSemanticResultProjector()
    )
    let base = await controller.currentAuthorityCoordinate()

    let result = try await workspace.executeSemanticProgram(
        ProjectSemanticProgramRequest(
            compilation: compilation,
            authority: base,
            dryRun: false,
            resultBudget: semanticResultBudget()
        )
    )
    let failure = try requireSemanticCommittedFailure(result)
    let committed = await controller.currentAuthorityCoordinate()

    #expect(failure.code == .resultProjectionFailed)
    #expect(failure.retryDisposition == .mustNotRetry)
    #expect(failure.authority == committed)
    #expect(committed.projectID == base.projectID)
    #expect(committed.documentGeneration.value == base.documentGeneration.value + 1)
    #expect(committed.transactionRevision.value == base.transactionRevision.value + 1)
    #expect(committed.publicationSequence == base.publicationSequence + 1)
    #expect(committed.workspaceRevision == base.workspaceRevision)
    #expect(await controller.currentDocument().cadDocument.designGraph.nodes.isEmpty == false)
    #expect(await workspace.view?.authorityCoordinate == committed)
}

private func semanticBoxCompilation() throws -> SemanticCompilationResult {
    try semanticBoxCompiler().compile(
        SemanticDirectRequest(
            schemaVersion: .current,
            invocation: semanticBoxInvocation(),
            requestedOutputs: [SemanticOutputID("body")]
        ),
        context: SemanticCompilationContext(),
        limits: semanticBoxLimits()
    )
}

private func semanticBoxCompiler() throws -> DefaultSemanticProgramCompiler {
    let operationID: DomainCapabilityID = "fixture.semantic-box"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let estimate = SemanticOperationResultEstimate(
        diagnosticRecordCount: 0,
        diagnosticScalarCount: 0,
        diagnosticStringUTF8ByteCount: 0,
        telemetryRecordCount: 1,
        telemetryScalarCount: 6,
        telemetryStringUTF8ByteCount: 0
    )
    let descriptor = SemanticOperationDescriptor(
        operationID: operationID,
        version: version,
        outputs: [
            SemanticOperationOutputDescriptor(
                id: SemanticOutputID("body"),
                type: .sourceBody(role: .body),
                selector: .sourceBody(role: .body, index: 0)
            ),
        ],
        route: .source,
        effect: .sourceMutation,
        estimatedExpandedSourceWork: 5,
        resultEstimate: estimate
    )
    return DefaultSemanticProgramCompiler(
        registry: try SemanticOperationRegistry(registrations: [
            SemanticOperationRegistration(
                descriptor: descriptor,
                lowerer: SemanticBoxLowerer(
                    operationID: operationID,
                    operationVersion: version,
                    resultEstimate: estimate
                )
            ),
        ])
    )
}

private func semanticBoxInvocation() -> SemanticOperationInvocation {
    SemanticOperationInvocation(
        operationID: "fixture.semantic-box",
        operationVersion: SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    )
}

private func semanticBoxProgram(nodeCount: Int) -> SemanticProgram {
    let nodes = (0..<nodeCount).map { index in
        SemanticProgramNode(
            symbol: ProgramNodeSymbol("box-\(index)"),
            invocation: semanticBoxInvocation()
        )
    }
    return SemanticProgram(
        schemaVersion: .current,
        nodes: nodes,
        requestedOutputs: nodes.map { node in
            SemanticOutputReference(
                node: node.symbol,
                output: SemanticOutputID("body"),
                kind: .sourceBody(role: .body)
            )
        }
    )
}

private func semanticBoxLimits() -> SemanticProgramLimitPolicy {
    SemanticProgramLimitPolicy(
        maximumDecodedValueCount: 128,
        maximumDecodedNestingDepth: 16,
        maximumNodeCount: 8,
        maximumEdgeCount: 8,
        maximumParameterCount: 8,
        maximumRequestedOutputCount: 8,
        maximumLocalOutputReferenceCount: 8,
        maximumExpressionCount: 8,
        maximumExpressionDepth: 8,
        maximumExpressionWork: 32,
        maximumLoweredCommandCount: 8,
        maximumExpandedSourceWork: 40,
        maximumPreparedInputSlotCount: 8,
        maximumPreparedOutputSlotCount: 8,
        resultLimits: SemanticResultLimits(
            maximumRequestedOutputCount: 8,
            maximumDiagnosticRecordCount: 8,
            maximumDiagnosticScalarCount: 32,
            maximumDiagnosticStringUTF8ByteCount: 512,
            maximumTelemetryRecordCount: 16,
            maximumTelemetryScalarCount: 128,
            maximumTelemetryStringUTF8ByteCount: 512
        )
    )
}

private func semanticResultBudget(
    maximumRequestedOutputCount: UInt64 = 8
) -> ProjectSemanticResultBudget {
    ProjectSemanticResultBudget(
        maximumRequestedOutputCount: maximumRequestedOutputCount,
        maximumEvaluatedBodyLookupCount: 8,
        maximumDiagnosticRecordCount: 8,
        maximumDiagnosticScalarCount: 32,
        maximumDiagnosticStringUTF8ByteCount: 512,
        maximumTelemetryRecordCount: 16,
        maximumTelemetryScalarCount: 128,
        maximumTelemetryStringUTF8ByteCount: 512
    )
}

private func makeSemanticProjectController(
    document: DesignDocument,
    preparedProgramExecutor: any PreparedAutomationProgramExecuting =
        DefaultPreparedAutomationProgramExecutor()
) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge(),
        preparedProgramExecutor: preparedProgramExecutor
    )
}

private func requireSemanticCommit(
    _ result: ProjectSemanticProgramResult
) throws -> ProjectSemanticProgramCommit {
    guard case .committed(let commit) = result else {
        Issue.record("Expected a committed semantic program result.")
        throw SemanticWorkspaceTestError.unexpectedResult
    }
    return commit
}

private func requireSemanticCommittedFailure(
    _ result: ProjectSemanticProgramResult
) throws -> ProjectSemanticProgramCommittedFailure {
    guard case .committedFailure(let failure) = result else {
        Issue.record("Expected a post-commit semantic program failure.")
        throw SemanticWorkspaceTestError.unexpectedResult
    }
    return failure
}

private func expectRequestedSourceBodies(
    _ outputs: [ProjectSemanticOutputBinding],
    requested: [CompiledSemanticOutputRequest],
    view: ProjectViewSnapshot
) throws {
    let evaluation = try #require(view.cadInteraction)
    for binding in outputs {
        #expect(requested.contains { $0.source == binding.output })
        guard case .body(let featureID, let role, let evaluatedBodyID) = binding.value else {
            Issue.record("Expected a requested source-body binding with an evaluated BodyID.")
            continue
        }
        #expect(role == .body)
        #expect(
            view.document.document.cadDocument.designGraph.nodes[featureID]?.outputs.contains {
                $0.role == .body
            } == true
        )
        let matchingBodies = evaluation.evaluatedDocument.subshapes.entries.compactMap {
            subshapeID, reference -> BodyID? in
            guard subshapeID.featureID == featureID,
                  case .body(let bodyID) = reference else {
                return nil
            }
            return bodyID
        }
        #expect(matchingBodies == [evaluatedBodyID])
    }
}

private struct SemanticBoxLowerer: SemanticOperationLowerer {
    let operationID: DomainCapabilityID
    let operationVersion: SemanticOperationVersion
    let resultEstimate: SemanticOperationResultEstimate

    func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
        SemanticLoweredOperation(
            step: PreparedAutomationStep(
                inputs: request.preparedInputs,
                outputs: request.preparedOutputs,
                estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
                commandBuilder: PreparedAutomationCommandBuilder(name: "semantic-box") { _ in
                    try ContextResolvedEditorCommand(validating: .createExtrudedRectangle(
                        name: "Semantic Box",
                        plane: .xy,
                        width: .length(1, .meter),
                        height: .length(1, .meter),
                        depth: .length(1, .meter),
                        direction: .normal
                    ))
                }
            )
        )
    }
}

private final class SemanticPreparedExecutionProbe: Sendable {
    private let count = Mutex(0)

    var executionCount: Int {
        count.withLock { $0 }
    }

    func recordExecution() {
        count.withLock { $0 += 1 }
    }
}

private struct ProbedSemanticPreparedProgramExecutor: PreparedAutomationProgramExecuting {
    let probe: SemanticPreparedExecutionProbe

    func execute(
        _ program: PreparedAutomationProgram,
        in stagedSession: EditorSession
    ) throws -> PreparedAutomationExecutionReceipt {
        probe.recordExecution()
        return try DefaultPreparedAutomationProgramExecutor().execute(
            program,
            in: stagedSession
        )
    }
}

private struct RejectingSemanticViewBuilder: ProjectViewSnapshotBuilding {
    func build(from _: ProjectStateSnapshot) throws -> ProjectViewSnapshot {
        throw SemanticWorkspaceTestError.viewProjectionRejected
    }
}

private struct RejectingSemanticResultProjector: ProjectSemanticResultProjecting {
    func project(
        plan _: ProjectResultProjectionPlan,
        receipt _: PreparedAutomationExecutionReceipt,
        state _: ProjectStateSnapshot
    ) throws -> [ProjectSemanticOutputBinding] {
        throw SemanticWorkspaceTestError.resultProjectionRejected
    }
}

private enum SemanticWorkspaceTestError: Error {
    case unexpectedResult
    case viewProjectionRejected
    case resultProjectionRejected
}
