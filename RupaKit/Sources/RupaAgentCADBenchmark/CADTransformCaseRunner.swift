import Foundation
import RupaAutomation
import RupaCore
import RupaKit

/// Executes the prepared transform route without claiming shared activation authority.
@MainActor
struct CADTransformCaseRunner {
    private static let operationName = "setSceneNodeTransform"
    private static let defaultTimeoutWallNanoseconds: UInt64 = 10_000_000_000

    private let preparedCase: CADTransformPreparedCase
    private let timeoutWallNanoseconds: UInt64
    private let preRouteDelayNanoseconds: UInt64

    init(
        case preparedCase: CADTransformPreparedCase,
        timeoutWallNanoseconds: UInt64 = Self.defaultTimeoutWallNanoseconds,
        preRouteDelayNanoseconds: UInt64 = 0
    ) {
        self.preparedCase = preparedCase
        self.timeoutWallNanoseconds = max(1, timeoutWallNanoseconds)
        self.preRouteDelayNanoseconds = preRouteDelayNanoseconds
    }

    func runReference() async throws -> CADTransformCaseResult {
        let entry = try preparedCase.catalogEntry
        let submission = try CADTransformReferenceCandidate().submission(
            for: entry.challenge
        )
        return try await run(submission: submission)
    }

    /// Executes one candidate decision through the same lifecycle used by the
    /// production Agent route.
    func run(candidate: any CADCandidateProtocol) async throws -> CADTransformCaseResult {
        let totalStart = now()
        let entry = try preparedCase.catalogEntry
        let projection = try CADTransformChallengeProjection.decode(entry.challenge)
        let seed = try CADTransformGeometryMapping.seed(projection: projection)
        let record = try await makeCandidateHarness(
            entry: entry,
            projection: projection,
            seed: seed
        ).runReference(candidate: candidate)
        return project(
            record,
            entry: entry,
            seed: seed,
            submission: nil,
            totalStart: totalStart
        )
    }

    /// Executes a supplied public action for adversarial route tests.
    func run(action: CADCandidateAction) async throws -> CADTransformCaseResult {
        let totalStart = now()
        let entry = try preparedCase.catalogEntry
        let projection = try CADTransformChallengeProjection.decode(entry.challenge)
        let seed = try CADTransformGeometryMapping.seed(projection: projection)
        let record = try await makeCandidateHarness(
            entry: entry,
            projection: projection,
            seed: seed
        ).run(action: action)
        return project(
            record,
            entry: entry,
            seed: seed,
            submission: nil,
            totalStart: totalStart
        )
    }

    func run(submission: CADTransformSubmission) async throws -> CADTransformCaseResult {
        try await run(submission: submission, stale: false)
    }

    func runStale(submission: CADTransformSubmission) async throws -> CADTransformCaseResult {
        try await run(submission: submission, stale: true)
    }

    private func run(
        submission: CADTransformSubmission,
        stale: Bool
    ) async throws -> CADTransformCaseResult {
        let totalStart = now()
        let entry = try preparedCase.catalogEntry
        let projection = try CADTransformChallengeProjection.decode(entry.challenge)
        let seed = try CADTransformGeometryMapping.seed(projection: projection)
        let expectedSourceAction = seed.sourceAction
        let harness = CADCaseLifecycleHarness(
            caseID: preparedCase.caseID,
            challenge: entry.challenge,
            routing: CADCaseActionRouting(
                operationName: Self.operationName,
                planBuilder: { action, _, _ in
                    guard action == expectedSourceAction else {
                        throw CADBenchmarkError.invalidInput(
                            caseID: projection.id.rawValue,
                            reason: "The prepared transform route received a substituted source declaration."
                        )
                    }
                    return .command(.setSceneNodeTransform(
                        id: seed.sceneNodeID,
                        localTransform: try CADTransformGeometryMapping.localTransform(
                            submission: submission,
                            caseID: projection.id
                        )
                    ))
                }
            ),
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            preRouteDelayNanoseconds: preRouteDelayNanoseconds,
            initialDocumentProvider: { seed.document }
        )
        let record = stale
            ? try await harness.runStale(action: expectedSourceAction)
            : try await harness.run(action: expectedSourceAction)
        return project(
            record,
            entry: entry,
            seed: seed,
            submission: submission,
            totalStart: totalStart
        )
    }

    private func makeCandidateHarness(
        entry: CADCatalogEntry,
        projection: CADTransformChallengeProjection,
        seed: CADTransformGeometryMapping.Seed
    ) -> CADCaseLifecycleHarness {
        let routing = CADCaseActionRouting(
            operationName: Self.operationName,
            planBuilder: { action, _, _ in
                guard case .automation(.transform(let transform)) = action else {
                    throw CADBenchmarkError.invalidInput(
                        caseID: projection.id.rawValue,
                        reason: "The transform route requires one transform automation action."
                    )
                }
                let submission = CADTransformSubmission(
                    translation: transform.translation,
                    axisPoint: transform.axisPoint,
                    rotationAxis: transform.rotationAxis,
                    rotation: transform.rotation
                )
                let localTransform = try CADTransformGeometryMapping.localTransform(
                    submission: submission,
                    caseID: projection.id
                )
                return .command(.setSceneNodeTransform(
                    id: seed.sceneNodeID,
                    localTransform: localTransform
                ))
            }
        )
        return CADCaseLifecycleHarness(
            caseID: preparedCase.caseID,
            challenge: entry.challenge,
            routing: routing,
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            preRouteDelayNanoseconds: preRouteDelayNanoseconds,
            initialDocumentProvider: { seed.document }
        )
    }

