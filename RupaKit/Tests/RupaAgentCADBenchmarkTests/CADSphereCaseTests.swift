import Foundation
import Testing
import RupaAgentRuntime
import SwiftCAD
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADSphereCaseTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: CADActivatedSphereCase.allCases)
    func activatedSphereCaseMapsUnavailableCapabilityToExpectedUnsupported(
        activatedCase: CADActivatedSphereCase
    ) async throws {
        let result = try await CADSphereCaseRunner(case: activatedCase).runReference()

        try result.validate()
        #expect(result.caseID == activatedCase.caseID)
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
        #expect(result.telemetry.oracleWallNanoseconds == 0)
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

    @Test
    func sphereActivationBoundaryEqualsTheCompletePreparedSphereCatalog() throws {
        #expect(CADActivatedSphereCase.allCases.map(\.rawValue) == [
            "SPH-001", "SPH-002", "SPH-003", "SPH-004", "SPH-005",
        ])
        #expect(CADSpherePreparationCase.allCases.map(\.rawValue) == [
            "SPH-001", "SPH-002", "SPH-003", "SPH-004", "SPH-005",
        ])
        #expect(
            CADActivatedSphereCase.allCases.map(\.caseID)
                == CADSpherePreparationCase.allCases.map(\.caseID)
        )
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
            case: .sphere001,
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
            try await CADSphereCaseRunner(case: .sphere001).runReference()
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
        let result = try await CADSphereCaseRunner(case: .sphere001).run(
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

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func finishDecisionCannotTurnUnavailableSphereIntoACommand() async throws {
        let result = try await CADSphereCaseRunner(case: .sphere001).run(
            candidate: FixedSphereDecisionCandidate(
                decision: .finish(CADOutputRoleBindings(bindings: []))
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.commandCount == 0)
        #expect(result.routeEvidence.sourceMutationCount == 0)
        #expect(result.telemetry.capabilityRequestCount == 1)
        #expect(result.telemetry.readCount == 1)
        #expect(result.telemetry.publicationCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func wrongUnsupportedReasonCannotBecomeExpectedUnsupported() async throws {
        let result = try await CADSphereCaseRunner(case: .sphere001).run(
            candidate: FixedSphereDecisionCandidate(
                decision: .unsupported(CADUnsupportedDeclaration(
                    capabilityID: "cad.solid.analytic-sphere",
                    capabilityVersion: "1",
                    reason: .capabilityUnavailable
                ))
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.commandCount == 0)
        #expect(result.routeEvidence.sourceMutationCount == 0)
        #expect(result.telemetry.capabilityRequestCount == 1)
        #expect(result.telemetry.readCount == 1)
        #expect(result.telemetry.publicationCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executorActivatesAllSphereCapabilityObservationsAndCompletesTheCatalog() async throws {
        let executor = DefaultCADActivatedCaseExecutor()

        #expect(executor.activatedCaseIDs.count == 100)
        #expect(executor.activatedCaseIDs.prefix(95).last == "CMP-007")
        #expect(executor.activatedCaseIDs.prefix(96).last == "SPH-001")
        #expect(executor.activatedCaseIDs.prefix(97).last == "SPH-002")
        #expect(executor.activatedCaseIDs.prefix(98).last == "SPH-003")
        #expect(executor.activatedCaseIDs.prefix(99).last == "SPH-004")
        #expect(executor.activatedCaseIDs.last == "SPH-005")
        #expect(Set(executor.activatedCaseIDs) == Set(try CADBenchmarkCatalog().caseIDs))

        let context = try executor.context(for: "SPH-001")
        #expect(context.challenge.category == .sphere)
        #expect(context.capabilities.statuses == [
            CADCapabilityStatus(
                id: "cad.solid.analytic-sphere",
                version: "1",
                available: false,
                reasonCode: "not-exposed"
            ),
        ])

        let result = try await executor.evaluate(
            caseID: "SPH-001",
            candidate: CADSphereReferenceCandidate()
        )
        #expect(result.id == "SPH-001")
        #expect(result.category == .sphere)
        #expect(result.outcome == .expectedUnsupported)
        try result.validate()

        let finalContext = try executor.context(for: "SPH-005")
        #expect(finalContext.challenge.id == "SPH-005")
        #expect(finalContext.challenge.category == .sphere)
        #expect(finalContext.capabilities.statuses == context.capabilities.statuses)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func sphere002PreservesItsPublicTargetAndRejectsSolidSubstitutesBeforePublication() async throws {
        let entry = try CADSpherePreparationCase.sph002.catalogEntry
        guard case let .sphere(expected) = entry.input else {
            Issue.record("SPH-002 must retain an analytic sphere target.")
            return
        }
        #expect(expected.center == CADPoint3D(x: 50, y: -25, z: 10, unit: .millimeter))
        #expect(expected.radius == CADLength(value: 25, unit: .millimeter))

        let decisions: [CADCandidateDecision] = [
            .action(.automation(.solid(.box(
                name: "sphere-substitute-box",
                origin: CADPoint3D(x: 25, y: -50, z: -15, unit: .millimeter),
                width: CADLength(value: 50, unit: .millimeter),
                depth: CADLength(value: 50, unit: .millimeter),
                height: CADLength(value: 50, unit: .millimeter)
            )))),
            .action(.automation(.solid(.cylinder(
                name: "sphere-substitute-cylinder",
                baseCenter: CADPoint3D(x: 50, y: -25, z: -15, unit: .millimeter),
                axis: CADDirection3D(x: 0, y: 0, z: 1),
                radius: CADLength(value: 25, unit: .millimeter),
                depth: CADLength(value: 50, unit: .millimeter)
            )))),
        ]

        for decision in decisions {
            let result = try await CADSphereCaseRunner(case: .sphere002).run(
                candidate: FixedSphereDecisionCandidate(decision: decision)
            )
            try result.validate()
            #expect(result.outcome == .invalidSubmission)
            #expect(result.routeEvidence.didPublish == false)
            #expect(result.routeEvidence.commandCount == 0)
            #expect(result.routeEvidence.sourceMutationCount == 0)
            #expect(result.telemetry.capabilityRequestCount == 1)
            #expect(result.telemetry.readCount == 1)
            #expect(result.telemetry.actionCount == 0)
            #expect(result.telemetry.publicationCount == 0)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func sphere003PreservesMeterValuesAndRejectsSolidSubstitutesBeforePublication() async throws {
        let entry = try CADSpherePreparationCase.sph003.catalogEntry
        guard case let .sphere(expected) = entry.input else {
            Issue.record("SPH-003 must retain an analytic sphere target.")
            return
        }
        #expect(expected.center == CADPoint3D(x: 0, y: 0, z: 0.1, unit: .meter))
        #expect(expected.radius == CADLength(value: 0.1, unit: .meter))

        let decisions: [CADCandidateDecision] = [
            .action(.automation(.solid(.box(
                name: "sphere-substitute-box",
                origin: CADPoint3D(x: -0.1, y: -0.1, z: 0, unit: .meter),
                width: CADLength(value: 0.2, unit: .meter),
                depth: CADLength(value: 0.2, unit: .meter),
                height: CADLength(value: 0.2, unit: .meter)
            )))),
            .action(.automation(.solid(.cylinder(
                name: "sphere-substitute-cylinder",
                baseCenter: CADPoint3D(x: 0, y: 0, z: 0, unit: .meter),
                axis: CADDirection3D(x: 0, y: 0, z: 1),
                radius: CADLength(value: 0.1, unit: .meter),
                depth: CADLength(value: 0.2, unit: .meter)
            )))),
        ]

        for decision in decisions {
            let result = try await CADSphereCaseRunner(case: .sphere003).run(
                candidate: FixedSphereDecisionCandidate(decision: decision)
            )
            try result.validate()
            #expect(result.outcome == .invalidSubmission)
            #expect(result.routeEvidence.didPublish == false)
            #expect(result.routeEvidence.commandCount == 0)
            #expect(result.routeEvidence.sourceMutationCount == 0)
            #expect(result.telemetry.capabilityRequestCount == 1)
            #expect(result.telemetry.readCount == 1)
            #expect(result.telemetry.actionCount == 0)
            #expect(result.telemetry.publicationCount == 0)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func sphere004PreservesInchValuesAndRejectsSolidSubstitutesBeforePublication() async throws {
        let entry = try CADSpherePreparationCase.sph004.catalogEntry
        guard case let .sphere(expected) = entry.input else {
            Issue.record("SPH-004 must retain an analytic sphere target.")
            return
        }
        #expect(expected.center == CADPoint3D(x: -2, y: 3, z: 1, unit: .inch))
        #expect(expected.radius == CADLength(value: 2, unit: .inch))

        let decisions: [CADCandidateDecision] = [
            .action(.automation(.solid(.box(
                name: "sphere-substitute-box",
                origin: CADPoint3D(x: -4, y: 1, z: -1, unit: .inch),
                width: CADLength(value: 4, unit: .inch),
                depth: CADLength(value: 4, unit: .inch),
                height: CADLength(value: 4, unit: .inch)
            )))),
            .action(.automation(.solid(.cylinder(
                name: "sphere-substitute-cylinder",
                baseCenter: CADPoint3D(x: -2, y: 3, z: -1, unit: .inch),
                axis: CADDirection3D(x: 0, y: 0, z: 1),
                radius: CADLength(value: 2, unit: .inch),
                depth: CADLength(value: 4, unit: .inch)
            )))),
        ]

        for decision in decisions {
            let result = try await CADSphereCaseRunner(case: .sphere004).run(
                candidate: FixedSphereDecisionCandidate(decision: decision)
            )
            try result.validate()
            #expect(result.outcome == .invalidSubmission)
            #expect(result.routeEvidence.didPublish == false)
            #expect(result.routeEvidence.commandCount == 0)
            #expect(result.routeEvidence.sourceMutationCount == 0)
            #expect(result.telemetry.capabilityRequestCount == 1)
            #expect(result.telemetry.readCount == 1)
            #expect(result.telemetry.actionCount == 0)
            #expect(result.telemetry.publicationCount == 0)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func sphere005PreservesMillimeterValuesAndRejectsSolidSubstitutesBeforePublication() async throws {
        let entry = try CADSpherePreparationCase.sph005.catalogEntry
        guard case let .sphere(expected) = entry.input else {
            Issue.record("SPH-005 must retain an analytic sphere target.")
            return
        }
        #expect(expected.center == CADPoint3D(x: -100, y: 100, z: -50, unit: .millimeter))
        #expect(expected.radius == CADLength(value: 100, unit: .millimeter))

        let decisions: [CADCandidateDecision] = [
            .action(.automation(.solid(.box(
                name: "sphere-substitute-box",
                origin: CADPoint3D(x: -200, y: 0, z: -150, unit: .millimeter),
                width: CADLength(value: 200, unit: .millimeter),
                depth: CADLength(value: 200, unit: .millimeter),
                height: CADLength(value: 200, unit: .millimeter)
            )))),
            .action(.automation(.solid(.cylinder(
                name: "sphere-substitute-cylinder",
                baseCenter: CADPoint3D(x: -100, y: 100, z: -150, unit: .millimeter),
                axis: CADDirection3D(x: 0, y: 0, z: 1),
                radius: CADLength(value: 100, unit: .millimeter),
                depth: CADLength(value: 200, unit: .millimeter)
            )))),
        ]

        for decision in decisions {
            let result = try await CADSphereCaseRunner(case: .sphere005).run(
                candidate: FixedSphereDecisionCandidate(decision: decision)
            )
            try result.validate()
            #expect(result.outcome == .invalidSubmission)
            #expect(result.routeEvidence.didPublish == false)
            #expect(result.routeEvidence.commandCount == 0)
            #expect(result.routeEvidence.sourceMutationCount == 0)
            #expect(result.telemetry.capabilityRequestCount == 1)
            #expect(result.telemetry.readCount == 1)
            #expect(result.telemetry.actionCount == 0)
            #expect(result.telemetry.publicationCount == 0)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func sphereContextUsesTheSamePureClassifierAsLiveObservation() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "SPH-001")
        let executor = DefaultCADActivatedCaseExecutor()
        let context = try executor.context(for: "SPH-001")
        let controller = ProjectAgentCommandController(name: "SPH-001.context")
        let observation = try await CADSphereCapabilityObservation.observe(
            challenge: challenge,
            controller: controller
        )

        #expect(context.capabilities == observation.snapshot)
        #expect(context.challenge == observation.challenge)
        #expect(context.remainingActions == challenge.budget.maximumActions)
        #expect(context.remainingRounds == challenge.budget.maximumRounds)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executorPreservesCandidateFailureAsTypedError() async throws {
        let executor = DefaultCADActivatedCaseExecutor()

        do {
            _ = try await executor.evaluate(
                caseID: "SPH-001",
                candidate: ThrowingSphereCandidate()
            )
            Issue.record("Candidate failure must be thrown as a typed executor error.")
        } catch let error as CADActivatedCaseExecutorError {
            #expect(error == .candidateFailure("SPH-001"))
        }
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

private struct ThrowingSphereCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        throw SphereCandidateError.failed
    }
}

private struct FixedSphereDecisionCandidate: CADCandidateProtocol {
    let decision: CADCandidateDecision

    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        decision
    }
}

private enum SphereCandidateError: Error {
    case failed
}
