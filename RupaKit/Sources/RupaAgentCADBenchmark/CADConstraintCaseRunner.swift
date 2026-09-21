import Foundation
import RupaAgentProtocol
import RupaCADDomain
import RupaCore
import RupaKit

/// Runs activated constraint cases through the production semantic-program route.
@MainActor
struct CADConstraintCaseRunner {
    private static let defaultTimeoutWallNanoseconds: UInt64 = 10_000_000_000

    private let activatedCase: CADActivatedConstraintCase
    private let timeoutWallNanoseconds: UInt64
    private let preRouteDelayNanoseconds: UInt64
    private let postRegistrationDelayNanoseconds: UInt64

    init(
        case activatedCase: CADActivatedConstraintCase,
        timeoutWallNanoseconds: UInt64 = Self.defaultTimeoutWallNanoseconds,
        preRouteDelayNanoseconds: UInt64 = 0,
        postRegistrationDelayNanoseconds: UInt64 = 0
    ) {
        self.activatedCase = activatedCase
        self.timeoutWallNanoseconds = max(1, timeoutWallNanoseconds)
        self.preRouteDelayNanoseconds = preRouteDelayNanoseconds
        self.postRegistrationDelayNanoseconds = postRegistrationDelayNanoseconds
    }

    private var caseID: CADBenchmarkCaseID { activatedCase.caseID }

    func runReference() async throws -> CADConstraintCaseResult {
        try await run(candidate: CADConstraintReferenceCandidate())
    }

    func run(candidate: any CADCandidateProtocol) async throws -> CADConstraintCaseResult {
        let start = now()
        let entry = try activatedCase.catalogEntry
        let record = try await harness(entry: entry).runReference(candidate: candidate)
        return await project(record, entry: entry, totalStart: start)
    }

    func run(action: CADCandidateAction) async throws -> CADConstraintCaseResult {
        let start = now()
        let entry = try activatedCase.catalogEntry
        let record = try await harness(entry: entry).run(action: action)
        return await project(record, entry: entry, totalStart: start)
    }

    func runStaleReference() async throws -> CADConstraintCaseResult {
        let start = now()
        let entry = try activatedCase.catalogEntry
        let action = try CADConstraintReferenceCandidate.action(for: entry.challenge)
        let record = try await harness(entry: entry).runStale(action: action)
        return await project(record, entry: entry, totalStart: start)
    }

    private func harness(entry: CADCatalogEntry) -> CADCaseLifecycleHarness {
        CADCaseLifecycleHarness(
            caseID: caseID,
            challenge: entry.challenge,
            programPlanner: { action in
                try DefaultCADSemanticProgramPlanner().plan(
                    for: entry,
                    action: action
                )
            },
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            preRouteDelayNanoseconds: preRouteDelayNanoseconds,
            postRegistrationDelayNanoseconds: postRegistrationDelayNanoseconds
        )
    }

    private func project(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        totalStart: UInt64
    ) async -> CADConstraintCaseResult {
        switch record.outcome {
        case .published:
            return await projectPublished(record, entry: entry, totalStart: totalStart)
        case .cancelledAfterPublication:
            return result(
                outcome: .cancellation,
                record: record,
                evidence: semanticEvidence(from: record.response).map {
                    mutationEvidence(from: $0)
                },
                totalStart: totalStart
            )
        case .invalidSubmission:
            return result(outcome: .invalidSubmission, record: record, totalStart: totalStart)
        case .executionFailure:
            return result(outcome: .executionFailure, record: record, totalStart: totalStart)
        case .timeout:
            return result(outcome: .timeout, record: record, totalStart: totalStart)
        case .cancellation:
            return result(outcome: .cancellation, record: record, totalStart: totalStart)
        case .infrastructureFailure:
            return result(outcome: .infrastructureFailure, record: record, totalStart: totalStart)
        }
    }

