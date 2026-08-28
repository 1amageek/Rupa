import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaKit
import SwiftCAD

struct CADLineRecorder: Equatable, Sendable {
    fileprivate init() {}
}

/// Projects the shared production lifecycle into the line-category result.
///
/// The facade owns line activation, public-to-CAD mapping, private catalog
/// access, and the exact line oracle. Workspace mutation, registration,
/// deadlines, route dispatch, and cleanup are owned by the shared harness.
@MainActor
struct CADLineCaseRunner {
    private static let operationName = "createLineSketch"
    private static let defaultTimeoutWallNanoseconds: UInt64 = 10_000_000_000

    private let activatedCase: CADActivatedLineCase
    private let recorder = CADLineRecorder()
    private let timeoutWallNanoseconds: UInt64
    private let preRouteDelayNanoseconds: UInt64
    private let postRegistrationDelayNanoseconds: UInt64

    init(
        case activatedCase: CADActivatedLineCase,
        timeoutWallNanoseconds: UInt64 = Self.defaultTimeoutWallNanoseconds,
        preRouteDelayNanoseconds: UInt64 = 0,
        postRegistrationDelayNanoseconds: UInt64 = 0
    ) {
        self.activatedCase = activatedCase
        self.timeoutWallNanoseconds = max(1, timeoutWallNanoseconds)
        self.preRouteDelayNanoseconds = preRouteDelayNanoseconds
        self.postRegistrationDelayNanoseconds = postRegistrationDelayNanoseconds
    }

    private var caseID: CADBenchmarkCaseID {
        activatedCase.caseID
    }

    func runReference() async throws -> CADLineCaseResult {
        let totalStart = now()
        let entry = try catalogEntry()
        let record = try await makeHarness(challenge: entry.challenge)
            .runReference(candidate: CADLineReferenceCandidate())
        return await project(record, entry: entry, totalStart: totalStart)
    }

    func run(action: CADCandidateAction) async throws -> CADLineCaseResult {
        let totalStart = now()
        let entry = try catalogEntry()
        let record = try await makeHarness(challenge: entry.challenge)
            .run(action: action)
        return await project(record, entry: entry, totalStart: totalStart)
    }

    func runStaleReference() async throws -> CADLineCaseResult {
        let totalStart = now()
        let entry = try catalogEntry()
        let action = try CADLineReferenceCandidate.action(for: entry.challenge)
        let record = try await makeHarness(challenge: entry.challenge)
            .runStale(action: action)
        return await project(record, entry: entry, totalStart: totalStart)
    }

    private func makeHarness(challenge: CADChallenge) -> CADCaseLifecycleHarness {
        let routing = CADCaseActionRouting(
            operationName: Self.operationName,
            commandBuilder: { [self] action, challenge, modelingTolerance in
                try self.makeCommand(
                    from: action,
                    challenge: challenge,
                    modelingTolerance: modelingTolerance
                )
            }
        )
        return CADCaseLifecycleHarness(
            caseID: caseID,
            challenge: challenge,
            routing: routing,
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            preRouteDelayNanoseconds: preRouteDelayNanoseconds,
            postRegistrationDelayNanoseconds: postRegistrationDelayNanoseconds
        )
    }

