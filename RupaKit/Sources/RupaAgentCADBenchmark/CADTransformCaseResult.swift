/// Typed evidence from one authority-neutral transform preparation attempt.
struct CADTransformCaseResult: Equatable, Sendable {
    let caseID: CADBenchmarkCaseID
    let outcome: CADCaseOutcome
    let routeEvidence: CADTransformRouteEvidence
    let telemetry: CADTransformTelemetry
    let diagnostics: [String]

    var realized: Bool { outcome == .realized }

    func validate() throws {
        guard CADTransformPreparedCase(rawValue: caseID.rawValue) != nil,
              diagnostics.allSatisfy({ $0.isEmpty == false }),
              telemetry.totalWallNanoseconds > 0,
              telemetry.timeoutWallNanoseconds > 0,
              telemetry.actionCount >= 0,
              telemetry.commandCount >= 0,
              telemetry.readCount >= 0,
              telemetry.featureCount >= 0,
              telemetry.sceneNodeCount >= 0,
              telemetry.bodyCount >= 0,
              routeEvidence.cleanupCompleted,
              routeEvidence.cleanupWallNanoseconds > 0,
              routeEvidence.remainingRegistrationCount == 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Transform result evidence is incomplete."
            )
        }
        guard outcome == .realized else { return }
        guard routeEvidence.didPublish,
              routeEvidence.finalPublicationSequence == routeEvidence.initialPublicationSequence + 1,
              routeEvidence.finalDocumentGeneration.value
                == routeEvidence.initialDocumentGeneration.value + 1,
              routeEvidence.finalTransactionRevision.value
                == routeEvidence.initialTransactionRevision.value + 1,
              telemetry.actionCount == 1,
              telemetry.commandCount == 1,
              telemetry.readCount == expectedReadCount,
              telemetry.featureCount > 0,
              telemetry.sceneNodeCount > 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A realized transform must publish one exact production mutation."
            )
        }
    }

    private var expectedReadCount: Int {
        switch CADTransformPreparedCase(rawValue: caseID.rawValue) {
        case .transform004, .transform005:
            3
        case .transform001, .transform002, .transform003,
             .transform006, .transform007, .transform008:
            2
        case nil:
            0
        }
    }
}
