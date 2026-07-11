import SwiftCAD
import Testing
import RupaCore
@testable import RupaAutomation

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationBatchResolvesHomogeneousEffects() async throws {
    #expect(try AutomationBatch(commands: []).validatedEffect() == .readOnly)
    #expect(
        try AutomationBatch(
            commands: [.describeDocument, .validateDocument]
        ).validatedEffect() == .readOnly
    )
    #expect(
        try AutomationBatch(
            commands: [.describeDocument, .renameDocument(name: "Source")]
        ).validatedEffect() == .sourceMutation
    )
    #expect(
        try AutomationBatch(
            commands: [.describeDocument, .setDisplayUnit(.meter)]
        ).validatedEffect() == .workspaceMutation
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationBatchRejectsMixedMutationEffectsBeforePublication() async throws {
    let session = EditorSession(document: .empty(named: "Before"))
    let originalStore = session.store
    let originalCommandStack = session.commandStack
    var caught: EditorError?

    do {
        _ = try AutomationRunner().executeBatch(
            AutomationBatch(
                commands: [
                    .renameDocument(name: "Never Committed"),
                    .setDisplayUnit(.meter),
                ]
            ),
            in: session
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(caught?.message.contains("cannot mix") == true)
    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.workspaceState.displayUnit == .millimeter)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.workspaceState.revision == WorkspaceRevision(0))
    #expect(session.store === originalStore)
    #expect(session.commandStack === originalCommandStack)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationWorkspaceBatchCommitsAtomicallyWithoutDirtyingSource() async throws {
    let session = EditorSession()
    let originalStore = session.store
    let originalCommandStack = session.commandStack
    let batch = AutomationBatch(
        commands: [
            .setDisplayUnit(.meter),
            .describeDocument,
            .setViewportGridSettings(
                ViewportGridSettings(visualSpacingMode: .fixed)
            ),
        ],
        expectedGeneration: DocumentGeneration(0),
        expectedWorkspaceRevision: WorkspaceRevision(0)
    )

    let execution = try AutomationRunner().executeBatchTransaction(
        batch,
        in: session,
        commits: true
    )

    #expect(execution.effect == .workspaceMutation)
    #expect(execution.baseGeneration == DocumentGeneration(0))
    #expect(execution.proposedGeneration == DocumentGeneration(0))
    #expect(execution.baseWorkspaceRevision == WorkspaceRevision(0))
    #expect(execution.proposedWorkspaceRevision == WorkspaceRevision(2))
    #expect(execution.didCommit)
    #expect(execution.results.map(\.effect) == [.workspaceMutation, .readOnly, .workspaceMutation])
    #expect(execution.results[1].message.contains("m display units"))
    #expect(session.workspaceState.displayUnit == .meter)
    #expect(session.workspaceState.viewportGridSettings.visualSpacingMode == .fixed)
    #expect(session.workspaceState.revision == WorkspaceRevision(2))
    #expect(session.generation == DocumentGeneration(0))
    #expect(!session.isDirty)
    #expect(session.commandStack.undoEntries.isEmpty)
    #expect(session.store === originalStore)
    #expect(session.commandStack === originalCommandStack)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationWorkspaceBatchDryRunReturnsProposalWithoutPublication() async throws {
    let session = EditorSession()
    let execution = try AutomationRunner().executeBatchTransaction(
        AutomationBatch(
            commands: [
                .setDisplayUnit(.meter),
                .setViewportGridSettings(
                    ViewportGridSettings(visualSpacingMode: .fixed)
                ),
            ]
        ),
        in: session,
        commits: false
    )

    #expect(execution.effect == .workspaceMutation)
    #expect(execution.proposedWorkspaceRevision == WorkspaceRevision(2))
    #expect(!execution.didCommit)
    #expect(execution.results.last?.workspaceRevision == WorkspaceRevision(2))
    #expect(session.workspaceState.displayUnit == .millimeter)
    #expect(session.workspaceState.viewportGridSettings == .standard)
    #expect(session.workspaceState.revision == WorkspaceRevision(0))
    #expect(session.generation == DocumentGeneration(0))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationWorkspaceBatchFailureRollsBackEveryCommand() async throws {
    let session = EditorSession()
    var caught: EditorError?

    do {
        _ = try AutomationRunner().executeBatch(
            AutomationBatch(
                commands: [
                    .setDisplayUnit(.meter),
                    .setActiveConstructionPlane(id: ConstructionPlaneSourceID()),
                ]
            ),
            in: session
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .referenceUnresolved)
    #expect(session.workspaceState.displayUnit == .millimeter)
    #expect(session.workspaceState.activeConstructionPlaneID == nil)
    #expect(session.workspaceState.revision == WorkspaceRevision(0))
    #expect(session.generation == DocumentGeneration(0))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationBatchRejectsStaleWorkspaceRevision() async throws {
    let session = EditorSession()
    _ = try AutomationRunner().execute(.setDisplayUnit(.meter), in: session)
    var caught: EditorError?

    do {
        _ = try AutomationRunner().executeBatch(
            AutomationBatch(
                commands: [.setViewportGridSettings(.standard)],
                expectedGeneration: DocumentGeneration(0),
                expectedWorkspaceRevision: WorkspaceRevision(0)
            ),
            in: session
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .workspaceRevisionMismatch)
    #expect(session.workspaceState.revision == WorkspaceRevision(1))
    #expect(session.generation == DocumentGeneration(0))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationSourceBatchDryRunDoesNotPublishSource() async throws {
    let session = EditorSession(document: .empty(named: "Before"))
    let execution = try AutomationRunner().executeBatchTransaction(
        AutomationBatch(
            commands: [
                .renameDocument(name: "Proposed"),
                .validateDocument,
            ]
        ),
        in: session,
        commits: false
    )

    #expect(execution.effect == .sourceMutation)
    #expect(execution.baseGeneration == DocumentGeneration(0))
    #expect(execution.proposedGeneration == DocumentGeneration(1))
    #expect(!execution.didCommit)
    #expect(execution.results.map(\.effect) == [.sourceMutation, .readOnly])
    #expect(execution.metrics.commandCount == 2)
    #expect(execution.metrics.evaluationPassCount == 1)
    #expect(execution.metrics.historyEntryCount == 1)
    #expect(execution.metrics.richResultCount == 0)
    #expect(execution.metrics.modelingEvaluation == nil)
    #expect(execution.results.first?.workspaceScale == nil)
    #expect(execution.results.last?.workspaceScale == nil)
    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.undoEntries.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationReadOnlyBatchDoesNotPublishEvaluationState() async throws {
    let session = EditorSession()
    let originalStore = session.store
    let execution = try AutomationRunner().executeBatchTransaction(
        AutomationBatch(commands: [.validateDocument, .describeDocument]),
        in: session,
        commits: true
    )

    #expect(execution.effect == .readOnly)
    #expect(!execution.didCommit)
    #expect(execution.baseGeneration == execution.proposedGeneration)
    #expect(execution.baseWorkspaceRevision == execution.proposedWorkspaceRevision)
    #expect(execution.results.allSatisfy { $0.effect == .readOnly })
    #expect(execution.metrics.commandCount == 2)
    #expect(execution.metrics.evaluationPassCount == 1)
    #expect(execution.metrics.historyEntryCount == 0)
    #expect(execution.metrics.richResultCount == 1)
    #expect(session.store === originalStore)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.workspaceState.revision == WorkspaceRevision(0))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationSourceBatchBuildsMultipleBodiesWithOneEvaluation() async throws {
    let session = EditorSession()
    let commands = (0..<8).map { index in
        AutomationCommand.createExtrudedRectangle(
            name: "Body \(index)",
            plane: .xy,
            width: .length(Double(index + 1) * 0.01, .meter),
            height: .length(0.02, .meter),
            depth: .length(0.03, .meter),
            direction: .normal
        )
    }

    let execution = try AutomationRunner().executeBatchTransaction(
        AutomationBatch(
            commands: commands,
            expectedGeneration: DocumentGeneration()
        ),
        in: session,
        commits: true
    )

    #expect(execution.results.count == 8)
    #expect(execution.metrics.commandCount == 8)
    #expect(execution.metrics.evaluationPassCount == 1)
    #expect(execution.metrics.historyEntryCount == 1)
    #expect(execution.metrics.richResultCount == 0)
    let modelingEvaluation = try #require(execution.metrics.modelingEvaluation)
    #expect(modelingEvaluation.totalFeatureCount == 16)
    #expect(modelingEvaluation.rebuiltFeatureCount == 16)
    #expect(modelingEvaluation.reusedFeatureCount == 0)
    #expect(modelingEvaluation.tessellatedBodyCount == 8)
    #expect(modelingEvaluation.reusedMeshCount == 0)
    #expect(execution.results.allSatisfy { !$0.createdFeatureIDs.isEmpty })
    #expect(execution.results.allSatisfy { $0.workspaceScale == nil })
    #expect(session.evaluatedBodyCount == 8)
    #expect(session.commandStack.undoEntries.count == 1)
}

@Test(.timeLimit(.minutes(1)))
func automationBatchRequiresWorkspaceContextQueryToBeFinal() {
    #expect(throws: EditorError.self) {
        try AutomationBatch(
            commands: [.describeDocument, .validateDocument]
        ).validatedEffect()
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationSourceBatchAddsWorkspaceContextOnlyWhenExplicitlyRequested() throws {
    let session = EditorSession(document: .empty(named: "Before"))

    let execution = try AutomationRunner().executeBatchTransaction(
        AutomationBatch(
            commands: [
                .renameDocument(name: "After"),
                .describeDocument,
            ]
        ),
        in: session,
        commits: true
    )

    #expect(execution.effect == .sourceMutation)
    #expect(execution.metrics.richResultCount == 1)
    #expect(execution.results.first?.workspaceScale == nil)
    #expect(execution.results.last?.workspaceScale != nil)
    #expect(session.document.cadDocument.metadata.name == "After")
}
