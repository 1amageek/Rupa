struct CADCompoundRecorder: Equatable, Sendable {
    init() {}
}

/// The binary, typed result of one prepared compound attempt.
struct CADCompoundCaseResult: Equatable, Sendable {
    private let recorder: CADCompoundRecorder
    let caseID: CADBenchmarkCaseID
    let outcome: CADCaseOutcome
    let candidateResults: [CADCandidateStepResult]?
    let roleBindings: CADOutputRoleBindings?
    let routeEvidence: CADCompoundRouteEvidence
    let telemetry: CADCompoundTelemetry
    let diagnostics: [String]

    init(
        recordedBy recorder: CADCompoundRecorder,
        caseID: CADBenchmarkCaseID,
        outcome: CADCaseOutcome,
        candidateResults: [CADCandidateStepResult]? = nil,
        roleBindings: CADOutputRoleBindings? = nil,
        routeEvidence: CADCompoundRouteEvidence,
        telemetry: CADCompoundTelemetry,
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

    func replacingTotalWallNanoseconds(_ value: UInt64) -> CADCompoundCaseResult {
        CADCompoundCaseResult(
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
        guard CADCompoundActivatedCase(rawValue: caseID.rawValue) != nil,
              diagnostics.allSatisfy({ !$0.isEmpty }) else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The compound result has an invalid case or diagnostic."
            )
        }
        if let candidateResults {
            for candidateResult in candidateResults {
                try candidateResult.validate()
            }
        }
        try routeEvidence.validate(caseID: caseID)
        try telemetry.validate(caseID: caseID)
        if outcome == .timeout {
            guard telemetry.totalWallNanoseconds >= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A timed-out compound must reach its wall-time bound."
                )
            }
        } else {
            guard telemetry.totalWallNanoseconds <= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A non-timeout compound cannot exceed its wall-time bound."
                )
            }
        }
        guard outcome == .realized else { return }
        let entry = try CADCompoundActivatedCase(caseID: caseID).catalogEntry
        guard case .compound(let expected) = entry.expected else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A compound result has no compound expectation."
            )
        }
        guard let candidateResults,
              let roleBindings,
              candidateResults.count == expected.members.count,
              roleBindings.bindings.count == expected.members.count,
              candidateResults.enumerated().allSatisfy({ index, result in
                  result.stepIndex == index
                      && result.status == .published
                      && result.createdFeatureIDs.count == 2
                      && result.primaryFeatureID == result.createdFeatureIDs.last
              }),
              roleBindings.bindings.enumerated().allSatisfy({ index, binding in
                  binding.role == expected.members[index].role
                      && binding.stepIndex == index
                      && binding.selector == .primary
              }),
              Set(candidateResults.flatMap(\.createdFeatureIDs)).count
                  == candidateResults.flatMap(\.createdFeatureIDs).count,
              routeEvidence.didPublish,
              routeEvidence.memberCount == expected.members.count,
              routeEvidence.commandCount == expected.members.count,
              routeEvidence.evaluationPassCount == 1,
              routeEvidence.historyEntryCount == 1,
              telemetry.planningWallNanoseconds > 0,
              telemetry.routeWallNanoseconds > 0,
              telemetry.oracleWallNanoseconds > 0,
              telemetry.totalWallNanoseconds > 0,
              telemetry.actionCount == 1,
              telemetry.commandCount == expected.members.count,
              telemetry.readCount >= 2,
              telemetry.entityCount == expected.members.reduce(into: 0, {
                  $0 += $1.primitive == .box ? 4 : 1
              }),
              telemetry.featureCount == expected.members.count * 2,
              telemetry.bodyCount == expected.members.count,
              telemetry.faceCount == expected.members.count * 6,
              telemetry.edgeCount == expected.members.count * 12,
              telemetry.vertexCount == expected.members.count * 8 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A realized compound must retain exact ordered member and B-rep evidence."
            )
        }
    }
}
