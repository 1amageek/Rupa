import Foundation
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProject
import Synchronization
import Testing
@testable import RupaKit

@Test(.timeLimit(.minutes(1)))
func projectWorkspacePlannerStampsDirectSourceActionFromOneSnapshot() async throws {
    let controller = try makeActionController(document: .empty(named: "Before"))
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()

    let action = try DefaultProjectWorkspaceActionPlanner().source(
        name: "action.rename",
        commands: [.renameDocument(name: "After")],
        from: snapshot
    )

    guard case .source(let transaction) = action else {
        Issue.record("Direct source planning must produce a source action.")
        return
    }
    #expect(transaction.expectedProjectID == snapshot.projectID)
    #expect(transaction.expectedTransactionRevision == snapshot.transactionRevision)
    #expect(transaction.expectedPublicationSequence == snapshot.publicationSequence)
    #expect(transaction.commands == [.renameDocument(name: "After")])
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceExecutesPreparedSourceAutomationAndPreservesResults() async throws {
    let controller = try makeActionController(document: .empty(named: "Before"))
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let action = try DefaultProjectWorkspaceActionPlanner().automation(
        AutomationBatch(
            commands: [
                .renameDocument(name: "After"),
                .describeDocument,
            ]
        ),
        from: snapshot
    )

    let result = try await workspace.perform(action)
    guard case .source(let commit, let view) = result else {
        Issue.record("Source Automation must produce a source result.")
        return
    }
    let execution = try #require(commit.automationExecution)

    #expect(commit.commandResults.isEmpty)
    #expect(execution.results.count == 2)
    #expect(execution.results[1].generation == view.documentGeneration)
    #expect(execution.finalContext.document.cadDocument.metadata.name == "After")
    #expect(execution.didCommit)
    #expect(execution.diagnostics == commit.diagnostics)
    #expect(!execution.diagnostics.isEmpty)
    #expect(execution.proposedTransactionRevision == view.transactionRevision)
    #expect(commit.state.publicationSequence == view.publicationSequence)
    #expect(view.document.name == "After")
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceExecutesPreparedInteractionAutomationAndPreservesResults() async throws {
    let controller = try makeActionController(document: .empty(named: "Interaction"))
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let action = try DefaultProjectWorkspaceActionPlanner().automation(
        AutomationBatch(
            commands: [
                .setDisplayUnit(.meter),
                .describeDocument,
            ]
        ),
        from: snapshot
    )

    let result = try await workspace.perform(action)
    guard case .interaction(let commit, let view) = result else {
        Issue.record("Workspace Automation must produce an interaction result.")
        return
    }
    let execution = try #require(commit.automationExecution)

    #expect(execution.results.count == 2)
    #expect(execution.results[1].message.contains("m display units"))
    #expect(execution.didCommit)
    #expect(view.transactionRevision == snapshot.transactionRevision)
    #expect(view.publicationSequence > snapshot.publicationSequence)
    #expect(view.workspaceState.displayUnit == .meter)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspacePlannerRejectsReadOnlyAutomationFromMutationRoute() async throws {
    let controller = try makeActionController(document: .empty(named: "Read"))
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    var caught: ProjectWorkspaceActionError?

    do {
        _ = try DefaultProjectWorkspaceActionPlanner().automation(
            AutomationBatch(commands: [.validateDocument]),
            from: snapshot
        )
    } catch let error as ProjectWorkspaceActionError {
        caught = error
    }

    #expect(caught?.code == .readRouteRequired)
    #expect(try await controller.currentState().publicationSequence == snapshot.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceAutomationFailureRollsBackAllProjectAuthorities() async throws {
    let controller = try makeActionController(document: .empty(named: "Before"))
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let retained = try await controller.currentState()
    let action = try DefaultProjectWorkspaceActionPlanner().automation(
        AutomationBatch(
            commands: [
                .renameDocument(name: "Transient"),
                .setFeatureSuppression(featureID: FeatureID(), isSuppressed: true),
            ]
        ),
        from: snapshot
    )

    var didThrow = false
    do {
        _ = try await workspace.perform(action)
    } catch {
        didThrow = true
    }
    let current = try await controller.currentState()
    let published = try #require(await workspace.view)

    #expect(didThrow)
    #expect(current.document.cadDocument.metadata.name == "Before")
    #expect(current.documentGeneration == retained.documentGeneration)
    #expect(current.package.productSource == retained.package.productSource)
    #expect(current.evaluation.id == retained.evaluation.id)
    #expect(current.evaluationSource == retained.evaluationSource)
    #expect(current.transactionRevision == retained.transactionRevision)
    #expect(current.publicationSequence == retained.publicationSequence)
    #expect(published.publicationSequence == snapshot.publicationSequence)
    #expect(published.document.name == "Before")
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceSourcePreviewReturnsProposalWithoutPublishing() async throws {
    let controller = try makeActionController(document: .empty(named: "Before"))
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let initial = try await controller.currentState()
    let action = try DefaultProjectWorkspaceActionPlanner().source(
        name: "preview.rename",
        commands: [.renameDocument(name: "After")],
        from: snapshot
    )

    let result = try await workspace.preview(action)
    guard case .source(let preview) = result else {
        Issue.record("A source action must return a source preview.")
        return
    }
    let retained = try await controller.currentState()
    let published = try #require(await workspace.view)

    #expect(preview.base.transactionRevision == snapshot.transactionRevision)
    #expect(preview.base.projectID == snapshot.projectID)
    #expect(preview.base.publicationSequence == snapshot.publicationSequence)
    #expect(preview.proposedTransactionRevision.value == snapshot.transactionRevision.value + 1)
    #expect(preview.proposedDocumentGeneration.value == snapshot.documentGeneration.value + 1)
    #expect(preview.renderPayload.document.cadDocument.metadata.name == "After")
    #expect(preview.renderPayload.evaluationSource.id == snapshot.projectID)
    #expect(
        preview.renderPayload.evaluation.id.sourceRevision
            == preview.proposedTransactionRevision
    )
    #expect(preview.renderPayload.evaluation.id.purpose == .presentation)
    #expect(preview.wouldMutate)
    #expect(preview.commandResults.count == 1)
    #expect(!preview.diagnostics.isEmpty)
    #expect(retained.document.cadDocument.metadata.name == "Before")
    #expect(retained.transactionRevision == snapshot.transactionRevision)
    #expect(retained.publicationSequence == snapshot.publicationSequence)
    #expect(retained.package.productSource == initial.package.productSource)
    #expect(retained.evaluation.id == initial.evaluation.id)
    #expect(published.document.name == "Before")
    #expect(published.publicationSequence == snapshot.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceSourcePreviewRenderPayloadMatchesStagedCandidate() async throws {
    let controller = try makeActionController(document: .empty(named: "Before"))
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let transaction = try ProjectSourceTransaction(
        name: "preview.render.create",
        commands: [
            .createExtrudedRectangle(
                name: "Preview Body",
                plane: .xy,
                width: .length(1, .meter),
                height: .length(1, .meter),
                depth: .length(1, .meter),
                direction: .normal
            ),
        ],
        expectedProjectID: initial.projectID,
        expectedTransactionRevision: initial.transactionRevision,
        expectedPublicationSequence: initial.publicationSequence
    )

    let payload = try await workspace.previewRenderPayload(transaction)
    let item = try #require(payload.presentationScene.items.first)
    let sceneNodeID = try #require(
        payload.presentationSceneNodeIDByOccurrenceID[item.id]
    )
    let source = try DesignDocumentProjectBridge().sourceModel(for: payload.document)
    let sourceOccurrence = try #require(source.occurrences[item.id])

    #expect(payload.document.cadDocument.metadata.name == "Before")
    #expect(payload.presentationScene.items.count == 1)
    #expect(
        payload.presentationScene.snapshotID.sourceRevision
            == DocumentTransactionRevision(initial.transactionRevision.value + 1)
    )
    #expect(payload.presentationScene.snapshotID.purpose == .presentation)
    #expect(source.id == initial.projectID)
    #expect(sourceOccurrence.definitionID == item.definitionID)
    let sceneNode = try #require(payload.document.productMetadata.sceneNodes[sceneNodeID])
    let presentation = try #require(
        sceneNode.object?.geometryRepresentations.representation(for: .presentation)
    )
    #expect(presentation.id == item.representationID)
    #expect(presentation.source == item.reference)

    let retained = try await controller.currentState()
    let published = try #require(await workspace.view)
    #expect(retained.transactionRevision == initial.transactionRevision)
    #expect(retained.publicationSequence == initial.publicationSequence)
    #expect(published.transactionRevision == initial.transactionRevision)
    #expect(published.publicationSequence == initial.publicationSequence)
    #expect(published.viewport.items.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceSourcePreviewRenderPayloadFailureDoesNotPublish() async throws {
    let controller = try makeActionController(document: .empty(named: "Before"))
    let workspace = await ProjectWorkspace(
        project: controller,
        previewRenderPayloadBuilder: RejectingProjectPreviewRenderPayloadBuilder()
    )
    let initial = try await workspace.evaluate()
    let transaction = try ProjectSourceTransaction(
        name: "preview.render.failure",
        commands: [.renameDocument(name: "Candidate")],
        expectedProjectID: initial.projectID,
        expectedTransactionRevision: initial.transactionRevision,
        expectedPublicationSequence: initial.publicationSequence
    )

    var didThrow = false
    do {
        _ = try await workspace.previewRenderPayload(transaction)
    } catch {
        didThrow = true
    }

    let retained = try await controller.currentState()
    let published = try #require(await workspace.view)
    #expect(didThrow)
    #expect(retained.document.cadDocument.metadata.name == "Before")
    #expect(retained.transactionRevision == initial.transactionRevision)
    #expect(retained.publicationSequence == initial.publicationSequence)
    #expect(published.document.name == "Before")
    #expect(published.publicationSequence == initial.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceSourcePreviewRenderPayloadRejectsStaleReplacement() async throws {
    let gate = ProjectPreviewRenderPayloadGate()
    defer { gate.release() }
    let controller = try makeActionController(document: .empty(named: "Before"))
    let workspace = await ProjectWorkspace(
        project: controller,
        previewRenderPayloadBuilder: BlockingProjectPreviewRenderPayloadBuilder(
            gate: gate
        )
    )
    let initial = try await workspace.evaluate()
    let previewTransaction = try ProjectSourceTransaction(
        name: "preview.render.stale",
        commands: [.renameDocument(name: "Preview")],
        expectedProjectID: initial.projectID,
        expectedTransactionRevision: initial.transactionRevision,
        expectedPublicationSequence: initial.publicationSequence
    )
    let preview = Task {
        try await workspace.previewRenderPayload(previewTransaction)
    }
    while !gate.didStart {
        try await Task.sleep(for: .milliseconds(1))
    }

    let committed = try await workspace.commit(
        ProjectSourceTransaction(
            name: "preview.render.replacement",
            commands: [.renameDocument(name: "Committed")],
            expectedProjectID: initial.projectID,
            expectedTransactionRevision: initial.transactionRevision,
            expectedPublicationSequence: initial.publicationSequence
        )
    )
    gate.release()

    var didReject = false
    do {
        _ = try await preview.value
    } catch {
        didReject = true
    }
    #expect(didReject)
    #expect(committed.document.name == "Committed")
    #expect(await workspace.view?.document.name == "Committed")
    #expect(await workspace.view?.publicationSequence == committed.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceSourcePreviewRenderPayloadCancellationDoesNotPublish() async throws {
    let gate = ProjectPreviewRenderPayloadGate()
    defer { gate.release() }
    let controller = try makeActionController(document: .empty(named: "Before"))
    let workspace = await ProjectWorkspace(
        project: controller,
        previewRenderPayloadBuilder: BlockingProjectPreviewRenderPayloadBuilder(
            gate: gate
        )
    )
    let initial = try await workspace.evaluate()
    let transaction = try ProjectSourceTransaction(
        name: "preview.render.cancel",
        commands: [.renameDocument(name: "Cancelled")],
        expectedProjectID: initial.projectID,
        expectedTransactionRevision: initial.transactionRevision,
        expectedPublicationSequence: initial.publicationSequence
    )
    let preview = Task {
        try await workspace.previewRenderPayload(transaction)
    }
    while !gate.didStart {
        try await Task.sleep(for: .milliseconds(1))
    }
    preview.cancel()
    gate.release()

    var wasCancelled = false
    do {
        _ = try await preview.value
    } catch is CancellationError {
        wasCancelled = true
    }
    #expect(wasCancelled)
    #expect(await workspace.view?.document.name == "Before")
    #expect(await workspace.view?.publicationSequence == initial.publicationSequence)
    #expect(await controller.currentTransactionRevision() == initial.transactionRevision)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceSourcePreviewRenderPayloadEvaluatesExactlyOnce() async throws {
    let probe = ProjectPreviewEvaluationProbe()
    let controller = try ProjectController(
        document: .empty(named: "Before"),
        evaluatorPreparer: CountingProjectPreviewEvaluatorPreparer(probe: probe),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let countBeforePreview = probe.evaluationCount
    let transaction = try ProjectSourceTransaction(
        name: "preview.render.once",
        commands: [.renameDocument(name: "Candidate")],
        expectedProjectID: initial.projectID,
        expectedTransactionRevision: initial.transactionRevision,
        expectedPublicationSequence: initial.publicationSequence
    )

    _ = try await workspace.previewRenderPayload(transaction)

    #expect(probe.evaluationCount == countBeforePreview + 1)
    #expect(await controller.currentTransactionRevision() == initial.transactionRevision)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceInteractionPreviewReportsNoOpWithoutPublishing() async throws {
    let controller = try makeActionController(document: .empty(named: "Interaction Preview"))
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let action = try DefaultProjectWorkspaceActionPlanner().interaction(
        selection: .clear,
        workspaceCommands: [],
        from: snapshot
    )

    let result = try await workspace.preview(action)
    guard case .interaction(let preview) = result else {
        Issue.record("An interaction action must return an interaction preview.")
        return
    }
    let retained = try await controller.currentState()

    #expect(preview.base.transactionRevision == snapshot.transactionRevision)
    #expect(preview.base.projectID == snapshot.projectID)
    #expect(preview.base.publicationSequence == snapshot.publicationSequence)
    #expect(!preview.wouldPublish)
    #expect(preview.proposedSelection == snapshot.selection)
    #expect(preview.proposedWorkspaceState.revision == snapshot.workspaceState.revision)
    #expect(preview.proposedWorkspaceState.displayUnit == snapshot.workspaceState.displayUnit)
    #expect(retained.publicationSequence == snapshot.publicationSequence)
    #expect(await workspace.view?.publicationSequence == snapshot.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceSourceAutomationPreviewPreservesResultsWithoutCommit() async throws {
    let controller = try makeActionController(document: .empty(named: "Before"))
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let action = try DefaultProjectWorkspaceActionPlanner().automation(
        AutomationBatch(commands: [
            .renameDocument(name: "After"),
            .describeDocument,
        ]),
        from: snapshot
    )

    let result = try await workspace.preview(action)
    guard case .source(let preview) = result else {
        Issue.record("Source Automation must return a source preview.")
        return
    }
    let execution = try #require(preview.automationExecution)

    #expect(execution.results.count == 2)
    #expect(!execution.didCommit)
    #expect(execution.finalContext.document.cadDocument.metadata.name == "After")
    #expect(execution.finalContext.transactionRevision == preview.proposedTransactionRevision)
    #expect(execution.diagnostics == preview.diagnostics)
    #expect(!preview.diagnostics.isEmpty)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Before")
    #expect(try await controller.currentState().publicationSequence == snapshot.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceInteractionAutomationPreviewPreservesResultsWithoutCommit() async throws {
    let controller = try makeActionController(document: .empty(named: "Workspace Preview"))
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let action = try DefaultProjectWorkspaceActionPlanner().automation(
        AutomationBatch(commands: [
            .setDisplayUnit(.meter),
            .describeDocument,
        ]),
        from: snapshot
    )

    let result = try await workspace.preview(action)
    guard case .interaction(let preview) = result else {
        Issue.record("Workspace Automation must return an interaction preview.")
        return
    }
    let execution = try #require(preview.automationExecution)

    #expect(preview.wouldPublish)
    #expect(preview.proposedWorkspaceState.displayUnit == .meter)
    #expect(execution.results.count == 2)
    #expect(!execution.didCommit)
    #expect(try await controller.currentState().workspaceState.displayUnit == .millimeter)
    #expect(try await controller.currentState().publicationSequence == snapshot.publicationSequence)
    #expect(await workspace.view?.workspaceState.displayUnit == .millimeter)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceInteractionAutomationPreviewCanonicalizesSemanticNoOpContext() async throws {
    let controller = try makeActionController(document: .empty(named: "No-op Preview"))
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let action = try DefaultProjectWorkspaceActionPlanner().automation(
        AutomationBatch(commands: [
            .setDisplayUnit(.millimeter),
            .describeDocument,
        ]),
        from: snapshot
    )

    let result = try await workspace.preview(action)
    guard case .interaction(let preview) = result else {
        Issue.record("Workspace Automation must return an interaction preview.")
        return
    }
    let execution = try #require(preview.automationExecution)

    #expect(!preview.wouldPublish)
    #expect(preview.proposedWorkspaceState.revision == snapshot.workspaceState.revision)
    #expect(preview.proposedWorkspaceState.displayUnit == snapshot.workspaceState.displayUnit)
    #expect(execution.proposedWorkspaceRevision == snapshot.workspaceState.revision)
    #expect(execution.finalContext.workspaceState.revision == snapshot.workspaceState.revision)
    #expect(execution.finalContext.workspaceState.displayUnit == snapshot.workspaceState.displayUnit)
    #expect(!execution.didCommit)
    #expect(try await controller.currentState().publicationSequence == snapshot.publicationSequence)
    #expect(await workspace.view?.publicationSequence == snapshot.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceRejectsCrossProjectMutationAndPreviewActions() async throws {
    let sourceController = try makeActionController(document: .empty(named: "Source"))
    let targetController = try makeActionController(document: .empty(named: "Target"))
    let sourceWorkspace = await ProjectWorkspace(project: sourceController)
    let targetWorkspace = await ProjectWorkspace(project: targetController)
    let sourceSnapshot = try await sourceWorkspace.evaluate()
    let targetSnapshot = try await targetWorkspace.evaluate()
    let planner = DefaultProjectWorkspaceActionPlanner()
    let sourceAction = try planner.source(
        name: "cross-project.rename",
        commands: [.renameDocument(name: "Rejected")],
        from: sourceSnapshot
    )
    let interactionAction = try planner.interaction(
        selection: .clear,
        workspaceCommands: [.setDisplayUnit(.meter)],
        from: sourceSnapshot
    )

    var failures: [ProjectControllerError.Code] = []
    do {
        _ = try await targetWorkspace.perform(sourceAction)
    } catch let error as ProjectControllerError {
        failures.append(error.code)
    }
    do {
        _ = try await targetWorkspace.perform(interactionAction)
    } catch let error as ProjectControllerError {
        failures.append(error.code)
    }
    do {
        _ = try await targetWorkspace.preview(sourceAction)
    } catch let error as ProjectControllerError {
        failures.append(error.code)
    }
    do {
        _ = try await targetWorkspace.preview(interactionAction)
    } catch let error as ProjectControllerError {
        failures.append(error.code)
    }
    let retained = try await targetController.currentState()

    #expect(sourceSnapshot.projectID != targetSnapshot.projectID)
    #expect(failures == Array(repeating: .projectMismatch, count: 4))
    #expect(retained.document.cadDocument.metadata.name == "Target")
    #expect(retained.publicationSequence == targetSnapshot.publicationSequence)
    #expect(retained.workspaceState.displayUnit == targetSnapshot.workspaceState.displayUnit)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceReportsExactCommittedStateWhenViewProjectionFails() async throws {
    let controller = try makeActionController(document: .empty(named: "Before"))
    let builder = NthFailingProjectViewSnapshotBuilder(failingBuildNumber: 2)
    let workspace = await ProjectWorkspace(project: controller, viewBuilder: builder)
    let snapshot = try await workspace.evaluate()
    let action = try DefaultProjectWorkspaceActionPlanner().source(
        name: "post-commit.rename",
        commands: [.renameDocument(name: "After")],
        from: snapshot
    )

    var caught: ProjectWorkspacePostCommitError?
    do {
        _ = try await workspace.perform(action)
    } catch let error as ProjectWorkspacePostCommitError {
        caught = error
    }
    let error = try #require(caught)
    let committedState = error.commit.state
    let current = try await controller.currentState()

    #expect(error.stage == .viewProjection)
    #expect(committedState.document.cadDocument.metadata.name == "After")
    #expect(committedState.publicationSequence > snapshot.publicationSequence)
    #expect(current.publicationSequence == committedState.publicationSequence)
    #expect(current.document.cadDocument.metadata.name == "After")
    #expect(await workspace.view?.publicationSequence == snapshot.publicationSequence)
}

