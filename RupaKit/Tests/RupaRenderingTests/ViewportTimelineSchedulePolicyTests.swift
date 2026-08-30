import Foundation
import Testing
@testable import RupaRendering

@Test(.timeLimit(.minutes(1)))
func viewportTimelineSchedulePausesWithoutProjectionTransition() {
    let policy = ViewportTimelineSchedulePolicy(
        projectionTransition: nil
    )

    #expect(policy.isPaused)
}

@Test(.timeLimit(.minutes(1)))
func viewportTimelineScheduleRunsWithProjectionTransition() {
    let startDate = Date(timeIntervalSinceReferenceDate: 100.0)
    let transition = ViewportProjectionTransition(
        startBasis: .axisFront(.x),
        targetBasis: .axisFront(.y),
        startDate: startDate,
        duration: 0.34
    )
    let policy = ViewportTimelineSchedulePolicy(
        projectionTransition: transition
    )

    #expect(!policy.isPaused)
}

@Test(.timeLimit(.minutes(1)))
func viewportTimelineSchedulePausesAfterProjectionTransitionClears() {
    let startDate = Date(timeIntervalSinceReferenceDate: 100.0)
    var transition: ViewportProjectionTransition? = ViewportProjectionTransition(
        startBasis: .axisFront(.x),
        targetBasis: .axisFront(.y),
        startDate: startDate,
        duration: 0.34
    )
    transition = nil
    let policy = ViewportTimelineSchedulePolicy(projectionTransition: transition)

    #expect(policy.isPaused)
}

@Test(.timeLimit(.minutes(1)))
func viewportTimelineProjectionBasisAdvancesDuringTransition() {
    let startDate = Date(timeIntervalSinceReferenceDate: 100.0)
    let transition = ViewportProjectionTransition(
        startBasis: .axisFront(.x),
        targetBasis: .axisFront(.y),
        startDate: startDate,
        duration: 0.34
    )
    let activeBasis = transition.basis(at: startDate.addingTimeInterval(0.17))

    #expect(activeBasis != transition.startBasis)
    #expect(activeBasis != transition.targetBasis)
}

@Test(.timeLimit(.minutes(1)))
func viewportTimelineProjectionBasisCompletesTransition() {
    let startDate = Date(timeIntervalSinceReferenceDate: 100.0)
    let transition = ViewportProjectionTransition(
        startBasis: .axisFront(.x),
        targetBasis: .axisFront(.y),
        startDate: startDate,
        duration: 0.34
    )
    let completionDate = startDate.addingTimeInterval(transition.duration)
    let completedBasis = transition.basis(at: completionDate)

    expectProjectionBasis(completedBasis, approximatelyEquals: transition.targetBasis)
}

private func expectProjectionBasis(
    _ actual: ViewportProjectionBasis,
    approximatelyEquals expected: ViewportProjectionBasis,
    tolerance: CGFloat = 1.0e-12
) {
    #expect(actual.mode == expected.mode)
    #expect(abs(actual.xDirection.dx - expected.xDirection.dx) <= tolerance)
    #expect(abs(actual.xDirection.dy - expected.xDirection.dy) <= tolerance)
    #expect(abs(actual.yDirection.dx - expected.yDirection.dx) <= tolerance)
    #expect(abs(actual.yDirection.dy - expected.yDirection.dy) <= tolerance)
    #expect(abs(actual.zDirection.dx - expected.zDirection.dx) <= tolerance)
    #expect(abs(actual.zDirection.dy - expected.zDirection.dy) <= tolerance)
}
