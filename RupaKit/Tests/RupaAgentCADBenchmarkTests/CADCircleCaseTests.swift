import Foundation
import Testing
import RupaCore
import SwiftCAD
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADCircleCaseTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cir001CreatesExactAnalyticCircleThroughProductionController() async throws {
        let result = try await CADCircleCaseRunner(case: .cir001).runReference()

        try result.validate()
        #expect(result.caseID == "CIR-001")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 1)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.first)
        #expect(result.roleBindings?.bindings.count == 1)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 1)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cir001ProjectsWithinToleranceNormalOffsetOntoCanonicalPlane() async throws {
        let action = circleAction(
            name: "CIR-001.within-tolerance",
            center: CADPoint3D(
                x: 0,
                y: 0,
                z: ModelingTolerance.standard.distance * 0.5,
                unit: .meter
            ),
            radius: CADLength(value: 5, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir001).run(action: action)

        try result.validate()
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cir001OracleRejectsWrongRadiusAfterOnePublicationWithoutRetry() async throws {
        let action = circleAction(
            name: "CIR-001.wrong-radius",
            center: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            radius: CADLength(value: 6, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir001).run(action: action)

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
    func cir001OracleRejectsWrongInPlaneCenterAfterOnePublicationWithoutRetry() async throws {
        let action = circleAction(
            name: "CIR-001.wrong-center",
            center: CADPoint3D(x: 1, y: 0, z: 0, unit: .millimeter),
            radius: CADLength(value: 5, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir001).run(action: action)

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
    func cir001RejectsOffPlaneCenterBeforePublication() async throws {
        let action = circleAction(
            name: "CIR-001.off-plane",
            center: CADPoint3D(x: 0, y: 0, z: 2, unit: .millimeter),
            radius: CADLength(value: 5, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir001).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.initialPublicationSequence == result.routeEvidence.finalPublicationSequence)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cir001TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCircleCaseRunner(
            case: .cir001,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func cir001ReferenceCandidatePreservesPublicCircleValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CIR-001")
        let decision = try await CADCircleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.circle(
            _, let plane, let center, let radius
        )))) = decision else {
            Issue.record("CIR-001 candidate did not produce one circle action.")
            return
        }
        #expect(plane == .xy)
        #expect(center == CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter))
        #expect(radius == CADLength(value: 5, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cir002CreatesExactAnalyticCircleThroughProductionController() async throws {
        let result = try await CADCircleCaseRunner(case: .cir002).runReference()

        try result.validate()
        #expect(result.caseID == "CIR-002")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 1)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.first)
        #expect(result.roleBindings?.bindings.count == 1)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 1)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cir002OracleRejectsWorldOriginCenterAfterOnePublicationWithoutRetry() async throws {
        let action = circleAction(
            name: "CIR-002.world-origin",
            center: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            radius: CADLength(value: 12.5, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir002).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 1)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cir002RejectsOffPlaneCenterBeforePublication() async throws {
        let action = circleAction(
            name: "CIR-002.off-plane",
            center: CADPoint3D(x: 25, y: -10, z: 2, unit: .millimeter),
            radius: CADLength(value: 12.5, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir002).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.initialPublicationSequence == result.routeEvidence.finalPublicationSequence)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cir002TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCircleCaseRunner(
            case: .cir002,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func cir002ReferenceCandidatePreservesPublicCircleValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CIR-002")
        let decision = try await CADCircleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.circle(
            _, let plane, let center, let radius
        )))) = decision else {
            Issue.record("CIR-002 candidate did not produce one circle action.")
            return
        }
        #expect(plane == .xy)
        #expect(center == CADPoint3D(x: 25, y: -10, z: 0, unit: .millimeter))
        #expect(radius == CADLength(value: 12.5, unit: .millimeter))
    }

    @Test
    func cir003UsesPositiveYNormalAndRoundTripsXZWorldCoordinates() throws {
        let caseID: CADBenchmarkCaseID = "CIR-003"
        let targetCenter = CADPoint3D(x: 0, y: 0, z: 50, unit: .millimeter)
        let sourcePlane = try CADCircleGeometryMapping.sourcePlane(
            orientation: .xz,
            targetCenter: targetCenter,
            submittedCenter: targetCenter,
            modelingTolerance: ModelingTolerance.standard,
            caseID: caseID
        )
        let normal = CADCircleGeometryMapping.normal(for: .xz)
        #expect(normal.x == 0)
        #expect(normal.y == 1)
        #expect(normal.z == 0)

        let worldPoint = CADPoint3D(x: 12, y: 0, z: 58, unit: .millimeter)
        let localPoint = try CADCircleGeometryMapping.localPoint(
            from: worldPoint,
            sourcePlane: sourcePlane,
            modelingTolerance: ModelingTolerance.standard,
            caseID: caseID
        )
        let reconstructed = try CADCircleGeometryMapping.worldPoint(
            from: SketchEntitySummaryResult.Point(x: localPoint.x, y: localPoint.y),
            sourcePlane: sourcePlane,
            modelingTolerance: ModelingTolerance.standard
        )
        let expected = worldPoint.meters
        #expect(abs(reconstructed.x - expected.x) <= 1e-12)
        #expect(abs(reconstructed.y - expected.y) <= 1e-12)
        #expect(abs(reconstructed.z - expected.z) <= 1e-12)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cir003CreatesExactAnalyticXZCircleThroughProductionController() async throws {
        let result = try await CADCircleCaseRunner(case: .cir003).runReference()

        try result.validate()
        #expect(result.caseID == "CIR-003")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 1)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.first)
        #expect(result.roleBindings?.bindings.count == 1)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 1)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cir003OracleRejectsWorldOriginCenterAfterOnePublicationWithoutRetry() async throws {
        let action = circleAction(
            name: "CIR-003.world-origin",
            plane: .xz,
            center: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            radius: CADLength(value: 25, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir003).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 1)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cir003RejectsOffPlaneCenterBeforePublication() async throws {
        let action = circleAction(
            name: "CIR-003.off-plane",
            plane: .xz,
            center: CADPoint3D(x: 0, y: 2, z: 50, unit: .millimeter),
            radius: CADLength(value: 25, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir003).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.initialPublicationSequence == result.routeEvidence.finalPublicationSequence)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cir003TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCircleCaseRunner(
            case: .cir003,
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
    func cir003ReferenceCandidatePreservesPublicXZCircleValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CIR-003")
        let decision = try await CADCircleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.circle(
            _, let plane, let center, let radius
        )))) = decision else {
            Issue.record("CIR-003 candidate did not produce one circle action.")
            return
        }
        #expect(plane == .xz)
        #expect(center == CADPoint3D(x: 0, y: 0, z: 50, unit: .millimeter))
        #expect(radius == CADLength(value: 25, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executorActivatesCIR001ThroughCIR003AndRejectsCIR004() async throws {
        let executor = DefaultCADActivatedCaseExecutor()
        #expect(executor.activatedCaseIDs.last?.rawValue == "CIR-003")
        #expect(executor.activatedCaseIDs.contains("CIR-001"))
        #expect(executor.activatedCaseIDs.contains("CIR-002"))
        #expect(executor.activatedCaseIDs.contains("CIR-003"))

        do {
            _ = try executor.context(for: "CIR-004")
            Issue.record("CIR-004 must remain inactive.")
        } catch let error as CADActivatedCaseExecutorError {
            #expect(error == .inactiveCase("CIR-004"))
        }

        let result = try await executor.evaluate(
            caseID: "CIR-003",
            candidate: CADCircleReferenceCandidate()
        )
        #expect(result.outcome == .realized)
        try result.validate()
        let encoded = try JSONEncoder().encode(result)
        let text = String(decoding: encoded, as: UTF8.self)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(text.contains(forbidden) == false)
        }
    }
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

private func circleAction(
    name: String,
    plane: CADSketchPlane = .xy,
    center: CADPoint3D,
    radius: CADLength
) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: plane,
        center: center,
        radius: radius
    )))
}
