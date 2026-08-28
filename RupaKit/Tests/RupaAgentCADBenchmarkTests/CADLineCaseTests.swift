import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADLineCaseTests {

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin001CreatesExactSourceLineThroughProductionController() async throws {
    let result = try await CADLineCaseRunner(case: .lin001).runReference()

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

    let result = try await CADLineCaseRunner(case: .lin001).run(action: wrong)

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

    let result = try await CADLineCaseRunner(case: .lin001).run(action: invalid)

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
    let result = try await CADLineCaseRunner(case: .lin001).runStaleReference()

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
        return try await CADLineCaseRunner(case: .lin001).runReference()
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
    let result = try await CADLineCaseRunner(
        case: .lin001,
        timeoutWallNanoseconds: 1
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
func lin001SharedDeadlineTerminatesDelayedProductionRoute() async throws {
    let result = try await CADLineCaseRunner(
        case: .lin001,
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
    let result = try await CADLineCaseRunner(
        case: .lin001,
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

    let accepted = try await CADLineCaseRunner(case: .lin001).run(action: withinTolerance)
    let rejected = try await CADLineCaseRunner(case: .lin001).run(action: outsideTolerance)

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
    let candidate: any CADCandidateProtocol = CADLineReferenceCandidate()

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
    let fabricated = CADLineRouteEvidence(
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
        try fabricated.validate(caseID: "LIN-001")
        Issue.record("LIN-001 route evidence must reject more than one publication.")
    } catch let error as CADBenchmarkError {
        guard case .invalidInput = error else {
            Issue.record("Unexpected typed error: \(error)")
            return
        }
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin002CreatesExactTranslatedVerticalLineThroughProductionController() async throws {
    let result = try await CADLineCaseRunner(case: .lin002).runReference()

    try result.validate()
    #expect(result.caseID == "LIN-002")
    #expect(result.outcome == .realized)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount >= 1)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 1)
    #expect(result.telemetry.bodyCount == 0)
    print(
        "LIN-002 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
            + "route=\(result.telemetry.routeWallNanoseconds)ns "
            + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
            + "total=\(result.telemetry.totalWallNanoseconds)ns"
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin002OracleRejectsReversedPublishedEndpointsWithoutRetry() async throws {
    let reversed = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-002.reversed",
        plane: .xy,
        start: CADPoint3D(x: 10, y: 40, z: 0, unit: .millimeter),
        end: CADPoint3D(x: 10, y: -10, z: 0, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin002).run(action: reversed)

    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount == 2)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin002RejectsOffPlaneInputBeforePublication() async throws {
    let offPlane = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-002.off-plane",
        plane: .xy,
        start: CADPoint3D(x: 10, y: -10, z: 2, unit: .millimeter),
        end: CADPoint3D(x: 10, y: 40, z: 2, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin002).run(action: offPlane)

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
func lin002TimeoutIsTypedAndCleansUp() async throws {
    let result = try await CADLineCaseRunner(
        case: .lin002,
        timeoutWallNanoseconds: 1
    ).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test
func lin002ReferenceCandidateUsesOnlyPublicContext() async throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "LIN-002")
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
    let candidate: any CADCandidateProtocol = CADLineReferenceCandidate()

    let decision = try await candidate.decide(for: context)

    guard case .action(.automation(.sketch(.line(_, let plane, let start, let end)))) = decision else {
        Issue.record("LIN-002 public context did not produce one line action.")
        return
    }
    #expect(plane == .xy)
    #expect(start == CADPoint3D(x: 10, y: -10, z: 0, unit: .millimeter))
    #expect(end == CADPoint3D(x: 10, y: 40, z: 0, unit: .millimeter))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin003CreatesExactHorizontalLineThroughProductionController() async throws {
    let result = try await CADLineCaseRunner(case: .lin003).runReference()

    try result.validate()
    #expect(result.caseID == "LIN-003")
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
        "LIN-003 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
            + "route=\(result.telemetry.routeWallNanoseconds)ns "
            + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
            + "total=\(result.telemetry.totalWallNanoseconds)ns"
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin003OracleRejectsReversedPublishedEndpointsWithoutRetry() async throws {
    let reversed = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-003.reversed",
        plane: .xy,
        start: CADPoint3D(x: 30, y: 15, z: 0, unit: .millimeter),
        end: CADPoint3D(x: -30, y: 15, z: 0, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin003).run(action: reversed)

    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.candidateResult?.status == .published)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount == 2)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 1)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin003RejectsOffPlaneInputBeforePublication() async throws {
    let offPlane = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-003.off-plane",
        plane: .xy,
        start: CADPoint3D(x: -30, y: 15, z: 2, unit: .millimeter),
        end: CADPoint3D(x: 30, y: 15, z: 2, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin003).run(action: offPlane)

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
func lin003TimeoutIsTypedAndCleansUp() async throws {
    let result = try await CADLineCaseRunner(
        case: .lin003,
        timeoutWallNanoseconds: 1
    ).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test
func lin003ReferenceCandidateUsesOnlyPublicContext() async throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "LIN-003")
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
    let candidate: any CADCandidateProtocol = CADLineReferenceCandidate()

    let decision = try await candidate.decide(for: context)

    guard case .action(.automation(.sketch(.line(_, let plane, let start, let end)))) = decision else {
        Issue.record("LIN-003 public context did not produce one line action.")
        return
    }
    #expect(plane == .xy)
    #expect(start == CADPoint3D(x: -30, y: 15, z: 0, unit: .millimeter))
    #expect(end == CADPoint3D(x: 30, y: 15, z: 0, unit: .millimeter))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin004CreatesExactXZLineThroughProductionController() async throws {
    let result = try await CADLineCaseRunner(case: .lin004).runReference()

    try result.validate()
    #expect(result.caseID == "LIN-004")
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
        "LIN-004 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
            + "route=\(result.telemetry.routeWallNanoseconds)ns "
            + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
            + "total=\(result.telemetry.totalWallNanoseconds)ns"
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin004OracleRejectsReversedPublishedEndpointsWithoutRetry() async throws {
    let reversed = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-004.reversed",
        plane: .xz,
        start: CADPoint3D(x: 0, y: 0, z: 100, unit: .millimeter),
        end: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin004).run(action: reversed)

    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.candidateResult?.status == .published)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount == 2)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 1)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin004RejectsOffXZPlaneInputBeforePublication() async throws {
    let offPlane = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-004.off-plane",
        plane: .xz,
        start: CADPoint3D(x: 0, y: 2, z: 0, unit: .millimeter),
        end: CADPoint3D(x: 0, y: 2, z: 100, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin004).run(action: offPlane)

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
func lin004TimeoutIsTypedAndCleansUp() async throws {
    let result = try await CADLineCaseRunner(
        case: .lin004,
        timeoutWallNanoseconds: 1
    ).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test
func lin004ReferenceCandidateUsesOnlyPublicContext() async throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "LIN-004")
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
    let candidate: any CADCandidateProtocol = CADLineReferenceCandidate()

    let decision = try await candidate.decide(for: context)

    guard case .action(.automation(.sketch(.line(_, let plane, let start, let end)))) = decision else {
        Issue.record("LIN-004 public context did not produce one line action.")
        return
    }
    #expect(plane == .xz)
    #expect(start == CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter))
    #expect(end == CADPoint3D(x: 0, y: 0, z: 100, unit: .millimeter))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin005CreatesExactYZWorldLineThroughProductionController() async throws {
    let result = try await CADLineCaseRunner(case: .lin005).runReference()

    try result.validate()
    #expect(result.caseID == "LIN-005")
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
        "LIN-005 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
            + "route=\(result.telemetry.routeWallNanoseconds)ns "
            + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
            + "total=\(result.telemetry.totalWallNanoseconds)ns"
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin005OracleRejectsReversedPublishedEndpointsWithoutRetry() async throws {
    let reversed = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-005.reversed",
        plane: .yz,
        start: CADPoint3D(x: 0, y: 170, z: 0, unit: .millimeter),
        end: CADPoint3D(x: 0, y: 20, z: 0, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin005).run(action: reversed)

    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.candidateResult?.status == .published)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount == 2)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 1)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin005RejectsOffYZPlaneInputBeforePublication() async throws {
    let offPlane = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-005.off-plane",
        plane: .yz,
        start: CADPoint3D(x: 2, y: 20, z: 0, unit: .millimeter),
        end: CADPoint3D(x: 2, y: 170, z: 0, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin005).run(action: offPlane)

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
func lin005TimeoutIsTypedAndCleansUp() async throws {
    let result = try await CADLineCaseRunner(
        case: .lin005,
        timeoutWallNanoseconds: 1
    ).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test
func lin005ReferenceCandidateUsesOnlyPublicContext() async throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "LIN-005")
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
    let candidate: any CADCandidateProtocol = CADLineReferenceCandidate()

    let decision = try await candidate.decide(for: context)

    guard case .action(.automation(.sketch(.line(_, let plane, let start, let end)))) = decision else {
        Issue.record("LIN-005 public context did not produce one line action.")
        return
    }
    #expect(plane == .yz)
    #expect(start == CADPoint3D(x: 0, y: 20, z: 0, unit: .millimeter))
    #expect(end == CADPoint3D(x: 0, y: 170, z: 0, unit: .millimeter))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin006CreatesExactXYDiagonalWorldLineThroughProductionController() async throws {
    let result = try await CADLineCaseRunner(case: .lin006).runReference()

    try result.validate()
    #expect(result.caseID == "LIN-006")
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
        "LIN-006 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
            + "route=\(result.telemetry.routeWallNanoseconds)ns "
            + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
            + "total=\(result.telemetry.totalWallNanoseconds)ns"
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin006OracleRejectsSameLengthWrongDirectionWithoutRetry() async throws {
    let wrongDirection = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-006.same-length-wrong-direction",
        plane: .xy,
        start: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
        end: CADPoint3D(x: 40, y: 30, z: 0, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin006).run(action: wrongDirection)

    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.candidateResult?.status == .published)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount == 2)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 1)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin006RejectsOffXYPlaneInputBeforePublication() async throws {
    let offPlane = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-006.off-plane",
        plane: .xy,
        start: CADPoint3D(x: 0, y: 0, z: 2, unit: .millimeter),
        end: CADPoint3D(x: 30, y: 40, z: 2, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin006).run(action: offPlane)

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
func lin006TimeoutIsTypedAndCleansUp() async throws {
    let result = try await CADLineCaseRunner(
        case: .lin006,
        timeoutWallNanoseconds: 1
    ).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test
func lin006ReferenceCandidateUsesOnlyPublicContext() async throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "LIN-006")
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
    let candidate: any CADCandidateProtocol = CADLineReferenceCandidate()

    let decision = try await candidate.decide(for: context)

    guard case .action(.automation(.sketch(.line(_, let plane, let start, let end)))) = decision else {
        Issue.record("LIN-006 public context did not produce one line action.")
        return
    }
    #expect(plane == .xy)
    #expect(start == CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter))
    #expect(end == CADPoint3D(x: 30, y: 40, z: 0, unit: .millimeter))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin007CreatesExactReverseWorldXLineThroughProductionController() async throws {
    let result = try await CADLineCaseRunner(case: .lin007).runReference()

    try result.validate()
    #expect(result.caseID == "LIN-007")
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
        "LIN-007 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
            + "route=\(result.telemetry.routeWallNanoseconds)ns "
            + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
            + "total=\(result.telemetry.totalWallNanoseconds)ns"
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin007OracleRejectsWrongForwardEndpointOrderWithoutRetry() async throws {
    let wrongOrder = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-007.wrong-forward-order",
        plane: .xy,
        start: CADPoint3D(x: -40, y: 20, z: 0, unit: .millimeter),
        end: CADPoint3D(x: 40, y: 20, z: 0, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin007).run(action: wrongOrder)

    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.candidateResult?.status == .published)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount == 2)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 1)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin007RejectsOffXYPlaneInputBeforePublication() async throws {
    let offPlane = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-007.off-plane",
        plane: .xy,
        start: CADPoint3D(x: 40, y: 20, z: 2, unit: .millimeter),
        end: CADPoint3D(x: -40, y: 20, z: 2, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin007).run(action: offPlane)

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
func lin007TimeoutIsTypedAndCleansUp() async throws {
    let result = try await CADLineCaseRunner(
        case: .lin007,
        timeoutWallNanoseconds: 1
    ).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test
func lin007ReferenceCandidateUsesOnlyPublicContext() async throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "LIN-007")
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
    let candidate: any CADCandidateProtocol = CADLineReferenceCandidate()

    let decision = try await candidate.decide(for: context)

    guard case .action(.automation(.sketch(.line(_, let plane, let start, let end)))) = decision else {
        Issue.record("LIN-007 public context did not produce one line action.")
        return
    }
    #expect(plane == .xy)
    #expect(start == CADPoint3D(x: 40, y: 20, z: 0, unit: .millimeter))
    #expect(end == CADPoint3D(x: -40, y: 20, z: 0, unit: .millimeter))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin008CreatesExactCentimeterXYLineThroughProductionController() async throws {
    let result = try await CADLineCaseRunner(case: .lin008).runReference()

    try result.validate()
    #expect(result.caseID == "LIN-008")
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
        "LIN-008 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
            + "route=\(result.telemetry.routeWallNanoseconds)ns "
            + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
            + "total=\(result.telemetry.totalWallNanoseconds)ns"
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin008OracleRejectsMillimeterValuesForCentimeterCoordinatesWithoutRetry() async throws {
    let wrongScale = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-008.same-numeric-values-millimeter",
        plane: .xy,
        start: CADPoint3D(x: -20, y: -20, z: 0, unit: .millimeter),
        end: CADPoint3D(x: 105, y: -20, z: 0, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin008).run(action: wrongScale)

    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.candidateResult?.status == .published)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount == 2)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 1)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin008RejectsOffXYPlaneInputBeforePublication() async throws {
    let offPlane = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-008.off-plane",
        plane: .xy,
        start: CADPoint3D(x: -20, y: -20, z: 1, unit: .centimeter),
        end: CADPoint3D(x: 105, y: -20, z: 1, unit: .centimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin008).run(action: offPlane)

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
func lin008TimeoutIsTypedAndCleansUp() async throws {
    let result = try await CADLineCaseRunner(
        case: .lin008,
        timeoutWallNanoseconds: 1
    ).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test
func lin008ReferenceCandidatePreservesCentimeterPublicContext() async throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "LIN-008")
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
    let candidate: any CADCandidateProtocol = CADLineReferenceCandidate()

    let decision = try await candidate.decide(for: context)

    guard case .action(.automation(.sketch(.line(_, let plane, let start, let end)))) = decision else {
        Issue.record("LIN-008 public context did not produce one line action.")
        return
    }
    #expect(plane == .xy)
    #expect(start == CADPoint3D(x: -20, y: -20, z: 0, unit: .centimeter))
    #expect(end == CADPoint3D(x: 105, y: -20, z: 0, unit: .centimeter))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin009CreatesExactXZWorldXLineThroughProductionController() async throws {
    let result = try await CADLineCaseRunner(case: .lin009).runReference()

    try result.validate()
    #expect(result.caseID == "LIN-009")
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
        "LIN-009 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
            + "route=\(result.telemetry.routeWallNanoseconds)ns "
            + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
            + "total=\(result.telemetry.totalWallNanoseconds)ns"
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin009OracleRejectsCentimeterValuesForMeterCoordinatesWithoutRetry() async throws {
    let wrongScale = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-009.same-numeric-values-centimeter",
        plane: .xz,
        start: CADPoint3D(x: 0, y: 0, z: 0, unit: .centimeter),
        end: CADPoint3D(x: 0.25, y: 0, z: 0, unit: .centimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin009).run(action: wrongScale)

    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.candidateResult?.status == .published)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount == 2)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 1)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin009RejectsOffXZPlaneInputBeforePublication() async throws {
    let offPlane = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-009.off-plane",
        plane: .xz,
        start: CADPoint3D(x: 0, y: 0.01, z: 0, unit: .meter),
        end: CADPoint3D(x: 0.25, y: 0.01, z: 0, unit: .meter)
    )))

    let result = try await CADLineCaseRunner(case: .lin009).run(action: offPlane)

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
func lin009TimeoutIsTypedAndCleansUp() async throws {
    let result = try await CADLineCaseRunner(
        case: .lin009,
        timeoutWallNanoseconds: 1
    ).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test
func lin009ReferenceCandidatePreservesMeterXZPublicContext() async throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "LIN-009")
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
    let candidate: any CADCandidateProtocol = CADLineReferenceCandidate()

    let decision = try await candidate.decide(for: context)

    guard case .action(.automation(.sketch(.line(_, let plane, let start, let end)))) = decision else {
        Issue.record("LIN-009 public context did not produce one line action.")
        return
    }
    #expect(plane == .xz)
    #expect(start == CADPoint3D(x: 0, y: 0, z: 0, unit: .meter))
    #expect(end == CADPoint3D(x: 0.25, y: 0, z: 0, unit: .meter))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin010CreatesExactAffineYZLineThroughProductionController() async throws {
    let result = try await CADLineCaseRunner(case: .lin010).runReference()

    try result.validate()
    #expect(result.caseID == "LIN-010")
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
        "LIN-010 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
            + "route=\(result.telemetry.routeWallNanoseconds)ns "
            + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
            + "total=\(result.telemetry.totalWallNanoseconds)ns"
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin010OracleRejectsReversedEndpointsOnAffinePlaneWithoutRetry() async throws {
    let reversed = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-010.reversed-affine-plane",
        plane: .yz,
        start: CADPoint3D(x: -5, y: 10, z: 0, unit: .inch),
        end: CADPoint3D(x: -5, y: 0, z: 0, unit: .inch)
    )))

    let result = try await CADLineCaseRunner(case: .lin010).run(action: reversed)

    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.candidateResult?.status == .published)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount == 2)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 1)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin010RejectsBuiltInYZPlaneAtWrongXBeforePublication() async throws {
    let offTarget = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-010.built-in-yz-off-target",
        plane: .yz,
        start: CADPoint3D(x: 0, y: 0, z: 0, unit: .inch),
        end: CADPoint3D(x: 0, y: 10, z: 0, unit: .inch)
    )))

    let result = try await CADLineCaseRunner(case: .lin010).run(action: offTarget)

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
func lin010TimeoutIsTypedAndCleansUp() async throws {
    let result = try await CADLineCaseRunner(
        case: .lin010,
        timeoutWallNanoseconds: 1
    ).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test
func lin010ReferenceCandidatePreservesInchYZPublicContext() async throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "LIN-010")
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
    let candidate: any CADCandidateProtocol = CADLineReferenceCandidate()

    let decision = try await candidate.decide(for: context)

    guard case .action(.automation(.sketch(.line(_, let plane, let start, let end)))) = decision else {
        Issue.record("LIN-010 public context did not produce one line action.")
        return
    }
    #expect(plane == .yz)
    #expect(start == CADPoint3D(x: -5, y: 0, z: 0, unit: .inch))
    #expect(end == CADPoint3D(x: -5, y: 10, z: 0, unit: .inch))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin011CreatesExactNegativeZLineThroughProductionController() async throws {
    let result = try await CADLineCaseRunner(case: .lin011).runReference()

    try result.validate()
    #expect(result.caseID == "LIN-011")
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
        "LIN-011 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
            + "route=\(result.telemetry.routeWallNanoseconds)ns "
            + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
            + "total=\(result.telemetry.totalWallNanoseconds)ns"
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin011OracleRejectsSameLengthPositiveZDirectionWithoutRetry() async throws {
    let wrongDirection = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-011.same-length-wrong-positive-z",
        plane: .xz,
        start: CADPoint3D(x: 0, y: 0, z: 0, unit: .meter),
        end: CADPoint3D(x: 0, y: 0, z: 2, unit: .meter)
    )))

    let result = try await CADLineCaseRunner(case: .lin011).run(action: wrongDirection)

    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.candidateResult?.status == .published)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount == 2)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 1)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin011RejectsOffXZPlaneInputBeforePublication() async throws {
    let offPlane = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-011.off-plane",
        plane: .xz,
        start: CADPoint3D(x: 0, y: 0.01, z: 0, unit: .meter),
        end: CADPoint3D(x: 0, y: 0.01, z: -2, unit: .meter)
    )))

    let result = try await CADLineCaseRunner(case: .lin011).run(action: offPlane)

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
func lin011TimeoutIsTypedAndCleansUp() async throws {
    let result = try await CADLineCaseRunner(
        case: .lin011,
        timeoutWallNanoseconds: 1
    ).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test
func lin011ReferenceCandidatePreservesMeterXZNegativeZPublicContext() async throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "LIN-011")
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
    let candidate: any CADCandidateProtocol = CADLineReferenceCandidate()

    let decision = try await candidate.decide(for: context)

    guard case .action(.automation(.sketch(.line(_, let plane, let start, let end)))) = decision else {
        Issue.record("LIN-011 public context did not produce one line action.")
        return
    }
    #expect(plane == .xz)
    #expect(start == CADPoint3D(x: 0, y: 0, z: 0, unit: .meter))
    #expect(end == CADPoint3D(x: 0, y: 0, z: -2, unit: .meter))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin012CreatesExactMillimeterXYLineThroughProductionController() async throws {
    let result = try await CADLineCaseRunner(case: .lin012).runReference()

    try result.validate()
    #expect(result.caseID == "LIN-012")
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
        "LIN-012 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
            + "route=\(result.telemetry.routeWallNanoseconds)ns "
            + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
            + "total=\(result.telemetry.totalWallNanoseconds)ns"
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin012OracleRejectsSameLengthWrongOriginWithoutRetry() async throws {
    let wrongPlacement = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-012.same-length-wrong-origin",
        plane: .xy,
        start: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
        end: CADPoint3D(x: 375, y: 0, z: 0, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin012).run(action: wrongPlacement)

    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.candidateResult?.status == .published)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount == 2)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 1)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lin012RejectsOffXYPlaneInputBeforePublication() async throws {
    let offPlane = CADCandidateAction.automation(.sketch(.line(
        name: "LIN-012.off-plane",
        plane: .xy,
        start: CADPoint3D(x: 125, y: -75, z: 1, unit: .millimeter),
        end: CADPoint3D(x: 500, y: -75, z: 1, unit: .millimeter)
    )))

    let result = try await CADLineCaseRunner(case: .lin012).run(action: offPlane)

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
func lin012TimeoutIsTypedAndCleansUp() async throws {
    let result = try await CADLineCaseRunner(
        case: .lin012,
        timeoutWallNanoseconds: 1
    ).runReference()

    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(!result.routeEvidence.didPublish)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

@MainActor
@Test
func lin012ReferenceCandidatePreservesMillimeterXYPublicContext() async throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "LIN-012")
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
    let candidate: any CADCandidateProtocol = CADLineReferenceCandidate()

    let decision = try await candidate.decide(for: context)

    guard case .action(.automation(.sketch(.line(_, let plane, let start, let end)))) = decision else {
        Issue.record("LIN-012 public context did not produce one line action.")
        return
    }
    #expect(plane == .xy)
    #expect(start == CADPoint3D(x: 125, y: -75, z: 0, unit: .millimeter))
    #expect(end == CADPoint3D(x: 500, y: -75, z: 0, unit: .millimeter))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lineCheckpointReplaysTenActivatedCasesAndMatchesPublicCoverage() async throws {
    let firstTenCases: [CADActivatedLineCase] = [
        .lin001, .lin002, .lin003, .lin004, .lin005,
        .lin006, .lin007, .lin008, .lin009, .lin010,
    ]
    let activatedCases = Array(CADActivatedLineCase.allCases.prefix(firstTenCases.count))
    #expect(activatedCases == firstTenCases)

    let catalog = try CADBenchmarkCatalog()
    var projections: [CADLineChallengeProjection] = []
    for activatedCase in activatedCases {
        let challenge = try catalog.challenge(for: activatedCase.caseID)
        let projection = try CADLineChallengeProjection.decode(challenge)
        #expect(projection.id == activatedCase.caseID)
        projections.append(projection)
    }
    #expect(projections.count == firstTenCases.count)
    #expect(projections.filter { $0.orientation == .xy }.count == 6)
    #expect(projections.filter { $0.orientation == .xz }.count == 2)
    #expect(projections.filter { $0.orientation == .yz }.count == 2)
    #expect(projections.filter { $0.length.unit == .millimeter }.count == 7)
    #expect(projections.filter { $0.length.unit == .centimeter }.count == 1)
    #expect(projections.filter { $0.length.unit == .meter }.count == 1)
    #expect(projections.filter { $0.length.unit == .inch }.count == 1)

    for activatedCase in activatedCases {
        let result = try await CADLineCaseRunner(case: activatedCase).runReference()

        try result.validate()
        #expect(result.caseID == activatedCase.caseID)
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.finalDocumentGeneration.value == result.routeEvidence.initialDocumentGeneration.value + 1)
        #expect(result.routeEvidence.finalTransactionRevision.value == result.routeEvidence.initialTransactionRevision.value + 1)
        #expect(result.routeEvidence.finalWorkspaceRevision >= result.routeEvidence.initialWorkspaceRevision)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 1)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds <= result.telemetry.totalWallNanoseconds)
        #expect(result.telemetry.routeWallNanoseconds <= result.telemetry.totalWallNanoseconds)
        #expect(result.telemetry.oracleWallNanoseconds <= result.telemetry.totalWallNanoseconds)
        #expect(result.telemetry.totalWallNanoseconds <= result.telemetry.timeoutWallNanoseconds)
        print(
            "\(activatedCase.rawValue) checkpoint: planning=\(result.telemetry.planningWallNanoseconds)ns "
                + "route=\(result.telemetry.routeWallNanoseconds)ns "
                + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
                + "total=\(result.telemetry.totalWallNanoseconds)ns"
        )
    }

}

