import Foundation
import RupaAgentProtocol
import RupaAgentRuntime
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaDomainFoundation
import RupaEvaluation
import RupaKit
import RupaProject
import RupaProjectModel
import Synchronization
import Testing

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentSemanticProgramCommitsMultipleNodesInOneWorkspaceExecution() async throws {
    let executionProbe = ProjectAgentPreparedProgramExecutionProbe()
    let project = try ProjectController(
        document: .empty(named: "Semantic Multi-Node Commit"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge(),
        preparedProgramExecutor: executionProbe
    )
    let workspace = ProjectWorkspace(project: project)
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController(
        semanticProgramCompiler: try projectAgentSemanticCompiler()
    )
    let sessionID = try await controller.register(workspace: workspace)
    let view = try #require(workspace.view)
    let outputs = [
        AgentSemanticOutputReference(
            node: "first",
            output: "body",
            kind: .sourceBody(role: .body)
        ),
        AgentSemanticOutputReference(
            node: "second",
            output: "body",
            kind: .sourceBody(role: .body)
        ),
    ]
    let envelope = AgentRequestEnvelope(
        id: "semantic-multi-node-commit",
        params: .executeProgram(
            AgentSemanticProgramExecutionRequest(
                sessionID: sessionID,
                authority: projectAgentAuthority(view),
                dryRun: false,
                program: AgentSemanticProgramRequest(
                    schemaVersion: .init(major: 1, minor: 0, patch: 0),
                    nodes: [
                        projectAgentProgramBoxNode(
                            symbol: "first",
                            name: "First Box"
                        ),
                        projectAgentProgramBoxNode(
                            symbol: "second",
                            name: "Second Box",
                            originX: 0.4
                        ),
                    ],
                    requestedOutputs: outputs
                )
            )
        )
    )

    let handled = await controller.handle(envelope)

    guard case .planned(let response, let reservation) = handled,
          case .programExecution(.success(.committed(let receipt))) = response else {
        Issue.record("Expected one planned multi-node semantic commit.")
        return
    }
    #expect(executionProbe.executionCount == 1)
    #expect(receipt.outputs.map(\.output) == outputs)
    #expect(receipt.authority.documentGeneration.value == view.documentGeneration.value + 2)
    #expect(receipt.authority.transactionRevision.value == view.transactionRevision.value + 1)
    #expect(receipt.authority.publicationSequence == view.publicationSequence + 1)
    _ = try AgentMessageCodec().encode(response, consuming: reservation)

    let state = try await project.currentState()
    #expect(state.documentGeneration == receipt.authority.documentGeneration)
    #expect(state.transactionRevision == receipt.authority.transactionRevision)
    #expect(state.publicationSequence == receipt.authority.publicationSequence)
    #expect(state.document.cadDocument.designGraph.order.count == 4)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentSemanticRejectsEveryStaleAuthorityCoordinateWithoutPublication() async throws {
    let project = try ProjectController(
        document: .empty(named: "Semantic Stale Authority"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: project)
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController(
        semanticProgramCompiler: try projectAgentSemanticCompiler()
    )
    let sessionID = try await controller.register(workspace: workspace)
    let view = try #require(workspace.view)
    let authority = projectAgentAuthority(view)
    let variants: [(String, AgentProjectAuthorityCoordinate, DomainCapabilityErrorCode)] = [
        (
            "project",
            AgentProjectAuthorityCoordinate(
                projectID: ProjectID(rawValue: "other-project"),
                documentGeneration: authority.documentGeneration,
                transactionRevision: authority.transactionRevision,
                publicationSequence: authority.publicationSequence,
                workspaceRevision: authority.workspaceRevision
            ),
            "projectMismatch"
        ),
        (
            "generation",
            AgentProjectAuthorityCoordinate(
                projectID: authority.projectID,
                documentGeneration: DocumentGeneration(authority.documentGeneration.value + 1),
                transactionRevision: authority.transactionRevision,
                publicationSequence: authority.publicationSequence,
                workspaceRevision: authority.workspaceRevision
            ),
            "documentGenerationMismatch"
        ),
        (
            "transaction",
            AgentProjectAuthorityCoordinate(
                projectID: authority.projectID,
                documentGeneration: authority.documentGeneration,
                transactionRevision: DocumentTransactionRevision(
                    authority.transactionRevision.value + 1
                ),
                publicationSequence: authority.publicationSequence,
                workspaceRevision: authority.workspaceRevision
            ),
            "transactionRevisionMismatch"
        ),
        (
            "publication",
            AgentProjectAuthorityCoordinate(
                projectID: authority.projectID,
                documentGeneration: authority.documentGeneration,
                transactionRevision: authority.transactionRevision,
                publicationSequence: authority.publicationSequence + 1,
                workspaceRevision: authority.workspaceRevision
            ),
            "publicationSequenceMismatch"
        ),
        (
            "workspace",
            AgentProjectAuthorityCoordinate(
                projectID: authority.projectID,
                documentGeneration: authority.documentGeneration,
                transactionRevision: authority.transactionRevision,
                publicationSequence: authority.publicationSequence,
                workspaceRevision: WorkspaceRevision(authority.workspaceRevision.value + 1)
            ),
            "workspaceRevisionMismatch"
        ),
    ]
    let before = try await project.currentState()

    for (name, staleAuthority, expectedCode) in variants {
        let handled = await controller.handle(
            AgentRequestEnvelope(
                id: "semantic-stale-\(name)",
                params: .invokeCapability(
                    projectAgentDirectBoxRequest(
                        sessionID: sessionID,
                        authority: staleAuthority,
                        name: "Rejected Box"
                    )
                )
            )
        )
        guard case .planned(let response, let reservation) = handled,
              case .capabilityExecution(.prepublicationFailure(let failure)) = response else {
            Issue.record("Expected \(name) authority mismatch to be a planned failure.")
            continue
        }
        #expect(failure.stage == .authorityRejected)
        #expect(failure.code == expectedCode)
        #expect(failure.publicationDisposition == .notPublished)
        #expect(failure.retryDisposition == .retryPermitted)
        _ = try AgentMessageCodec().encode(response, consuming: reservation)
    }

    let after = try await project.currentState()
    #expect(after.documentGeneration == before.documentGeneration)
    #expect(after.transactionRevision == before.transactionRevision)
    #expect(after.publicationSequence == before.publicationSequence)
    #expect(after.package.documentID == before.package.documentID)
    #expect(after.package.productSource == before.package.productSource)
    #expect(after.package.cadSource == before.package.cadSource)
    #expect(after.package.authoredMeshAssets == before.package.authoredMeshAssets)
    #expect(after.evaluationSnapshot == before.evaluationSnapshot)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentSemanticUnknownAndLimitFailuresArePlannedBeforePublication() async throws {
    let project = try ProjectController(
        document: .empty(named: "Semantic Compilation Rejection"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: project)
    _ = try await workspace.evaluate()
    let view = try #require(workspace.view)
    let before = try await project.currentState()

    let unknownController = ProjectAgentCommandController(
        semanticProgramCompiler: try projectAgentSemanticCompiler()
    )
    let unknownSessionID = try await unknownController.register(workspace: workspace)
    let unknownRequest = AgentSemanticDirectExecutionRequest(
        sessionID: unknownSessionID,
        authority: projectAgentAuthority(view),
        dryRun: false,
        request: AgentSemanticDirectRequest(
            schemaVersion: .init(major: 1, minor: 0, patch: 0),
            operationID: "cad.unknown.operation",
            operationVersion: .init(major: 1, minor: 0, patch: 0),
            requestedOutputs: []
        )
    )
    let unknownHandled = await unknownController.handle(
        AgentRequestEnvelope(
            id: "semantic-unknown-operation",
            params: .invokeCapability(unknownRequest)
        )
    )
    try projectAgentRequirePlannedCompilationFailure(
        unknownHandled,
        method: .capability,
        code: "unknownOperation"
    )

    let limitedController = ProjectAgentCommandController(
        semanticProgramCompiler: try projectAgentSemanticCompiler(),
        semanticProgramLimits: projectAgentSemanticLimits(maximumNodeCount: 1)
    )
    let limitedSessionID = try await limitedController.register(workspace: workspace)
    let limitedRequest = AgentSemanticProgramExecutionRequest(
        sessionID: limitedSessionID,
        authority: projectAgentAuthority(view),
        dryRun: false,
        program: AgentSemanticProgramRequest(
            schemaVersion: .init(major: 1, minor: 0, patch: 0),
            nodes: [
                projectAgentProgramBoxNode(symbol: "first", name: "First"),
                projectAgentProgramBoxNode(symbol: "second", name: "Second", originX: 0.4),
            ]
        )
    )
    let limitedHandled = await limitedController.handle(
        AgentRequestEnvelope(
            id: "semantic-node-limit",
            params: .executeProgram(limitedRequest)
        )
    )
    try projectAgentRequirePlannedCompilationFailure(
        limitedHandled,
        method: .program,
        code: "limitExceeded"
    )

    let after = try await project.currentState()
    #expect(after.documentGeneration == before.documentGeneration)
    #expect(after.transactionRevision == before.transactionRevision)
    #expect(after.publicationSequence == before.publicationSequence)
    #expect(after.package.documentID == before.package.documentID)
    #expect(after.package.productSource == before.package.productSource)
    #expect(after.package.cadSource == before.package.cadSource)
    #expect(after.package.authoredMeshAssets == before.package.authoredMeshAssets)
    #expect(after.evaluationSnapshot == before.evaluationSnapshot)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentSemanticFailureOnlyResponsePlanDoesNotStageTheProject() async throws {
    let executionProbe = ProjectAgentPreparedProgramExecutionProbe()
    let project = try ProjectController(
        document: .empty(named: "Semantic Response Plan Rejection"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge(),
        preparedProgramExecutor: executionProbe
    )
    let workspace = ProjectWorkspace(project: project)
    _ = try await workspace.evaluate()
    let view = try #require(workspace.view)
    let authority = projectAgentAuthority(view)
    let requestID = String(repeating: "\"", count: 1_024)
    let compiler = try projectAgentSemanticCompiler()
    let direct = projectAgentDirectBoxRequest(
        sessionID: UUID(),
        authority: authority,
        name: "Unstaged Box"
    )
    let compilation = try compiler.compile(
        direct.request.semanticValue(),
        context: SemanticCompilationContext(),
        limits: ProjectAgentSemanticProgramLimits.standard
    )
    let probeLimits = AgentProtocolEncodingLimits(
        maximumRequestByteCount: 1_000_000,
        maximumResponseByteCount: 1_000_000,
        maximumIdentifierUTF8ByteCount: 1_024,
        maximumProjectIDUTF8ByteCount: 64
    )
    let probeReservation = try AgentMessageCodec(limits: probeLimits).reserveResponse(
        requestID: requestID,
        method: "capability.invoke",
        authority: authority,
        requestedOutputs: compilation.requestedOutputs.map {
            AgentSemanticOutputReference($0.source)
        },
        resultCharge: compilation.resultCharge
    )
    #expect(
        probeReservation.plan.maximumSuccessEncodedByteCount
            > probeReservation.plan.prepublicationFailureEncodedByteCount
    )
    let failureOnlyLimits = AgentProtocolEncodingLimits(
        maximumRequestByteCount: probeLimits.maximumRequestByteCount,
        maximumResponseByteCount: probeReservation.plan.prepublicationFailureEncodedByteCount,
        maximumIdentifierUTF8ByteCount: probeLimits.maximumIdentifierUTF8ByteCount,
        maximumProjectIDUTF8ByteCount: probeLimits.maximumProjectIDUTF8ByteCount
    )
    let controller = ProjectAgentCommandController(
        semanticProgramCompiler: compiler,
        semanticProtocolEncodingLimits: failureOnlyLimits
    )
    let sessionID = try await controller.register(workspace: workspace)
    let before = try await project.currentState()
    let handled = await controller.handle(
        AgentRequestEnvelope(
            id: requestID,
            params: .invokeCapability(
                projectAgentDirectBoxRequest(
                    sessionID: sessionID,
                    authority: authority,
                    name: "Unstaged Box"
                )
            )
        )
    )

    guard case .planned(let response, let reservation) = handled,
          case .capabilityExecution(.prepublicationFailure(let failure)) = response else {
        Issue.record("Expected a failure-only response reservation before staging.")
        return
    }
    #expect(reservation.plan.isFailureOnly)
    #expect(
        failure.stage
            == AgentSemanticPrepublicationFailure.Stage.responsePlanRejected
    )
    #expect(failure.code == "responsePlanRejected")
    #expect(executionProbe.executionCount == 0)
    _ = try AgentMessageCodec(limits: failureOnlyLimits).encode(
        response,
        consuming: reservation
    )
    let after = try await project.currentState()
    #expect(after.documentGeneration == before.documentGeneration)
    #expect(after.transactionRevision == before.transactionRevision)
    #expect(after.publicationSequence == before.publicationSequence)
    #expect(after.package.productSource == before.package.productSource)
    #expect(after.package.cadSource == before.package.cadSource)
    #expect(after.evaluationSnapshot == before.evaluationSnapshot)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentSemanticInitialFailureOnlyReservationStopsBeforeAuthorityValidation() async throws {
    let executionProbe = ProjectAgentPreparedProgramExecutionProbe()
    let project = try ProjectController(
        document: .empty(named: "Semantic Initial Reservation Failure"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge(),
        preparedProgramExecutor: executionProbe
    )
    let workspace = ProjectWorkspace(project: project)
    _ = try await workspace.evaluate()
    let view = try #require(workspace.view)
    let limits = AgentProtocolEncodingLimits(
        maximumRequestByteCount: 1_000_000,
        maximumResponseByteCount: 1_000_000,
        maximumIdentifierUTF8ByteCount: 1_024,
        maximumProjectIDUTF8ByteCount: 8
    )
    let controller = ProjectAgentCommandController(
        semanticProgramCompiler: try projectAgentSemanticCompiler(),
        semanticProtocolEncodingLimits: limits
    )
    let sessionID = try await controller.register(workspace: workspace)
    let currentAuthority = projectAgentAuthority(view)
    let oversizedAuthority = AgentProjectAuthorityCoordinate(
        projectID: ProjectID(rawValue: String(repeating: "p", count: 9)),
        documentGeneration: currentAuthority.documentGeneration,
        transactionRevision: currentAuthority.transactionRevision,
        publicationSequence: currentAuthority.publicationSequence,
        workspaceRevision: currentAuthority.workspaceRevision
    )
    let before = try await project.currentState()

    let handled = await controller.handle(
        AgentRequestEnvelope(
            id: "initial-plan-failure",
            params: .invokeCapability(
                projectAgentDirectBoxRequest(
                    sessionID: sessionID,
                    authority: oversizedAuthority,
                    name: "Never Staged"
                )
            )
        )
    )

    guard case .planned(let response, let reservation) = handled,
          case .capabilityExecution(.prepublicationFailure(let failure)) = response else {
        Issue.record("Expected response-plan rejection before authority validation.")
        return
    }
    #expect(reservation.plan.isFailureOnly)
    #expect(
        failure.stage
            == AgentSemanticPrepublicationFailure.Stage.responsePlanRejected
    )
    #expect(failure.code == "responsePlanRejected")
    #expect(executionProbe.executionCount == 0)
    _ = try AgentMessageCodec(limits: limits).encode(
        response,
        consuming: reservation
    )
    let after = try await project.currentState()
    #expect(after.documentGeneration == before.documentGeneration)
    #expect(after.transactionRevision == before.transactionRevision)
    #expect(after.publicationSequence == before.publicationSequence)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentSemanticEvaluationFailureRollsBackStagedProgram() async throws {
    let evaluator = ProjectAgentSemanticNthFailingEvaluator(failingEvaluation: 2)
    let executionProbe = ProjectAgentPreparedProgramExecutionProbe()
    let project = try ProjectController(
        document: .empty(named: "Semantic Evaluation Rollback"),
        evaluatorPreparer: ProjectAgentSemanticStaticEvaluatorPreparer(evaluator: evaluator),
        projector: DesignDocumentProjectBridge(),
        preparedProgramExecutor: executionProbe
    )
    let workspace = ProjectWorkspace(project: project)
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController(
        semanticProgramCompiler: try projectAgentSemanticCompiler()
    )
    let sessionID = try await controller.register(workspace: workspace)
    let view = try #require(workspace.view)
    let before = try await project.currentState()
    let handled = await controller.handle(
        AgentRequestEnvelope(
            id: "semantic-evaluation-rollback",
            params: .invokeCapability(
                projectAgentDirectBoxRequest(
                    sessionID: sessionID,
                    authority: projectAgentAuthority(view),
                    name: "Rolled Back Box"
                )
            )
        )
    )

    guard case .planned(let response, let reservation) = handled,
          case .capabilityExecution(.prepublicationFailure(let failure)) = response else {
        Issue.record("Expected evaluation failure before project publication.")
        return
    }
    #expect(failure.stage == .evaluationRejected)
    #expect(failure.code == "evaluationFailed")
    #expect(executionProbe.executionCount == 1)
    _ = try AgentMessageCodec().encode(response, consuming: reservation)

    let after = try await project.currentState()
    #expect(after.documentGeneration == before.documentGeneration)
    #expect(after.transactionRevision == before.transactionRevision)
    #expect(after.publicationSequence == before.publicationSequence)
    #expect(after.document.cadDocument.designGraph.order == before.document.cadDocument.designGraph.order)
    #expect(after.package.productSource == before.package.productSource)
    #expect(after.package.cadSource == before.package.cadSource)
    #expect(after.evaluationSnapshot == before.evaluationSnapshot)
    #expect(workspace.view?.authorityCoordinate == view.authorityCoordinate)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentSemanticProgramExecutesAgainstLoadedMixedRepresentationProject() async throws {
    let project = try ProjectController(
        document: .empty(named: "Semantic Loaded Project"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: project)
    _ = try await workspace.evaluate()
    let packageURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("RupaVerification.rupa")
    _ = try await workspace.load(from: packageURL)
    var view = try #require(workspace.view)
    let controller = ProjectAgentCommandController(
        semanticProgramCompiler: try projectAgentSemanticCompiler()
    )
    let sessionID = try await controller.register(workspace: workspace)
    let codec = AgentMessageCodec()
    let directHandled = await controller.handle(
        AgentRequestEnvelope(
            id: "loaded-project-direct",
            params: .invokeCapability(
                projectAgentDirectBoxRequest(
                    sessionID: sessionID,
                    authority: projectAgentAuthority(view),
                    name: "Loaded Project Direct Box"
                )
            )
        )
    )
    guard case .planned(let directResponse, let directReservation) = directHandled,
          case .capabilityExecution(.success(.committed)) = directResponse else {
        Issue.record("Expected the direct semantic request to commit through the project Agent controller.")
        return
    }
    _ = try codec.encode(directResponse, consuming: directReservation)

    view = try #require(workspace.view)
    let request = AgentSemanticProgramRequest(
        schemaVersion: .init(major: 1, minor: 0, patch: 0),
        nodes: [
            projectAgentProgramBoxNode(
                symbol: "loadedBox",
                name: "Loaded Project Box",
                originX: 3.8
            ),
        ],
        requestedOutputs: [
            AgentSemanticOutputReference(
                node: "loadedBox",
                output: "body",
                kind: .sourceBody(role: .body)
            ),
        ]
    )
    let programHandled = await controller.handle(
        AgentRequestEnvelope(
            id: "loaded-project-program",
            params: .executeProgram(
                AgentSemanticProgramExecutionRequest(
                    sessionID: sessionID,
                    authority: projectAgentAuthority(view),
                    dryRun: false,
                    program: request
                )
            )
        )
    )
    guard case .planned(let programResponse, let programReservation) = programHandled,
          case .programExecution(.success(.committed(let commit))) = programResponse else {
        Issue.record("Expected the semantic program to commit through the same project Agent controller.")
        return
    }
    #expect(commit.outputs.count == 1)
    _ = try codec.encode(programResponse, consuming: programReservation)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentSemanticCommittedProjectionFailurePreservesAuthorityAndForbidsRetry() async throws {
    let executionProbe = ProjectAgentPreparedProgramExecutionProbe()
    let project = try ProjectController(
        document: .empty(named: "Semantic Committed Failure"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge(),
        preparedProgramExecutor: executionProbe
    )
    let workspace = ProjectWorkspace(
        project: project,
        semanticResultProjector: ProjectAgentRejectingSemanticResultProjector()
    )
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController(
        semanticProgramCompiler: try projectAgentSemanticCompiler()
    )
    let sessionID = try await controller.register(workspace: workspace)
    let view = try #require(workspace.view)
    let before = try await project.currentState()
    let handled = await controller.handle(
        AgentRequestEnvelope(
            id: "semantic-committed-failure",
            params: .invokeCapability(
                projectAgentDirectBoxRequest(
                    sessionID: sessionID,
                    authority: projectAgentAuthority(view),
                    name: "Committed Box"
                )
            )
        )
    )

    guard case .planned(let response, let reservation) = handled,
          case .capabilityExecution(.committedFailure(let failure)) = response else {
        Issue.record("Expected committed result projection failure to remain planned.")
        return
    }
    #expect(executionProbe.executionCount == 1)
    #expect(failure.code == .resultProjectionFailed)
    #expect(failure.retryDisposition == .mustNotRetry)
    #expect(failure.authority.documentGeneration.value == view.documentGeneration.value + 1)
    #expect(failure.authority.transactionRevision.value == view.transactionRevision.value + 1)
    #expect(failure.authority.publicationSequence == view.publicationSequence + 1)
    _ = try AgentMessageCodec().encode(response, consuming: reservation)

    let after = try await project.currentState()
    #expect(after.documentGeneration.value == before.documentGeneration.value + 1)
    #expect(after.transactionRevision.value == before.transactionRevision.value + 1)
    #expect(after.publicationSequence == before.publicationSequence + 1)
    #expect(failure.authority.projectID == after.document.projectID)
    #expect(failure.authority.workspaceRevision == after.workspaceState.revision)
}

private enum ProjectAgentSemanticMethod {
    case capability
    case program
}

private func projectAgentRequirePlannedCompilationFailure(
    _ handled: AgentHandledResponse,
    method: ProjectAgentSemanticMethod,
    code: DomainCapabilityErrorCode
) throws {
    guard case .planned(let response, let reservation) = handled else {
        Issue.record("Expected semantic compilation failure to retain a response plan.")
        return
    }
    let failure: AgentSemanticPrepublicationFailure
    switch (method, response) {
    case (.capability, .capabilityExecution(.prepublicationFailure(let value))),
         (.program, .programExecution(.prepublicationFailure(let value))):
        failure = value
    default:
        Issue.record("Expected a semantic compilation prepublication failure.")
        return
    }
    #expect(failure.stage == .compilationRejected)
    #expect(failure.code == code)
    #expect(failure.publicationDisposition == .notPublished)
    #expect(failure.retryDisposition == .retryPermitted)
    _ = try AgentMessageCodec().encode(response, consuming: reservation)
}

private final class ProjectAgentPreparedProgramExecutionProbe:
    PreparedAutomationProgramExecuting,
    Sendable {
    private let count = Mutex(0)
    private let implementation = DefaultPreparedAutomationProgramExecutor()

    var executionCount: Int {
        count.withLock { $0 }
    }

    func execute(
        _ program: PreparedAutomationProgram,
        in stagedSession: EditorSession
    ) throws -> PreparedAutomationExecutionReceipt {
        count.withLock { $0 += 1 }
        return try implementation.execute(program, in: stagedSession)
    }
}

private final class ProjectAgentSemanticNthFailingEvaluator:
    ProjectEvaluating,
    Sendable {
    private let count = Mutex(0)
    private let failingEvaluation: Int

    init(failingEvaluation: Int) {
        self.failingEvaluation = failingEvaluation
    }

    func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        let evaluation = count.withLock { value in
            value += 1
            return value
        }
        guard evaluation != failingEvaluation else {
            throw ProjectAgentSemanticRuntimeTestError.evaluationFailed
        }
        return try ProjectEvaluationEngine().evaluate(
            project: project,
            purpose: purpose,
            revision: revision
        )
    }
}

private struct ProjectAgentSemanticStaticEvaluatorPreparer:
    ProjectEvaluatorPreparing,
    Sendable {
    let evaluator: any ProjectEvaluating

    func makeEvaluator(
        for _: DesignDocument,
        reusing _: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        evaluator
    }
}

private struct ProjectAgentRejectingSemanticResultProjector:
    ProjectSemanticResultProjecting,
    Sendable {
    func project(
        plan _: ProjectResultProjectionPlan,
        receipt _: PreparedAutomationExecutionReceipt,
        state _: ProjectStateSnapshot
    ) throws -> [ProjectSemanticOutputBinding] {
        throw ProjectAgentSemanticRuntimeTestError.resultProjectionFailed
    }
}

private enum ProjectAgentSemanticRuntimeTestError: Error {
    case evaluationFailed
    case resultProjectionFailed
}
