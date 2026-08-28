import Foundation

struct CADAngleRecorder: Equatable, Sendable {
    init() {}
}

/// The binary, typed result of one activated angle attempt.
struct CADAngleCaseResult: Equatable, Sendable {
    private let recorder: CADAngleRecorder
    let caseID: CADBenchmarkCaseID
    let outcome: CADCaseOutcome
    let candidateResults: [CADCandidateStepResult]
    let roleBindings: CADOutputRoleBindings?
    let routeEvidence: CADAngleRouteEvidence
    let telemetry: CADAngleTelemetry
    let diagnostics: [String]

    init(
        recordedBy recorder: CADAngleRecorder,
        caseID: CADBenchmarkCaseID,
        outcome: CADCaseOutcome,
        candidateResults: [CADCandidateStepResult] = [],
        roleBindings: CADOutputRoleBindings? = nil,
        routeEvidence: CADAngleRouteEvidence,
        telemetry: CADAngleTelemetry,
        diagnostics: [String] = []
    ) {
        self.recorder = recorder
        self.caseID = caseID
        self.outcome = outcome
        self.candidateResults = candidateResults
        self.roleBindings = roleBindings
        self.routeEvidence = routeEvidence
        self.telemetry = telemetry
        self.diagnostics = diagnostics
    }

    var realized: Bool { outcome == .realized }

    func replacingTotalWallNanoseconds(_ value: UInt64) -> CADAngleCaseResult {
        CADAngleCaseResult(
            recordedBy: recorder,
            caseID: caseID,
            outcome: outcome,
            candidateResults: candidateResults,
            roleBindings: roleBindings,
            routeEvidence: routeEvidence,
            telemetry: telemetry.replacing(totalWallNanoseconds: max(1, value)),
            diagnostics: diagnostics
        )
    }

    func validate() throws {
        guard CADActivatedAngleCase(rawValue: caseID.rawValue) != nil,
              diagnostics.allSatisfy({ !$0.isEmpty }),
              Set(candidateResults.map(\.stepIndex)).count == candidateResults.count else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The angle result has an invalid case, diagnostic, or duplicate step."
            )
        }
        try candidateResults.forEach { try $0.validate() }
        try routeEvidence.validate(caseID: caseID)
        try telemetry.validate(caseID: caseID)
        if outcome == .timeout {
            guard telemetry.totalWallNanoseconds >= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A timed-out angle must reach its wall-time bound."
                )
            }
        } else {
            guard telemetry.totalWallNanoseconds <= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A non-timeout angle cannot exceed its wall-time bound."
                )
            }
        }
        guard outcome == .realized else { return }
        guard candidateResults.count == 2,
              candidateResults.map(\.stepIndex) == [0, 1],
              candidateResults.allSatisfy({
                  $0.status == .published
                      && $0.createdFeatureIDs.count == 1
                      && $0.primaryFeatureID == $0.createdFeatureIDs.first
              }),
              let roleBindings,
              roleBindings.bindings == [
                  CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .primary),
                  CADOutputRoleBinding(role: "second-line", stepIndex: 1, selector: .primary),
              ],
              routeEvidence.didPublish,
              telemetry.planningWallNanoseconds > 0,
              telemetry.routeWallNanoseconds > 0,
              telemetry.oracleWallNanoseconds > 0,
              telemetry.totalWallNanoseconds > 0,
              telemetry.actionCount == 1,
              telemetry.commandCount == 2,
              telemetry.readCount >= 1,
              telemetry.entityCount == 2,
              telemetry.featureCount == 2,
              telemetry.bodyCount == 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A realized angle must retain exact atomic-batch publication and oracle evidence."
            )
        }
    }
}
