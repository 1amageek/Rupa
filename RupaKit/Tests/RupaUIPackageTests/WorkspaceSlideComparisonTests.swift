import Foundation
import RupaCore
@testable import RupaKit
import Testing
@testable import RupaUI

/// Slide's Control toggle draws the project as it was when Slide started while Control is held,
/// and the current project otherwise.
@MainActor
@Test(.timeLimit(.minutes(1)))
func slideComparisonShowsTheProjectBeforeSlidingWhileControlIsHeld() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(document: session.document)
    _ = try await workspace.evaluate()
    let before = try #require(workspace.view)
    let after = ProjectViewSnapshot(
        documentLifetimeID: before.documentLifetimeID,
        projectID: before.projectID,
        projectName: before.projectName,
        document: before.document,
        documentGeneration: DocumentGeneration(before.documentGeneration.value + 1),
        transactionRevision: before.transactionRevision,
        publicationSequence: before.publicationSequence,
        isDirty: true,
        canUndo: true,
        canRedo: before.canRedo,
        selection: before.selection,
        workspaceState: before.workspaceState,
        objectRegistry: before.objectRegistry,
        evaluationSnapshot: before.evaluationSnapshot,
        viewport: before.viewport,
        cadInteraction: before.cadInteraction,
        sceneNodeIDByOccurrenceID: before.sceneNodeIDByOccurrenceID,
        retiredObjectProperties: before.retiredObjectProperties
    )

    var comparison = WorkspaceSlideComparison()
    // Control without Slide compares nothing.
    comparison.controlChanged(isHeld: true)
    #expect(!comparison.isComparing)
    #expect(comparison.displayed(after).documentGeneration == after.documentGeneration)

    comparison.controlChanged(isHeld: false)
    comparison.slideActivityChanged(isActive: true, current: before)
    #expect(comparison.displayed(after).documentGeneration == after.documentGeneration)
    comparison.controlChanged(isHeld: true)
    #expect(comparison.isComparing)
    #expect(comparison.displayed(after).documentGeneration == before.documentGeneration)
    comparison.controlChanged(isHeld: false)
    #expect(comparison.displayed(after).documentGeneration == after.documentGeneration)

    // Ending Slide drops the baseline and the held Control.
    comparison.controlChanged(isHeld: true)
    comparison.slideActivityChanged(isActive: false, current: after)
    #expect(!comparison.isComparing)
    #expect(comparison.baseline == nil)
    #expect(comparison.displayed(after).documentGeneration == after.documentGeneration)
}
