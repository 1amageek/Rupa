import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADSphereCaseTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: CADActivatedSphereCase.allCases)
    func activatedSphereCreatesExactAnalyticSolid(
        activatedCase: CADActivatedSphereCase
    ) async throws {
        let result = try await CADSphereCaseRunner(case: activatedCase).runReference()

        try result.validate()
        #expect(result.caseID == activatedCase.caseID)
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 1)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.first)
        #expect(result.roleBindings?.bindings.first?.role == "sphere")
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalDocumentGeneration.value == result.routeEvidence.initialDocumentGeneration.value + 1)
        #expect(result.routeEvidence.finalTransactionRevision.value == result.routeEvidence.initialTransactionRevision.value + 1)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.finalWorkspaceRevision == result.routeEvidence.initialWorkspaceRevision)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 8)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 6)
        #expect(result.telemetry.analyticSurfaceCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func wrongSphereGeometryPublishesOnceThenFailsTheExactOracle() async throws {
        let result = try await CADSphereCaseRunner(case: .sphere001).run(
            action: sphereAction(
                name: "SPH-001.wrong-radius",
                center: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
                radius: CADLength(value: 6, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.analyticSurfaceCount == 8)
        #expect(result.diagnostics.contains { $0.contains("radius") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func boxSubstituteIsRejectedBeforePublication() async throws {
        let result = try await CADSphereCaseRunner(case: .sphere001).run(
            action: .automation(.solid(.box(
                name: "SPH-001.box-substitute",
                origin: CADPoint3D(x: -5, y: -5, z: -5, unit: .millimeter),
                width: CADLength(value: 10, unit: .millimeter),
                depth: CADLength(value: 10, unit: .millimeter),
                height: CADLength(value: 10, unit: .millimeter)
            )))
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.telemetry.bodyCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func invalidRadiusIsRejectedBeforePublication() async throws {
        let result = try await CADSphereCaseRunner(case: .sphere001).run(
            action: sphereAction(
                name: "SPH-001.zero-radius",
                center: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
                radius: CADLength(value: 0, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.commandCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func timeoutAndCancellationLeaveNoPublication() async throws {
        let timedOut = try await CADSphereCaseRunner(
            case: .sphere001,
            timeoutWallNanoseconds: 1
        ).runReference()
        try timedOut.validate()
        #expect(timedOut.outcome == .timeout)
        #expect(!timedOut.routeEvidence.didPublish)
        #expect(timedOut.routeEvidence.cleanupCompleted)

        let task = Task { @MainActor in
            try await CADSphereCaseRunner(case: .sphere001).runReference()
        }
        task.cancel()
        let cancelled = try await task.value
        try cancelled.validate()
        #expect(cancelled.outcome == .cancellation)
        #expect(!cancelled.routeEvidence.didPublish)
        #expect(cancelled.routeEvidence.cleanupCompleted)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func sphereContextAndExecutorExposeTheSemanticCapability() async throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let context = try executor.context(for: "SPH-001")

        #expect(context.capabilities.statuses == [
            CADCapabilityStatus(
                id: "cad.solid.analytic-sphere",
                version: "1",
                available: true
            ),
        ])
        let result = try await executor.evaluate(
            caseID: "SPH-001",
            candidate: CADSphereReferenceCandidate()
        )
        try result.validate()
        #expect(result.outcome == .realized)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executorPreservesCandidateFailureAsTypedError() async throws {
        do {
            _ = try await DefaultCADActivatedCaseExecutor().evaluate(
                caseID: "SPH-001",
                candidate: ThrowingSphereCandidate()
            )
            Issue.record("Candidate failure must be thrown as a typed executor error.")
        } catch let error as CADActivatedCaseExecutorError {
            #expect(error == .candidateFailure("SPH-001"))
        }
    }

    @Test
    func referenceCandidateDecodesEveryPublicSphereUnit() throws {
        for activatedCase in CADActivatedSphereCase.allCases {
            let action = try CADSphereReferenceCandidate.action(
                for: activatedCase.catalogEntry.challenge
            )
            guard case .automation(.solid(.sphere(let name, let center, let radius))) = action else {
                Issue.record("\(activatedCase.rawValue) did not produce a sphere action.")
                continue
            }
            #expect(name == activatedCase.rawValue)
            #expect(center.unit == radius.unit)
            #expect(radius.meters > 0)
        }
    }
}

private func sphereAction(
    name: String,
    center: CADPoint3D,
    radius: CADLength
) -> CADCandidateAction {
    .automation(.solid(.sphere(name: name, center: center, radius: radius)))
}

private struct ThrowingSphereCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        throw SphereCandidateError.failed
    }
}

private enum SphereCandidateError: Error {
    case failed
}
