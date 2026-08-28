import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaKit
import SwiftCAD

/// Projects the shared lifecycle into one box-category result.
@MainActor
struct CADBoxCaseRunner {
    struct SourceCounts: Equatable, Sendable {
        let readCount: Int
        let entityCount: Int
        let featureCount: Int
        let bodyCount: Int
        let faceCount: Int
        let edgeCount: Int
        let vertexCount: Int
    }

    private static let operationName = "createExtrudedRectangle"
    private static let defaultTimeoutWallNanoseconds: UInt64 = 10_000_000_000

    private let activatedCase: CADActivatedBoxCase
    private let recorder = CADBoxRecorder()
    private let timeoutWallNanoseconds: UInt64
    private let preRouteDelayNanoseconds: UInt64
    private let failureSourceReader: @MainActor (ProjectViewSnapshot) throws -> SourceCounts

    init(
        case activatedCase: CADActivatedBoxCase,
        timeoutWallNanoseconds: UInt64 = Self.defaultTimeoutWallNanoseconds,
        preRouteDelayNanoseconds: UInt64 = 0,
        failureSourceReader: @escaping @MainActor (ProjectViewSnapshot) throws -> SourceCounts = {
            try Self.readSourceCounts(in: $0)
        }
    ) {
        self.activatedCase = activatedCase
        self.timeoutWallNanoseconds = max(1, timeoutWallNanoseconds)
        self.preRouteDelayNanoseconds = preRouteDelayNanoseconds
        self.failureSourceReader = failureSourceReader
    }

    private var caseID: CADBenchmarkCaseID { activatedCase.caseID }

    func runReference() async throws -> CADBoxCaseResult {
        try await run(candidate: CADBoxReferenceCandidate())
    }

    func run(candidate: any CADCandidateProtocol) async throws -> CADBoxCaseResult {
        let totalStart = now()
        let entry = try activatedCase.catalogEntry
        let record = try await harness(challenge: entry.challenge).runReference(
            candidate: candidate
        )
        return await project(record, entry: entry, totalStart: totalStart)
    }

