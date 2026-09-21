import Foundation

struct CADRectangleRecorder: Equatable, Sendable {
    init() {}
}

/// The binary, typed result of one activated rectangle attempt.
struct CADRectangleCaseResult: Equatable, Sendable {
    private let recorder: CADRectangleRecorder
    let caseID: CADBenchmarkCaseID
    let outcome: CADCaseOutcome
    let candidateResult: CADCandidateStepResult?
    let roleBindings: CADOutputRoleBindings?
    let routeEvidence: CADRectangleRouteEvidence
    let telemetry: CADRectangleTelemetry
    let diagnostics: [String]

    init(
        recordedBy recorder: CADRectangleRecorder,
        caseID: CADBenchmarkCaseID,
        outcome: CADCaseOutcome,
        candidateResult: CADCandidateStepResult? = nil,
        roleBindings: CADOutputRoleBindings? = nil,
        routeEvidence: CADRectangleRouteEvidence,
        telemetry: CADRectangleTelemetry,
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

    var realized: Bool { outcome == .realized }

    func replacingTotalWallNanoseconds(_ value: UInt64) -> CADRectangleCaseResult {
        CADRectangleCaseResult(
            recordedBy: recorder,
            caseID: caseID,
            outcome: outcome,
            candidateResult: candidateResult,
            roleBindings: roleBindings,
            routeEvidence: routeEvidence,
            telemetry: telemetry.replacing(totalWallNanoseconds: max(1, value)),
            diagnostics: diagnostics
        )
    }

    func validate() throws {
        guard CADActivatedRectangleCase(rawValue: caseID.rawValue) != nil,
              diagnostics.allSatisfy({ !$0.isEmpty }) else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The rectangle result has an invalid case or diagnostic."
            )
        }
        try candidateResult?.validate()
        try routeEvidence.validate(caseID: caseID)
        try telemetry.validate(caseID: caseID)
        if outcome == .timeout {
            guard telemetry.totalWallNanoseconds >= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A timed-out rectangle must reach its wall-time bound."
                )
            }
        } else {
            guard telemetry.totalWallNanoseconds <= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A non-timeout rectangle cannot exceed its wall-time bound."
                )
            }
        }
        guard outcome == .realized else { return }
        guard let candidateResult,
              let roleBindings,
              candidateResult.status == .published,
              candidateResult.createdFeatureIDs.count == 1,
              candidateResult.primaryFeatureID == candidateResult.createdFeatureIDs.first,
              roleBindings.bindings.count == 1,
              let binding = roleBindings.bindings.first,
              binding.role == "rectangle",
              binding.stepIndex == candidateResult.stepIndex,
              binding.selector == .primary,
              routeEvidence.didPublish,
              telemetry.actionCount == 1,
              telemetry.commandCount == 1,
              telemetry.readCount >= 1,
              telemetry.entityCount == 4,
              telemetry.featureCount == 1,
              telemetry.bodyCount == 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A realized rectangle must retain exact publication and oracle evidence."
            )
        }
    }
}
