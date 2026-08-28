import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADRectangleCaseTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec001CreatesExactClosedRectangleThroughProductionController() async throws {
        let result = try await CADRectangleCaseRunner(case: .rec001).runReference()

        try result.validate()
        #expect(result.caseID == "REC-001")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 1)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.first)
        #expect(result.roleBindings?.bindings.count == 1)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
        print(
            "REC-001 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
                + "route=\(result.telemetry.routeWallNanoseconds)ns "
                + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
                + "total=\(result.telemetry.totalWallNanoseconds)ns"
        )
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec001OracleRejectsSameAreaSwappedDimensionsWithoutRetry() async throws {
        let swapped = CADCandidateAction.automation(.sketch(.rectangle(
            name: "REC-001.swapped",
            plane: .xy,
            center: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 20, unit: .millimeter),
            height: CADLength(value: 40, unit: .millimeter)
        )))

        let result = try await CADRectangleCaseRunner(case: .rec001).run(action: swapped)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec001RejectsOffPlaneCenterBeforePublication() async throws {
        let offPlane = CADCandidateAction.automation(.sketch(.rectangle(
            name: "REC-001.off-plane",
            plane: .xy,
            center: CADPoint3D(x: 0, y: 0, z: 2, unit: .millimeter),
            width: CADLength(value: 40, unit: .millimeter),
            height: CADLength(value: 20, unit: .millimeter)
        )))

        let result = try await CADRectangleCaseRunner(case: .rec001).run(action: offPlane)

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
    func rec001TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADRectangleCaseRunner(
            case: .rec001,
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
    func rec001ReferenceCandidateUsesOnlyChallengeProjection() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "REC-001")
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
        let decision = try await CADRectangleReferenceCandidate().decide(for: context)

        guard case .action(.automation(.sketch(.rectangle(
            _, let plane, let center, let width, let height
        )))) = decision else {
            Issue.record("REC-001 candidate did not produce one rectangle action.")
            return
        }
        #expect(plane == .xy)
        #expect(center == CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter))
        #expect(width == CADLength(value: 40, unit: .millimeter))
        #expect(height == CADLength(value: 20, unit: .millimeter))
    }

    @Test
    func activatedRectangleBoundaryMatchesReviewedCases() throws {
        #expect(CADActivatedRectangleCase.allCases == [.rec001, .rec002, .rec003, .rec004, .rec005, .rec006, .rec007, .rec008, .rec009, .rec010, .rec011, .rec012])

        for rejectedCaseID in ["CIR-001", "LIN-001"] {
            do {
                _ = try CADActivatedRectangleCase(caseID: rejectedCaseID)
                Issue.record("\(rejectedCaseID) must remain outside the rectangle activation boundary.")
            } catch let error as CADBenchmarkError {
                guard case .invalidCaseID(let observed) = error,
                      observed == rejectedCaseID else {
                    Issue.record("Unexpected typed error for \(rejectedCaseID): \(error)")
                    continue
                }
            }
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec002CreatesExactTranslatedRectangleThroughProductionController() async throws {
        let result = try await CADRectangleCaseRunner(case: .rec002).runReference()

        try result.validate()
        #expect(result.caseID == "REC-002")
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec002OracleRejectsSameSizeWrongCenterWithoutRetry() async throws {
        let wrongCenter = rectangleAction(
            name: "REC-002.wrong-center",
            plane: .xy,
            center: CADPoint3D(x: 25, y: -20, z: 0, unit: .millimeter),
            width: CADLength(value: 80, unit: .millimeter),
            height: CADLength(value: 30, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec002).run(action: wrongCenter)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec002RejectsOffPlaneCenterBeforePublication() async throws {
        let offPlane = rectangleAction(
            name: "REC-002.off-plane",
            plane: .xy,
            center: CADPoint3D(x: 15, y: -20, z: 2, unit: .millimeter),
            width: CADLength(value: 80, unit: .millimeter),
            height: CADLength(value: 30, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec002).run(action: offPlane)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec002TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADRectangleCaseRunner(
            case: .rec002,
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
    func rec002CandidatePreservesTranslatedPublicCenter() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "REC-002")
        let decision = try await CADRectangleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.rectangle(
            _, let plane, let center, let width, let height
        )))) = decision else {
            Issue.record("REC-002 candidate did not produce one rectangle action.")
            return
        }
        #expect(plane == .xy)
        #expect(center == CADPoint3D(x: 15, y: -20, z: 0, unit: .millimeter))
        #expect(width == CADLength(value: 80, unit: .millimeter))
        #expect(height == CADLength(value: 30, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec003CreatesExactXZRectangleThroughProductionController() async throws {
        let result = try await CADRectangleCaseRunner(case: .rec003).runReference()

        try result.validate()
        #expect(result.caseID == "REC-003")
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec003OracleRejectsSwappedXZDimensionsWithoutRetry() async throws {
        let swapped = rectangleAction(
            name: "REC-003.swapped",
            plane: .xz,
            center: CADPoint3D(x: 0, y: 0, z: 25, unit: .millimeter),
            width: CADLength(value: 60, unit: .millimeter),
            height: CADLength(value: 120, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec003).run(action: swapped)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec003RejectsOffXZCenterBeforePublication() async throws {
        let offPlane = rectangleAction(
            name: "REC-003.off-plane",
            plane: .xz,
            center: CADPoint3D(x: 0, y: 2, z: 25, unit: .millimeter),
            width: CADLength(value: 120, unit: .millimeter),
            height: CADLength(value: 60, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec003).run(action: offPlane)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec003TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADRectangleCaseRunner(
            case: .rec003,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func rec003CandidatePreservesXZPlaneAndCenter() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "REC-003")
        let decision = try await CADRectangleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.rectangle(
            _, let plane, let center, let width, let height
        )))) = decision else {
            Issue.record("REC-003 candidate did not produce one rectangle action.")
            return
        }
        #expect(plane == .xz)
        #expect(center == CADPoint3D(x: 0, y: 0, z: 25, unit: .millimeter))
        #expect(width == CADLength(value: 120, unit: .millimeter))
        #expect(height == CADLength(value: 60, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec004CreatesExactAffineYZRectangleThroughProductionController() async throws {
        let result = try await CADRectangleCaseRunner(case: .rec004).runReference()

        try result.validate()
        #expect(result.caseID == "REC-004")
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec004OracleRejectsWrongInPlaneCenterWithoutRetry() async throws {
        let wrongCenter = rectangleAction(
            name: "REC-004.wrong-center",
            plane: .yz,
            center: CADPoint3D(x: -50, y: 10, z: 0, unit: .millimeter),
            width: CADLength(value: 250, unit: .millimeter),
            height: CADLength(value: 100, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec004).run(action: wrongCenter)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec004RejectsWrongNormalPositionBeforePublication() async throws {
        let offPlane = rectangleAction(
            name: "REC-004.off-plane",
            plane: .yz,
            center: CADPoint3D(x: -48, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 250, unit: .millimeter),
            height: CADLength(value: 100, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec004).run(action: offPlane)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec004TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADRectangleCaseRunner(
            case: .rec004,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func rec004CandidatePreservesAffineYZPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "REC-004")
        let decision = try await CADRectangleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.rectangle(
            _, let plane, let center, let width, let height
        )))) = decision else {
            Issue.record("REC-004 candidate did not produce one rectangle action.")
            return
        }
        #expect(plane == .yz)
        #expect(center == CADPoint3D(x: -50, y: 0, z: 0, unit: .millimeter))
        #expect(width == CADLength(value: 250, unit: .millimeter))
        #expect(height == CADLength(value: 100, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec005CreatesExactCentimeterRectangleThroughProductionController() async throws {
        let result = try await CADRectangleCaseRunner(case: .rec005).runReference()

        try result.validate()
        #expect(result.caseID == "REC-005")
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec005OracleRejectsMillimeterValuesForCentimeterDimensions() async throws {
        let wrongScale = rectangleAction(
            name: "REC-005.wrong-scale",
            plane: .xy,
            center: CADPoint3D(x: 0, y: 0, z: 0, unit: .centimeter),
            width: CADLength(value: 10, unit: .millimeter),
            height: CADLength(value: 5, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec005).run(action: wrongScale)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec005RejectsOffXYCenterBeforePublication() async throws {
        let offPlane = rectangleAction(
            name: "REC-005.off-plane",
            plane: .xy,
            center: CADPoint3D(x: 0, y: 0, z: 0.2, unit: .centimeter),
            width: CADLength(value: 10, unit: .centimeter),
            height: CADLength(value: 5, unit: .centimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec005).run(action: offPlane)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec005TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADRectangleCaseRunner(
            case: .rec005,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func rec005CandidatePreservesCentimeterPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "REC-005")
        let decision = try await CADRectangleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.rectangle(
            _, let plane, let center, let width, let height
        )))) = decision else {
            Issue.record("REC-005 candidate did not produce one rectangle action.")
            return
        }
        #expect(plane == .xy)
        #expect(center == CADPoint3D(x: 0, y: 0, z: 0, unit: .centimeter))
        #expect(width == CADLength(value: 10, unit: .centimeter))
        #expect(height == CADLength(value: 5, unit: .centimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec006CreatesExactMeterXZRectangleThroughProductionController() async throws {
        let result = try await CADRectangleCaseRunner(case: .rec006).runReference()

        try result.validate()
        #expect(result.caseID == "REC-006")
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec006OracleRejectsCentimeterValuesForMeterDimensions() async throws {
        let wrongScale = rectangleAction(
            name: "REC-006.wrong-scale",
            plane: .xz,
            center: CADPoint3D(x: 0, y: 0, z: 0, unit: .meter),
            width: CADLength(value: 0.4, unit: .centimeter),
            height: CADLength(value: 0.2, unit: .centimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec006).run(action: wrongScale)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec006RejectsOffXZCenterBeforePublication() async throws {
        let offPlane = rectangleAction(
            name: "REC-006.off-plane",
            plane: .xz,
            center: CADPoint3D(x: 0, y: 0.002, z: 0, unit: .meter),
            width: CADLength(value: 0.4, unit: .meter),
            height: CADLength(value: 0.2, unit: .meter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec006).run(action: offPlane)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec006TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADRectangleCaseRunner(
            case: .rec006,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func rec006CandidatePreservesMeterXZPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "REC-006")
        let decision = try await CADRectangleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.rectangle(
            _, let plane, let center, let width, let height
        )))) = decision else {
            Issue.record("REC-006 candidate did not produce one rectangle action.")
            return
        }
        #expect(plane == .xz)
        #expect(center == CADPoint3D(x: 0, y: 0, z: 0, unit: .meter))
        #expect(width == CADLength(value: 0.4, unit: .meter))
        #expect(height == CADLength(value: 0.2, unit: .meter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec007CreatesExactSlenderAffineYZRectangle() async throws {
        let result = try await CADRectangleCaseRunner(case: .rec007).runReference()

        try result.validate()
        #expect(result.caseID == "REC-007")
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec007OracleRejectsSameAreaDimensionSwapWithoutRetry() async throws {
        let swapped = rectangleAction(
            name: "REC-007.swapped",
            plane: .yz,
            center: CADPoint3D(x: 20, y: -40, z: 0, unit: .millimeter),
            width: CADLength(value: 90, unit: .millimeter),
            height: CADLength(value: 12, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec007).run(action: swapped)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec007RejectsWrongNormalPositionBeforePublication() async throws {
        let offPlane = rectangleAction(
            name: "REC-007.off-plane",
            plane: .yz,
            center: CADPoint3D(x: 22, y: -40, z: 0, unit: .millimeter),
            width: CADLength(value: 12, unit: .millimeter),
            height: CADLength(value: 90, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec007).run(action: offPlane)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec007TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADRectangleCaseRunner(
            case: .rec007,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func rec007CandidatePreservesSlenderAffineYZValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "REC-007")
        let decision = try await CADRectangleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.rectangle(
            _, let plane, let center, let width, let height
        )))) = decision else {
            Issue.record("REC-007 candidate did not produce one rectangle action.")
            return
        }
        #expect(plane == .yz)
        #expect(center == CADPoint3D(x: 20, y: -40, z: 0, unit: .millimeter))
        #expect(width == CADLength(value: 12, unit: .millimeter))
        #expect(height == CADLength(value: 90, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec008CreatesExactLargeTranslatedXYRectangle() async throws {
        let result = try await CADRectangleCaseRunner(case: .rec008).runReference()

        try result.validate()
        #expect(result.caseID == "REC-008")
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec008OracleRejectsSameSizeWrongCenterWithoutRetry() async throws {
        let wrongCenter = rectangleAction(
            name: "REC-008.wrong-center",
            plane: .xy,
            center: CADPoint3D(x: -200, y: 125, z: 0, unit: .millimeter),
            width: CADLength(value: 500, unit: .millimeter),
            height: CADLength(value: 125, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec008).run(action: wrongCenter)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec008RejectsOffXYCenterBeforePublication() async throws {
        let offPlane = rectangleAction(
            name: "REC-008.off-plane",
            plane: .xy,
            center: CADPoint3D(x: -250, y: 125, z: 2, unit: .millimeter),
            width: CADLength(value: 500, unit: .millimeter),
            height: CADLength(value: 125, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec008).run(action: offPlane)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec008TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADRectangleCaseRunner(
            case: .rec008,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func rec008CandidatePreservesLargeTranslatedPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "REC-008")
        let decision = try await CADRectangleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.rectangle(
            _, let plane, let center, let width, let height
        )))) = decision else {
            Issue.record("REC-008 candidate did not produce one rectangle action.")
            return
        }
        #expect(plane == .xy)
        #expect(center == CADPoint3D(x: -250, y: 125, z: 0, unit: .millimeter))
        #expect(width == CADLength(value: 500, unit: .millimeter))
        #expect(height == CADLength(value: 125, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec009CreatesExactInchXZRectangleThroughProductionController() async throws {
        let result = try await CADRectangleCaseRunner(case: .rec009).runReference()

        try result.validate()
        #expect(result.caseID == "REC-009")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 1)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.first)
        #expect(result.roleBindings?.bindings.count == 1)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec009OracleRejectsSameNumericMillimeterDimensionsWithoutRetry() async throws {
        let wrongScale = rectangleAction(
            name: "REC-009.wrong-scale",
            plane: .xz,
            center: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 1, unit: .millimeter),
            height: CADLength(value: 0.5, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec009).run(action: wrongScale)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec009RejectsOffXZCenterBeforePublication() async throws {
        let offPlane = rectangleAction(
            name: "REC-009.off-plane",
            plane: .xz,
            center: CADPoint3D(x: 0, y: 1, z: 0, unit: .inch),
            width: CADLength(value: 1, unit: .inch),
            height: CADLength(value: 0.5, unit: .inch)
        )

        let result = try await CADRectangleCaseRunner(case: .rec009).run(action: offPlane)

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
    func rec009TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADRectangleCaseRunner(
            case: .rec009,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func rec009CandidatePreservesInchXZPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "REC-009")
        let decision = try await CADRectangleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.rectangle(
            _, let plane, let center, let width, let height
        )))) = decision else {
            Issue.record("REC-009 candidate did not produce one rectangle action.")
            return
        }
        #expect(plane == .xz)
        #expect(center == CADPoint3D(x: 0, y: 0, z: 0, unit: .inch))
        #expect(width == CADLength(value: 1, unit: .inch))
        #expect(height == CADLength(value: 0.5, unit: .inch))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec010CreatesExactMetreXYRectangleThroughProductionController() async throws {
        let result = try await CADRectangleCaseRunner(case: .rec010).runReference()

        try result.validate()
        #expect(result.caseID == "REC-010")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 1)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.first)
        #expect(result.roleBindings?.bindings.count == 1)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec010OracleRejectsSameNumericMillimeterDimensionsWithoutRetry() async throws {
        let wrongScale = rectangleAction(
            name: "REC-010.wrong-scale",
            plane: .xy,
            center: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 2, unit: .millimeter),
            height: CADLength(value: 1, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec010).run(action: wrongScale)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec010RejectsOffXYCenterBeforePublication() async throws {
        let offPlane = rectangleAction(
            name: "REC-010.off-plane",
            plane: .xy,
            center: CADPoint3D(x: 0, y: 0, z: 0.01, unit: .meter),
            width: CADLength(value: 2, unit: .meter),
            height: CADLength(value: 1, unit: .meter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec010).run(action: offPlane)

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
    func rec010TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADRectangleCaseRunner(
            case: .rec010,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func rec010CandidatePreservesMetreXYPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "REC-010")
        let decision = try await CADRectangleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.rectangle(
            _, let plane, let center, let width, let height
        )))) = decision else {
            Issue.record("REC-010 candidate did not produce one rectangle action.")
            return
        }
        #expect(plane == .xy)
        #expect(center == CADPoint3D(x: 0, y: 0, z: 0, unit: .meter))
        #expect(width == CADLength(value: 2, unit: .meter))
        #expect(height == CADLength(value: 1, unit: .meter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec011CreatesExactMillimetreYZSquareThroughProductionController() async throws {
        let result = try await CADRectangleCaseRunner(case: .rec011).runReference()

        try result.validate()
        #expect(result.caseID == "REC-011")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 1)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.first)
        #expect(result.roleBindings?.bindings.count == 1)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec011OracleRejectsWrongInPlaneCenterWithoutRetry() async throws {
        let wrongCenter = rectangleAction(
            name: "REC-011.wrong-center",
            plane: .yz,
            center: CADPoint3D(x: 0, y: 20, z: -15, unit: .millimeter),
            width: CADLength(value: 35, unit: .millimeter),
            height: CADLength(value: 35, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec011).run(action: wrongCenter)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec011RejectsOffYZCenterBeforePublication() async throws {
        let offPlane = rectangleAction(
            name: "REC-011.off-plane",
            plane: .yz,
            center: CADPoint3D(x: 2, y: 15, z: -15, unit: .millimeter),
            width: CADLength(value: 35, unit: .millimeter),
            height: CADLength(value: 35, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec011).run(action: offPlane)

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
    func rec011TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADRectangleCaseRunner(
            case: .rec011,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func rec011CandidatePreservesMillimetreYZPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "REC-011")
        let decision = try await CADRectangleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.rectangle(
            _, let plane, let center, let width, let height
        )))) = decision else {
            Issue.record("REC-011 candidate did not produce one rectangle action.")
            return
        }
        #expect(plane == .yz)
        #expect(center == CADPoint3D(x: 0, y: 15, z: -15, unit: .millimeter))
        #expect(width == CADLength(value: 35, unit: .millimeter))
        #expect(height == CADLength(value: 35, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec012CreatesExactMillimetreXYRectangleThroughProductionController() async throws {
        let result = try await CADRectangleCaseRunner(case: .rec012).runReference()

        try result.validate()
        #expect(result.caseID == "REC-012")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 1)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.first)
        #expect(result.roleBindings?.bindings.count == 1)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec012OracleRejectsWrongInPlaneCenterWithoutRetry() async throws {
        let wrongCenter = rectangleAction(
            name: "REC-012.wrong-center",
            plane: .xy,
            center: CADPoint3D(x: -50, y: -40, z: 0, unit: .millimeter),
            width: CADLength(value: 750, unit: .millimeter),
            height: CADLength(value: 80, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec012).run(action: wrongCenter)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec012RejectsOffXYCenterBeforePublication() async throws {
        let offPlane = rectangleAction(
            name: "REC-012.off-plane",
            plane: .xy,
            center: CADPoint3D(x: -100, y: -40, z: 2, unit: .millimeter),
            width: CADLength(value: 750, unit: .millimeter),
            height: CADLength(value: 80, unit: .millimeter)
        )

        let result = try await CADRectangleCaseRunner(case: .rec012).run(action: offPlane)

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
    func rec012TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADRectangleCaseRunner(
            case: .rec012,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func rec012CandidatePreservesMillimetreXYPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "REC-012")
        let decision = try await CADRectangleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.rectangle(
            _, let plane, let center, let width, let height
        )))) = decision else {
            Issue.record("REC-012 candidate did not produce one rectangle action.")
            return
        }
        #expect(plane == .xy)
        #expect(center == CADPoint3D(x: -100, y: -40, z: 0, unit: .millimeter))
        #expect(width == CADLength(value: 750, unit: .millimeter))
        #expect(height == CADLength(value: 80, unit: .millimeter))
    }
}

private func rectangleAction(
    name: String,
    plane: CADSketchPlane,
    center: CADPoint3D,
    width: CADLength,
    height: CADLength
) -> CADCandidateAction {
    .automation(.sketch(.rectangle(
        name: name,
        plane: plane,
        center: center,
        width: width,
        height: height
    )))
}

private func candidateContext(_ challenge: CADChallenge) -> CADCandidateContext {
    CADCandidateContext(
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
}
