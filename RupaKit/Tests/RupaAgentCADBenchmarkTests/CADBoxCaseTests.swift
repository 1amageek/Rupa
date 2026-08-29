import Testing
import RupaCore
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADBoxCaseTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box001CreatesExactClosedSolidThroughProductionController() async throws {
        let result = try await CADBoxCaseRunner(case: .box001).runReference()

        try result.validate()
        #expect(result.caseID == "BOX-001")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 2)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.last)
        #expect(result.roleBindings?.bindings.count == 1)
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
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 6)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box001OracleRejectsWrongWidthAfterOnePublicationWithoutRetry() async throws {
        let action = boxAction(
            name: "BOX-001.wrong-width",
            origin: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 12, unit: .millimeter),
            depth: CADLength(value: 10, unit: .millimeter),
            height: CADLength(value: 10, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box001).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box001FailureTelemetryReadFailureIsAnOracleFailure() async throws {
        let action = boxAction(
            name: "BOX-001.wrong-width",
            origin: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 12, unit: .millimeter),
            depth: CADLength(value: 10, unit: .millimeter),
            height: CADLength(value: 10, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(
            case: .box001,
            failureSourceReader: { _ in throw BoxFailureSourceReadError.unavailable }
        ).run(action: action)

        try result.validate()
        #expect(result.outcome == .oracleFailure)
        #expect(result.telemetry.readCount == 2)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("failure telemetry read failed") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box001RejectsZeroHeightBeforePublication() async throws {
        let action = boxAction(
            name: "BOX-001.zero-height",
            origin: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 10, unit: .millimeter),
            depth: CADLength(value: 10, unit: .millimeter),
            height: CADLength(value: 0, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box001).run(action: action)

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
    func box001RejectsRectangleSketchSubstituteBeforePublication() async throws {
        let action = CADCandidateAction.automation(.sketch(.rectangle(
            name: "BOX-001.rectangle-substitute",
            plane: .xy,
            center: CADPoint3D(x: 5, y: 5, z: 0, unit: .millimeter),
            width: CADLength(value: 10, unit: .millimeter),
            height: CADLength(value: 10, unit: .millimeter)
        )))
        let result = try await CADBoxCaseRunner(case: .box001).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box001OracleRejectsWrongNormalPlacementAfterOnePublicationWithoutRetry() async throws {
        let action = boxAction(
            name: "BOX-001.off-plane",
            origin: CADPoint3D(x: 0, y: 0, z: 2, unit: .millimeter),
            width: CADLength(value: 10, unit: .millimeter),
            depth: CADLength(value: 10, unit: .millimeter),
            height: CADLength(value: 10, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box001).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box001TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADBoxCaseRunner(
            case: .box001,
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
    func box001ReferenceCandidatePreservesPublicLowerCornerAndDimensions() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "BOX-001")
        let decision = try await CADBoxReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.box(
            let name, let origin, let width, let depth, let height
        )))) = decision else {
            Issue.record("BOX-001 candidate did not produce one solid box action.")
            return
        }
        #expect(name == "BOX-001")
        #expect(origin == CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter))
        #expect(width == CADLength(value: 10, unit: .millimeter))
        #expect(depth == CADLength(value: 10, unit: .millimeter))
        #expect(height == CADLength(value: 10, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box002CreatesExactTranslatedCubeThroughProductionController() async throws {
        let result = try await CADBoxCaseRunner(case: .box002).runReference()

        try result.validate()
        #expect(result.caseID == "BOX-002")
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
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 6)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box002OracleRejectsWrongLowerCornerAfterOnePublicationWithoutRetry() async throws {
        let action = boxAction(
            name: "BOX-002.wrong-origin",
            origin: CADPoint3D(x: 25, y: -20, z: 0, unit: .millimeter),
            width: CADLength(value: 25, unit: .millimeter),
            depth: CADLength(value: 25, unit: .millimeter),
            height: CADLength(value: 25, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box002).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box002RejectsZeroWidthBeforePublication() async throws {
        let action = boxAction(
            name: "BOX-002.zero-width",
            origin: CADPoint3D(x: 20, y: -20, z: 0, unit: .millimeter),
            width: CADLength(value: 0, unit: .millimeter),
            depth: CADLength(value: 25, unit: .millimeter),
            height: CADLength(value: 25, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box002).run(action: action)

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
    func box002TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADBoxCaseRunner(
            case: .box002,
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
    func box002ReferenceCandidatePreservesTranslatedPublicCubeValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "BOX-002")
        let decision = try await CADBoxReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.box(
            let name, let origin, let width, let depth, let height
        )))) = decision else {
            Issue.record("BOX-002 candidate did not produce one solid box action.")
            return
        }
        #expect(name == "BOX-002")
        #expect(origin == CADPoint3D(x: 20, y: -20, z: 0, unit: .millimeter))
        #expect(width == CADLength(value: 25, unit: .millimeter))
        #expect(depth == CADLength(value: 25, unit: .millimeter))
        #expect(height == CADLength(value: 25, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box003CreatesExactTranslatedRectangularSolidThroughProductionController() async throws {
        let result = try await CADBoxCaseRunner(case: .box003).runReference()

        try result.validate()
        #expect(result.caseID == "BOX-003")
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
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 6)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box003OracleRejectsSwappedDepthAndHeightAfterOnePublicationWithoutRetry() async throws {
        let action = boxAction(
            name: "BOX-003.wrong-depth-height",
            origin: CADPoint3D(x: -25, y: 15, z: 5, unit: .millimeter),
            width: CADLength(value: 50, unit: .millimeter),
            depth: CADLength(value: 20, unit: .millimeter),
            height: CADLength(value: 30, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box003).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box003RejectsZeroDepthBeforePublication() async throws {
        let action = boxAction(
            name: "BOX-003.zero-depth",
            origin: CADPoint3D(x: -25, y: 15, z: 5, unit: .millimeter),
            width: CADLength(value: 50, unit: .millimeter),
            depth: CADLength(value: 0, unit: .millimeter),
            height: CADLength(value: 20, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box003).run(action: action)

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
    func box003TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADBoxCaseRunner(
            case: .box003,
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
    func box003ReferenceCandidatePreservesPublicRectangularValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "BOX-003")
        let decision = try await CADBoxReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.box(
            let name, let origin, let width, let depth, let height
        )))) = decision else {
            Issue.record("BOX-003 candidate did not produce one solid box action.")
            return
        }
        #expect(name == "BOX-003")
        #expect(origin == CADPoint3D(x: -25, y: 15, z: 5, unit: .millimeter))
        #expect(width == CADLength(value: 50, unit: .millimeter))
        #expect(depth == CADLength(value: 30, unit: .millimeter))
        #expect(height == CADLength(value: 20, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box004CreatesExactTranslatedRectangularSolidThroughProductionController() async throws {
        let result = try await CADBoxCaseRunner(case: .box004).runReference()

        try result.validate()
        #expect(result.caseID == "BOX-004")
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
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 6)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box004OracleRejectsWrongNormalPlacementAfterOnePublicationWithoutRetry() async throws {
        let action = boxAction(
            name: "BOX-004.wrong-origin-z",
            origin: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 100, unit: .millimeter),
            depth: CADLength(value: 50, unit: .millimeter),
            height: CADLength(value: 75, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box004).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box004RejectsZeroHeightBeforePublication() async throws {
        let action = boxAction(
            name: "BOX-004.zero-height",
            origin: CADPoint3D(x: 0, y: 0, z: -25, unit: .millimeter),
            width: CADLength(value: 100, unit: .millimeter),
            depth: CADLength(value: 50, unit: .millimeter),
            height: CADLength(value: 0, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box004).run(action: action)

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
    func box004RejectsOverflowedBottomCenterBeforePublication() async throws {
        let action = boxAction(
            name: "BOX-004.overflowed-bottom-center",
            origin: CADPoint3D(
                x: Double.greatestFiniteMagnitude,
                y: 0,
                z: -25,
                unit: .meter
            ),
            width: CADLength(value: Double.greatestFiniteMagnitude, unit: .meter),
            depth: CADLength(value: 50, unit: .millimeter),
            height: CADLength(value: 75, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box004).run(action: action)

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
    func box004TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADBoxCaseRunner(
            case: .box004,
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
    func box004ReferenceCandidatePreservesPublicRectangularValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "BOX-004")
        let decision = try await CADBoxReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.box(
            let name, let origin, let width, let depth, let height
        )))) = decision else {
            Issue.record("BOX-004 candidate did not produce one solid box action.")
            return
        }
        #expect(name == "BOX-004")
        #expect(origin == CADPoint3D(x: 0, y: 0, z: -25, unit: .millimeter))
        #expect(width == CADLength(value: 100, unit: .millimeter))
        #expect(depth == CADLength(value: 50, unit: .millimeter))
        #expect(height == CADLength(value: 75, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box005CreatesExactTranslatedRectangularSolidThroughProductionController() async throws {
        let result = try await CADBoxCaseRunner(case: .box005).runReference()

        try result.validate()
        #expect(result.caseID == "BOX-005")
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
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 6)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box005OracleRejectsWrongHeightAfterOnePublicationWithoutRetry() async throws {
        let action = boxAction(
            name: "BOX-005.wrong-height",
            origin: CADPoint3D(x: -125, y: -50, z: 0, unit: .millimeter),
            width: CADLength(value: 250, unit: .millimeter),
            depth: CADLength(value: 100, unit: .millimeter),
            height: CADLength(value: 100, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box005).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box005RejectsZeroWidthBeforePublication() async throws {
        let action = boxAction(
            name: "BOX-005.zero-width",
            origin: CADPoint3D(x: -125, y: -50, z: 0, unit: .millimeter),
            width: CADLength(value: 0, unit: .millimeter),
            depth: CADLength(value: 100, unit: .millimeter),
            height: CADLength(value: 125, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box005).run(action: action)

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
    func box005TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADBoxCaseRunner(
            case: .box005,
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
    func box005ReferenceCandidatePreservesPublicRectangularValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "BOX-005")
        let decision = try await CADBoxReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.box(
            let name, let origin, let width, let depth, let height
        )))) = decision else {
            Issue.record("BOX-005 candidate did not produce one solid box action.")
            return
        }
        #expect(name == "BOX-005")
        #expect(origin == CADPoint3D(x: -125, y: -50, z: 0, unit: .millimeter))
        #expect(width == CADLength(value: 250, unit: .millimeter))
        #expect(depth == CADLength(value: 100, unit: .millimeter))
        #expect(height == CADLength(value: 125, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box006CreatesExactMeterScaleSolidThroughProductionController() async throws {
        let result = try await CADBoxCaseRunner(case: .box006).runReference()

        try result.validate()
        #expect(result.caseID == "BOX-006")
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
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 6)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box006OracleRejectsCentimeterSubmissionAfterOnePublicationWithoutRetry() async throws {
        let action = boxAction(
            name: "BOX-006.wrong-unit",
            origin: CADPoint3D(x: 0, y: 0, z: 0, unit: .centimeter),
            width: CADLength(value: 0.1, unit: .centimeter),
            depth: CADLength(value: 0.05, unit: .centimeter),
            height: CADLength(value: 0.025, unit: .centimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box006).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box006RejectsZeroDepthBeforePublication() async throws {
        let action = boxAction(
            name: "BOX-006.zero-depth",
            origin: CADPoint3D(x: 0, y: 0, z: 0, unit: .meter),
            width: CADLength(value: 0.1, unit: .meter),
            depth: CADLength(value: 0, unit: .meter),
            height: CADLength(value: 0.025, unit: .meter)
        )
        let result = try await CADBoxCaseRunner(case: .box006).run(action: action)

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
    func box006TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADBoxCaseRunner(
            case: .box006,
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
    func box006ReferenceCandidatePreservesPublicMeterValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "BOX-006")
        let decision = try await CADBoxReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.box(
            let name, let origin, let width, let depth, let height
        )))) = decision else {
            Issue.record("BOX-006 candidate did not produce one solid box action.")
            return
        }
        #expect(name == "BOX-006")
        #expect(origin == CADPoint3D(x: 0, y: 0, z: 0, unit: .meter))
        #expect(width == CADLength(value: 0.1, unit: .meter))
        #expect(depth == CADLength(value: 0.05, unit: .meter))
        #expect(height == CADLength(value: 0.025, unit: .meter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box007CreatesExactImperialSolidThroughProductionController() async throws {
        let result = try await CADBoxCaseRunner(case: .box007).runReference()

        try result.validate()
        #expect(result.caseID == "BOX-007")
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
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 6)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box007OracleRejectsMillimeterSubmissionAfterOnePublicationWithoutRetry() async throws {
        let action = boxAction(
            name: "BOX-007.wrong-unit",
            origin: CADPoint3D(x: -1, y: -1, z: 0, unit: .millimeter),
            width: CADLength(value: 1, unit: .millimeter),
            depth: CADLength(value: 2, unit: .millimeter),
            height: CADLength(value: 3, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box007).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box007RejectsZeroHeightBeforePublication() async throws {
        let action = boxAction(
            name: "BOX-007.zero-height",
            origin: CADPoint3D(x: -1, y: -1, z: 0, unit: .inch),
            width: CADLength(value: 1, unit: .inch),
            depth: CADLength(value: 2, unit: .inch),
            height: CADLength(value: 0, unit: .inch)
        )
        let result = try await CADBoxCaseRunner(case: .box007).run(action: action)

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
    func box007TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADBoxCaseRunner(
            case: .box007,
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
    func box007ReferenceCandidatePreservesPublicImperialValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "BOX-007")
        let decision = try await CADBoxReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.box(
            let name, let origin, let width, let depth, let height
        )))) = decision else {
            Issue.record("BOX-007 candidate did not produce one solid box action.")
            return
        }
        #expect(name == "BOX-007")
        #expect(origin == CADPoint3D(x: -1, y: -1, z: 0, unit: .inch))
        #expect(width == CADLength(value: 1, unit: .inch))
        #expect(depth == CADLength(value: 2, unit: .inch))
        #expect(height == CADLength(value: 3, unit: .inch))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box008CreatesExactTranslatedCubeThroughProductionController() async throws {
        let result = try await CADBoxCaseRunner(case: .box008).runReference()

        try result.validate()
        #expect(result.caseID == "BOX-008")
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
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 6)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box008OracleRejectsWrongLowerCornerAfterOnePublicationWithoutRetry() async throws {
        let action = boxAction(
            name: "BOX-008.wrong-origin",
            origin: CADPoint3D(x: 0, y: 100, z: 100, unit: .millimeter),
            width: CADLength(value: 300, unit: .millimeter),
            depth: CADLength(value: 300, unit: .millimeter),
            height: CADLength(value: 300, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box008).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box008RejectsZeroWidthBeforePublication() async throws {
        let action = boxAction(
            name: "BOX-008.zero-width",
            origin: CADPoint3D(x: 100, y: 100, z: 100, unit: .millimeter),
            width: CADLength(value: 0, unit: .millimeter),
            depth: CADLength(value: 300, unit: .millimeter),
            height: CADLength(value: 300, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box008).run(action: action)

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
    func box008TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADBoxCaseRunner(
            case: .box008,
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
    func box008ReferenceCandidatePreservesPublicMillimeterCubeValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "BOX-008")
        let decision = try await CADBoxReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.box(
            let name, let origin, let width, let depth, let height
        )))) = decision else {
            Issue.record("BOX-008 candidate did not produce one solid box action.")
            return
        }
        #expect(name == "BOX-008")
        #expect(origin == CADPoint3D(x: 100, y: 100, z: 100, unit: .millimeter))
        #expect(width == CADLength(value: 300, unit: .millimeter))
        #expect(depth == CADLength(value: 300, unit: .millimeter))
        #expect(height == CADLength(value: 300, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box009CreatesExactNegativePlacementCubeThroughProductionController() async throws {
        let result = try await CADBoxCaseRunner(case: .box009).runReference()

        try result.validate()
        #expect(result.caseID == "BOX-009")
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
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 6)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box009OracleRejectsWrongHeightAfterOnePublicationWithoutRetry() async throws {
        let action = boxAction(
            name: "BOX-009.wrong-height",
            origin: CADPoint3D(x: -12, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 12, unit: .millimeter),
            depth: CADLength(value: 12, unit: .millimeter),
            height: CADLength(value: 10, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box009).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box009RejectsZeroDepthBeforePublication() async throws {
        let action = boxAction(
            name: "BOX-009.zero-depth",
            origin: CADPoint3D(x: -12, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 12, unit: .millimeter),
            depth: CADLength(value: 0, unit: .millimeter),
            height: CADLength(value: 12, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box009).run(action: action)

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
    func box009TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADBoxCaseRunner(
            case: .box009,
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
    func box009ReferenceCandidatePreservesPublicNegativePlacementCubeValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "BOX-009")
        let decision = try await CADBoxReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.box(
            let name, let origin, let width, let depth, let height
        )))) = decision else {
            Issue.record("BOX-009 candidate did not produce one solid box action.")
            return
        }
        #expect(name == "BOX-009")
        #expect(origin == CADPoint3D(x: -12, y: 0, z: 0, unit: .millimeter))
        #expect(width == CADLength(value: 12, unit: .millimeter))
        #expect(depth == CADLength(value: 12, unit: .millimeter))
        #expect(height == CADLength(value: 12, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box010CreatesExactRectangularSolidThroughProductionController() async throws {
        let result = try await CADBoxCaseRunner(case: .box010).runReference()

        try result.validate()
        #expect(result.caseID == "BOX-010")
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
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 6)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box010OracleRejectsSwappedWidthAndDepthAfterOnePublicationWithoutRetry() async throws {
        let action = boxAction(
            name: "BOX-010.swapped-width-depth",
            origin: CADPoint3D(x: 0, y: -100, z: 50, unit: .millimeter),
            width: CADLength(value: 200, unit: .millimeter),
            depth: CADLength(value: 400, unit: .millimeter),
            height: CADLength(value: 50, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box010).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box010RejectsZeroHeightBeforePublication() async throws {
        let action = boxAction(
            name: "BOX-010.zero-height",
            origin: CADPoint3D(x: 0, y: -100, z: 50, unit: .millimeter),
            width: CADLength(value: 400, unit: .millimeter),
            depth: CADLength(value: 200, unit: .millimeter),
            height: CADLength(value: 0, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box010).run(action: action)

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
    func box010TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADBoxCaseRunner(
            case: .box010,
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
    func box010ReferenceCandidatePreservesPublicRectangularSolidValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "BOX-010")
        let decision = try await CADBoxReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.box(
            let name, let origin, let width, let depth, let height
        )))) = decision else {
            Issue.record("BOX-010 candidate did not produce one solid box action.")
            return
        }
        #expect(name == "BOX-010")
        #expect(origin == CADPoint3D(x: 0, y: -100, z: 50, unit: .millimeter))
        #expect(width == CADLength(value: 400, unit: .millimeter))
        #expect(depth == CADLength(value: 200, unit: .millimeter))
        #expect(height == CADLength(value: 50, unit: .millimeter))
    }

    @Test
    func activatedBoxBoundaryContainsOnlyReviewedCases() throws {
        #expect(CADActivatedBoxCase.allCases == [.box001, .box002, .box003, .box004, .box005, .box006, .box007, .box008, .box009, .box010])
        for rejectedCaseID in ["BOX-011", "REC-001", "CIR-001"] {
            do {
                _ = try CADActivatedBoxCase(caseID: rejectedCaseID)
                Issue.record("\(rejectedCaseID) must remain outside the box activation boundary.")
            } catch let error as CADBenchmarkError {
                guard case .invalidCaseID(let observed) = error,
                      observed == rejectedCaseID else {
                    Issue.record("Unexpected typed error for \(rejectedCaseID): \(error)")
                    continue
                }
            }
        }
    }

    private func boxAction(
        name: String,
        origin: CADPoint3D,
        width: CADLength,
        depth: CADLength,
        height: CADLength
    ) -> CADCandidateAction {
        .automation(.solid(.box(
            name: name,
            origin: origin,
            width: width,
            depth: depth,
            height: height
        )))
    }
}

private enum BoxFailureSourceReadError: Error {
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