private func makeActionController(document: DesignDocument) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
}

private final class NthFailingProjectViewSnapshotBuilder: ProjectViewSnapshotBuilding, Sendable {
    private let state = Mutex(0)
    private let failingBuildNumber: Int

    init(failingBuildNumber: Int) {
        self.failingBuildNumber = failingBuildNumber
    }

    func build(from state: ProjectStateSnapshot) throws -> ProjectViewSnapshot {
        let buildNumber = self.state.withLock { count in
            count += 1
            return count
        }
        guard buildNumber != failingBuildNumber else {
            throw ProjectWorkspaceActionTestError.viewProjectionFailed
        }
        return try ProjectViewSnapshotBuilder().build(from: state)
    }
}

private struct RejectingProjectPreviewRenderPayloadBuilder:
    ProjectPreviewRenderPayloadBuilding,
    Sendable
{
    func build(
        from _: ProjectSourcePreviewRenderPayload
    ) throws -> ProjectPreviewRenderPayload {
        throw ProjectWorkspaceActionTestError.previewRenderProjectionFailed
    }
}

private final class ProjectPreviewRenderPayloadGate: Sendable {
    private struct State {
        var didStart = false
        var isReleased = false
    }

    private let state = Mutex(State())

    var didStart: Bool {
        state.withLock { $0.didStart }
    }