    private func makeCommand(
        from action: CADCandidateAction,
        challenge: CADChallenge,
        modelingTolerance: ModelingTolerance
    ) throws -> AutomationCommand {
        let projection = try CADLineChallengeProjection.decode(challenge)
        guard case .automation(.sketch(.line(let name, let plane, let start, let end))) = action,
              !name.isEmpty,
              plane == projection.orientation else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The activated line action must use the public challenge orientation."
            )
        }
        let sourcePlane = try CADLineGeometryMapping.sourcePlane(
            orientation: projection.orientation,
            anchor: projection.anchor,
            modelingTolerance: modelingTolerance,
            caseID: caseID
        )
        let startProjection = try CADLineGeometryMapping.projection(
            of: start,
            sourcePlane: sourcePlane,
            modelingTolerance: modelingTolerance,
            caseID: caseID,
            field: "action.start"
        )
        let endProjection = try CADLineGeometryMapping.projection(
            of: end,
            sourcePlane: sourcePlane,
            modelingTolerance: modelingTolerance,
            caseID: caseID,
            field: "action.end"
        )
        return .createLineSketch(
            name: name,
            plane: SketchPlaneReference(sketchPlane: sourcePlane),
            start: SketchPoint(
                x: .constant(.length(startProjection.point.x, unit: .meter)),
                y: .constant(.length(startProjection.point.y, unit: .meter))
            ),
            end: SketchPoint(
                x: .constant(.length(endProjection.point.x, unit: .meter)),
                y: .constant(.length(endProjection.point.y, unit: .meter))
            )
        )
    }

    private func project(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        totalStart: UInt64
    ) async -> CADLineCaseResult {
        let routeEvidence = CADLineRouteEvidence(from: record.routeEvidence)
        switch record.outcome {
        case .published:
            return await projectPublished(
                record,
                entry: entry,
                routeEvidence: routeEvidence,
                totalStart: totalStart
            )
        case .cancelledAfterPublication:
            return finish(
                projectPublishedMutation(
                    record,
                    routeEvidence: routeEvidence,
                    outcome: .cancellation
                ),
                totalStart: totalStart
            )
        case .invalidSubmission:
            return finish(
                result(
                    outcome: .invalidSubmission,
                    record: record,
                    routeEvidence: routeEvidence
                ),
                totalStart: totalStart
            )
        case .executionFailure:
            return finish(
                result(
                    outcome: .executionFailure,
                    record: record,
                    routeEvidence: routeEvidence
                ),
                totalStart: totalStart
            )
        case .timeout:
            return finish(
                result(
                    outcome: .timeout,
                    record: record,
                    routeEvidence: routeEvidence
                ),
                totalStart: totalStart
            )
        case .cancellation:
            return finish(
                result(
                    outcome: .cancellation,
                    record: record,
                    routeEvidence: routeEvidence
                ),
                totalStart: totalStart
            )
        case .infrastructureFailure:
            return finish(
                result(
                    outcome: .infrastructureFailure,
                    record: record,
                    routeEvidence: routeEvidence
                ),
                totalStart: totalStart
            )
        }
    }

    private func projectPublished(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        routeEvidence: CADLineRouteEvidence,
        totalStart: UInt64
    ) async -> CADLineCaseResult {
        guard let finalView = record.finalView,
              let automationResult = commandResult(from: record.response) else {
            return finish(
                result(
                    outcome: .infrastructureFailure,
                    record: record,
                    routeEvidence: routeEvidence
                ),
                totalStart: totalStart
            )
        }
        let (stepResult, bindings) = publishedMutationEvidence(from: automationResult)
        let oracleStart = now()
        do {
            guard case .line(let expected) = entry.expected else {
                throw CADLineOracleError.mismatch(
                    "The activated line case has no private line expectation."
                )
            }
            let observation = try await record.deadline.run {
                try CADLineOracle.evaluate(
                    expected: expected,
                    challenge: entry.challenge,
                    bindings: bindings,
                    stepResults: [stepResult],
                    snapshot: finalView
                )
            }
            return finish(
                result(
                    outcome: .realized,
                    record: record,
                    candidateResult: stepResult,
                    roleBindings: bindings,
                    routeEvidence: routeEvidence,
                    telemetry: telemetry(
                        from: record,
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
                    outcome: .timeout,
                    record: record,
                    candidateResult: stepResult,
                    roleBindings: bindings,
                    routeEvidence: routeEvidence,
                    telemetry: telemetry(
                        from: record,
                        oracleWallNanoseconds: elapsed(since: oracleStart),
                        readCount: 1,
                        entityCount: 0,
                        featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                        bodyCount: finalView.evaluationSnapshot.bodyCount
                    ),
                    diagnostics: [
                        "\(caseID.rawValue) oracle exceeded its shared deadline after publication; no retry was attempted."
                    ]
                ),
                totalStart: totalStart
            )
        } catch let error as CADLineOracleError {
            let observedCounts: (readCount: Int, entityCount: Int)
            do {
                let source = try SketchEntitySnapshotService().snapshot(
                    document: finalView.document.document,
                    objectRegistry: finalView.objectRegistry
                )
                observedCounts = (2, source.counts.entityCount)
            } catch {
                return finish(
                    result(
                        outcome: .oracleFailure,
                        record: record,
                        candidateResult: stepResult,
                        roleBindings: bindings,
                        routeEvidence: routeEvidence,
                        telemetry: telemetry(
                            from: record,
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
                    outcome: .invalidSubmission,
                    record: record,
                    candidateResult: stepResult,
                    roleBindings: bindings,
                    routeEvidence: routeEvidence,
                    telemetry: telemetry(
                        from: record,
                        oracleWallNanoseconds: elapsed(since: oracleStart),
                        readCount: observedCounts.readCount,
                        entityCount: observedCounts.entityCount,
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
                    outcome: .oracleFailure,
                    record: record,
                    candidateResult: stepResult,
                    roleBindings: bindings,
                    routeEvidence: routeEvidence,
                    telemetry: telemetry(
                        from: record,
                        oracleWallNanoseconds: elapsed(since: oracleStart),
                        readCount: 1,
                        entityCount: 0,
                        featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                        bodyCount: finalView.evaluationSnapshot.bodyCount
                    ),
                    diagnostics: ["\(caseID.rawValue) oracle failed: \(message(error))"]
                ),
                totalStart: totalStart
            )
        }
    }

    private func projectPublishedMutation(
        _ record: CADCaseLifecycleRecord,
        routeEvidence: CADLineRouteEvidence,
        outcome: CADCaseOutcome
    ) -> CADLineCaseResult {
        guard let automationResult = commandResult(from: record.response) else {
            return result(
                outcome: .infrastructureFailure,
                record: record,
                routeEvidence: routeEvidence
            )
        }
        let (stepResult, bindings) = publishedMutationEvidence(from: automationResult)
        return result(
            outcome: outcome,
            record: record,
            candidateResult: stepResult,
            roleBindings: bindings,
            routeEvidence: routeEvidence,
            telemetry: telemetry(from: record)
        )
    }

    private func commandResult(from response: AgentResponse?) -> AutomationResult? {
        guard case .command(let automationResult) = response else {
            return nil
        }
        return automationResult
    }

    private func publishedMutationEvidence(
        from automationResult: AutomationResult
    ) -> (CADCandidateStepResult, CADOutputRoleBindings) {
        let stepResult = CADCandidateStepResult(
            stepIndex: 0,
            operation: Self.operationName,
            status: automationResult.didMutate ? .published : .unchanged,
            primaryFeatureID: automationResult.primaryFeatureID?.description,
            createdFeatureIDs: automationResult.createdFeatureIDs.map(\.description),
            diagnostics: automationResult.diagnostics.map(\.message)
        )
        let bindings = CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(role: "segment", stepIndex: 0, selector: .primary),
        ])
        return (stepResult, bindings)
    }

    private func result(
        outcome: CADCaseOutcome,
        record: CADCaseLifecycleRecord,
        candidateResult: CADCandidateStepResult? = nil,
        roleBindings: CADOutputRoleBindings? = nil,
        routeEvidence: CADLineRouteEvidence,
        telemetry: CADLineTelemetry? = nil,
        diagnostics: [String]? = nil
    ) -> CADLineCaseResult {
        CADLineCaseResult(
            recordedBy: recorder,
            caseID: caseID,
            outcome: outcome,
            candidateResult: candidateResult,
            roleBindings: roleBindings,
            routeEvidence: routeEvidence,
            telemetry: telemetry ?? self.telemetry(from: record),
            diagnostics: diagnostics ?? record.diagnostics
        )
    }

    private func telemetry(
        from record: CADCaseLifecycleRecord,
        oracleWallNanoseconds: UInt64 = 0,
        readCount: Int = 0,
        entityCount: Int = 0,
        featureCount: Int = 0,
        bodyCount: Int = 0
    ) -> CADLineTelemetry {
        CADLineTelemetry(
            planningWallNanoseconds: record.telemetry.planningWallNanoseconds,
            routeWallNanoseconds: record.telemetry.routeWallNanoseconds,
            oracleWallNanoseconds: oracleWallNanoseconds,
            totalWallNanoseconds: record.telemetry.totalWallNanoseconds,
            actionCount: record.telemetry.actionCount,
            commandCount: record.telemetry.commandCount,
            readCount: readCount,
            entityCount: entityCount,
            featureCount: featureCount,
            bodyCount: bodyCount,
            timeoutWallNanoseconds: record.telemetry.timeoutWallNanoseconds,
            cancellationCheckpointCount: record.telemetry.cancellationCheckpointCount
        )
    }

    private func catalogEntry() throws -> CADCatalogEntry {
        try activatedCase.catalogEntry
    }

    private func finish(
        _ result: CADLineCaseResult,
        totalStart: UInt64
    ) -> CADLineCaseResult {
        result.withTotalWallNanoseconds(elapsed(since: totalStart))
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
           !description.isEmpty {
            return description
        }
        return String(describing: error)
    }
}

private extension CADLineRouteEvidence {
    init(from evidence: CADCaseLifecycleRecord.RouteEvidence) {
        self.init(
            initialDocumentGeneration: evidence.initialDocumentGeneration,
            finalDocumentGeneration: evidence.finalDocumentGeneration,
            initialTransactionRevision: evidence.initialTransactionRevision,
            finalTransactionRevision: evidence.finalTransactionRevision,
            initialPublicationSequence: evidence.initialPublicationSequence,
            finalPublicationSequence: evidence.finalPublicationSequence,
            initialWorkspaceRevision: evidence.initialWorkspaceRevision,
            finalWorkspaceRevision: evidence.finalWorkspaceRevision,
            didPublish: evidence.didPublish,
            cleanupCompleted: evidence.cleanupCompleted,
            cleanupWallNanoseconds: evidence.cleanupWallNanoseconds,
            remainingRegistrationCount: evidence.remainingRegistrationCount
        )
    }
}
