import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADLIN001Tests {

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin001CreatesExactSourceLineThroughProductionController() async throws {
    let result = try await CADLIN001CaseRunner().runReference()

    try result.validate()
    #expect(result.caseID == "LIN-001")
    #expect(result.outcome == .realized)
    #expect(result.realized)
    #expect(result.candidateResult?.status == .published)
    #expect(result.candidateResult?.createdFeatureIDs.count == 1)
    #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.first)
    #expect(result.roleBindings?.bindings.count == 1)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount >= 1)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 1)
    #expect(result.telemetry.bodyCount == 0)
    #expect(result.telemetry.cancellationCheckpointCount >= 1)
    #expect(result.telemetry.planningWallNanoseconds <= result.telemetry.totalWallNanoseconds)
    #expect(result.telemetry.routeWallNanoseconds <= result.telemetry.totalWallNanoseconds)
    #expect(result.telemetry.oracleWallNanoseconds <= result.telemetry.totalWallNanoseconds)
    print(
        "LIN-001 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
            + "route=\(result.telemetry.routeWallNanoseconds)ns "
            + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
            + "total=\(result.telemetry.totalWallNanoseconds)ns"
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin001OracleRejectsWrongPublishedGeometryWithoutRetry() async throws {
    let wrong = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-001.wrong-length",
        plane: .xy,
        start: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
        end: CADPoint3D(x: 30, y: 0, z: 0, unit: .millimeter)
    )))

    let result = try await CADLIN001CaseRunner().run(action: wrong)

    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.telemetry.readCount == 2)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 1)
    #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin001InvalidPrepublicationActionPublishesNothing() async throws {
    let invalid = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-001.invalid-plane",
        plane: .xz,
        start: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
        end: CADPoint3D(x: 25, y: 0, z: 0, unit: .millimeter)
    )))

    let result = try await CADLIN001CaseRunner().run(action: invalid)

    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.routeEvidence.initialPublicationSequence == result.routeEvidence.finalPublicationSequence)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 0)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin001StaleProductionCoordinatesPublishNothing() async throws {
    let result = try await CADLIN001CaseRunner().runStaleReference()

    try result.validate()
    #expect(result.outcome == .executionFailure)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.routeEvidence.initialPublicationSequence == result.routeEvidence.finalPublicationSequence)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin001CancellationBeforePlanningPublishesNothing() async throws {
    let task = Task { @MainActor in
        await Task.yield()
        return try await CADLIN001CaseRunner().runReference()
    }
    task.cancel()

    let result = try await task.value

    try result.validate()
    #expect(result.outcome == .cancellation)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin001TimeoutBeforePublicationIsTypedAndCleansUp() async throws {
    let result = try await CADLIN001CaseRunner(timeoutWallNanoseconds: 1).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin001SharedDeadlineTerminatesDelayedProductionRoute() async throws {
    let result = try await CADLIN001CaseRunner(
        timeoutWallNanoseconds: 500_000_000,
        preRouteDelayNanoseconds: 2_000_000_000
    ).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin001TimedOutRegistrationCleansLateEntry() async throws {
    let result = try await CADLIN001CaseRunner(
        timeoutWallNanoseconds: 500_000_000,
        postRegistrationDelayNanoseconds: 2_000_000_000
    ).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin001AdapterUsesFreshModelingToleranceForPlaneDistance() async throws {
    let withinTolerance = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-001.within-plane-tolerance",
        plane: .xy,
        start: CADPoint3D(x: 0, y: 0, z: 0.5e-6, unit: .meter),
        end: CADPoint3D(x: 0.025, y: 0, z: 0.5e-6, unit: .meter)
    )))
    let outsideTolerance = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-001.outside-plane-tolerance",
        plane: .xy,
        start: CADPoint3D(x: 0, y: 0, z: 2e-6, unit: .meter),
        end: CADPoint3D(x: 0.025, y: 0, z: 2e-6, unit: .meter)
    )))

    let accepted = try await CADLIN001CaseRunner().run(action: withinTolerance)
    let rejected = try await CADLIN001CaseRunner().run(action: outsideTolerance)

    try accepted.validate()
    try rejected.validate()
    #expect(accepted.outcome == .realized)
    #expect(rejected.outcome == .invalidSubmission)
    #expect(!rejected.routeEvidence.didPublish)
}

@MainActor
@Test
func lin001ReferenceCandidateUsesOnlyPublicContext() async throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "LIN-001")
    let context = CADCandidateContext(
        challenge: challenge,
        capabilities: CADCapabilitySnapshot(
            version: "test.v1",
            statuses: [CADCapabilityStatus(
                id: challenge.requiredCapability.id,
                version: challenge.requiredCapability.version,
                available: true
            )]
        ),
        remainingRounds: challenge.budget.maximumRounds,
        remainingActions: challenge.budget.maximumActions
    )
    let candidate: any CADCandidateProtocol = CADLIN001ReferenceCandidate()

    let decision = try await candidate.decide(for: context)

    guard case .action(.automation(.sketch(.line(_, let plane, let start, let end)))) = decision else {
        Issue.record("LIN-001 public context did not produce one line action.")
        return
    }
    #expect(plane == .xy)
    #expect(start == CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter))
    #expect(end == CADPoint3D(x: 25, y: 0, z: 0, unit: .millimeter))
}

@Test
func lin001RouteEvidenceRejectsMoreThanOnePublication() throws {
    let fabricated = CADLIN001RouteEvidence(
        initialDocumentGeneration: .init(1),
        finalDocumentGeneration: .init(3),
        initialTransactionRevision: .init(2),
        finalTransactionRevision: .init(4),
        initialPublicationSequence: 5,
        finalPublicationSequence: 7,
        initialWorkspaceRevision: .init(0),
        finalWorkspaceRevision: .init(0),
        didPublish: true,
        cleanupCompleted: true,
        cleanupWallNanoseconds: 1,
        remainingRegistrationCount: 0
    )

    do {
        try fabricated.validate()
        Issue.record("LIN-001 route evidence must reject more than one publication.")
    } catch let error as CADBenchmarkError {
        guard case .invalidInput = error else {
            Issue.record("Unexpected typed error: \(error)")
            return
        }
    }
}

}
