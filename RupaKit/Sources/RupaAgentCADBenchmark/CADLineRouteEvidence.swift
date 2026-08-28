import RupaCore

/// Coordinates and cleanup evidence for one activated line production route.
struct CADLineRouteEvidence: Codable, Equatable, Sendable {
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

    init(
        initialDocumentGeneration: DocumentGeneration = DocumentGeneration(),
        finalDocumentGeneration: DocumentGeneration = DocumentGeneration(),
        initialTransactionRevision: DocumentTransactionRevision = DocumentTransactionRevision(),
        finalTransactionRevision: DocumentTransactionRevision = DocumentTransactionRevision(),
        initialPublicationSequence: UInt64 = 0,
        finalPublicationSequence: UInt64 = 0,
        initialWorkspaceRevision: WorkspaceRevision = WorkspaceRevision(),
        finalWorkspaceRevision: WorkspaceRevision = WorkspaceRevision(),
        didPublish: Bool = false,
        cleanupCompleted: Bool = false,
        cleanupWallNanoseconds: UInt64 = 0,
        remainingRegistrationCount: Int = 0
    ) {
        self.initialDocumentGeneration = initialDocumentGeneration
        self.finalDocumentGeneration = finalDocumentGeneration
        self.initialTransactionRevision = initialTransactionRevision
        self.finalTransactionRevision = finalTransactionRevision
        self.initialPublicationSequence = initialPublicationSequence
        self.finalPublicationSequence = finalPublicationSequence
        self.initialWorkspaceRevision = initialWorkspaceRevision
        self.finalWorkspaceRevision = finalWorkspaceRevision
        self.didPublish = didPublish
        self.cleanupCompleted = cleanupCompleted
        self.cleanupWallNanoseconds = cleanupWallNanoseconds
        self.remainingRegistrationCount = remainingRegistrationCount
    }

    static let empty = CADLineRouteEvidence()

    func validate(caseID: CADBenchmarkCaseID) throws {
        guard finalDocumentGeneration >= initialDocumentGeneration,
              finalTransactionRevision >= initialTransactionRevision,
              finalPublicationSequence >= initialPublicationSequence,
              finalWorkspaceRevision >= initialWorkspaceRevision else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Line route coordinates cannot move backwards."
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
                    reason: "A published line route must advance its no-retry coordinates exactly once."
                )
            }
        } else {
            guard finalDocumentGeneration == initialDocumentGeneration,
                  finalTransactionRevision == initialTransactionRevision,
                  finalPublicationSequence == initialPublicationSequence,
                  finalWorkspaceRevision == initialWorkspaceRevision else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A non-published line route must preserve its initial coordinates."
                )
            }
        }
        guard remainingRegistrationCount >= 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Line cleanup registration count must be non-negative."
            )
        }
        if cleanupCompleted {
            guard cleanupWallNanoseconds > 0,
                  remainingRegistrationCount == 0 else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "Completed line cleanup must be measured and leave no registration."
                )
            }
        }
    }
}
