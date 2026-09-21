import Foundation

/// The binary, typed result of one activated line case attempt.
struct CADLineCaseResult: Equatable, Sendable {
    private let recorder: CADLineRecorder
    let caseID: CADBenchmarkCaseID
    let outcome: CADCaseOutcome
    let candidateResult: CADCandidateStepResult?
    let roleBindings: CADOutputRoleBindings?
    let routeEvidence: CADLineRouteEvidence
    let telemetry: CADLineTelemetry
    let diagnostics: [String]

    init(
        recordedBy recorder: CADLineRecorder,
        caseID: CADBenchmarkCaseID,
        outcome: CADCaseOutcome,
        candidateResult: CADCandidateStepResult? = nil,
        roleBindings: CADOutputRoleBindings? = nil,
        routeEvidence: CADLineRouteEvidence = .empty,
        telemetry: CADLineTelemetry,
        diagnostics: [String] = []
    ) {
        self.recorder = recorder
        self.caseID = caseID
        self.outcome = outcome
        self.candidateResult = candidateResult
        self.roleBindings = roleBindings
        self.routeEvidence = routeEvidence
        self.telemetry = telemetry
        self.diagnostics = diagnostics
    }

    var realized: Bool {
        outcome == .realized
    }

    func withCleanupEvidence(
        cleanupWallNanoseconds: UInt64,
        remainingRegistrationCount: Int
    ) -> CADLineCaseResult {
        CADLineCaseResult(
            recordedBy: recorder,
            caseID: caseID,
            outcome: outcome,
            candidateResult: candidateResult,
            roleBindings: roleBindings,
            routeEvidence: CADLineRouteEvidence(
                initialDocumentGeneration: routeEvidence.initialDocumentGeneration,
                finalDocumentGeneration: routeEvidence.finalDocumentGeneration,
                initialTransactionRevision: routeEvidence.initialTransactionRevision,
                finalTransactionRevision: routeEvidence.finalTransactionRevision,
                initialPublicationSequence: routeEvidence.initialPublicationSequence,
                finalPublicationSequence: routeEvidence.finalPublicationSequence,
                initialWorkspaceRevision: routeEvidence.initialWorkspaceRevision,
                finalWorkspaceRevision: routeEvidence.finalWorkspaceRevision,
                didPublish: routeEvidence.didPublish,
                cleanupCompleted: remainingRegistrationCount == 0,
                cleanupWallNanoseconds: cleanupWallNanoseconds,
                remainingRegistrationCount: remainingRegistrationCount
            ),
            telemetry: telemetry,
            diagnostics: diagnostics
        )
    }

    func withTotalWallNanoseconds(_ totalWallNanoseconds: UInt64) -> CADLineCaseResult {
        CADLineCaseResult(
            recordedBy: recorder,
            caseID: caseID,
            outcome: outcome,
            candidateResult: candidateResult,
            roleBindings: roleBindings,
            routeEvidence: routeEvidence,
            telemetry: CADLineTelemetry(
                planningWallNanoseconds: telemetry.planningWallNanoseconds,
                routeWallNanoseconds: telemetry.routeWallNanoseconds,
                oracleWallNanoseconds: telemetry.oracleWallNanoseconds,
                totalWallNanoseconds: max(1, totalWallNanoseconds),
                actionCount: telemetry.actionCount,
                commandCount: telemetry.commandCount,
                readCount: telemetry.readCount,
                entityCount: telemetry.entityCount,
                featureCount: telemetry.featureCount,
                bodyCount: telemetry.bodyCount,
                timeoutWallNanoseconds: telemetry.timeoutWallNanoseconds,
                cancellationCheckpointCount: telemetry.cancellationCheckpointCount
            ),
            diagnostics: diagnostics
        )
    }

    func validate() throws {
        guard CADActivatedLineCase(rawValue: caseID.rawValue) != nil else {
            throw CADBenchmarkError.invalidCaseID(caseID.rawValue)
        }
        if let candidateResult {
            try candidateResult.validate()
        }
        guard diagnostics.allSatisfy({ !$0.isEmpty }) else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Line diagnostics must not contain empty messages."
            )
        }
        guard routeEvidence.cleanupCompleted else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Activated line results must retain guaranteed workspace cleanup evidence."
            )
        }
        try routeEvidence.validate(caseID: caseID)
        try telemetry.validate(caseID: caseID)
        if outcome == .timeout {
            guard telemetry.totalWallNanoseconds >= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A timed-out line result must reach its declared wall-time bound."
                )
            }
        } else {
            guard telemetry.totalWallNanoseconds <= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A non-timeout line result cannot exceed its wall-time bound."
                )
            }
        }

        guard outcome == .realized else {
            return
        }

        guard let candidateResult,
              let roleBindings else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A realized line result must include candidate evidence and role bindings."
            )
        }
        guard candidateResult.status == .published,
              candidateResult.createdFeatureIDs.count == 1,
              candidateResult.primaryFeatureID == candidateResult.createdFeatureIDs.first,
              roleBindings.bindings.count == 1,
              let binding = roleBindings.bindings.first,
              binding.role == "segment",
              binding.stepIndex == candidateResult.stepIndex,
              binding.selector == .primary else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A realized line result must bind the published segment to its primary feature alias."
            )
        }
        guard routeEvidence.didPublish, routeEvidence.cleanupCompleted else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A realized line result must retain published coordinates and cleanup evidence."
            )
        }
        guard telemetry.totalWallNanoseconds > 0,
              telemetry.actionCount == 1,
              telemetry.commandCount == 1,
              telemetry.readCount >= 1,
              telemetry.entityCount == 1,
              telemetry.featureCount == 1,
              telemetry.bodyCount == 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A realized line result must contain measured route and oracle evidence."
            )
        }
    }
}
