import Foundation

struct CADSphereRecorder: Equatable, Sendable {
    init() {}
}

/// The typed result of one analytic-sphere production attempt.
struct CADSphereCaseResult: Equatable, Sendable {
    private let recorder: CADSphereRecorder
    let caseID: CADBenchmarkCaseID
    let outcome: CADCaseOutcome
    let candidateResult: CADCandidateStepResult?
    let roleBindings: CADOutputRoleBindings?
    let routeEvidence: CADSphereRouteEvidence
    let telemetry: CADSphereTelemetry
    let diagnostics: [String]

    init(
        recordedBy recorder: CADSphereRecorder,
        caseID: CADBenchmarkCaseID,
        outcome: CADCaseOutcome,
        candidateResult: CADCandidateStepResult? = nil,
        roleBindings: CADOutputRoleBindings? = nil,
        routeEvidence: CADSphereRouteEvidence,
        telemetry: CADSphereTelemetry,
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

    func replacingTotalWallNanoseconds(_ value: UInt64) -> CADSphereCaseResult {
        CADSphereCaseResult(
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
        guard CADActivatedSphereCase(rawValue: caseID.rawValue) != nil,
              diagnostics.allSatisfy({ !$0.isEmpty }) else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The sphere result has an invalid case or diagnostic."
            )
        }
        try candidateResult?.validate()
        try routeEvidence.validate(caseID: caseID)
        try telemetry.validate(caseID: caseID)
        if outcome == .timeout {
            guard telemetry.totalWallNanoseconds >= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A timed-out sphere must reach its wall-time bound."
                )
            }
        } else {
            guard telemetry.totalWallNanoseconds <= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A non-timeout sphere cannot exceed its wall-time bound."
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
              binding.role == "sphere",
              binding.stepIndex == candidateResult.stepIndex,
              binding.selector == .primary,
              routeEvidence.didPublish,
              telemetry.actionCount == 1,
              telemetry.commandCount == 1,
              telemetry.readCount == 2,
              telemetry.featureCount == 1,
              telemetry.bodyCount == 1,
              telemetry.faceCount == 8,
              telemetry.edgeCount == 12,
              telemetry.vertexCount == 6,
              telemetry.analyticSurfaceCount == 8 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A realized sphere must retain exact analytic source and B-rep evidence."
            )
        }
    }
}
