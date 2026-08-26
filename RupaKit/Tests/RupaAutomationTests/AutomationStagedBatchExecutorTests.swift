import SwiftCAD
import Testing
import RupaCore
@testable import RupaAutomation

@MainActor
@Test(.timeLimit(.minutes(1)))
func stagedAutomationExecutorObservesMutationBeforeFollowingRead() async throws {
    let session = EditorSession(document: .empty(named: "Before"))
    let batch = AutomationBatch(
        commands: [
            .renameDocument(name: "After"),
            .describeDocument,
        ]
    )
    let prepared = try DefaultAutomationBatchPlanner().prepare(
        batch,
        in: automationPlanningContext(for: session)
    )

    let execution = try AutomationStagedBatchExecutor().execute(
        prepared,
        in: session
    )

    #expect(execution.results.count == 2)
    #expect(execution.results[1].generation == DocumentGeneration(1))
    #expect(execution.finalContext.document.cadDocument.metadata.name == "After")
    #expect(execution.proposedGeneration == DocumentGeneration(1))
    #expect(!execution.didCommit)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func stagedAutomationExecutorObservesWorkspaceMutationBeforeFollowingRead() async throws {
    let session = EditorSession()
    let prepared = try DefaultAutomationBatchPlanner().prepare(
        AutomationBatch(
            commands: [
                .setDisplayUnit(.meter),
                .describeDocument,
            ]
        ),
        in: automationPlanningContext(for: session)
    )

    let execution = try AutomationStagedBatchExecutor().execute(
        prepared,
        in: session
    )

    #expect(execution.results[1].message.contains("m display units"))
    #expect(execution.finalContext.workspaceState.displayUnit == .meter)
    #expect(execution.proposedWorkspaceRevision == WorkspaceRevision(1))
    #expect(!execution.didCommit)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func stagedAutomationExecutorPreservesResultsAndMetrics() async throws {
    let session = EditorSession()
    let batch = AutomationBatch(
        commands: [
            .createExtrudedRectangle(
                name: "Box",
                plane: .xy,
                width: .length(0.1, .meter),
                height: .length(0.2, .meter),
                depth: .length(0.3, .meter),
                direction: .normal
            ),
            .describeDocument,
        ]
    )
    let prepared = try DefaultAutomationBatchPlanner().prepare(
        batch,
        in: automationPlanningContext(for: session)
    )

    let execution = try AutomationStagedBatchExecutor().execute(
        prepared,
        in: session
    )

    #expect(execution.results.count == 2)
    #expect(!execution.generatedFeatureIDs.isEmpty)
    #expect(execution.generatedFeatureIDs == execution.results[0].createdFeatureIDs)
    #expect(execution.metrics.commandCount == 2)
    #expect(execution.metrics.evaluationPassCount == 1)
    #expect(execution.metrics.historyEntryCount == 1)
    #expect(execution.finalContext.generation == execution.proposedGeneration)
    #expect(execution.diagnostics == execution.finalContext.diagnostics)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func legacyAutomationBatchMatchesSharedStagedExecutorResults() async throws {
    let legacySession = EditorSession()
    let stagedSession = EditorSession()
    let batch = AutomationBatch(
        commands: [
            .renameDocument(name: "After"),
            .describeDocument,
        ]
    )
    let prepared = try DefaultAutomationBatchPlanner().prepare(
        batch,
        in: automationPlanningContext(for: stagedSession)
    )

    let legacy = try AutomationRunner().executeBatchTransaction(
        batch,
        in: legacySession,
        commits: true
    )
    let initialEvaluationPassCount = stagedSession.store.completedEvaluationPassCount
    let initialHistoryEntryCount = stagedSession.commandStack.undoEntries.count
    var staged = try stagedSession.withSourceCommandGroup(named: "automationBatch.source") {
        groupedSession in
        try AutomationStagedBatchExecutor().execute(prepared, in: groupedSession)
    }
    staged = AutomationStagedBatchExecutor().finalizingSourceMetrics(
        staged,
        initialEvaluationPassCount: initialEvaluationPassCount,
        initialHistoryEntryCount: initialHistoryEntryCount,
        in: stagedSession
    )

    #expect(staged.effect == legacy.effect)
    #expect(staged.results == legacy.results)
    #expect(staged.metrics == legacy.metrics)
    #expect(staged.generatedFeatureIDs == legacy.generatedFeatureIDs)
    #expect(staged.generatedFeatureIDs.isEmpty)
    #expect(legacy.finalContext.transactionRevision == legacy.proposedTransactionRevision)
    #expect(stagedSession.document.cadDocument.metadata.name == legacySession.document.cadDocument.metadata.name)
    #expect(stagedSession.generation == legacySession.generation)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func stagedAutomationExecutorLeavesFailureRollbackToCaller() async throws {
    let session = EditorSession(document: .empty(named: "Before"))
    let initial = session.transactionSnapshot()
    let batch = AutomationBatch(
        commands: [
            .renameDocument(name: "Transient"),
            .setFeatureSuppression(featureID: FeatureID(), isSuppressed: true),
        ]
    )
    let prepared = try DefaultAutomationBatchPlanner().prepare(
        batch,
        in: automationPlanningContext(for: session)
    )

    var didThrow = false
    do {
        _ = try AutomationStagedBatchExecutor().execute(prepared, in: session)
    } catch {
        didThrow = true
    }
    #expect(didThrow)
    #expect(session.document.cadDocument.metadata.name == "Transient")

    session.restoreTransactionSnapshot(initial)
    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.undoEntries.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationBatchPlannerRejectsStaleInitialCoordinates() throws {
    let session = EditorSession()
    var caught: EditorError?
    do {
        _ = try DefaultAutomationBatchPlanner().prepare(
            AutomationBatch(
                commands: [.renameDocument(name: "Rejected")],
                expectedGeneration: DocumentGeneration(1)
            ),
            in: automationPlanningContext(for: session)
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .documentGenerationMismatch)
    #expect(session.document.cadDocument.metadata.name == "Untitled")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func stagedAutomationExecutorRejectsPreparedBatchAfterSourceRevisionChanges() async throws {
    let session = EditorSession()
    let prepared = try DefaultAutomationBatchPlanner().prepare(
        AutomationBatch(commands: [.renameDocument(name: "Planned")]),
        in: automationPlanningContext(for: session)
    )
    _ = try AutomationRunner().execute(.renameDocument(name: "Intervening"), in: session)

    var caught: EditorError?
    do {
        _ = try AutomationStagedBatchExecutor().execute(prepared, in: session)
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .documentGenerationMismatch)
    #expect(session.document.cadDocument.metadata.name == "Intervening")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationBatchPlannerMakesEdgeSupportExplicitFromInitialContext() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodySceneNodeID = try #require(
        session.document.productMetadata.sceneNodes.first { entry in
            entry.value.reference?.kind == .body
        }?.key
    )
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let supportFace = try #require(
        topology.entries.first {
            $0.kind == .face
                && $0.sceneNodeID == bodySceneNodeID.description
                && $0.generatedRole == "startFace"
        }?.selectionTarget()
    )
    let edge = try #require(
        topology.entries.first {
            $0.kind == .edge
                && $0.sceneNodeID == bodySceneNodeID.description
                && $0.curveKind == "line"
        }?.selectionTarget()
    )
    #expect(session.selectTargets([supportFace, edge]))

    let prepared = try DefaultAutomationBatchPlanner().prepare(
        AutomationBatch(
            commands: [
                .offsetCurve(
                    target: edge,
                    distance: .length(1.0, .millimeter),
                    options: OffsetCurveOptions(),
                    vertexHandle: nil
                ),
            ]
        ),
        in: automationPlanningContext(for: session)
    )

    guard case .offsetCurve(_, _, let options, _) = prepared.batch.commands[0] else {
        Issue.record("The planner must preserve the Offset Curve command shape.")
        return
    }
    #expect(options.supportTarget == supportFace)
}

