import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaKit
import SwiftCAD

/// Projects the shared lifecycle into one rectangle-category result.
@MainActor
struct CADRectangleCaseRunner {
    private static let operationName = "createRectangleSketch"
    private static let defaultTimeoutWallNanoseconds: UInt64 = 10_000_000_000

    private let activatedCase: CADActivatedRectangleCase
    private let recorder = CADRectangleRecorder()
    private let timeoutWallNanoseconds: UInt64
    private let preRouteDelayNanoseconds: UInt64

    init(
        case activatedCase: CADActivatedRectangleCase,
        timeoutWallNanoseconds: UInt64 = Self.defaultTimeoutWallNanoseconds,
        preRouteDelayNanoseconds: UInt64 = 0
    ) {
        self.activatedCase = activatedCase
        self.timeoutWallNanoseconds = max(1, timeoutWallNanoseconds)
        self.preRouteDelayNanoseconds = preRouteDelayNanoseconds
    }

    private var caseID: CADBenchmarkCaseID { activatedCase.caseID }

    func runReference() async throws -> CADRectangleCaseResult {
        try await run(candidate: CADRectangleReferenceCandidate())
    }

    func run(candidate: any CADCandidateProtocol) async throws -> CADRectangleCaseResult {
        let totalStart = now()
        let entry = try activatedCase.catalogEntry
        let record = try await harness(challenge: entry.challenge).runReference(
            candidate: candidate
        )
        return await project(record, entry: entry, totalStart: totalStart)
    }

    func run(action: CADCandidateAction) async throws -> CADRectangleCaseResult {
        let totalStart = now()
        let entry = try activatedCase.catalogEntry
        let record = try await harness(challenge: entry.challenge).run(action: action)
        return await project(record, entry: entry, totalStart: totalStart)
    }

    private func harness(challenge: CADChallenge) -> CADCaseLifecycleHarness {
        CADCaseLifecycleHarness(
            caseID: caseID,
            challenge: challenge,
            routing: CADCaseActionRouting(
                operationName: Self.operationName,
                commandBuilder: { [self] action, challenge, tolerance in
                    try makeCommand(
                        from: action,
                        challenge: challenge,
                        modelingTolerance: tolerance
                    )
                }
            ),
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            preRouteDelayNanoseconds: preRouteDelayNanoseconds
        )
    }