    private func projectPublished(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        totalStart: UInt64
    ) async -> CADConstraintCaseResult {
        guard let finalView = record.finalView,
              let semanticEvidence = semanticEvidence(from: record.response),
              semanticEvidence.receipt.telemetry.execution.stepCount == 1,
              semanticEvidence.commandCount == 1 else {
            return result(
                outcome: .infrastructureFailure,
                record: record,
                totalStart: totalStart
            )
        }
        let evidence = mutationEvidence(from: semanticEvidence)
        let oracleStart = now()
        do {
            guard case .constraint(let expected) = entry.expected else {
                throw CADConstraintOracleError.mismatch(
                    "The activated case has no private constraint expectation."
                )
            }
            let observation = try await record.deadline.run {
                try CADConstraintOracle.evaluate(
                    expected: expected,
                    challenge: entry.challenge,
                    bindings: evidence.bindings,
                    stepResults: [evidence.step],
                    snapshot: finalView
                )
            }
            return result(
                outcome: .realized,
                record: record,
                evidence: evidence,
                oracleWallNanoseconds: elapsed(since: oracleStart),
                readCount: observation.readCount,
                entityCount: observation.entityCount,
                featureCount: observation.featureCount,
                bodyCount: observation.bodyCount,
                totalStart: totalStart
            )
        } catch is CADCaseDeadlineError {
            return result(
                outcome: .timeout,
                record: record,
                evidence: evidence,
                oracleWallNanoseconds: elapsed(since: oracleStart),
                readCount: 1,
                featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                bodyCount: finalView.evaluationSnapshot.bodyCount,
                diagnostics: [
                    "\(caseID.rawValue) constraint oracle exceeded its shared deadline after publication; no retry was attempted."
                ],
                totalStart: totalStart
            )
        } catch let error as CADConstraintOracleError {
            do {
                let entityCount = try SketchEntitySnapshotService().snapshot(
                    document: finalView.document.document,
                    objectRegistry: finalView.objectRegistry
                ).counts.entityCount
                return result(
                    outcome: .invalidSubmission,
                    record: record,
                    evidence: evidence,
                    oracleWallNanoseconds: elapsed(since: oracleStart),
                    readCount: 2,
                    entityCount: entityCount,
                    featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                    bodyCount: finalView.evaluationSnapshot.bodyCount,
                    diagnostics: [error.description],
                    totalStart: totalStart
                )
            } catch {
                return result(
                    outcome: .oracleFailure,
                    record: record,
                    evidence: evidence,
                    oracleWallNanoseconds: elapsed(since: oracleStart),
                    readCount: 2,
                    featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                    bodyCount: finalView.evaluationSnapshot.bodyCount,
                    diagnostics: [
                        "\(caseID.rawValue) constraint failure telemetry read failed: \(message(error))"
                    ],
                    totalStart: totalStart
                )
            }
        } catch {
            return result(
                outcome: .oracleFailure,
                record: record,
                evidence: evidence,
                oracleWallNanoseconds: elapsed(since: oracleStart),
                readCount: 1,
                featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                bodyCount: finalView.evaluationSnapshot.bodyCount,
                diagnostics: ["\(caseID.rawValue) constraint oracle failed: \(message(error))"],
                totalStart: totalStart
            )
        }
    }

    private typealias MutationEvidence = (
        step: CADCandidateStepResult,
        bindings: CADOutputRoleBindings
    )

    private func semanticEvidence(from response: AgentResponse?) -> CADSemanticExecutionEvidence? {
        guard let receipt = CADSemanticExecutionEvidence.committedReceipt(from: response) else {
            return nil
        }
        return CADSemanticExecutionEvidence(receipt: receipt)
    }

    private func mutationEvidence(
        from semanticEvidence: CADSemanticExecutionEvidence
    ) -> MutationEvidence {
        (
            semanticEvidence.stepResult(
                node: "constraint",
                operation: RupaCADSemanticOperationID.sketchConstrained.rawValue,
                index: 0,
                primaryOutputs: ["sketch"]
            ),
            CADOutputRoleBindings(bindings: [
                CADOutputRoleBinding(role: "relation", stepIndex: 0, selector: .primary),
            ])
        )
    }

    private func result(
        outcome: CADCaseOutcome,
        record: CADCaseLifecycleRecord,
        evidence: MutationEvidence? = nil,
        oracleWallNanoseconds: UInt64 = 0,
        readCount: Int = 0,
        entityCount: Int = 0,
        featureCount: Int = 0,
        bodyCount: Int = 0,
        diagnostics: [String]? = nil,
        totalStart: UInt64
    ) -> CADConstraintCaseResult {
        let total = max(record.telemetry.totalWallNanoseconds, elapsed(since: totalStart))
        return CADConstraintCaseResult(
            caseID: caseID,
            outcome: outcome,
            candidateResult: evidence?.step,
            roleBindings: evidence?.bindings,
            routeEvidence: CADConstraintRouteEvidence(from: record.routeEvidence),
            telemetry: CADConstraintTelemetry(
                planningWallNanoseconds: record.telemetry.planningWallNanoseconds,
                routeWallNanoseconds: record.telemetry.routeWallNanoseconds,
                oracleWallNanoseconds: oracleWallNanoseconds,
                totalWallNanoseconds: total,
                actionCount: record.telemetry.actionCount,
                commandCount: record.telemetry.commandCount,
                readCount: readCount,
                entityCount: entityCount,
                featureCount: featureCount,
                bodyCount: bodyCount,
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
