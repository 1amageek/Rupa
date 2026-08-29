import Foundation

/// The typed result of one authority-neutral sphere preparation attempt.
struct CADSphereCaseResult: Equatable, Sendable {
    private let recorder: CADSphereRecorder
    let caseID: CADBenchmarkCaseID
    let outcome: CADCaseOutcome
    let candidateDecision: CADCandidateDecision?
    let capabilityError: CADSphereCapabilityObservationError?
    let routeEvidence: CADSphereRouteEvidence
    let telemetry: CADSphereTelemetry
    let diagnostics: [String]

    init(
        recordedBy recorder: CADSphereRecorder,
        caseID: CADBenchmarkCaseID,
        outcome: CADCaseOutcome,
        candidateDecision: CADCandidateDecision? = nil,
        capabilityError: CADSphereCapabilityObservationError? = nil,
        routeEvidence: CADSphereRouteEvidence,
        telemetry: CADSphereTelemetry,
        diagnostics: [String] = []
    ) {
        self.recorder = recorder
        self.caseID = caseID
        self.outcome = outcome
        self.candidateDecision = candidateDecision
        self.capabilityError = capabilityError
        self.routeEvidence = routeEvidence
        self.telemetry = telemetry
        self.diagnostics = diagnostics
    }

    var realized: Bool {
        outcome == .realized
    }

    func replacing(
        routeEvidence: CADSphereRouteEvidence? = nil,
        telemetry: CADSphereTelemetry? = nil,
        diagnostics: [String]? = nil
    ) -> CADSphereCaseResult {
        CADSphereCaseResult(
            recordedBy: recorder,
            caseID: caseID,
            outcome: outcome,
            candidateDecision: candidateDecision,
            capabilityError: capabilityError,
            routeEvidence: routeEvidence ?? self.routeEvidence,
            telemetry: telemetry ?? self.telemetry,
            diagnostics: diagnostics ?? self.diagnostics
        )
    }

    func replacingTotalWallNanoseconds(_ value: UInt64) -> CADSphereCaseResult {
        replacing(
            telemetry: telemetry.replacing(totalWallNanoseconds: max(1, value))
        )
    }

    func validate() throws {
        guard CADSpherePreparationCase(rawValue: caseID.rawValue) != nil,
              diagnostics.allSatisfy({ !$0.isEmpty }) else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The sphere result has an invalid preparation case or diagnostic."
            )
        }
        try routeEvidence.validate(
            caseID: caseID,
            requireCapabilityObservation: outcome == .expectedUnsupported
        )
        try telemetry.validate(caseID: caseID)
        if outcome == .timeout {
            guard telemetry.totalWallNanoseconds >= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A timed-out sphere observation must reach its wall-time bound."
                )
            }
        } else {
            guard telemetry.totalWallNanoseconds <= telemetry.timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A non-timeout sphere observation cannot exceed its wall-time bound."
                )
            }
        }

        guard outcome == .expectedUnsupported else { return }
        guard case let .unsupported(declaration) = candidateDecision,
              declaration.reason == .analyticSphereUnavailable,
              capabilityError.map(isAnalyticSphereUnavailable) == true,
              routeEvidence.didPublish == false,
              routeEvidence.commandCount == 0,
              routeEvidence.sourceMutationCount == 0,
              telemetry.capabilityRequestCount == 1,
              telemetry.actionCount == 0,
              telemetry.commandCount == 0,
              telemetry.publicationCount == 0,
              telemetry.sourceMutationCount == 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Expected unsupported sphere results must retain the typed absence and zero-mutation evidence."
            )
        }
    }

    private func isAnalyticSphereUnavailable(
        _ error: CADSphereCapabilityObservationError
    ) -> Bool {
        if case .analyticSphereUnavailable = error { return true }
        return false
    }
}

struct CADSphereRecorder: Equatable, Sendable {
    init() {}
}
