import Foundation

struct CADBoxRecorder: Equatable, Sendable {
    init() {}
}

/// The binary, typed result of one activated box attempt.
struct CADBoxCaseResult: Equatable, Sendable {
    private let recorder: CADBoxRecorder
    let caseID: CADBenchmarkCaseID
    let outcome: CADCaseOutcome
    let candidateResult: CADCandidateStepResult?
    let roleBindings: CADOutputRoleBindings?
    let routeEvidence: CADBoxRouteEvidence
    let telemetry: CADBoxTelemetry
    let diagnostics: [String]

    init(
        recordedBy recorder: CADBoxRecorder,
        caseID: CADBenchmarkCaseID,
        outcome: CADCaseOutcome,
        candidateResult: CADCandidateStepResult? = nil,
        roleBindings: CADOutputRoleBindings? = nil,
        routeEvidence: CADBoxRouteEvidence,
        telemetry: CADBoxTelemetry,
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

    func replacingTotalWallNanoseconds(_ value: UInt64) -> CADBoxCaseResult {
        CADBoxCaseResult(
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
        guard CADActivatedBoxCase(rawValue: caseID.rawValue) != nil,
              diagnostics.allSatisfy({ !$0.isEmpty }) else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The box result has an invalid case or diagnostic."
            )
        }
        try candidateResult?.validate()
        try routeEvidence.validate(caseID: caseID)
        try telemetry.validate(caseID: caseID)
        if outcome == .timeout {
            guard telemetry.totalWallNanoseconds >= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A timed-out box must reach its wall-time bound."
                )
            }
        } else {
            guard telemetry.totalWallNanoseconds <= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A non-timeout box cannot exceed its wall-time bound."
                )
            }
        }
        guard outcome == .realized else { return }
        guard let candidateResult,
              let roleBindings,
              candidateResult.status == .published,
              candidateResult.createdFeatureIDs.count == 2,
              candidateResult.primaryFeatureID == candidateResult.createdFeatureIDs.last,
              roleBindings.bindings.count == 1,
              let binding = roleBindings.bindings.first,
              binding.role == "solid",
              binding.stepIndex == candidateResult.stepIndex,
              binding.selector == .primary,
              routeEvidence.didPublish,
              telemetry.planningWallNanoseconds > 0,
              telemetry.routeWallNanoseconds > 0,
              telemetry.oracleWallNanoseconds > 0,
              telemetry.totalWallNanoseconds > 0,
              telemetry.actionCount == 1,
              telemetry.commandCount == 1,
              telemetry.readCount >= 1,
              telemetry.entityCount == 4,
              telemetry.featureCount == 2,
              telemetry.bodyCount == 1,
              telemetry.faceCount == 6,
              telemetry.edgeCount == 12,
              telemetry.vertexCount == 8 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A realized box must retain exact source and B-rep evidence."
            )
        }
    }
}
