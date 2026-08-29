import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADCylinderCaseTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder001CreatesExactAnalyticSolidThroughProductionController() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder001).runReference()

        try result.validate()
        #expect(result.caseID == "CYL-001")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 2)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.last)
        #expect(result.roleBindings?.bindings.first?.role == "solid")
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalDocumentGeneration.value == result.routeEvidence.initialDocumentGeneration.value + 1)
        #expect(result.routeEvidence.finalTransactionRevision.value == result.routeEvidence.initialTransactionRevision.value + 1)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.finalWorkspaceRevision == result.routeEvidence.initialWorkspaceRevision)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 1)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 6)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder001OracleRejectsWrongRadiusAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder001).run(
            action: Self.cylinderAction(radius: 6)
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 1)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder001FailureTelemetryReadFailureIsOracleFailure() async throws {
        let result = try await CADCylinderCaseRunner(
            case: .cylinder001,
            failureSourceReader: { _ in throw CylinderFailureSourceReadError.unavailable }
        ).run(action: Self.cylinderAction(radius: 6))

        try result.validate()
        #expect(result.outcome == .oracleFailure)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("failure telemetry read failed") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: [
        cylinderAction(radius: 0),
        cylinderAction(depth: 0),
        cylinderAction(axis: CADDirection3D(x: 0, y: 0, z: 0)),
        cylinderAction(axis: CADDirection3D(x: .infinity, y: 0, z: 1)),
    ])
    func cylinder001RejectsDegenerateInputBeforePublication(
        action: CADCandidateAction
    ) async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder001).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder001RejectsBoxSubstituteBeforePublication() async throws {
        let action = CADCandidateAction.automation(.solid(.box(
            name: "CYL-001.box-substitute",
            origin: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 10, unit: .millimeter),
            depth: CADLength(value: 10, unit: .millimeter),
            height: CADLength(value: 20, unit: .millimeter)
        )))
        let result = try await CADCylinderCaseRunner(case: .cylinder001).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder001TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCylinderCaseRunner(
            case: .cylinder001,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @Test
    func cylinder001ReferenceCandidateUsesOnlyPublicChallengeValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CYL-001")
        let decision = try await CADCylinderReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.cylinder(
            let name, let baseCenter, let axis, let radius, let depth
        )))) = decision else {
            Issue.record("CYL-001 candidate did not produce one solid cylinder action.")
            return
        }
        #expect(name == "CYL-001")
        #expect(baseCenter == CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter))
        #expect(axis == CADDirection3D(x: 0, y: 0, z: 1))
        #expect(radius == CADLength(value: 5, unit: .millimeter))
        #expect(depth == CADLength(value: 20, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder002CreatesExactTranslatedXAxisSolidThroughProductionController() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder002).runReference()

        try result.validate()
        #expect(result.caseID == "CYL-002")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 2)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.last)
        #expect(result.roleBindings?.bindings.first?.role == "solid")
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalDocumentGeneration.value == result.routeEvidence.initialDocumentGeneration.value + 1)
        #expect(result.routeEvidence.finalTransactionRevision.value == result.routeEvidence.initialTransactionRevision.value + 1)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.finalWorkspaceRevision == result.routeEvidence.initialWorkspaceRevision)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 1)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 6)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder002OracleRejectsWrongAxisAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder002).run(
            action: Self.cylinder002Action(axis: CADDirection3D(x: 0, y: 0, z: 1))
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 1)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder002RejectsZeroAxisBeforePublication() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder002).run(
            action: Self.cylinder002Action(axis: CADDirection3D(x: 0, y: 0, z: 0))
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder002TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCylinderCaseRunner(
            case: .cylinder002,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @Test
    func cylinder002ReferenceCandidatePreservesTranslatedXAxisPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CYL-002")
        let decision = try await CADCylinderReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.cylinder(
            let name, let baseCenter, let axis, let radius, let depth
        )))) = decision else {
            Issue.record("CYL-002 candidate did not produce one solid cylinder action.")
            return
        }
        #expect(name == "CYL-002")
        #expect(baseCenter == CADPoint3D(x: 25, y: -25, z: 0, unit: .millimeter))
        #expect(axis == CADDirection3D(x: 1, y: 0, z: 0))
        #expect(radius == CADLength(value: 10, unit: .millimeter))
        #expect(depth == CADLength(value: 50, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder003CreatesExactTranslatedYAxisSolidThroughProductionController() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder003).runReference()

        try assertRealizedCylinder(result, caseID: "CYL-003")
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder003OracleRejectsWrongAxisAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder003).run(
            action: Self.cylinder003Action(axis: CADDirection3D(x: 0, y: 0, z: 1))
        )

        try assertRejectedPublishedCylinder(result)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder003RejectsZeroAxisBeforePublication() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder003).run(
            action: Self.cylinder003Action(axis: CADDirection3D(x: 0, y: 0, z: 0))
        )

        try assertRejectedPrepublicationCylinder(result)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder003TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCylinderCaseRunner(
            case: .cylinder003,
            timeoutWallNanoseconds: 1
        ).runReference()

        try assertTimedOutCylinder(result)
    }

    @Test
    func cylinder003ReferenceCandidatePreservesTranslatedYAxisPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CYL-003")
        let decision = try await CADCylinderReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.cylinder(
            let name, let baseCenter, let axis, let radius, let depth
        )))) = decision else {
            Issue.record("CYL-003 candidate did not produce one solid cylinder action.")
            return
        }
        #expect(name == "CYL-003")
        #expect(baseCenter == CADPoint3D(x: -50, y: 20, z: 10, unit: .millimeter))
        #expect(axis == CADDirection3D(x: 0, y: 1, z: 0))
        #expect(radius == CADLength(value: 25, unit: .millimeter))
        #expect(depth == CADLength(value: 100, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder004CreatesExactNegativeZSolidThroughProductionController() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder004).runReference()
        try assertRealizedCylinder(result, caseID: "CYL-004")
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder004OracleRejectsPositiveZReversalAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder004).run(
            action: Self.cylinder004Action(axis: CADDirection3D(x: 0, y: 0, z: 1))
        )
        try assertRejectedPublishedCylinder(result)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder004RejectsZeroAxisBeforePublication() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder004).run(
            action: Self.cylinder004Action(axis: CADDirection3D(x: 0, y: 0, z: 0))
        )
        try assertRejectedPrepublicationCylinder(result)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder004TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCylinderCaseRunner(
            case: .cylinder004,
            timeoutWallNanoseconds: 1
        ).runReference()
        try assertTimedOutCylinder(result)
    }

    @Test
    func cylinder004ReferenceCandidatePreservesNegativeZPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CYL-004")
        let decision = try await CADCylinderReferenceCandidate().decide(for: candidateContext(challenge))

        guard case .action(.automation(.solid(.cylinder(
            let name, let baseCenter, let axis, let radius, let depth
        )))) = decision else {
            Issue.record("CYL-004 candidate did not produce one solid cylinder action.")
            return
        }
        #expect(name == "CYL-004")
        #expect(baseCenter == CADPoint3D(x: 0, y: 0, z: -100, unit: .millimeter))
        #expect(axis == CADDirection3D(x: 0, y: 0, z: -1))
        #expect(radius == CADLength(value: 50, unit: .millimeter))
        #expect(depth == CADLength(value: 250, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder005CreatesExactCentimeterDiagonalSolidThroughProductionController() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder005).runReference()
        try assertRealizedCylinder(result, caseID: "CYL-005")
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder005OracleRejectsXAxisSubstituteAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder005).run(
            action: Self.cylinder005Action(axis: CADDirection3D(x: 1, y: 0, z: 0))
        )
        try assertRejectedPublishedCylinder(result)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder005RejectsZeroAxisBeforePublication() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder005).run(
            action: Self.cylinder005Action(axis: CADDirection3D(x: 0, y: 0, z: 0))
        )
        try assertRejectedPrepublicationCylinder(result)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder005TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCylinderCaseRunner(
            case: .cylinder005,
            timeoutWallNanoseconds: 1
        ).runReference()
        try assertTimedOutCylinder(result)
    }

    @Test
    func cylinder005ReferenceCandidatePreservesCentimeterDiagonalPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CYL-005")
        let decision = try await CADCylinderReferenceCandidate().decide(for: candidateContext(challenge))

        guard case .action(.automation(.solid(.cylinder(
            let name, let baseCenter, let axis, let radius, let depth
        )))) = decision else {
            Issue.record("CYL-005 candidate did not produce one solid cylinder action.")
            return
        }
        #expect(name == "CYL-005")
        #expect(baseCenter == CADPoint3D(x: 0, y: 0, z: 0, unit: .centimeter))
        #expect(axis == CADDirection3D(x: 0.707106781187, y: 0.707106781187, z: 0))
        #expect(radius == CADLength(value: 2, unit: .centimeter))
        #expect(depth == CADLength(value: 10, unit: .centimeter))
    }

    @MainActor @Test(.timeLimit(.minutes(1)))
    func cylinder006CreatesExactMeterYZDiagonalSolidThroughProductionController() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder006).runReference()
        try assertRealizedCylinder(result, caseID: "CYL-006")
    }

    @MainActor @Test(.timeLimit(.minutes(1)))
    func cylinder006OracleRejectsYAxisSubstituteAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder006).run(
            action: Self.cylinder006Action(axis: CADDirection3D(x: 0, y: 1, z: 0))
        )
        try assertRejectedPublishedCylinder(result)
    }

    @MainActor @Test(.timeLimit(.minutes(1)))
    func cylinder006RejectsZeroAxisBeforePublication() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder006).run(
            action: Self.cylinder006Action(axis: CADDirection3D(x: 0, y: 0, z: 0))
        )
        try assertRejectedPrepublicationCylinder(result)
    }

    @MainActor @Test(.timeLimit(.minutes(1)))
    func cylinder006TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCylinderCaseRunner(
            case: .cylinder006,
            timeoutWallNanoseconds: 1
        ).runReference()
        try assertTimedOutCylinder(result)
    }

    @Test
    func cylinder006ReferenceCandidatePreservesMeterYZDiagonalPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CYL-006")
        let decision = try await CADCylinderReferenceCandidate().decide(for: candidateContext(challenge))
        guard case .action(.automation(.solid(.cylinder(
            let name, let baseCenter, let axis, let radius, let depth
        )))) = decision else {
            Issue.record("CYL-006 candidate did not produce one solid cylinder action.")
            return
        }
        #expect(name == "CYL-006")
        #expect(baseCenter == CADPoint3D(x: -0.1, y: 0.05, z: 0, unit: .meter))
        #expect(axis == CADDirection3D(x: 0, y: 0.707106781187, z: 0.707106781187))
        #expect(radius == CADLength(value: 0.05, unit: .meter))
        #expect(depth == CADLength(value: 0.2, unit: .meter))
    }

    @MainActor @Test(.timeLimit(.minutes(1)))
    func cylinder007CreatesExactInchNegativeXAxisSolidThroughProductionController() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder007).runReference()
        try assertRealizedCylinder(result, caseID: "CYL-007")
    }

    @MainActor @Test(.timeLimit(.minutes(1)))
    func cylinder007OracleRejectsSameNumericMillimeterSubstituteAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder007).run(
            action: Self.cylinder007Action(unit: .millimeter)
        )
        try assertRejectedPublishedCylinder(result)
    }

    @MainActor @Test(.timeLimit(.minutes(1)))
    func cylinder007RejectsZeroAxisBeforePublication() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder007).run(
            action: Self.cylinder007Action(axis: CADDirection3D(x: 0, y: 0, z: 0))
        )
        try assertRejectedPrepublicationCylinder(result)
    }

    @MainActor @Test(.timeLimit(.minutes(1)))
    func cylinder007TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCylinderCaseRunner(
            case: .cylinder007,
            timeoutWallNanoseconds: 1
        ).runReference()
        try assertTimedOutCylinder(result)
    }

    @Test
    func cylinder007ReferenceCandidatePreservesInchNegativeXAxisPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CYL-007")
        let decision = try await CADCylinderReferenceCandidate().decide(for: candidateContext(challenge))
        guard case .action(.automation(.solid(.cylinder(
            let name, let baseCenter, let axis, let radius, let depth
        )))) = decision else {
            Issue.record("CYL-007 candidate did not produce one solid cylinder action.")
            return
        }
        #expect(name == "CYL-007")
        #expect(baseCenter == CADPoint3D(x: 2, y: 3, z: -1, unit: .inch))
        #expect(axis == CADDirection3D(x: -1, y: 0, z: 0))
        #expect(radius == CADLength(value: 1, unit: .inch))
        #expect(depth == CADLength(value: 4, unit: .inch))
    }

    @MainActor @Test(.timeLimit(.minutes(1)))
    func cylinder008CreatesExactThreeAxisDiagonalSolidThroughProductionController() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder008).runReference()
        try assertRealizedCylinder(result, caseID: "CYL-008")
    }

    @MainActor @Test(.timeLimit(.minutes(1)))
    func cylinder008OracleRejectsNegativeZAxisSubstituteAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder008).run(
            action: Self.cylinder008Action(
                axis: CADDirection3D(
                    x: 0.57735026919,
                    y: 0.57735026919,
                    z: -0.57735026919
                )
            )
        )
        try assertRejectedPublishedCylinder(result)
    }

    @MainActor @Test(.timeLimit(.minutes(1)))
    func cylinder008RejectsZeroAxisBeforePublication() async throws {
        let result = try await CADCylinderCaseRunner(case: .cylinder008).run(
            action: Self.cylinder008Action(axis: CADDirection3D(x: 0, y: 0, z: 0))
        )
        try assertRejectedPrepublicationCylinder(result)
    }

    @MainActor @Test(.timeLimit(.minutes(1)))
    func cylinder008TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCylinderCaseRunner(
            case: .cylinder008,
            timeoutWallNanoseconds: 1
        ).runReference()
        try assertTimedOutCylinder(result)
    }

    @Test
    func cylinder008ReferenceCandidatePreservesThreeAxisDiagonalPublicValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CYL-008")
        let decision = try await CADCylinderReferenceCandidate().decide(for: candidateContext(challenge))
        guard case .action(.automation(.solid(.cylinder(
            let name, let baseCenter, let axis, let radius, let depth
        )))) = decision else {
            Issue.record("CYL-008 candidate did not produce one solid cylinder action.")
            return
        }
        #expect(name == "CYL-008")
        #expect(baseCenter == CADPoint3D(x: 100, y: 100, z: 100, unit: .millimeter))
        #expect(axis == CADDirection3D(x: 0.57735026919, y: 0.57735026919, z: 0.57735026919))
        #expect(radius == CADLength(value: 75, unit: .millimeter))
        #expect(depth == CADLength(value: 150, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executorActivatesReviewedCylindersAndUsesProductionCapability() async throws {
        let executor = DefaultCADActivatedCaseExecutor()

        #expect(executor.activatedCaseIDs.count == 77)
        #expect(executor.activatedCaseIDs.prefix(72).last == "CYL-008")
        #expect(executor.activatedCaseIDs.last == "CON-005")
        #expect(try executor.context(for: "CYL-001").capabilities.statuses.first?.available == true)
        let result = try await executor.evaluate(
            caseID: "CYL-001",
            candidate: CADCylinderReferenceCandidate()
        )
        #expect(result.outcome == .realized)
        do {
            _ = try executor.context(for: "CON-006")
            Issue.record("CON-006 must remain inactive.")
        } catch let error as CADActivatedCaseExecutorError {
            #expect(error == .inactiveCase("CON-006"))
        }
    }

    @Test
    func activatedCylinderBoundaryContainsOnlyReviewedCases() throws {
        #expect(CADActivatedCylinderCase.allCases == [.cylinder001, .cylinder002, .cylinder003, .cylinder004, .cylinder005, .cylinder006, .cylinder007, .cylinder008])
        for rejected in ["CYL-009", "BOX-001", "SPH-001"] {
            do {
                _ = try CADActivatedCylinderCase(caseID: rejected)
                Issue.record("\(rejected) must remain outside the cylinder activation boundary.")
            } catch let error as CADBenchmarkError {
                guard case .invalidCaseID(let observed) = error else {
                    Issue.record("Unexpected error for \(rejected): \(error)")
                    continue
                }
                #expect(observed == rejected)
            }
        }
    }

    private static func cylinderAction(
        radius: Double = 5,
        depth: Double = 20,
        axis: CADDirection3D = CADDirection3D(x: 0, y: 0, z: 1)
    ) -> CADCandidateAction {
        .automation(.solid(.cylinder(
            name: "CYL-001",
            baseCenter: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            axis: axis,
            radius: CADLength(value: radius, unit: .millimeter),
            depth: CADLength(value: depth, unit: .millimeter)
        )))
    }

    private static func cylinder002Action(
        axis: CADDirection3D = CADDirection3D(x: 1, y: 0, z: 0)
    ) -> CADCandidateAction {
        .automation(.solid(.cylinder(
            name: "CYL-002",
            baseCenter: CADPoint3D(x: 25, y: -25, z: 0, unit: .millimeter),
            axis: axis,
            radius: CADLength(value: 10, unit: .millimeter),
            depth: CADLength(value: 50, unit: .millimeter)
        )))
    }

    private static func cylinder003Action(
        axis: CADDirection3D = CADDirection3D(x: 0, y: 1, z: 0)
    ) -> CADCandidateAction {
        .automation(.solid(.cylinder(
            name: "CYL-003",
            baseCenter: CADPoint3D(x: -50, y: 20, z: 10, unit: .millimeter),
            axis: axis,
            radius: CADLength(value: 25, unit: .millimeter),
            depth: CADLength(value: 100, unit: .millimeter)
        )))
    }

    private static func cylinder004Action(
        axis: CADDirection3D = CADDirection3D(x: 0, y: 0, z: -1)
    ) -> CADCandidateAction {
        .automation(.solid(.cylinder(
            name: "CYL-004",
            baseCenter: CADPoint3D(x: 0, y: 0, z: -100, unit: .millimeter),
            axis: axis,
            radius: CADLength(value: 50, unit: .millimeter),
            depth: CADLength(value: 250, unit: .millimeter)
        )))
    }

    private static func cylinder005Action(
        axis: CADDirection3D = CADDirection3D(
            x: 0.707106781187,
            y: 0.707106781187,
            z: 0
        )
    ) -> CADCandidateAction {
        .automation(.solid(.cylinder(
            name: "CYL-005",
            baseCenter: CADPoint3D(x: 0, y: 0, z: 0, unit: .centimeter),
            axis: axis,
            radius: CADLength(value: 2, unit: .centimeter),
            depth: CADLength(value: 10, unit: .centimeter)
        )))
    }

    private static func cylinder006Action(
        axis: CADDirection3D = CADDirection3D(
            x: 0,
            y: 0.707106781187,
            z: 0.707106781187
        )
    ) -> CADCandidateAction {
        .automation(.solid(.cylinder(
            name: "CYL-006",
            baseCenter: CADPoint3D(x: -0.1, y: 0.05, z: 0, unit: .meter),
            axis: axis,
            radius: CADLength(value: 0.05, unit: .meter),
            depth: CADLength(value: 0.2, unit: .meter)
        )))
    }

    private static func cylinder007Action(
        unit: CADLengthUnit = .inch,
        axis: CADDirection3D = CADDirection3D(x: -1, y: 0, z: 0)
    ) -> CADCandidateAction {
        .automation(.solid(.cylinder(
            name: "CYL-007",
            baseCenter: CADPoint3D(x: 2, y: 3, z: -1, unit: unit),
            axis: axis,
            radius: CADLength(value: 1, unit: unit),
            depth: CADLength(value: 4, unit: unit)
        )))
    }

    private static func cylinder008Action(
        axis: CADDirection3D = CADDirection3D(
            x: 0.57735026919,
            y: 0.57735026919,
            z: 0.57735026919
        )
    ) -> CADCandidateAction {
        .automation(.solid(.cylinder(
            name: "CYL-008",
            baseCenter: CADPoint3D(x: 100, y: 100, z: 100, unit: .millimeter),
            axis: axis,
            radius: CADLength(value: 75, unit: .millimeter),
            depth: CADLength(value: 150, unit: .millimeter)
        )))
    }
}

