import Foundation
import Testing
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADConstraintCaseTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func con001CreatesExactCoincidentSourceRelationThroughProductionController() async throws {
        let result = try await CADConstraintCaseRunner(case: .constraint001).runReference()

        try result.validate()
        #expect(result.caseID == "CON-001")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 1)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.first)
        #expect(result.roleBindings?.bindings.first?.role == "relation")
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalDocumentGeneration.value == result.routeEvidence.initialDocumentGeneration.value + 1)
        #expect(result.routeEvidence.finalTransactionRevision.value == result.routeEvidence.initialTransactionRevision.value + 1)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.finalWorkspaceRevision == result.routeEvidence.initialWorkspaceRevision)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func con001OracleRejectsWrongFirstStartAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADConstraintCaseRunner(case: .constraint001).run(
            action: Self.action(firstStartX: 10)
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func con001RejectsNoSharedEndpointBeforePublication() async throws {
        let result = try await CADConstraintCaseRunner(case: .constraint001).run(
            action: Self.action(secondEndY: 19)
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
    func con001StaleCoordinatesDoNotPublishAgain() async throws {
        let result = try await CADConstraintCaseRunner(case: .constraint001).runStaleReference()

        try result.validate()
        #expect(result.outcome == .executionFailure)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func con001CancellationBeforePlanningPublishesNothing() async throws {
        let task = Task { @MainActor in
            await Task.yield()
            return try await CADConstraintCaseRunner(case: .constraint001).runReference()
        }
        task.cancel()
        let result = try await task.value

        try result.validate()
        #expect(result.outcome == .cancellation)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func con001TimeoutPublishesNothingAndCleansUp() async throws {
        let result = try await CADConstraintCaseRunner(
            case: .constraint001,
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
    @Test(.timeLimit(.minutes(1)))
    func con001NonActionPublishesNothingAndCleansUp() async throws {
        let result = try await CADConstraintCaseRunner(case: .constraint001).run(
            candidate: ConstraintFinishCandidate()
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @Test
    func con001ReferenceCandidateUsesOnlyPublicGeometryAndNoSourceIDs() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CON-001")
        let decision = try await CADConstraintReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.sketch(.constraint(let action)))) = decision else {
            Issue.record("CON-001 candidate did not produce one constraint action.")
            return
        }
        #expect(action.name == "CON-001")
        #expect(action.plane == .xy)
        #expect(action.relation == .coincident)
        #expect(action.first == .line(
            start: CADPoint3D(x: 20, y: 0, z: 0),
            end: CADPoint3D(x: 0, y: 20, z: 0)
        ))
        #expect(action.second == .line(
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: 0, y: 20, z: 0)
        ))
        let encoded = String(decoding: try JSONEncoder().encode(action), as: UTF8.self)
        for privateName in ["FeatureID", "EntityID", "expectation", "tolerance", "oracle"] {
            #expect(encoded.contains(privateName) == false)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func con001OracleRejectsMissingExtraAndSubstituteProductionSources() async throws {
        let exactSketch = try exactConstraintSketch()

        var missingSketch = exactSketch
        let retainedID = try #require(missingSketch.entityOrder.first)
        missingSketch.entities = [retainedID: try #require(missingSketch.entities[retainedID])]
        missingSketch.entityOrder = [retainedID]
        missingSketch.constraints = []
        let missing = try await productionRecord(commands: [
            .createSketch(name: "CON-001.missing", sketch: missingSketch, geometryRole: .curve),
        ])
        try expectOracleMismatch(record: missing, primaryStepIndex: 0)

        let extra = try await productionRecord(commands: [
            .createSketch(name: "CON-001", sketch: exactSketch, geometryRole: .curve),
            circleSubstituteCommand(plane: exactSketch.plane, name: "CON-001.extra"),
        ])
        try expectOracleMismatch(record: extra, primaryStepIndex: 0)

        let substitute = try await productionRecord(commands: [
            circleSubstituteCommand(plane: exactSketch.plane, name: "CON-001.substitute"),
        ])
        try expectOracleMismatch(record: substitute, primaryStepIndex: 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executorActivatesOnlyCon001AndLeavesCon002Inactive() async throws {
        let executor = DefaultCADActivatedCaseExecutor()

        #expect(executor.activatedCaseIDs.count == 73)
        #expect(executor.activatedCaseIDs.last == "CON-001")
        #expect(try executor.context(for: "CON-001").capabilities.statuses.first?.available == true)
        let result = try await executor.evaluate(
            caseID: "CON-001",
            candidate: CADConstraintReferenceCandidate()
        )
        #expect(result.outcome == .realized)
        do {
            _ = try executor.context(for: "CON-002")
            Issue.record("CON-002 must remain inactive.")
        } catch let error as CADActivatedCaseExecutorError {
            #expect(error == .inactiveCase("CON-002"))
        }
    }

    private static func action(
        firstStartX: Double = 20,
        secondEndY: Double = 20
    ) -> CADCandidateAction {
        .automation(.sketch(.constraint(CADConstraintAction(
            name: "CON-001",
            plane: .xy,
            relation: .coincident,
            first: .line(
                start: CADPoint3D(x: firstStartX, y: 0, z: 0),
                end: CADPoint3D(x: 0, y: 20, z: 0)
            ),
            second: .line(
                start: CADPoint3D(x: 0, y: 0, z: 0),
                end: CADPoint3D(x: 0, y: secondEndY, z: 0)
            )
        ))))
    }

    @MainActor
    private func exactConstraintSketch() throws -> Sketch {
        guard case .automation(.sketch(.constraint(let action))) = Self.action() else {
            throw CADBenchmarkError.invalidInput(
                caseID: "CON-001",
                reason: "The exact constraint fixture has no constraint action."
            )
        }
        return try CADConstraintGeometryMapping.sketch(
            from: action,
            modelingTolerance: .standard,
            caseID: "CON-001"
        )
    }

    private func circleSubstituteCommand(
        plane: SketchPlane,
        name: String
    ) -> AutomationCommand {
        .createCircleSketch(
            name: name,
            plane: SketchPlaneReference(sketchPlane: plane),
            center: SketchPoint(
                x: .constant(.length(0, unit: .meter)),
                y: .constant(.length(0, unit: .meter))
            ),
            radius: .constant(.length(0.01, unit: .meter))
        )
    }

    @MainActor
    private func productionRecord(
        commands: [AutomationCommand]
    ) async throws -> CADCaseLifecycleRecord {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CON-001")
        let harness = CADCaseLifecycleHarness(
            caseID: "CON-001",
            challenge: challenge,
            routing: CADCaseActionRouting(
                operationName: "createConstraint.fixture",
                planBuilder: { _, _, _ in .batch(commands) }
            ),
            timeoutWallNanoseconds: 10_000_000_000
        )
        return try await harness.run(action: Self.action())
    }

    private func expectOracleMismatch(
        record: CADCaseLifecycleRecord,
        primaryStepIndex: Int
    ) throws {
        let view = try #require(record.finalView)
        guard let response = record.response,
              case .batch(let batch) = response else {
            Issue.record("The constraint production fixture did not return one batch response.")
            return
        }
        let steps = batch.results.enumerated().map { index, result in
            CADCandidateStepResult(
                stepIndex: index,
                operation: "fixture.\(index)",
                status: result.didMutate ? .published : .unchanged,
                primaryFeatureID: result.primaryFeatureID?.description,
                createdFeatureIDs: result.createdFeatureIDs.map(\.description)
            )
        }
        let entry = try CADActivatedConstraintCase.constraint001.catalogEntry
        guard case .constraint(let expected) = entry.expected else {
            Issue.record("CON-001 has no private constraint expectation.")
            return
        }
        let bindings = CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(
                role: "relation",
                stepIndex: primaryStepIndex,
                selector: .primary
            ),
        ])
        #expect(throws: CADConstraintOracleError.self) {
            try CADConstraintOracle.evaluate(
                expected: expected,
                challenge: entry.challenge,
                bindings: bindings,
                stepResults: steps,
                snapshot: view
            )
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
}

private struct ConstraintFinishCandidate: CADCandidateProtocol {
    func decide(for _: CADCandidateContext) async throws -> CADCandidateDecision {
        .finish(CADOutputRoleBindings(bindings: []))
    }
}
