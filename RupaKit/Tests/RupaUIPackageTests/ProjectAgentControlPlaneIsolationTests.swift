import Foundation
import RupaAgentProtocol
@testable import RupaAgentRuntime
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaKit
import RupaProject
import RupaProjectModel
import Synchronization
import Testing

// MARK: - Control-plane isolation

/// Proves the Agent control plane answers while `MainActor` cannot run anything
/// else.
///
/// The test is deliberately not `MainActor`-isolated: an isolated test could
/// never observe the occupation it needs to assert against, because it would be
/// waiting behind it.
@Test(.timeLimit(.minutes(1)))
func agentControlPlaneAnswersCapabilityAndStatusWhileMainActorIsOccupied() async throws {
    let workspace = try await controlPlaneWorkspace(named: "Occupied Main Actor")
    let controller = ProjectAgentCommandController(
        semanticProgramCompiler: try projectAgentSemanticCompiler()
    )
    let sessionID = try await controller.register(workspace: workspace)

    // Warm up so lazy registry construction is not charged to a measured call.
    _ = await controller.projectAgentHandle(.capabilities)
    _ = await controller.projectAgentHandle(.capabilityRegistry)
    _ = await controller.projectAgentHandle(.status)

    let clock = ContinuousClock()
    let occupation = await occupyMainActor(for: .milliseconds(1500), clock: clock)

    let capabilities = await controller.projectAgentHandle(.capabilities)
    let registry = await controller.projectAgentHandle(.capabilityRegistry)
    let status = await controller.projectAgentHandle(.status)
    let completionInstant = clock.now

    // Nothing else can run on `MainActor` before the release instant, so a
    // response observed earlier cannot have waited for it.
    #expect(completionInstant < occupation.releaseInstant)

    guard case .capabilities(let descriptors) = capabilities else {
        Issue.record("Expected a capability response while MainActor was occupied.")
        return
    }
    #expect(descriptors.isEmpty == false)

    guard case .capabilityRegistry = registry else {
        Issue.record("Expected a capability registry response while MainActor was occupied.")
        return
    }

    guard case .status(let value) = status else {
        Issue.record("Expected a status response while MainActor was occupied.")
        return
    }
    #expect(value.running)
    #expect(value.sessionCount == 1)

    await occupation.task.value
    await controller.unregister(id: sessionID)
}

/// Proves one immutable project read stays inside its bound while `MainActor`
/// is under continuous frame-sized load.
///
/// The load is modelled as uninterrupted `MainActor` slices separated by
/// yields, not as a preparing render plan. Plan construction runs in a detached
/// task, so a preparing plan charges `MainActor` only its publication slice;
/// occupying every frame is therefore a strict superset of the contention the
/// product produces, and a read that stays in bounds here stays in bounds
/// there.
@Test(.timeLimit(.minutes(1)))
func anImmutableProjectReadCompletesUnderContinuousMainActorFrameLoad() async throws {
    let workspace = try await controlPlaneWorkspace(named: "Immutable Read Under Load")
    let controller = ProjectAgentCommandController(
        semanticProgramCompiler: try projectAgentSemanticCompiler()
    )
    let sessionID = try await controller.register(workspace: workspace)
    _ = await controller.projectAgentHandle(.sessions)

    let clock = ContinuousClock()
    let load = await loadMainActorWithFrameSlices(
        for: .seconds(2),
        slice: .milliseconds(16),
        clock: clock
    )

    let start = clock.now
    let response = await controller.projectAgentHandle(.sessions)
    let elapsed = clock.now - start

    load.cancel()
    await load.value

    guard case .sessions(let summaries) = response else {
        Issue.record("Expected a session listing under MainActor load.")
        return
    }
    #expect(summaries.count == 1)
    #expect(summaries.first?.id == sessionID)

    // The immutable-read acceptance row rejects beyond two seconds.
    #expect(elapsed < .seconds(2))

    await controller.unregister(id: sessionID)
}

// MARK: - Registration lifetime