private func assertRealizedCylinder(
    _ result: CADCylinderCaseResult,
    caseID: CADBenchmarkCaseID
) throws {
    try result.validate()
    #expect(result.caseID == caseID)
    #expect(
        result.outcome == .realized,
        Comment(rawValue: result.diagnostics.joined(separator: "\n"))
    )
    #expect(result.realized)
    #expect(result.candidateResult?.status == .published)
    #expect(result.candidateResult?.createdFeatureIDs.count == 2)
    #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.last)
    #expect(result.roleBindings?.bindings.first?.role == "solid")
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.finalDocumentGeneration.value == result.routeEvidence.initialDocumentGeneration.value + 1)
    #expect(result.routeEvidence.finalTransactionRevision.value == result.routeEvidence.initialTransactionRevision.value + 1)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
    #expect(result.routeEvidence.finalWorkspaceRevision == result.routeEvidence.initialWorkspaceRevision)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.telemetry.planningWallNanoseconds > 0)
    #expect(result.telemetry.routeWallNanoseconds > 0)
    #expect(result.telemetry.oracleWallNanoseconds > 0)
    #expect(result.telemetry.totalWallNanoseconds > 0)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount >= 1)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 2)
    #expect(result.telemetry.bodyCount == 1)
    #expect(result.telemetry.faceCount == 6)
    #expect(result.telemetry.edgeCount == 12)
    #expect(result.telemetry.vertexCount == 8)
}

private func assertRejectedPublishedCylinder(_ result: CADCylinderCaseResult) throws {
    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.routeEvidence.didPublish)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 1)
    #expect(result.telemetry.readCount == 2)
    #expect(result.telemetry.entityCount == 1)
    #expect(result.telemetry.featureCount == 2)
    #expect(result.telemetry.bodyCount == 1)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
    #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
}

private func assertRejectedPrepublicationCylinder(_ result: CADCylinderCaseResult) throws {
    try result.validate()
    #expect(result.outcome == .invalidSubmission)
    #expect(result.routeEvidence.didPublish == false)
    #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence)
    #expect(result.telemetry.actionCount == 1)
    #expect(result.telemetry.commandCount == 0)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

private func assertTimedOutCylinder(_ result: CADCylinderCaseResult) throws {
    try result.validate()
    #expect(result.outcome == .timeout)
    #expect(result.routeEvidence.didPublish == false)
    #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
    #expect(result.routeEvidence.cleanupCompleted)
    #expect(result.routeEvidence.remainingRegistrationCount == 0)
}

private enum CylinderFailureSourceReadError: Error {
    case unavailable
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