    private func project(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        seed: CADTransformGeometryMapping.Seed,
        submission: CADTransformSubmission?,
        totalStart: UInt64
    ) -> CADTransformCaseResult {
        let evidence = CADTransformRouteEvidence(from: record.routeEvidence)
        switch record.outcome {
        case .published:
            guard let initial = record.initialView,
                  let final = record.finalView,
                  case .transform(let expected) = entry.expected else {
                return result(
                    outcome: .infrastructureFailure,
                    record: record,
                    evidence: evidence,
                    totalStart: totalStart,
                    diagnostics: ["\(preparedCase.rawValue) published incomplete transform evidence."]
                )
            }
            let oracleStart = now()
            do {
                let transform: Transform3D
                if let submission {
                    transform = try CADTransformGeometryMapping.localTransform(
                        submission: submission,
                        caseID: preparedCase.caseID
                    )
                } else {
                    guard let finalNode = final.document.document.productMetadata
                        .sceneNodes[seed.sceneNodeID] else {
                        throw CADTransformOracleError.mismatch(
                            "The published transform source node is missing."
                        )
                    }
                    transform = finalNode.localTransform
                }
                let observation = try CADTransformOracle.evaluate(
                    expected: expected,
                    challenge: entry.challenge,
                    sceneNodeID: seed.sceneNodeID,
                    expectedTransform: transform,
                    initial: initial,
                    final: final
                )
                return result(
                    outcome: .realized,
                    record: record,
                    evidence: evidence,
                    totalStart: totalStart,
                    oracleWallNanoseconds: elapsed(since: oracleStart),
                    observation: observation
                )
            } catch let error as CADTransformOracleError {
                return result(
                    outcome: .invalidSubmission,
                    record: record,
                    evidence: evidence,
                    totalStart: totalStart,
                    oracleWallNanoseconds: elapsed(since: oracleStart),
                    fallbackView: final,
                    diagnostics: [error.description]
                )
            } catch {
                return result(
                    outcome: .oracleFailure,
                    record: record,
                    evidence: evidence,
                    totalStart: totalStart,
                    oracleWallNanoseconds: elapsed(since: oracleStart),
                    fallbackView: final,
                    diagnostics: ["\(preparedCase.rawValue) transform oracle failed: \(message(error))"]
                )
            }
        case .cancelledAfterPublication:
            return result(
                outcome: .cancellation,
                record: record,
                evidence: evidence,
                totalStart: totalStart
            )
        case .invalidSubmission:
            return result(
                outcome: .invalidSubmission,
                record: record,
                evidence: evidence,
                totalStart: totalStart
            )
        case .executionFailure:
            return result(
                outcome: .executionFailure,
                record: record,
                evidence: evidence,
                totalStart: totalStart
            )
        case .timeout:
            return result(
                outcome: .timeout,
                record: record,
                evidence: evidence,
                totalStart: totalStart
            )
        case .cancellation:
            return result(
                outcome: .cancellation,
                record: record,
                evidence: evidence,
                totalStart: totalStart
            )
        case .infrastructureFailure:
            return result(
                outcome: .infrastructureFailure,
                record: record,
                evidence: evidence,
                totalStart: totalStart
            )
        }
    }

    private func result(
        outcome: CADCaseOutcome,
        record: CADCaseLifecycleRecord,
        evidence: CADTransformRouteEvidence,
        totalStart: UInt64,
        oracleWallNanoseconds: UInt64 = 0,
        observation: CADTransformOracleObservation? = nil,
        fallbackView: ProjectViewSnapshot? = nil,
        diagnostics: [String]? = nil
    ) -> CADTransformCaseResult {
        let view = fallbackView ?? record.finalView
        return CADTransformCaseResult(
            caseID: preparedCase.caseID,
            outcome: outcome,
            routeEvidence: evidence,
            telemetry: CADTransformTelemetry(
                planningWallNanoseconds: record.telemetry.planningWallNanoseconds,
                routeWallNanoseconds: record.telemetry.routeWallNanoseconds,
                oracleWallNanoseconds: oracleWallNanoseconds,
                totalWallNanoseconds: elapsed(since: totalStart),
                actionCount: record.telemetry.actionCount,
                commandCount: record.telemetry.commandCount,
                readCount: observation?.readCount ?? 0,
                featureCount: observation?.featureCount
                    ?? view?.document.document.cadDocument.designGraph.nodes.count
                    ?? 0,
                sceneNodeCount: observation?.sceneNodeCount
                    ?? view.map {
                        CADTransformOracle.authoredSceneNodeCount(
                            in: $0.document.document.productMetadata
                        )
                    }
                    ?? 0,
                bodyCount: observation?.bodyCount ?? view?.evaluationSnapshot.bodyCount ?? 0,
                timeoutWallNanoseconds: record.telemetry.timeoutWallNanoseconds,
                cancellationCheckpointCount: record.telemetry.cancellationCheckpointCount
            ),
            diagnostics: diagnostics ?? record.diagnostics
        )
    }

    private func now() -> UInt64 {
        UInt64((ProcessInfo.processInfo.systemUptime * 1_000_000_000).rounded())
    }

    private func elapsed(since start: UInt64) -> UInt64 {
        max(1, now() - start)
    }

    private func message(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           description.isEmpty == false {
            return description
        }
        return String(describing: error)
    }
}
