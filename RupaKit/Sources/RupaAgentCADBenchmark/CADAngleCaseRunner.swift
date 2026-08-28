import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaKit
import SwiftCAD

/// Projects the shared lifecycle into one angle-category result.
@MainActor
struct CADAngleCaseRunner {
    private static let operationName = "createLineSketch"
    private static let defaultTimeoutWallNanoseconds: UInt64 = 10_000_000_000

    private let activatedCase: CADActivatedAngleCase
    private let recorder = CADAngleRecorder()
    private let timeoutWallNanoseconds: UInt64
    private let preRouteDelayNanoseconds: UInt64
    private let failureSourceReader: @MainActor (ProjectViewSnapshot) throws -> Int

    init(
        case activatedCase: CADActivatedAngleCase,
        timeoutWallNanoseconds: UInt64 = Self.defaultTimeoutWallNanoseconds,
        preRouteDelayNanoseconds: UInt64 = 0,
        failureSourceReader: @escaping @MainActor (ProjectViewSnapshot) throws -> Int = { view in
            let source = try SketchEntitySnapshotService().snapshot(
                document: view.document.document,
                objectRegistry: view.objectRegistry
            )
            return source.counts.entityCount
        }
    ) {
        self.activatedCase = activatedCase
        self.timeoutWallNanoseconds = max(1, timeoutWallNanoseconds)
        self.preRouteDelayNanoseconds = preRouteDelayNanoseconds
        self.failureSourceReader = failureSourceReader
    }

    private var caseID: CADBenchmarkCaseID { activatedCase.caseID }

    func runReference() async throws -> CADAngleCaseResult {
        try await run(candidate: CADAngleReferenceCandidate())
    }

    func run(candidate: any CADCandidateProtocol) async throws -> CADAngleCaseResult {
        let totalStart = now()
        let entry = try activatedCase.catalogEntry
        let record = try await harness(challenge: entry.challenge).runReference(candidate: candidate)
        return await project(record, entry: entry, totalStart: totalStart)
    }

    func run(action: CADCandidateAction) async throws -> CADAngleCaseResult {
        let totalStart = now()
        let entry = try activatedCase.catalogEntry
        let record = try await harness(challenge: entry.challenge).run(action: action)
        return await project(record, entry: entry, totalStart: totalStart)
    }

    func runStaleReference() async throws -> CADAngleCaseResult {
        let totalStart = now()
        let entry = try activatedCase.catalogEntry
        let action = try CADAngleReferenceCandidate.action(for: entry.challenge)
        let record = try await harness(challenge: entry.challenge).runStale(action: action)
        return await project(record, entry: entry, totalStart: totalStart)
    }