    private func makeCommand(
        from action: CADCandidateAction,
        challenge: CADChallenge,
        modelingTolerance: ModelingTolerance
    ) throws -> AutomationCommand {
        let projection = try CADRectangleChallengeProjection.decode(challenge)
        guard case .automation(
            .sketch(.rectangle(let name, let plane, let center, let width, let height))
        ) = action,
        name.isEmpty == false,
        plane == projection.orientation else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The rectangle action must use the challenge orientation."
            )
        }
        try width.validate(caseID: caseID, field: "action.width")
        try height.validate(caseID: caseID, field: "action.height")
        let tolerance = try CADBenchmarkTolerancePolicy(modelingTolerance: modelingTolerance)
        guard tolerance.isNonDegenerate(width.meters),
              tolerance.isNonDegenerate(height.meters) else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The submitted rectangle dimensions are degenerate."
            )
        }
        let sourcePlane = try CADRectangleGeometryMapping.sourcePlane(
            orientation: projection.orientation,
            targetCenter: projection.center,
            submittedCenter: center,
            modelingTolerance: modelingTolerance,
            caseID: caseID
        )
        return .createRectangleSketch(
            name: name,
            plane: SketchPlaneReference(sketchPlane: sourcePlane),
            width: .constant(.length(width.meters, unit: .meter)),
            height: .constant(.length(height.meters, unit: .meter))
        )
    }

    private func project(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        totalStart: UInt64
    ) async -> CADRectangleCaseResult {
        let evidence = CADRectangleRouteEvidence(from: record.routeEvidence)
        switch record.outcome {
        case .published:
            return await projectPublished(
                record,
                entry: entry,
                evidence: evidence,
                totalStart: totalStart
            )
        case .cancelledAfterPublication:
            return finish(
                publishedMutation(record, evidence: evidence, outcome: .cancellation),
                totalStart: totalStart
            )
        case .invalidSubmission:
            return finish(result(.invalidSubmission, record, evidence), totalStart: totalStart)
        case .executionFailure:
            return finish(result(.executionFailure, record, evidence), totalStart: totalStart)
        case .timeout:
            return finish(result(.timeout, record, evidence), totalStart: totalStart)
        case .cancellation:
            return finish(result(.cancellation, record, evidence), totalStart: totalStart)
        case .infrastructureFailure:
            return finish(result(.infrastructureFailure, record, evidence), totalStart: totalStart)
        }
    }

    private func projectPublished(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        evidence: CADRectangleRouteEvidence,
        totalStart: UInt64
    ) async -> CADRectangleCaseResult {
        guard let finalView = record.finalView,
              let automationResult = commandResult(from: record.response) else {
            return finish(result(.infrastructureFailure, record, evidence), totalStart: totalStart)
        }
        let (stepResult, bindings) = publishedEvidence(from: automationResult)
        let oracleStart = now()
        do {
            guard case .rectangle(let expected) = entry.expected else {
                throw CADRectangleOracleError.mismatch(
                    "The activated rectangle has no private rectangle expectation."
                )
            }
            let observation = try await record.deadline.run {
                try CADRectangleOracle.evaluate(
                    expected: expected,
                    challenge: entry.challenge,
                    bindings: bindings,
                    stepResults: [stepResult],
                    snapshot: finalView
                )
            }
            return finish(
                result(
                    .realized,
                    record,
                    evidence,
                    candidateResult: stepResult,
                    roleBindings: bindings,
                    telemetry: telemetry(from: record).replacing(
                        oracleWallNanoseconds: elapsed(since: oracleStart),
                        readCount: observation.readCount,
                        entityCount: observation.entityCount,
                        featureCount: observation.featureCount,
                        bodyCount: observation.bodyCount
                    )
                ),
                totalStart: totalStart
            )
        } catch is CADCaseDeadlineError {
            return finish(
                result(
                    .timeout,
                    record,
                    evidence,
                    candidateResult: stepResult,
                    roleBindings: bindings,
                    telemetry: failureTelemetry(record, view: finalView, oracleStart: oracleStart),
                    diagnostics: [
                        "\(caseID.rawValue) oracle exceeded its shared deadline after publication; no retry was attempted."
                    ]
                ),
                totalStart: totalStart
            )
        } catch let error as CADRectangleOracleError {
            let counts: (readCount: Int, entityCount: Int)
            do {
                counts = try sourceCounts(in: finalView)
            } catch {
                return finish(
                    result(
                        .oracleFailure,
                        record,
                        evidence,
                        candidateResult: stepResult,
                        roleBindings: bindings,
                        telemetry: telemetry(from: record).replacing(
                            oracleWallNanoseconds: elapsed(since: oracleStart),
                            readCount: 2,
                            entityCount: 0,
                            featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                            bodyCount: finalView.evaluationSnapshot.bodyCount
                        ),
                        diagnostics: [
                            "\(caseID.rawValue) failure telemetry read failed: \(message(error))"
                        ]
                    ),
                    totalStart: totalStart
                )
            }
            return finish(
                result(
                    .invalidSubmission,
                    record,
                    evidence,
                    candidateResult: stepResult,
                    roleBindings: bindings,
                    telemetry: telemetry(from: record).replacing(
                        oracleWallNanoseconds: elapsed(since: oracleStart),
                        readCount: counts.readCount,
                        entityCount: counts.entityCount,
                        featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                        bodyCount: finalView.evaluationSnapshot.bodyCount
                    ),
                    diagnostics: [error.description]
                ),
                totalStart: totalStart
            )
        } catch {
            return finish(
                result(
                    .oracleFailure,
                    record,
                    evidence,
                    candidateResult: stepResult,
                    roleBindings: bindings,
                    telemetry: failureTelemetry(record, view: finalView, oracleStart: oracleStart),
                    diagnostics: ["\(caseID.rawValue) oracle failed: \(message(error))"]
                ),
                totalStart: totalStart
            )
        }
    }

    private func publishedMutation(
        _ record: CADCaseLifecycleRecord,
        evidence: CADRectangleRouteEvidence,
        outcome: CADCaseOutcome
    ) -> CADRectangleCaseResult {
        guard let automationResult = commandResult(from: record.response) else {
            return result(.infrastructureFailure, record, evidence)
        }
        let (stepResult, bindings) = publishedEvidence(from: automationResult)
        return result(
            outcome,
            record,
            evidence,
            candidateResult: stepResult,
            roleBindings: bindings
        )
    }

    private func commandResult(from response: AgentResponse?) -> AutomationResult? {
        guard case .command(let result) = response else { return nil }
        return result
    }

    private func publishedEvidence(
        from result: AutomationResult
    ) -> (CADCandidateStepResult, CADOutputRoleBindings) {
        let step = CADCandidateStepResult(
            stepIndex: 0,
            operation: Self.operationName,
            status: result.didMutate ? .published : .unchanged,
            primaryFeatureID: result.primaryFeatureID?.description,
            createdFeatureIDs: result.createdFeatureIDs.map(\.description),
            diagnostics: result.diagnostics.map(\.message)
        )
        return (
            step,
            CADOutputRoleBindings(bindings: [
                CADOutputRoleBinding(role: "rectangle", stepIndex: 0, selector: .primary),
            ])
        )
    }

    private func result(
        _ outcome: CADCaseOutcome,
        _ record: CADCaseLifecycleRecord,
        _ evidence: CADRectangleRouteEvidence,
        candidateResult: CADCandidateStepResult? = nil,
        roleBindings: CADOutputRoleBindings? = nil,
        telemetry: CADRectangleTelemetry? = nil,
        diagnostics: [String]? = nil
    ) -> CADRectangleCaseResult {
        CADRectangleCaseResult(
            recordedBy: recorder,
            caseID: caseID,
            outcome: outcome,
            candidateResult: candidateResult,
            roleBindings: roleBindings,
            routeEvidence: evidence,
            telemetry: telemetry ?? self.telemetry(from: record),
            diagnostics: diagnostics ?? record.diagnostics
        )
    }

    private func telemetry(from record: CADCaseLifecycleRecord) -> CADRectangleTelemetry {
        CADRectangleTelemetry(
            planningWallNanoseconds: record.telemetry.planningWallNanoseconds,
            routeWallNanoseconds: record.telemetry.routeWallNanoseconds,
            oracleWallNanoseconds: 0,
            totalWallNanoseconds: record.telemetry.totalWallNanoseconds,
            actionCount: record.telemetry.actionCount,
            commandCount: record.telemetry.commandCount,
            readCount: 0,
            entityCount: 0,
            featureCount: 0,
            bodyCount: 0,
            timeoutWallNanoseconds: record.telemetry.timeoutWallNanoseconds,
            cancellationCheckpointCount: record.telemetry.cancellationCheckpointCount
        )
    }

    private func failureTelemetry(
        _ record: CADCaseLifecycleRecord,
        view: ProjectViewSnapshot,
        oracleStart: UInt64
    ) -> CADRectangleTelemetry {
        return telemetry(from: record).replacing(
            oracleWallNanoseconds: elapsed(since: oracleStart),
            readCount: 1,
            entityCount: 0,
            featureCount: view.document.document.cadDocument.designGraph.nodes.count,
            bodyCount: view.evaluationSnapshot.bodyCount
        )
    }

    private func sourceCounts(
        in view: ProjectViewSnapshot
    ) throws -> (readCount: Int, entityCount: Int) {
        let source = try SketchEntitySnapshotService().snapshot(
            document: view.document.document,
            objectRegistry: view.objectRegistry
        )
        return (2, source.counts.entityCount)
    }

    private func finish(
        _ result: CADRectangleCaseResult,
        totalStart: UInt64
    ) -> CADRectangleCaseResult {
        result.replacingTotalWallNanoseconds(elapsed(since: totalStart))
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