@MainActor
@Test(.timeLimit(.minutes(1)))
func lineCategoryCheckpointReplaysAllTwelveActivatedCasesAndMatchesPublicCoverage() async throws {
    let activatedCases = CADActivatedLineCase.allCases
    #expect(activatedCases.map(\.rawValue) == [
        "LIN-001", "LIN-002", "LIN-003", "LIN-004", "LIN-005", "LIN-006",
        "LIN-007", "LIN-008", "LIN-009", "LIN-010", "LIN-011", "LIN-012",
    ])

    let catalog = try CADBenchmarkCatalog()
    var projections: [CADLineChallengeProjection] = []
    for activatedCase in activatedCases {
        let challenge = try catalog.challenge(for: activatedCase.caseID)
        let projection = try CADLineChallengeProjection.decode(challenge)
        #expect(projection.id == activatedCase.caseID)
        projections.append(projection)
    }
    #expect(projections.count == activatedCases.count)
    #expect(projections.filter { $0.orientation == .xy }.count == 7)
    #expect(projections.filter { $0.orientation == .xz }.count == 3)
    #expect(projections.filter { $0.orientation == .yz }.count == 2)
    #expect(projections.filter { $0.length.unit == .millimeter }.count == 8)
    #expect(projections.filter { $0.length.unit == .centimeter }.count == 1)
    #expect(projections.filter { $0.length.unit == .meter }.count == 2)
    #expect(projections.filter { $0.length.unit == .inch }.count == 1)

    for activatedCase in activatedCases {
        let result = try await CADLineCaseRunner(case: activatedCase).runReference()

        try result.validate()
        #expect(result.caseID == activatedCase.caseID)
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.finalDocumentGeneration.value == result.routeEvidence.initialDocumentGeneration.value + 1)
        #expect(result.routeEvidence.finalTransactionRevision.value == result.routeEvidence.initialTransactionRevision.value + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 1)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds <= result.telemetry.totalWallNanoseconds)
        #expect(result.telemetry.routeWallNanoseconds <= result.telemetry.totalWallNanoseconds)
        #expect(result.telemetry.oracleWallNanoseconds <= result.telemetry.totalWallNanoseconds)
        #expect(result.telemetry.totalWallNanoseconds <= result.telemetry.timeoutWallNanoseconds)
        print(
            "\(activatedCase.rawValue) cumulative: p=\(result.telemetry.planningWallNanoseconds)ns "
                + "r=\(result.telemetry.routeWallNanoseconds)ns "
                + "o=\(result.telemetry.oracleWallNanoseconds)ns "
                + "t=\(result.telemetry.totalWallNanoseconds)ns"
        )
    }
}

@Test
func activatedLineBoundaryContainsExactlyReviewedCases() throws {
    #expect(CADActivatedLineCase.allCases.map(\.rawValue) == ["LIN-001", "LIN-002", "LIN-003", "LIN-004", "LIN-005", "LIN-006", "LIN-007", "LIN-008", "LIN-009", "LIN-010", "LIN-011", "LIN-012"])

    for rejectedCaseID in ["REC-001", "LIN-013"] {
        do {
            _ = try CADActivatedLineCase(caseID: rejectedCaseID)
            Issue.record("\(rejectedCaseID) must remain outside the activated line boundary.")
        } catch let error as CADBenchmarkError {
            guard case .invalidCaseID(let observedCaseID) = error,
                  observedCaseID == rejectedCaseID else {
                Issue.record("Unexpected typed error for \(rejectedCaseID): \(error)")
                continue
            }
        }
    }
}

}
