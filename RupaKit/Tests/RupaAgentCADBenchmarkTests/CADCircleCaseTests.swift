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

    @Test
    func cir004UsesPositiveXNormalAndRoundTripsYZWorldCoordinates() throws {
        let caseID: CADBenchmarkCaseID = "CIR-004"
        let targetCenter = CADPoint3D(x: -75, y: 0, z: 0, unit: .millimeter)
        let sourcePlane = try CADCircleGeometryMapping.sourcePlane(
            orientation: .yz,
            targetCenter: targetCenter,
            submittedCenter: targetCenter,
            modelingTolerance: ModelingTolerance.standard,
            caseID: caseID
        )
        let normal = CADCircleGeometryMapping.normal(for: .yz)
        #expect(normal.x == 1)
        #expect(normal.y == 0)
        #expect(normal.z == 0)

        let worldPoint = CADPoint3D(x: -75, y: 12, z: -8, unit: .millimeter)
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
    func cir004CreatesExactAnalyticYZCircleThroughProductionController() async throws {
        let result = try await CADCircleCaseRunner(case: .cir004).runReference()

        try result.validate()
        #expect(result.caseID == "CIR-004")
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
    func cir004OracleRejectsWrongInPlaneCenterAfterOnePublicationWithoutRetry() async throws {
        let action = circleAction(
            name: "CIR-004.wrong-center",
            plane: .yz,
            center: CADPoint3D(x: -75, y: 10, z: 0, unit: .millimeter),
            radius: CADLength(value: 50, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir004).run(action: action)

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
    func cir004RejectsOffPlaneCenterBeforePublication() async throws {
        let action = circleAction(
            name: "CIR-004.off-plane",
            plane: .yz,
            center: CADPoint3D(x: -73, y: 0, z: 0, unit: .millimeter),
            radius: CADLength(value: 50, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir004).run(action: action)

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
    func cir004TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCircleCaseRunner(
            case: .cir004,
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
    func cir004ReferenceCandidatePreservesPublicYZCircleValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CIR-004")
        let decision = try await CADCircleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.circle(
            _, let plane, let center, let radius
        )))) = decision else {
            Issue.record("CIR-004 candidate did not produce one circle action.")
            return
        }
        #expect(plane == .yz)
        #expect(center == CADPoint3D(x: -75, y: 0, z: 0, unit: .millimeter))
        #expect(radius == CADLength(value: 50, unit: .millimeter))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cir005CreatesExactLargeTranslatedXYCircleThroughProductionController() async throws {
        let result = try await CADCircleCaseRunner(case: .cir005).runReference()

        try result.validate()
        #expect(result.caseID == "CIR-005")
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
    func cir005OracleRejectsWrongRadiusAfterOnePublicationWithoutRetry() async throws {
        let action = circleAction(
            name: "CIR-005.wrong-radius",
            center: CADPoint3D(x: 100, y: 100, z: 0, unit: .millimeter),
            radius: CADLength(value: 50, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir005).run(action: action)

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
    func cir005RejectsOffPlaneCenterBeforePublication() async throws {
        let action = circleAction(
            name: "CIR-005.off-plane",
            center: CADPoint3D(x: 100, y: 100, z: 2, unit: .millimeter),
            radius: CADLength(value: 100, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir005).run(action: action)

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
    func cir005TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCircleCaseRunner(
            case: .cir005,
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
    func cir005ReferenceCandidatePreservesPublicTranslatedXYCircleValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CIR-005")
        let decision = try await CADCircleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.circle(
            _, let plane, let center, let radius
        )))) = decision else {
            Issue.record("CIR-005 candidate did not produce one circle action.")
            return
        }
        #expect(plane == .xy)
        #expect(center == CADPoint3D(x: 100, y: 100, z: 0, unit: .millimeter))
        #expect(radius == CADLength(value: 100, unit: .millimeter))
    }

    @Test
    func cir006UsesCentimeterConversionAndPositiveYNormal() throws {
        let caseID: CADBenchmarkCaseID = "CIR-006"
        let targetCenter = CADPoint3D(x: 0, y: 0, z: 20, unit: .centimeter)
        let radius = CADLength(value: 2, unit: .centimeter)
        #expect(abs(targetCenter.meters.z - 0.2) <= 1e-12)
        #expect(abs(radius.meters - 0.02) <= 1e-12)

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

        let worldPoint = CADPoint3D(x: 1, y: 0, z: 21, unit: .centimeter)
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
    func cir006CreatesExactCentimeterXZCircleThroughProductionController() async throws {
        let result = try await CADCircleCaseRunner(case: .cir006).runReference()

        try result.validate()
        #expect(result.caseID == "CIR-006")
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
    func cir006OracleRejectsMillimeterRadiusAfterOnePublicationWithoutRetry() async throws {
        let action = circleAction(
            name: "CIR-006.wrong-radius",
            plane: .xz,
            center: CADPoint3D(x: 0, y: 0, z: 20, unit: .centimeter),
            radius: CADLength(value: 2, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir006).run(action: action)

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
    func cir006RejectsOffPlaneCenterBeforePublication() async throws {
        let action = circleAction(
            name: "CIR-006.off-plane",
            plane: .xz,
            center: CADPoint3D(x: 0, y: 0.2, z: 20, unit: .centimeter),
            radius: CADLength(value: 2, unit: .centimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir006).run(action: action)

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
    func cir006TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCircleCaseRunner(
            case: .cir006,
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
    func cir006ReferenceCandidatePreservesPublicCentimeterXZCircleValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CIR-006")
        let decision = try await CADCircleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.circle(
            _, let plane, let center, let radius
        )))) = decision else {
            Issue.record("CIR-006 candidate did not produce one circle action.")
            return
        }
        #expect(plane == .xz)
        #expect(center == CADPoint3D(x: 0, y: 0, z: 20, unit: .centimeter))
        #expect(radius == CADLength(value: 2, unit: .centimeter))
        #expect(abs(center.meters.z - 0.2) <= 1e-12)
        #expect(abs(radius.meters - 0.02) <= 1e-12)
    }

    @Test
    func cir007UsesMeterConversionAndPositiveXNormalForSignedYZPlacement() throws {
        let caseID: CADBenchmarkCaseID = "CIR-007"
        let targetCenter = CADPoint3D(x: 0, y: -0.1, z: 0, unit: .meter)
        let radius = CADLength(value: 0.1, unit: .meter)
        #expect(abs(targetCenter.meters.y + 0.1) <= 1e-12)
        #expect(abs(radius.meters - 0.1) <= 1e-12)

        let sourcePlane = try CADCircleGeometryMapping.sourcePlane(
            orientation: .yz,
            targetCenter: targetCenter,
            submittedCenter: targetCenter,
            modelingTolerance: ModelingTolerance.standard,
            caseID: caseID
        )
        let normal = CADCircleGeometryMapping.normal(for: .yz)
        #expect(normal.x == 1)
        #expect(normal.y == 0)
        #expect(normal.z == 0)

        let worldPoint = CADPoint3D(x: 0, y: -0.05, z: 0.04, unit: .meter)
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
    func cir007CreatesExactMeterYZCircleThroughProductionController() async throws {
        let result = try await CADCircleCaseRunner(case: .cir007).runReference()

        try result.validate()
        #expect(result.caseID == "CIR-007")
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
    func cir007OracleRejectsMirroredInPlaneCenterAfterOnePublicationWithoutRetry() async throws {
        let action = circleAction(
            name: "CIR-007.wrong-center",
            plane: .yz,
            center: CADPoint3D(x: 0, y: 0.1, z: 0, unit: .meter),
            radius: CADLength(value: 0.1, unit: .meter)
        )
        let result = try await CADCircleCaseRunner(case: .cir007).run(action: action)

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
    func cir007RejectsOffPlaneCenterBeforePublication() async throws {
        let action = circleAction(
            name: "CIR-007.off-plane",
            plane: .yz,
            center: CADPoint3D(x: 0.002, y: -0.1, z: 0, unit: .meter),
            radius: CADLength(value: 0.1, unit: .meter)
        )
        let result = try await CADCircleCaseRunner(case: .cir007).run(action: action)

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
    func cir007TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCircleCaseRunner(
            case: .cir007,
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
    func cir007ReferenceCandidatePreservesPublicMeterYZCircleValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CIR-007")
        let decision = try await CADCircleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.circle(
            _, let plane, let center, let radius
        )))) = decision else {
            Issue.record("CIR-007 candidate did not produce one circle action.")
            return
        }
        #expect(plane == .yz)
        #expect(center == CADPoint3D(x: 0, y: -0.1, z: 0, unit: .meter))
        #expect(radius == CADLength(value: 0.1, unit: .meter))
        #expect(abs(center.meters.y + 0.1) <= 1e-12)
        #expect(abs(radius.meters - 0.1) <= 1e-12)
    }

    @Test
    func cir008UsesInchConversionAndMixedSignXYPlacement() throws {
        let caseID: CADBenchmarkCaseID = "CIR-008"
        let targetCenter = CADPoint3D(x: -2, y: 3, z: 0, unit: .inch)
        let radius = CADLength(value: 1, unit: .inch)
        #expect(abs(targetCenter.meters.x + 0.0508) <= 1e-12)
        #expect(abs(targetCenter.meters.y - 0.0762) <= 1e-12)
        #expect(abs(radius.meters - 0.0254) <= 1e-12)

        let sourcePlane = try CADCircleGeometryMapping.sourcePlane(
            orientation: .xy,
            targetCenter: targetCenter,
            submittedCenter: targetCenter,
            modelingTolerance: ModelingTolerance.standard,
            caseID: caseID
        )
        let normal = CADCircleGeometryMapping.normal(for: .xy)
        #expect(normal.x == 0)
        #expect(normal.y == 0)
        #expect(normal.z == 1)

        let worldPoint = CADPoint3D(x: -1, y: 4, z: 0, unit: .inch)
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
    func cir008CreatesExactInchXYCircleThroughProductionController() async throws {
        let result = try await CADCircleCaseRunner(case: .cir008).runReference()

        try result.validate()
        #expect(result.caseID == "CIR-008")
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
    func cir008OracleRejectsMillimeterRadiusAfterOnePublicationWithoutRetry() async throws {
        let action = circleAction(
            name: "CIR-008.wrong-radius",
            plane: .xy,
            center: CADPoint3D(x: -2, y: 3, z: 0, unit: .inch),
            radius: CADLength(value: 1, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir008).run(action: action)

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
    func cir008RejectsOffPlaneCenterBeforePublication() async throws {
        let action = circleAction(
            name: "CIR-008.off-plane",
            plane: .xy,
            center: CADPoint3D(x: -2, y: 3, z: 0.1, unit: .inch),
            radius: CADLength(value: 1, unit: .inch)
        )
        let result = try await CADCircleCaseRunner(case: .cir008).run(action: action)

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
    func cir008TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCircleCaseRunner(
            case: .cir008,
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
    func cir008ReferenceCandidatePreservesPublicInchXYCircleValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CIR-008")
        let decision = try await CADCircleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.circle(
            _, let plane, let center, let radius
        )))) = decision else {
            Issue.record("CIR-008 candidate did not produce one circle action.")
            return
        }
        #expect(plane == .xy)
        #expect(center == CADPoint3D(x: -2, y: 3, z: 0, unit: .inch))
        #expect(radius == CADLength(value: 1, unit: .inch))
        #expect(abs(center.meters.x + 0.0508) <= 1e-12)
        #expect(abs(center.meters.y - 0.0762) <= 1e-12)
        #expect(abs(radius.meters - 0.0254) <= 1e-12)
    }

    @Test
    func cir009UsesNegativeZCentricXZPlacementAndPositiveYNormal() throws {
        let caseID: CADBenchmarkCaseID = "CIR-009"
        let targetCenter = CADPoint3D(x: 0, y: 0, z: -125, unit: .millimeter)
        let radius = CADLength(value: 250, unit: .millimeter)
        #expect(abs(targetCenter.meters.z + 0.125) <= 1e-12)
        #expect(abs(radius.meters - 0.25) <= 1e-12)

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

        let worldPoint = CADPoint3D(x: 120, y: 0, z: -80, unit: .millimeter)
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
    func cir009CreatesExactNegativeZCircleThroughProductionController() async throws {
        let result = try await CADCircleCaseRunner(case: .cir009).runReference()

        try result.validate()
        #expect(result.caseID == "CIR-009")
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
    func cir009OracleRejectsMirroredInPlaneCenterAfterOnePublicationWithoutRetry() async throws {
        let action = circleAction(
            name: "CIR-009.wrong-center",
            plane: .xz,
            center: CADPoint3D(x: 0, y: 0, z: 125, unit: .millimeter),
            radius: CADLength(value: 250, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir009).run(action: action)

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
    func cir009RejectsOffPlaneCenterBeforePublication() async throws {
        let action = circleAction(
            name: "CIR-009.off-plane",
            plane: .xz,
            center: CADPoint3D(x: 0, y: 2, z: -125, unit: .millimeter),
            radius: CADLength(value: 250, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir009).run(action: action)

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
    func cir009TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCircleCaseRunner(
            case: .cir009,
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
    func cir009ReferenceCandidatePreservesPublicNegativeZMillimeterXZCircleValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CIR-009")
        let decision = try await CADCircleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.circle(
            _, let plane, let center, let radius
        )))) = decision else {
            Issue.record("CIR-009 candidate did not produce one circle action.")
            return
        }
        #expect(plane == .xz)
        #expect(center == CADPoint3D(x: 0, y: 0, z: -125, unit: .millimeter))
        #expect(radius == CADLength(value: 250, unit: .millimeter))
        #expect(abs(center.meters.z + 0.125) <= 1e-12)
        #expect(abs(radius.meters - 0.25) <= 1e-12)
    }

    @Test
    func cir010UsesMetreScaleAndMixedSignXYPlacement() throws {
        let caseID: CADBenchmarkCaseID = "CIR-010"
        let targetCenter = CADPoint3D(x: 0.5, y: -0.5, z: 0, unit: .meter)
        let radius = CADLength(value: 0.5, unit: .meter)
        #expect(abs(targetCenter.meters.x - 0.5) <= 1e-12)
        #expect(abs(targetCenter.meters.y + 0.5) <= 1e-12)
        #expect(abs(radius.meters - 0.5) <= 1e-12)

        let sourcePlane = try CADCircleGeometryMapping.sourcePlane(
            orientation: .xy,
            targetCenter: targetCenter,
            submittedCenter: targetCenter,
            modelingTolerance: ModelingTolerance.standard,
            caseID: caseID
        )
        let normal = CADCircleGeometryMapping.normal(for: .xy)
        #expect(normal.x == 0)
        #expect(normal.y == 0)
        #expect(normal.z == 1)

        let worldPoint = CADPoint3D(x: 0.75, y: -0.25, z: 0, unit: .meter)
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
    func cir010CreatesExactMetreScaleXYCircleThroughProductionController() async throws {
        let result = try await CADCircleCaseRunner(case: .cir010).runReference()

        try result.validate()
        #expect(result.caseID == "CIR-010")
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
    func cir010OracleRejectsOppositeSignedYCenterAfterOnePublicationWithoutRetry() async throws {
        let action = circleAction(
            name: "CIR-010.wrong-center",
            plane: .xy,
            center: CADPoint3D(x: 0.5, y: 0.5, z: 0, unit: .meter),
            radius: CADLength(value: 0.5, unit: .meter)
        )
        let result = try await CADCircleCaseRunner(case: .cir010).run(action: action)

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
    func cir010RejectsOffPlaneCenterBeforePublication() async throws {
        let action = circleAction(
            name: "CIR-010.off-plane",
            plane: .xy,
            center: CADPoint3D(x: 0.5, y: -0.5, z: 0.002, unit: .meter),
            radius: CADLength(value: 0.5, unit: .meter)
        )
        let result = try await CADCircleCaseRunner(case: .cir010).run(action: action)

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
    func cir010TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCircleCaseRunner(
            case: .cir010,
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
    func cir010ReferenceCandidatePreservesPublicMetreMixedSignXYCircleValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CIR-010")
        let decision = try await CADCircleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.circle(
            _, let plane, let center, let radius
        )))) = decision else {
            Issue.record("CIR-010 candidate did not produce one circle action.")
            return
        }
        #expect(plane == .xy)
        #expect(center == CADPoint3D(x: 0.5, y: -0.5, z: 0, unit: .meter))
        #expect(radius == CADLength(value: 0.5, unit: .meter))
        #expect(abs(center.meters.x - 0.5) <= 1e-12)
        #expect(abs(center.meters.y + 0.5) <= 1e-12)
        #expect(abs(radius.meters - 0.5) <= 1e-12)
    }

    @Test
    func cir011UsesFractionalRadiusAndOffsetYZPlane() throws {
        let caseID: CADBenchmarkCaseID = "CIR-011"
        let targetCenter = CADPoint3D(x: 20, y: 0, z: 30, unit: .millimeter)
        let radius = CADLength(value: 7.25, unit: .millimeter)
        #expect(abs(targetCenter.meters.x - 0.02) <= 1e-12)
        #expect(abs(targetCenter.meters.z - 0.03) <= 1e-12)
        #expect(abs(radius.meters - 0.00725) <= 1e-12)

        let sourcePlane = try CADCircleGeometryMapping.sourcePlane(
            orientation: .yz,
            targetCenter: targetCenter,
            submittedCenter: targetCenter,
            modelingTolerance: ModelingTolerance.standard,
            caseID: caseID
        )
        let normal = CADCircleGeometryMapping.normal(for: .yz)
        #expect(normal.x == 1)
        #expect(normal.y == 0)
        #expect(normal.z == 0)

        let worldPoint = CADPoint3D(x: 20, y: 10, z: 45, unit: .millimeter)
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
    func cir011CreatesExactFractionalRadiusOffsetYZCircleThroughProductionController() async throws {
        let result = try await CADCircleCaseRunner(case: .cir011).runReference()

        try result.validate()
        #expect(result.caseID == "CIR-011")
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
    func cir011OracleRejectsMirroredInPlaneZCenterAfterOnePublicationWithoutRetry() async throws {
        let action = circleAction(
            name: "CIR-011.wrong-center",
            plane: .yz,
            center: CADPoint3D(x: 20, y: 0, z: -30, unit: .millimeter),
            radius: CADLength(value: 7.25, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir011).run(action: action)

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
    func cir011RejectsOffPlaneCenterBeforePublication() async throws {
        let action = circleAction(
            name: "CIR-011.off-plane",
            plane: .yz,
            center: CADPoint3D(x: 22, y: 0, z: 30, unit: .millimeter),
            radius: CADLength(value: 7.25, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir011).run(action: action)

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
    func cir011TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCircleCaseRunner(
            case: .cir011,
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
    func cir011ReferenceCandidatePreservesPublicFractionalRadiusOffsetYZCircleValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CIR-011")
        let decision = try await CADCircleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.circle(
            _, let plane, let center, let radius
        )))) = decision else {
            Issue.record("CIR-011 candidate did not produce one circle action.")
            return
        }
        #expect(plane == .yz)
        #expect(center == CADPoint3D(x: 20, y: 0, z: 30, unit: .millimeter))
        #expect(radius == CADLength(value: 7.25, unit: .millimeter))
        #expect(abs(center.meters.x - 0.02) <= 1e-12)
        #expect(abs(center.meters.z - 0.03) <= 1e-12)
        #expect(abs(radius.meters - 0.00725) <= 1e-12)
    }

    @Test
    func cir012UsesMixedSignXYPlacementAndMillimeterRadius() throws {
        let caseID: CADBenchmarkCaseID = "CIR-012"
        let targetCenter = CADPoint3D(x: -80, y: 45, z: 0, unit: .millimeter)
        let radius = CADLength(value: 42, unit: .millimeter)
        #expect(abs(targetCenter.meters.x + 0.08) <= 1e-12)
        #expect(abs(targetCenter.meters.y - 0.045) <= 1e-12)
        #expect(abs(radius.meters - 0.042) <= 1e-12)

        let sourcePlane = try CADCircleGeometryMapping.sourcePlane(
            orientation: .xy,
            targetCenter: targetCenter,
            submittedCenter: targetCenter,
            modelingTolerance: ModelingTolerance.standard,
            caseID: caseID
        )
        let normal = CADCircleGeometryMapping.normal(for: .xy)
        #expect(normal.x == 0)
        #expect(normal.y == 0)
        #expect(normal.z == 1)

        let worldPoint = CADPoint3D(x: -38, y: 87, z: 0, unit: .millimeter)
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
    func cir012CreatesExactMixedSignXYCircleThroughProductionController() async throws {
        let result = try await CADCircleCaseRunner(case: .cir012).runReference()

        try result.validate()
        #expect(result.caseID == "CIR-012")
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
    func cir012OracleRejectsMirroredInPlaneXCenterAfterOnePublicationWithoutRetry() async throws {
        let action = circleAction(
            name: "CIR-012.wrong-center",
            plane: .xy,
            center: CADPoint3D(x: 80, y: 45, z: 0, unit: .millimeter),
            radius: CADLength(value: 42, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir012).run(action: action)

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
    func cir012RejectsOffPlaneCenterBeforePublication() async throws {
        let action = circleAction(
            name: "CIR-012.off-plane",
            plane: .xy,
            center: CADPoint3D(x: -80, y: 45, z: 2, unit: .millimeter),
            radius: CADLength(value: 42, unit: .millimeter)
        )
        let result = try await CADCircleCaseRunner(case: .cir012).run(action: action)

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
    func cir012TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADCircleCaseRunner(
            case: .cir012,
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
    func cir012ReferenceCandidatePreservesPublicMixedSignXYCircleValues() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CIR-012")
        let decision = try await CADCircleReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.circle(
            _, let plane, let center, let radius
        )))) = decision else {
            Issue.record("CIR-012 candidate did not produce one circle action.")
            return
        }
        #expect(plane == .xy)
        #expect(center == CADPoint3D(x: -80, y: 45, z: 0, unit: .millimeter))
        #expect(radius == CADLength(value: 42, unit: .millimeter))
        #expect(abs(center.meters.x + 0.08) <= 1e-12)
        #expect(abs(center.meters.y - 0.045) <= 1e-12)
        #expect(abs(radius.meters - 0.042) <= 1e-12)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executorRetainsCIR001ThroughCIR012AfterBOX011Activation() async throws {
        let executor = DefaultCADActivatedCaseExecutor()
        #expect(executor.activatedCaseIDs.last?.rawValue == "BOX-011")
        #expect(executor.activatedCaseIDs.contains("CIR-001"))
        #expect(executor.activatedCaseIDs.contains("CIR-002"))
        #expect(executor.activatedCaseIDs.contains("CIR-003"))
        #expect(executor.activatedCaseIDs.contains("CIR-004"))
        #expect(executor.activatedCaseIDs.contains("CIR-005"))
        #expect(executor.activatedCaseIDs.contains("CIR-006"))
        #expect(executor.activatedCaseIDs.contains("CIR-007"))
        #expect(executor.activatedCaseIDs.contains("CIR-008"))
        #expect(executor.activatedCaseIDs.contains("CIR-009"))
        #expect(executor.activatedCaseIDs.contains("CIR-010"))
        #expect(executor.activatedCaseIDs.contains("CIR-011"))
        #expect(executor.activatedCaseIDs.contains("CIR-012"))

        #expect(try executor.context(for: "BOX-001").challenge.id == "BOX-001")
        do {
            _ = try executor.context(for: "BOX-012")
            Issue.record("BOX-012 must remain inactive.")
        } catch let error as CADActivatedCaseExecutorError {
            #expect(error == .inactiveCase("BOX-012"))
        }

        let result = try await executor.evaluate(
            caseID: "CIR-012",
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
