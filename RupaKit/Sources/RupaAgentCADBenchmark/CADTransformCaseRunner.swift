import Foundation
import RupaCore
import RupaKit

/// Executes one self-contained transform program through the production agent
/// route and projects only immutable lifecycle evidence.
@MainActor
struct CADTransformCaseRunner {
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
        let action = try CADTransformReferenceCandidate.action(for: entry.challenge)
        let submission = try CADTransformReferenceCandidate().submission(for: entry.challenge)
        let totalStart = now()
        let record = try await makeHarness(entry: entry).run(action: action)
        return project(
            record,
            entry: entry,
            submission: submission,
            totalStart: totalStart
        )
    }

    /// Executes a supplied candidate decision through the production route.
    func run(candidate: any CADCandidateProtocol) async throws -> CADTransformCaseResult {
        let entry = try preparedCase.catalogEntry
        let totalStart = now()
        let record = try await makeHarness(entry: entry).runReference(candidate: candidate)
        return project(
            record,
            entry: entry,
            submission: nil,
            totalStart: totalStart
        )
    }

    /// Executes a supplied typed action for adversarial route tests.
    func run(action: CADCandidateAction) async throws -> CADTransformCaseResult {
        let entry = try preparedCase.catalogEntry
        let totalStart = now()
        let record = try await makeHarness(entry: entry).run(action: action)
        return project(
            record,
            entry: entry,
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
        let entry = try preparedCase.catalogEntry
        let action = try Self.action(
            for: submission,
            challenge: entry.challenge
        )
        let totalStart = now()
        let harness = makeHarness(entry: entry)
        let record = stale
            ? try await harness.runStale(action: action)
            : try await harness.run(action: action)
        return project(
            record,
            entry: entry,
            submission: submission,
            totalStart: totalStart
        )
    }

    private func makeHarness(entry: CADCatalogEntry) -> CADCaseLifecycleHarness {
        CADCaseLifecycleHarness(
            caseID: preparedCase.caseID,
            challenge: entry.challenge,
            programPlanner: { action in
                try DefaultCADSemanticProgramPlanner().plan(
                    for: entry,
                    action: action
                )
            },
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            preRouteDelayNanoseconds: preRouteDelayNanoseconds
        )
    }

    private static func action(
        for submission: CADTransformSubmission,
        challenge: CADChallenge
    ) throws -> CADCandidateAction {
        let reference = try CADTransformReferenceCandidate.action(for: challenge)
        guard case .automation(.transform(let transform)) = reference else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The transform challenge did not produce a typed transform action."
            )
        }
        return .automation(.transform(CADTransformAction(
            source: transform.source,
            translation: submission.translation,
            axisPoint: submission.axisPoint,
            rotationAxis: submission.rotationAxis,
            rotation: submission.rotation
        )))
    }

    private func project(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        submission: CADTransformSubmission?,
        totalStart: UInt64
    ) -> CADTransformCaseResult {
        let evidence = CADTransformRouteEvidence(from: record.routeEvidence)
        switch record.outcome {
        case .published:
            guard let final = record.finalView,
                  case .transform(let expected) = entry.expected,
                  let receipt = CADSemanticExecutionEvidence.committedReceipt(
                      from: record.response
                  ) else {
                return result(
                    outcome: .infrastructureFailure,
                    record: record,
                    evidence: evidence,
                    totalStart: totalStart,
                    diagnostics: ["\(preparedCase.rawValue) published incomplete transform evidence."]
                )
            }
            let semanticEvidence = CADSemanticExecutionEvidence(receipt: receipt)
            guard let sceneNodeID = semanticEvidence.typedSceneNodeID(
                forNode: "transform-source",
                preferredOutputs: ["bodyScene", "scene"]
            ) else {
                return result(
                    outcome: .infrastructureFailure,
                    record: record,
                    evidence: evidence,
                    totalStart: totalStart,
                    fallbackView: final,
                    diagnostics: ["\(preparedCase.rawValue) semantic receipt omitted the transform source scene node."]
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
                        .sceneNodes[sceneNodeID] else {
                        throw CADTransformOracleError.mismatch(
                            "The published transform source node is missing."
                        )
                    }
                    transform = finalNode.localTransform
                }
                let observation = try CADTransformOracle.evaluateSelfContained(
                    expected: expected,
                    challenge: entry.challenge,
                    sceneNodeID: sceneNodeID,
                    expectedTransform: transform,
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