    func markStarted() {
        state.withLock { $0.didStart = true }
    }

    func waitUntilReleased() {
        while !state.withLock({ $0.isReleased }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func release() {
        state.withLock { $0.isReleased = true }
    }
}

private struct BlockingProjectPreviewRenderPayloadBuilder:
    ProjectPreviewRenderPayloadBuilding,
    Sendable
{
    let gate: ProjectPreviewRenderPayloadGate

    func build(
        from payload: ProjectSourcePreviewRenderPayload
    ) throws -> ProjectPreviewRenderPayload {
        gate.markStarted()
        gate.waitUntilReleased()
        return try ProjectViewSnapshotBuilder().build(from: payload)
    }
}

private final class ProjectPreviewEvaluationProbe: Sendable {
    private let count = Mutex(0)

    var evaluationCount: Int {
        count.withLock { $0 }
    }

    func recordEvaluation() {
        count.withLock { $0 += 1 }
    }
}

private struct CountingProjectPreviewEvaluatorPreparer: ProjectEvaluatorPreparing {
    let probe: ProjectPreviewEvaluationProbe
    private let base = DefaultDesignDocumentProjectEvaluatorFactory()

    func makeEvaluator(
        for document: DesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        let evaluator = try base.makeEvaluator(
            for: document,
            reusing: currentEvaluation
        )
        return CountingProjectPreviewEvaluator(base: evaluator, probe: probe)
    }
}

private struct CountingProjectPreviewEvaluator: ProjectEvaluating {
    let base: any ProjectEvaluating
    let probe: ProjectPreviewEvaluationProbe

    func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        probe.recordEvaluation()
        return try base.evaluate(
            project: project,
            purpose: purpose,
            revision: revision
        )
    }
}

private enum ProjectWorkspaceActionTestError: Error {
    case viewProjectionFailed
    case previewRenderProjectionFailed
}
