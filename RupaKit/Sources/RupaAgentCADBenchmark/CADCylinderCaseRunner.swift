import Foundation
import RupaAgentProtocol
import RupaCADDomain
import RupaCore
import RupaKit

/// Projects the shared lifecycle into one cylinder-category result.
@MainActor
struct CADCylinderCaseRunner {
    struct SourceCounts: Equatable, Sendable {
        let readCount: Int
        let entityCount: Int
        let featureCount: Int
        let bodyCount: Int
        let faceCount: Int
        let edgeCount: Int
        let vertexCount: Int
    }

    private static let operationName = "createExtrudedCircle"
    private static let defaultTimeoutWallNanoseconds: UInt64 = 10_000_000_000

    private let activatedCase: CADActivatedCylinderCase
    private let recorder = CADCylinderRecorder()
    private let timeoutWallNanoseconds: UInt64
    private let preRouteDelayNanoseconds: UInt64
    private let failureSourceReader: @MainActor (ProjectViewSnapshot) throws -> SourceCounts

    init(
        case activatedCase: CADActivatedCylinderCase,
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

    func runReference() async throws -> CADCylinderCaseResult {
        try await run(candidate: CADCylinderReferenceCandidate())
    }

    func run(candidate: any CADCandidateProtocol) async throws -> CADCylinderCaseResult {
        let totalStart = now()
        let entry = try activatedCase.catalogEntry
        let record = try await harness(entry: entry).runReference(candidate: candidate)
        return await project(record, entry: entry, totalStart: totalStart)
    }

    func run(action: CADCandidateAction) async throws -> CADCylinderCaseResult {
        let totalStart = now()
        let entry = try activatedCase.catalogEntry
        let record = try await harness(entry: entry).run(action: action)
        return await project(record, entry: entry, totalStart: totalStart)
    }

    private func harness(entry: CADCatalogEntry) -> CADCaseLifecycleHarness {
        CADCaseLifecycleHarness(
            caseID: caseID,
            challenge: entry.challenge,
            programPlanner: { action in
                try DefaultCADSemanticProgramPlanner().plan(for: entry, action: action)
            },
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            preRouteDelayNanoseconds: preRouteDelayNanoseconds
        )
    }

    private func project(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        totalStart: UInt64
    ) async -> CADCylinderCaseResult {
        let evidence = CADCylinderRouteEvidence(from: record.routeEvidence)
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
        evidence: CADCylinderRouteEvidence,
        totalStart: UInt64
    ) async -> CADCylinderCaseResult {
        guard let finalView = record.finalView,
              let semanticReceipt = CADSemanticExecutionEvidence.committedReceipt(from: record.response) else {
            return finish(result(.infrastructureFailure, record, evidence), totalStart: totalStart)
        }
        let semanticEvidence = CADSemanticExecutionEvidence(receipt: semanticReceipt)
        let stepResult = semanticEvidence.stepResult(
            node: "cylinder",
            operation: RupaCADSemanticOperationID.solidCylinder.rawValue,
            index: 0,
            primaryOutputs: ["body"]
        )
        let bindings = CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(role: "solid", stepIndex: 0, selector: .primary),
        ])
        let oracleStart = now()
        do {
            guard case .cylinder(let expected) = entry.expected else {
                throw CADCylinderOracleError.mismatch(
                    "The activated cylinder has no private cylinder expectation."
                )
            }
            let observation = try await record.deadline.run {
                try CADCylinderOracle.evaluate(
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
                    diagnostic: "\(caseID.rawValue) cylinder oracle exceeded its shared deadline after publication; no retry was attempted."
                ),
                totalStart: totalStart
            )
        } catch let error as CADCylinderOracleError {
            do {
                let counts = try sourceCounts(in: finalView)
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
                    result(
                        .oracleFailure,
                        record,
                        evidence,
                        candidateResult: stepResult,
                        roleBindings: bindings,
                        telemetry: telemetry(from: record).replacing(
                            oracleWallNanoseconds: elapsed(since: oracleStart),
                            readCount: 2,
                            featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                            bodyCount: finalView.evaluationSnapshot.bodyCount
                        ),
                        diagnostics: [
                            errorMessage(error, prefix: "\(caseID.rawValue) failure telemetry read failed")
                        ]
                    ),
                    totalStart: totalStart
                )
            }
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
                    diagnostic: "\(caseID.rawValue) cylinder oracle failed: \(message(error))"
                ),
                totalStart: totalStart
            )
        }
    }

    private func publishedMutation(
        _ record: CADCaseLifecycleRecord,
        evidence: CADCylinderRouteEvidence,
        outcome: CADCaseOutcome
    ) -> CADCylinderCaseResult {
        guard let semanticReceipt = CADSemanticExecutionEvidence.committedReceipt(from: record.response) else {
            return result(.infrastructureFailure, record, evidence)
        }
        let semanticEvidence = CADSemanticExecutionEvidence(receipt: semanticReceipt)
        let stepResult = semanticEvidence.stepResult(
            node: "cylinder",
            operation: RupaCADSemanticOperationID.solidCylinder.rawValue,
            index: 0,
            primaryOutputs: ["body"]
        )
        let bindings = CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(role: "solid", stepIndex: 0, selector: .primary),
        ])
        return result(
            outcome,
            record,
            evidence,
            candidateResult: stepResult,
            roleBindings: bindings
        )
    }


    private func result(
        _ outcome: CADCaseOutcome,
        _ record: CADCaseLifecycleRecord,
        _ evidence: CADCylinderRouteEvidence,
        candidateResult: CADCandidateStepResult? = nil,
        roleBindings: CADOutputRoleBindings? = nil,
        telemetry: CADCylinderTelemetry? = nil,
        diagnostics: [String]? = nil
    ) -> CADCylinderCaseResult {
        CADCylinderCaseResult(
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

    private func telemetry(from record: CADCaseLifecycleRecord) -> CADCylinderTelemetry {
        CADCylinderTelemetry(
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
        evidence: CADCylinderRouteEvidence,
        candidateResult: CADCandidateStepResult,
        roleBindings: CADOutputRoleBindings,
        view: ProjectViewSnapshot,
        oracleStart: UInt64,
        diagnostic: String
    ) -> CADCylinderCaseResult {
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
                    errorMessage(error, prefix: "\(caseID.rawValue) cylinder failure telemetry read failed"),
                ]
            )
        }
    }

    private func sourceCounts(in view: ProjectViewSnapshot) throws -> SourceCounts {
        try failureSourceReader(view)
    }

    private static func readSourceCounts(in view: ProjectViewSnapshot) throws -> SourceCounts {
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
        _ result: CADCylinderCaseResult,
        totalStart: UInt64
    ) -> CADCylinderCaseResult {
        result.replacingTotalWallNanoseconds(elapsed(since: totalStart))
    }

    private func now() -> UInt64 {
        UInt64((ProcessInfo.processInfo.systemUptime * 1_000_000_000).rounded())
    }

    private func elapsed(since start: UInt64) -> UInt64 {
        max(1, now() - start)
    }

    private func errorMessage(_ error: Error, prefix: String) -> String {
        "\(prefix): \(message(error))"
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