/// Proves an accepted lease delays only the registration that issued it.
@Test(.timeLimit(.minutes(1)))
func unregisterWaitsOnlyForItsOwnAcceptedLeases() async throws {
    let registry = ProjectWorkspaceRegistry()
    let leased = try await controlPlaneWorkspace(named: "Leased Session")
    let independent = try await controlPlaneWorkspace(named: "Independent Session")
    let leasedID = try await registry.register(workspace: leased)
    let independentID = try await registry.register(workspace: independent)

    let lease = try await registry.lease(id: leasedID)

    // An unrelated registration is invalidated without waiting for this lease.
    await registry.unregister(id: independentID)
    let remainingAfterIndependent = await registry.registeredCount()
    #expect(remainingAfterIndependent == 1)

    let clock = ContinuousClock()
    let unregisterTask = Task {
        await registry.unregister(id: leasedID)
        return clock.now
    }
    try await Task.sleep(for: .milliseconds(200))

    let finishInstant = clock.now
    lease.operation.finish()
    let completionInstant = await unregisterTask.value

    // The invalidation resumed after the lease finished, not before it.
    #expect(completionInstant > finishInstant)
    let remaining = await registry.registeredCount()
    #expect(remaining == 0)
    withExtendedLifetime(lease) {}
}

/// Proves a registration invalidated during a workspace hop is rejected on
/// resume and is not written back by the call that was suspended.
@Test(.timeLimit(.minutes(1)))
func aWorkspaceHopFollowedByRegistrationInvalidationIsRejected() async throws {
    let registry = ProjectWorkspaceRegistry()
    let workspace = try await controlPlaneWorkspace(named: "Invalidated During Hop")
    let sessionID = try await registry.register(workspace: workspace)

    let clock = ContinuousClock()
    let occupation = await occupyMainActor(for: .milliseconds(800), clock: clock)

    // The summary suspends inside the registry on its workspace hop, which
    // releases the actor and lets the invalidation run before it resumes.
    let summaryTask = Task { try await registry.summary(id: sessionID) }
    try await Task.sleep(for: .milliseconds(100))
    await registry.unregister(id: sessionID)

    do {
        _ = try await summaryTask.value
        Issue.record("Expected the invalidated registration to reject its pending hop.")
    } catch let error as EditorError {
        #expect(error.code == .sessionNotFound)
    }

    await occupation.task.value

    let remaining = await registry.registeredCount()
    #expect(remaining == 0)

    // The rejected call must not have written its captured entry back, so the
    // identifier is free again.
    let reregisteredID = try await registry.register(workspace: workspace, id: sessionID)
    #expect(reregisteredID == sessionID)
}

// MARK: - Support

@MainActor
private func controlPlaneWorkspace(named name: String) async throws -> ProjectWorkspace {
    let project = try ProjectController(
        document: .empty(named: name),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: project)
    _ = try await workspace.evaluate()
    return workspace
}

private struct MainActorOccupation {
    let releaseInstant: ContinuousClock.Instant
    let task: Task<Void, Never>
}

/// Occupies `MainActor` with one uninterrupted busy loop and returns only after
/// that loop is running, together with the instant it releases.
private func occupyMainActor(
    for duration: Duration,
    clock: ContinuousClock
) async -> MainActorOccupation {
    let releaseInstant = Mutex<ContinuousClock.Instant?>(nil)
    let task = Task { @MainActor in
        let deadline = clock.now.advanced(by: duration)
        // Published before the loop begins, so observing it proves the task is
        // already executing on MainActor.
        releaseInstant.withLock { $0 = deadline }
        while clock.now < deadline {
            continue
        }
    }
    while true {
        if let instant = releaseInstant.withLock({ $0 }) {
            return MainActorOccupation(releaseInstant: instant, task: task)
        }
        await Task.yield()
    }
}

/// Loads `MainActor` with uninterrupted frame-sized slices separated by yields,
/// and returns only after the load is running.
private func loadMainActorWithFrameSlices(
    for duration: Duration,
    slice: Duration,
    clock: ContinuousClock
) async -> Task<Void, Never> {
    let started = Mutex(false)
    let task = Task { @MainActor in
        let end = clock.now.advanced(by: duration)
        started.withLock { $0 = true }
        while clock.now < end, !Task.isCancelled {
            let sliceEnd = clock.now.advanced(by: slice)
            while clock.now < sliceEnd {
                continue
            }
            await Task.yield()
        }
    }
    while started.withLock({ $0 }) == false {
        await Task.yield()
    }
    return task
}