    func run(action: CADCandidateAction) async throws -> CADBoxCaseResult {
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
        let projection = try CADBoxChallengeProjection.decode(challenge)
        guard case .automation(
            .solid(.box(let name, let origin, let width, let depth, let height))
        ) = action,
        name.isEmpty == false else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The box action must contain one named solid box."
            )
        }
        try origin.validate(caseID: caseID, field: "action.origin")
        try width.validate(caseID: caseID, field: "action.width")
        try depth.validate(caseID: caseID, field: "action.depth")
        try height.validate(caseID: caseID, field: "action.height")
        let tolerance = try CADBenchmarkTolerancePolicy(modelingTolerance: modelingTolerance)
        guard tolerance.isNonDegenerate(width.meters),
              tolerance.isNonDegenerate(depth.meters),
              tolerance.isNonDegenerate(height.meters) else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The submitted box dimensions are degenerate."
            )
        }
        let sourcePlane = try CADBoxGeometryMapping.sourcePlane(
            expectedOrigin: projection.origin,
            expectedWidth: projection.width,
            expectedDepth: projection.depth,
            submittedOrigin: origin,
            submittedWidth: width,
            submittedDepth: depth,
            modelingTolerance: modelingTolerance,
            caseID: caseID
        )
        return .createExtrudedRectangle(
            name: name,
            plane: SketchPlaneReference(sketchPlane: sourcePlane),
            width: .constant(.length(width.meters, unit: .meter)),
            height: .constant(.length(depth.meters, unit: .meter)),
            depth: .constant(.length(height.meters, unit: .meter)),
            direction: .normal
        )
    }

    private func project(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        totalStart: UInt64
    ) async -> CADBoxCaseResult {
        let evidence = CADBoxRouteEvidence(from: record.routeEvidence)
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
        evidence: CADBoxRouteEvidence,
        totalStart: UInt64
    ) async -> CADBoxCaseResult {
        guard let finalView = record.finalView,
              let automationResult = commandResult(from: record.response) else {
            return finish(result(.infrastructureFailure, record, evidence), totalStart: totalStart)
        }
        let (stepResult, bindings) = publishedEvidence(from: automationResult)
        let oracleStart = now()
        do {
            guard case .box(let expected) = entry.expected else {
                throw CADBoxOracleError.mismatch(
                    "The activated box has no private box expectation."
                )
            }
            let observation = try await record.deadline.run {
                try CADBoxOracle.evaluate(
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
                        bodyCount: observation.bodyCount,
                        faceCount: observation.faceCount,
                        edgeCount: observation.edgeCount,
                        vertexCount: observation.vertexCount
                    )
                ),
                totalStart: totalStart
            )
        } catch is CADCaseDeadlineError {
            return finish(
                failureResult(
                    outcome: .timeout,
                    record: record,
                    evidence: evidence,
                    candidateResult: stepResult,
                    roleBindings: bindings,
                    view: finalView,
                    oracleStart: oracleStart,
                    diagnostic: "\(caseID.rawValue) box oracle exceeded its shared deadline after publication; no retry was attempted."
                ),
                totalStart: totalStart
            )
        } catch let error as CADBoxOracleError {
            let counts: SourceCounts
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
                        featureCount: counts.featureCount,
                        bodyCount: counts.bodyCount,
                        faceCount: counts.faceCount,
                        edgeCount: counts.edgeCount,
                        vertexCount: counts.vertexCount
                    ),
                    diagnostics: [error.description]
                ),
                totalStart: totalStart
            )
        } catch {
            return finish(
                failureResult(
                    outcome: .oracleFailure,
                    record: record,
                    evidence: evidence,
                    candidateResult: stepResult,
                    roleBindings: bindings,
                    view: finalView,
                    oracleStart: oracleStart,
                    diagnostic: "\(caseID.rawValue) box oracle failed: \(message(error))"
                ),
                totalStart: totalStart
            )
        }
    }

    private func publishedMutation(
        _ record: CADCaseLifecycleRecord,
        evidence: CADBoxRouteEvidence,
        outcome: CADCaseOutcome
    ) -> CADBoxCaseResult {
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
                CADOutputRoleBinding(role: "solid", stepIndex: 0, selector: .primary),
            ])
        )
    }

    private func result(
        _ outcome: CADCaseOutcome,
        _ record: CADCaseLifecycleRecord,
        _ evidence: CADBoxRouteEvidence,
        candidateResult: CADCandidateStepResult? = nil,
        roleBindings: CADOutputRoleBindings? = nil,
        telemetry: CADBoxTelemetry? = nil,
        diagnostics: [String]? = nil
    ) -> CADBoxCaseResult {
        CADBoxCaseResult(
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

    private func telemetry(from record: CADCaseLifecycleRecord) -> CADBoxTelemetry {
        CADBoxTelemetry(
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
            faceCount: 0,
            edgeCount: 0,
            vertexCount: 0,
            timeoutWallNanoseconds: record.telemetry.timeoutWallNanoseconds,
            cancellationCheckpointCount: record.telemetry.cancellationCheckpointCount
        )
    }

    private func failureResult(
        outcome: CADCaseOutcome,
        record: CADCaseLifecycleRecord,
        evidence: CADBoxRouteEvidence,
        candidateResult: CADCandidateStepResult,
        roleBindings: CADOutputRoleBindings,
        view: ProjectViewSnapshot,
        oracleStart: UInt64,
        diagnostic: String
    ) -> CADBoxCaseResult {
        do {
            let counts = try sourceCounts(in: view)
            return result(
                outcome,
                record,
                evidence,
                candidateResult: candidateResult,
                roleBindings: roleBindings,
                telemetry: telemetry(from: record).replacing(
                    oracleWallNanoseconds: elapsed(since: oracleStart),
                    readCount: counts.readCount,
                    entityCount: counts.entityCount,
                    featureCount: counts.featureCount,
                    bodyCount: counts.bodyCount,
                    faceCount: counts.faceCount,
                    edgeCount: counts.edgeCount,
                    vertexCount: counts.vertexCount
                ),
                diagnostics: [diagnostic]
            )
        } catch {
            return result(
                .oracleFailure,
                record,
                evidence,
                candidateResult: candidateResult,
                roleBindings: roleBindings,
                telemetry: telemetry(from: record).replacing(
                    oracleWallNanoseconds: elapsed(since: oracleStart),
                    readCount: 2,
                    featureCount: view.document.document.cadDocument.designGraph.nodes.count,
                    bodyCount: view.evaluationSnapshot.bodyCount
                ),
                diagnostics: [
                    diagnostic,
                    "\(caseID.rawValue) box failure telemetry read failed: \(message(error))",
                ]
            )
        }
    }

    private func sourceCounts(
        in view: ProjectViewSnapshot
    ) throws -> SourceCounts {
        try failureSourceReader(view)
    }

    private static func readSourceCounts(
        in view: ProjectViewSnapshot
    ) throws -> SourceCounts {
        let source = try SketchEntitySnapshotService().snapshot(
            document: view.document.document,
            objectRegistry: view.objectRegistry
        )
        let topology = try TopologySnapshotService().snapshot(
            document: view.document.document,
            objectRegistry: view.objectRegistry,
            currentEvaluation: view.cadInteraction,
            currentGeneration: view.documentGeneration
        )
        return SourceCounts(
            readCount: 2,
            entityCount: source.counts.entityCount,
            featureCount: view.document.document.cadDocument.designGraph.nodes.count,
            bodyCount: topology.counts.bodyCount,
            faceCount: topology.counts.faceCount,
            edgeCount: topology.counts.edgeCount,
            vertexCount: topology.counts.vertexCount
        )
    }

    private func finish(
        _ result: CADBoxCaseResult,
        totalStart: UInt64
    ) -> CADBoxCaseResult {
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
