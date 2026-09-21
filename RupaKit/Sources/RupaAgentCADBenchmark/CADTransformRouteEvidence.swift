import RupaCore

/// Coordinates and cleanup evidence for one prepared transform route.
struct CADTransformRouteEvidence: Equatable, Sendable {
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
}
