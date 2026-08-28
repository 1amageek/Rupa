import Foundation
import Testing
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
    func executorActivatesOnlyCIR001AndRejectsCIR002() async throws {
        let executor = DefaultCADActivatedCaseExecutor()
        #expect(executor.activatedCaseIDs.last?.rawValue == "CIR-001")
        #expect(executor.activatedCaseIDs.contains("CIR-002") == false)

        do {
            _ = try executor.context(for: "CIR-002")
            Issue.record("CIR-002 must remain inactive.")
        } catch let error as CADActivatedCaseExecutorError {
            #expect(error == .inactiveCase("CIR-002"))
        }

        let result = try await executor.evaluate(
            caseID: "CIR-001",
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
    center: CADPoint3D,
    radius: CADLength
) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .xy,
        center: center,
        radius: radius
    )))
}
