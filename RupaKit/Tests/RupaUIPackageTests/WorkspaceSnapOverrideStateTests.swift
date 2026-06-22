import RupaCore
import RupaRendering
import Testing
@testable import RupaUI

@Test func workspaceSnapOverrideStateBypassesHoveredCandidateKind() {
    var state = WorkspaceSnapOverrideState()

    let emptyBypassStarted = state.beginCandidateKindBypass()
    #expect(!emptyBypassStarted)
    #expect(state.suppressedCandidateKinds.isEmpty)

    state.updateHoveredCandidateKind(.lineEnd)
    let lineBypassStarted = state.beginCandidateKindBypass()
    #expect(lineBypassStarted)
    #expect(state.suppressedCandidateKinds == [.lineEnd])

    state.updateHoveredCandidateKind(.circleCenter)
    let circleBypassStarted = state.beginCandidateKindBypass()
    #expect(circleBypassStarted)
    #expect(state.suppressedCandidateKinds == [.lineEnd, .circleCenter])

    let duplicateBypassStarted = state.beginCandidateKindBypass()
    #expect(!duplicateBypassStarted)
    #expect(state.suppressedCandidateKinds == [.lineEnd, .circleCenter])

    state.endCandidateKindBypass()
    #expect(state.suppressedCandidateKinds.isEmpty)
}

@Test func workspaceSnapOverrideStateMapsControlModifierToObjectTargetingOverride() {
    let state = WorkspaceSnapOverrideState()

    #expect(
        state.objectTargetingOverride(
            for: ViewportInputModifierFlags(containsControl: true)
        ) == .forceEnabled
    )
    #expect(
        state.objectTargetingOverride(
            for: ViewportInputModifierFlags()
        ) == .none
    )
}
