import Testing
import RupaCore
import RupaKit
import RupaProject
import RupaViewportScene
@testable import RupaUI

@Suite struct ModelingPreviewStateTests {
    @Test(.timeLimit(.minutes(1)))
    func modelingPreviewStateRejectsLateResultsAndConsumesApplyOnce() throws {
        let projectID = ProjectID(rawValue: "preview-state")
        let action = ProjectWorkspaceAction.source(try ProjectSourceTransaction(name: "Rename", commands: [.renameDocument(name: "Draft")], expectedProjectID: projectID, expectedTransactionRevision: DocumentTransactionRevision(), expectedPublicationSequence: 0))
        let payload = ProjectPreviewRenderPayload(
            document: .empty(),
            presentationScene: UniversalViewportScene(snapshotID: EvaluationSnapshotID(projectID: projectID, purpose: .presentation, sourceRevision: DocumentTransactionRevision()), projectID: projectID, items: []),
            presentationSceneNodeIDByOccurrenceID: [:]
        )
        var state = ModelingPreviewState()
        #expect(state.takeForApply() == nil)
        let stale = state.begin(.source(action))
        let current = state.begin(.source(action))
        state.complete(payload, token: stale)
        #expect(state.payload == nil)
        #expect(state.phase == .evaluating)
        state.complete(payload, token: current)
        #expect(state.phase == .ready)
        #expect(state.takeForApply() != nil)
        #expect(state.takeForApply() == nil)
        #expect(state.phase == .applying)
        state.invalidate()
        state.complete(payload, token: current)
        #expect(state.payload == nil)
        #expect(state.phase == .idle)
        let confirmed = state.beginConfirmedApply()
        #expect(state.phase == .applying)
        #expect(state.isBusy)
        #expect(state.takeForApply() == nil)
        state.complete(payload, token: confirmed)
        #expect(state.payload == nil)
    }
}
