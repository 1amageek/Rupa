import RupaCore

/// Coordinates and cleanup evidence for one cylinder production route.
struct CADCylinderRouteEvidence: Codable, Equatable, Sendable {
    let initialDocumentGeneration: DocumentGeneration
    let finalDocumentGeneration: DocumentGeneration
    let initialTransactionRevision: DocumentTransactionRevision
    let finalTransactionRevision: DocumentTransactionRevision
    let initialPublicationSequence: UInt64
    let finalPublicationSequence: UInt64
    let initialWorkspaceRevision: WorkspaceRevision
    let finalWorkspaceRevision: WorkspaceRevision
    let didPublish: Bool
    let cleanupCompleted: Bool
    let cleanupWallNanoseconds: UInt64
    let remainingRegistrationCount: Int

    init(from evidence: CADCaseLifecycleRecord.RouteEvidence) {
        initialDocumentGeneration = evidence.initialDocumentGeneration
        finalDocumentGeneration = evidence.finalDocumentGeneration
        initialTransactionRevision = evidence.initialTransactionRevision
        finalTransactionRevision = evidence.finalTransactionRevision
        initialPublicationSequence = evidence.initialPublicationSequence
        finalPublicationSequence = evidence.finalPublicationSequence
        initialWorkspaceRevision = evidence.initialWorkspaceRevision
        finalWorkspaceRevision = evidence.finalWorkspaceRevision
        didPublish = evidence.didPublish
        cleanupCompleted = evidence.cleanupCompleted
        cleanupWallNanoseconds = evidence.cleanupWallNanoseconds
        remainingRegistrationCount = evidence.remainingRegistrationCount
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        guard finalDocumentGeneration >= initialDocumentGeneration,
              finalTransactionRevision >= initialTransactionRevision,
              finalPublicationSequence >= initialPublicationSequence,
              finalWorkspaceRevision >= initialWorkspaceRevision else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Cylinder route coordinates cannot move backwards."
            )
        }
        if didPublish {
            guard initialPublicationSequence < UInt64.max,
                  initialDocumentGeneration.value < UInt64.max,
                  initialTransactionRevision.value < UInt64.max,
                  finalPublicationSequence == initialPublicationSequence + 1,
                  finalDocumentGeneration.value == initialDocumentGeneration.value + 1,
                  finalTransactionRevision.value == initialTransactionRevision.value + 1 else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A published cylinder route must advance once without retry."
                )
            }
        } else {
            guard finalDocumentGeneration == initialDocumentGeneration,
                  finalTransactionRevision == initialTransactionRevision,
                  finalPublicationSequence == initialPublicationSequence,
                  finalWorkspaceRevision == initialWorkspaceRevision else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A non-published cylinder route must preserve its coordinates."
                )
            }
        }
        guard cleanupCompleted,
              cleanupWallNanoseconds > 0,
              remainingRegistrationCount == 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Cylinder cleanup must be measured and leave no registration."
            )
        }
    }
}
