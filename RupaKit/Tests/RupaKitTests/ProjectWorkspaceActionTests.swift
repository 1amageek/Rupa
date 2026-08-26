import RupaAutomation
import RupaCore
import RupaCoreTypes
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

private enum ProjectWorkspaceActionTestError: Error {
    case viewProjectionFailed
}
