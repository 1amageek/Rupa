import Foundation

/// The typed result of one activated constraint attempt.
struct CADConstraintCaseResult: Equatable, Sendable {
    let caseID: CADBenchmarkCaseID
    let outcome: CADCaseOutcome
    let candidateResult: CADCandidateStepResult?
    let roleBindings: CADOutputRoleBindings?
    let routeEvidence: CADConstraintRouteEvidence
    let telemetry: CADConstraintTelemetry
    let diagnostics: [String]

    var realized: Bool { outcome == .realized }

    func validate() throws {
        let activated = try CADActivatedConstraintCase(caseID: caseID)
        try routeEvidence.validate(caseID: caseID)
        try telemetry.validate(caseID: caseID, outcome: outcome)
        try candidateResult?.validate()
        guard diagnostics.allSatisfy({ $0.isEmpty == false }) else {
            throw invalid("Constraint diagnostics must not contain empty messages.")
        }
        guard outcome == .realized else { return }
        let expectedEntityCount: Int
        switch try activated.catalogEntry.input {
        case .constraint(let input): expectedEntityCount = input.second == nil ? 1 : 2
        default: throw invalid("The activated case has no constraint input.")
        }
        guard let candidateResult,
              let roleBindings,
              candidateResult.status == .published,
              candidateResult.createdFeatureIDs.count == 1,
              candidateResult.primaryFeatureID == candidateResult.createdFeatureIDs.first,
              roleBindings.bindings.count == 1,
              let binding = roleBindings.bindings.first,
              binding.role == "relation",
              binding.stepIndex == candidateResult.stepIndex,
              binding.selector == .primary,
              routeEvidence.didPublish,
              telemetry.planningWallNanoseconds > 0,
              telemetry.routeWallNanoseconds > 0,
              telemetry.oracleWallNanoseconds > 0,
              telemetry.actionCount == 1,
              telemetry.commandCount == 1,
              telemetry.readCount >= 1,
              telemetry.entityCount == expectedEntityCount,
              telemetry.featureCount == 1,
              telemetry.bodyCount == 0 else {
            throw invalid("A realized constraint result lacks exact route, binding, or source evidence.")
        }
    }

    private func invalid(_ reason: String) -> CADBenchmarkError {
        .invalidInput(caseID: caseID.rawValue, reason: reason)
    }
}