    private func harness(challenge: CADChallenge) -> CADCaseLifecycleHarness {
        CADCaseLifecycleHarness(
            caseID: caseID,
            challenge: challenge,
            routing: CADCaseActionRouting(
                operationName: Self.operationName,
                planBuilder: { [self] action, challenge, tolerance in
                    try makePlan(
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

    private func makePlan(
        from action: CADCandidateAction,
        challenge: CADChallenge,
        modelingTolerance: ModelingTolerance
    ) throws -> CADCaseActionPlan {
        let projection = try CADAngleChallengeProjection.decode(challenge)
        guard case .automation(
            .sketch(
                .angle(
                    let name,
                    let plane,
                    let firstStart,
                    let firstEnd,
                    let secondStart,
                    let secondEnd
                )
            )
        ) = action,
        name.isEmpty == false,
        plane == projection.orientation else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The angle action must use the challenge orientation."
            )
        }
        let tolerance = try CADBenchmarkTolerancePolicy(modelingTolerance: modelingTolerance)
        let sourcePlane = try CADAngleGeometryMapping.sourcePlane(
            orientation: projection.orientation,
            intersection: projection.intersection,
            modelingTolerance: modelingTolerance,
            caseID: caseID
        )
        let submitted = [firstStart, firstEnd, secondStart, secondEnd]
        let fields = ["firstStart", "firstEnd", "secondStart", "secondEnd"]
        let local = try zip(submitted, fields).map { point, field in
            try CADAngleGeometryMapping.localPoint(
                from: point,
                sourcePlane: sourcePlane,
                modelingTolerance: modelingTolerance,
                caseID: caseID,
                field: "action.\(field)"
            )
        }
        guard tolerance.isNonDegenerate(hypot(local[1].x - local[0].x, local[1].y - local[0].y)),
              tolerance.isNonDegenerate(hypot(local[3].x - local[2].x, local[3].y - local[2].y)) else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The submitted angle contains a degenerate segment."
            )
        }
        let planeReference = SketchPlaneReference(sketchPlane: sourcePlane)
        return .batch([
            .createLineSketch(
                name: "\(name).first-line",
                plane: planeReference,
                start: sketchPoint(local[0]),
                end: sketchPoint(local[1])
            ),
            .createLineSketch(
                name: "\(name).second-line",
                plane: planeReference,
                start: sketchPoint(local[2]),
                end: sketchPoint(local[3])
            ),
        ])
    }

    private func sketchPoint(_ point: Point2D) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(point.x, unit: .meter)),
            y: .constant(.length(point.y, unit: .meter))
        )
    }

    private func project(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        totalStart: UInt64
    ) async -> CADAngleCaseResult {
        let evidence = CADAngleRouteEvidence(from: record.routeEvidence)
        switch record.outcome {
        case .published:
            return await projectPublished(record, entry: entry, evidence: evidence, totalStart: totalStart)
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
        evidence: CADAngleRouteEvidence,
        totalStart: UInt64
    ) async -> CADAngleCaseResult {
        guard let finalView = record.finalView,
              let batch = batchResult(from: record.response),
              batch.results.count == 2,
              batch.metrics.commandCount == 2,
              batch.metrics.evaluationPassCount == 1,
              batch.metrics.historyEntryCount == 1,
              batch.results.allSatisfy(\.didMutate),
              batch.results[0].generation.value < UInt64.max,
              batch.results[1].generation.value == batch.results[0].generation.value + 1 else {
            return finish(result(.infrastructureFailure, record, evidence), totalStart: totalStart)
        }
        let (steps, bindings) = publishedEvidence(from: batch.results)
        let oracleStart = now()
        do {
            guard case .angle(let expected) = entry.expected else {
                throw CADAngleOracleError.mismatch(
                    "The activated angle has no private angle expectation."
                )
            }
            let observation = try await record.deadline.run {
                try CADAngleOracle.evaluate(
                    expected: expected,
                    challenge: entry.challenge,
                    bindings: bindings,
                    stepResults: steps,
                    snapshot: finalView
                )
            }
            return finish(
                result(
                    .realized,
                    record,
                    evidence,
                    candidateResults: steps,
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
                    candidateResults: steps,
                    roleBindings: bindings,
                    telemetry: failureTelemetry(record, view: finalView, oracleStart: oracleStart),
                    diagnostics: [
                        "\(caseID.rawValue) angle oracle exceeded its shared deadline after publication; no retry was attempted."
                    ]
                ),
                totalStart: totalStart
            )
        } catch let error as CADAngleOracleError {
            let counts: (readCount: Int, entityCount: Int)
            do {
                counts = try sourceCounts(in: finalView)
            } catch {
                return finish(
                    result(
                        .oracleFailure,
                        record,
                        evidence,
                        candidateResults: steps,
                        roleBindings: bindings,
                        telemetry: telemetry(from: record).replacing(
                            oracleWallNanoseconds: elapsed(since: oracleStart),
                            readCount: 2,
                            featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                            bodyCount: finalView.evaluationSnapshot.bodyCount
                        ),
                        diagnostics: [
                            "\(caseID.rawValue) angle failure telemetry read failed: \(message(error))"
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
                    candidateResults: steps,
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
                    candidateResults: steps,
                    roleBindings: bindings,
                    telemetry: failureTelemetry(record, view: finalView, oracleStart: oracleStart),
                    diagnostics: ["\(caseID.rawValue) angle oracle failed: \(message(error))"]
                ),
                totalStart: totalStart
            )
        }
    }

    private func publishedMutation(
        _ record: CADCaseLifecycleRecord,
        evidence: CADAngleRouteEvidence,
        outcome: CADCaseOutcome
    ) -> CADAngleCaseResult {
        guard let batch = batchResult(from: record.response), batch.results.count == 2 else {
            return result(.infrastructureFailure, record, evidence)
        }
        let (steps, bindings) = publishedEvidence(from: batch.results)
        return result(
            outcome,
            record,
            evidence,
            candidateResults: steps,
            roleBindings: bindings
        )
    }

    private func batchResult(from response: AgentResponse?) -> AgentBatchResult? {
        guard case .batch(let result) = response else { return nil }
        return result
    }

    private func publishedEvidence(
        from results: [AutomationResult]
    ) -> ([CADCandidateStepResult], CADOutputRoleBindings) {
        let steps = results.enumerated().map { index, result in
            CADCandidateStepResult(
                stepIndex: index,
                operation: index == 0 ? "createLineSketch.first-line" : "createLineSketch.second-line",
                status: result.didMutate ? .published : .unchanged,
                primaryFeatureID: result.primaryFeatureID?.description,
                createdFeatureIDs: result.createdFeatureIDs.map(\.description),
                diagnostics: result.diagnostics.map(\.message)
            )
        }
        return (
            steps,
            CADOutputRoleBindings(bindings: [
                CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .primary),
                CADOutputRoleBinding(role: "second-line", stepIndex: 1, selector: .primary),
            ])
        )
    }

    private func result(
        _ outcome: CADCaseOutcome,
        _ record: CADCaseLifecycleRecord,
        _ evidence: CADAngleRouteEvidence,
        candidateResults: [CADCandidateStepResult] = [],
        roleBindings: CADOutputRoleBindings? = nil,
        telemetry: CADAngleTelemetry? = nil,
        diagnostics: [String]? = nil
    ) -> CADAngleCaseResult {
        CADAngleCaseResult(
            recordedBy: recorder,
            caseID: caseID,
            outcome: outcome,
            candidateResults: candidateResults,
            roleBindings: roleBindings,
            routeEvidence: evidence,
            telemetry: telemetry ?? self.telemetry(from: record),
            diagnostics: diagnostics ?? record.diagnostics
        )
    }

    private func telemetry(from record: CADCaseLifecycleRecord) -> CADAngleTelemetry {
        CADAngleTelemetry(
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
    ) -> CADAngleTelemetry {
        return telemetry(from: record).replacing(
            oracleWallNanoseconds: elapsed(since: oracleStart),
            readCount: 1,
            featureCount: view.document.document.cadDocument.designGraph.nodes.count,
            bodyCount: view.evaluationSnapshot.bodyCount
        )
    }

    private func sourceCounts(
        in view: ProjectViewSnapshot
    ) throws -> (readCount: Int, entityCount: Int) {
        (2, try failureSourceReader(view))
    }

    private func finish(_ result: CADAngleCaseResult, totalStart: UInt64) -> CADAngleCaseResult {
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