@Test(.timeLimit(.minutes(1)))
func automationBatchPlannerKeepsExplicitEdgeSupportUnchanged() throws {
    let edge = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .edge(SelectionComponentID(rawValue: "edge:explicit"))
    )
    let supportFace = SelectionTarget(
        sceneNodeID: edge.sceneNodeID,
        component: .face(SelectionComponentID(rawValue: "face:explicit"))
    )
    let command = AutomationCommand.offsetCurve(
        target: edge,
        distance: .length(1.0, .millimeter),
        options: OffsetCurveOptions(supportTarget: supportFace),
        vertexHandle: nil
    )
    let session = EditorSession()

    let prepared = try DefaultAutomationBatchPlanner().prepare(
        AutomationBatch(commands: [command]),
        in: automationPlanningContext(for: session)
    )

    #expect(prepared.batch.commands == [command])
}

@Test(.timeLimit(.minutes(1)))
func automationBatchPlannerRejectsInconsistentEvaluationSnapshot() throws {
    let session = EditorSession()
    let context = AutomationPlanningContext(
        document: session.document,
        generation: session.generation,
        transactionRevision: session.transactionRevision,
        publicationSequence: 0,
        selection: session.selection,
        workspaceState: session.workspaceState,
        objectRegistry: session.objectRegistry,
        evaluationSnapshot: EvaluationSnapshot(
            evaluatedGeneration: DocumentGeneration(1)
        ),
        currentEvaluation: nil
    )

    #expect(throws: EditorError.self) {
        try DefaultAutomationBatchPlanner().prepare(
            AutomationBatch(commands: [.validateDocument]),
            in: context
        )
    }
}

private func automationPlanningContext(
    for session: EditorSession
) -> AutomationPlanningContext {
    AutomationPlanningContext(
        document: session.document,
        generation: session.generation,
        transactionRevision: session.transactionRevision,
        publicationSequence: 0,
        selection: session.selection,
        workspaceState: session.workspaceState,
        objectRegistry: session.objectRegistry,
        evaluationSnapshot: session.evaluationSnapshot,
        currentEvaluation: session.currentEvaluation
    )
}
