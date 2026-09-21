struct CADCylinderRecorder: Equatable, Sendable {
    init() {}
}

/// The binary, typed result of one activated cylinder attempt.
struct CADCylinderCaseResult: Equatable, Sendable {
    private let recorder: CADCylinderRecorder
    let caseID: CADBenchmarkCaseID
    let outcome: CADCaseOutcome
    let candidateResult: CADCandidateStepResult?
    let roleBindings: CADOutputRoleBindings?
    let routeEvidence: CADCylinderRouteEvidence
    let telemetry: CADCylinderTelemetry
    let diagnostics: [String]

    init(
        recordedBy recorder: CADCylinderRecorder,
        caseID: CADBenchmarkCaseID,
        outcome: CADCaseOutcome,
        candidateResult: CADCandidateStepResult? = nil,
        roleBindings: CADOutputRoleBindings? = nil,
        routeEvidence: CADCylinderRouteEvidence,
        telemetry: CADCylinderTelemetry,
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

    func replacingTotalWallNanoseconds(_ value: UInt64) -> CADCylinderCaseResult {
        CADCylinderCaseResult(
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
        guard CADActivatedCylinderCase(rawValue: caseID.rawValue) != nil,
              diagnostics.allSatisfy({ !$0.isEmpty }) else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The cylinder result has an invalid case or diagnostic."
            )
        }
        try candidateResult?.validate()
        try routeEvidence.validate(caseID: caseID)
        try telemetry.validate(caseID: caseID)
        if outcome == .timeout {
            guard telemetry.totalWallNanoseconds >= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A timed-out cylinder must reach its wall-time bound."
                )
            }
        } else {
            guard telemetry.totalWallNanoseconds <= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A non-timeout cylinder cannot exceed its wall-time bound."
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
              telemetry.entityCount == 1,
              telemetry.featureCount == 2,
              telemetry.bodyCount == 1,
              telemetry.faceCount == 6,
              telemetry.edgeCount == 12,
              telemetry.vertexCount == 8 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A realized cylinder must retain exact source and B-rep evidence."
            )
        }
    }
}
