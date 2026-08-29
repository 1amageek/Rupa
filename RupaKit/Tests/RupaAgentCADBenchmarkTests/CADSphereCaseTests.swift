import Foundation
import Testing
import RupaAgentRuntime
import SwiftCAD
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADSphereCaseTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: CADSpherePreparationCase.allCases)
    func allSphereCasesMapUnavailableCapabilityToExpectedUnsupported(
        preparationCase: CADSpherePreparationCase
    ) async throws {
        let result = try await CADSphereCaseRunner(case: preparationCase).runReference()

        try result.validate()
        #expect(result.caseID == preparationCase.caseID)
        #expect(result.outcome == .expectedUnsupported)
        #expect(result.realized == false)
        #expect(result.routeEvidence.capabilityObservedThroughController)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.commandCount == 0)
        #expect(result.routeEvidence.sourceMutationCount == 0)
        #expect(result.routeEvidence.initialDocumentGeneration == result.routeEvidence.finalDocumentGeneration)
        #expect(result.routeEvidence.initialTransactionRevision == result.routeEvidence.finalTransactionRevision)
        #expect(result.routeEvidence.initialPublicationSequence == 0)
        #expect(result.routeEvidence.finalPublicationSequence == 0)
        #expect(result.routeEvidence.initialWorkspaceRevision == result.routeEvidence.finalWorkspaceRevision)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.capabilityRequestCount == 1)
        #expect(result.telemetry.actionCount == 0)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.telemetry.readCount == 1)
        #expect(result.telemetry.entityCount == 0)
        #expect(result.telemetry.featureCount == 0)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.publicationCount == 0)
        #expect(result.telemetry.sourceMutationCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)

        guard case let .unsupported(declaration) = result.candidateDecision else {
            Issue.record("The reference sphere candidate must return a typed unsupported declaration.")
            return
        }
        #expect(declaration.reason == .analyticSphereUnavailable)
        #expect(declaration.capabilityID == "cad.solid.analytic-sphere")
        #expect(declaration.capabilityVersion == "1")
        guard case .analyticSphereUnavailable = result.capabilityError else {
            Issue.record("The result must retain the typed analyticSphereUnavailable observation.")
            return
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func capabilityObservationUsesProductionControllerAndExcludesSphereIngress() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "SPH-001")
        let controller = ProjectAgentCommandController(name: "SPH-001.observation")
        let observation = try await CADSphereCapabilityObservation.observe(
            challenge: challenge,
            controller: controller
        )

        #expect(observation.requestCount == 1)
        #expect(observation.status.id == challenge.requiredCapability.id)
        #expect(observation.status.version == challenge.requiredCapability.version)
        #expect(observation.status.available == false)
        #expect(observation.status.reasonCode == "not-exposed")
        #expect(observation.observedAgentCapabilityNames.contains("createSphere") == false)
        #expect(observation.observedAgentCapabilityNames.contains("createAnalyticSphere") == false)
        guard case let .analyticSphereUnavailable(capabilityID, capabilityVersion, snapshotVersion) = observation.typedUnavailable else {
            Issue.record("The absent production ingress must have a typed analyticSphereUnavailable error.")
            return
        }
        #expect(capabilityID == challenge.requiredCapability.id)
        #expect(capabilityVersion == challenge.requiredCapability.version)
        #expect(snapshotVersion == CADSphereCapabilityObservation.snapshotVersion)

        guard case let .status(status) = await controller.handle(.status) else {
            Issue.record("The fresh capability-only controller must answer its status request.")
            return
        }
        #expect(status.sessionCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func timeoutIsTypedAndCleanupRemainsObservableWithoutMutation() async throws {
        let result = try await CADSphereCaseRunner(
            case: .sph001,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.commandCount == 0)
        #expect(result.routeEvidence.sourceMutationCount == 0)
        #expect(result.routeEvidence.initialPublicationSequence == 0)
        #expect(result.routeEvidence.finalPublicationSequence == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.telemetry.actionCount == 0)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.telemetry.publicationCount == 0)
        #expect(result.telemetry.sourceMutationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cancellationBeforeObservationHasNoRegistrationOrPublication() async throws {
        let task = Task { @MainActor in
            try await CADSphereCaseRunner(case: .sph001).runReference()
        }
        task.cancel()
        let result = try await task.value

        try result.validate()
        #expect(result.outcome == .cancellation)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.commandCount == 0)
        #expect(result.routeEvidence.sourceMutationCount == 0)
        #expect(result.routeEvidence.initialPublicationSequence == 0)
        #expect(result.routeEvidence.finalPublicationSequence == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func actionOrFinishDecisionCannotTurnUnavailableSphereIntoACommand() async throws {
        let result = try await CADSphereCaseRunner(case: .sph001).run(
            candidate: ActionReturningSphereCandidate()
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.capabilityObservedThroughController)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.commandCount == 0)
        #expect(result.routeEvidence.sourceMutationCount == 0)
        #expect(result.routeEvidence.initialPublicationSequence == 0)
        #expect(result.routeEvidence.finalPublicationSequence == 0)
        #expect(result.telemetry.actionCount == 0)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.telemetry.publicationCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @Test
    func sphereCandidateSourceDoesNotCrossPrivateOrMutationBoundaries() throws {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let packageRoot = testDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let candidatePath = packageRoot.appendingPathComponent(
            "Sources/RupaAgentCADBenchmark/CADSphereReferenceCandidate.swift"
        )
        let source = try String(contentsOf: candidatePath, encoding: .utf8)

        for forbidden in [
            "CADExpectedGeometry",
            "CADCatalogEntry",
            "ProjectViewSnapshot",
            "AutomationCommand",
            "appendFeatureGraph",
            ".action("
        ] {
            #expect(source.contains(forbidden) == false)
        }
    }

    @Test
    func sphereRunnerUsesSessionlessCapabilityFlowWithoutProjectLifecycle() throws {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let packageRoot = testDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let runnerPath = packageRoot.appendingPathComponent(
            "Sources/RupaAgentCADBenchmark/CADSphereCaseRunner.swift"
        )
        let source = try String(contentsOf: runnerPath, encoding: .utf8)

        for forbidden in [
            "DefaultProjectWorkspaceFactory",
            "ProjectWorkspace",
            "ProjectViewSnapshot",
            "controller.register(",
            "controller.unregister("
        ] {
            #expect(source.contains(forbidden) == false)
        }
        #expect(source.contains("CADSphereCapabilityObservation.observe"))
        #expect(source.contains("controller.handle(.status)"))
    }
}

private struct ActionReturningSphereCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(.automation(.solid(.box(
            name: "sphere-substitute",
            origin: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 1, unit: .millimeter),
            depth: CADLength(value: 1, unit: .millimeter),
            height: CADLength(value: 1, unit: .millimeter)
        ))))
    }
}
