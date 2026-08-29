import RupaCore
import RupaKit

/// Immutable lifecycle evidence for a sphere capability observation.
///
/// A sphere preparation has no mutation route. The coordinate and zero-count
/// invariants make an accidental command or source publication observable.
struct CADSphereRouteEvidence: Codable, Equatable, Sendable {
    let initialDocumentGeneration: DocumentGeneration
    let finalDocumentGeneration: DocumentGeneration
    let initialTransactionRevision: DocumentTransactionRevision
    let finalTransactionRevision: DocumentTransactionRevision
    let initialPublicationSequence: UInt64
    let finalPublicationSequence: UInt64
    let initialWorkspaceRevision: WorkspaceRevision
    let finalWorkspaceRevision: WorkspaceRevision
    let capabilityObservedThroughController: Bool
    let didPublish: Bool
    let commandCount: Int
    let sourceMutationCount: Int
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
        capabilityObservedThroughController: Bool = false,
        didPublish: Bool = false,
        commandCount: Int = 0,
        sourceMutationCount: Int = 0,
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
        self.capabilityObservedThroughController = capabilityObservedThroughController
        self.didPublish = didPublish
        self.commandCount = commandCount
        self.sourceMutationCount = sourceMutationCount
        self.cleanupCompleted = cleanupCompleted
        self.cleanupWallNanoseconds = cleanupWallNanoseconds
        self.remainingRegistrationCount = remainingRegistrationCount
    }

    init(
        initial: ProjectViewSnapshot,
        final: ProjectViewSnapshot,
        capabilityObservedThroughController: Bool,
        commandCount: Int = 0,
        sourceMutationCount: Int = 0
    ) {
        self.init(
            initialDocumentGeneration: initial.documentGeneration,
            finalDocumentGeneration: final.documentGeneration,
            initialTransactionRevision: initial.transactionRevision,
            finalTransactionRevision: final.transactionRevision,
            initialPublicationSequence: initial.publicationSequence,
            finalPublicationSequence: final.publicationSequence,
            initialWorkspaceRevision: initial.workspaceState.revision,
            finalWorkspaceRevision: final.workspaceState.revision,
            capabilityObservedThroughController: capabilityObservedThroughController,
            didPublish: final.publicationSequence > initial.publicationSequence,
            commandCount: commandCount,
            sourceMutationCount: sourceMutationCount
        )
    }

    static let empty = CADSphereRouteEvidence()

    func withCleanup(
        cleanupWallNanoseconds: UInt64,
        remainingRegistrationCount: Int
    ) -> CADSphereRouteEvidence {
        CADSphereRouteEvidence(
            initialDocumentGeneration: initialDocumentGeneration,
            finalDocumentGeneration: finalDocumentGeneration,
            initialTransactionRevision: initialTransactionRevision,
            finalTransactionRevision: finalTransactionRevision,
            initialPublicationSequence: initialPublicationSequence,
            finalPublicationSequence: finalPublicationSequence,
            initialWorkspaceRevision: initialWorkspaceRevision,
            finalWorkspaceRevision: finalWorkspaceRevision,
            capabilityObservedThroughController: capabilityObservedThroughController,
            didPublish: didPublish,
            commandCount: commandCount,
            sourceMutationCount: sourceMutationCount,
            cleanupCompleted: remainingRegistrationCount == 0,
            cleanupWallNanoseconds: cleanupWallNanoseconds,
            remainingRegistrationCount: remainingRegistrationCount
        )
    }

    func validate(
        caseID: CADBenchmarkCaseID,
        requireCapabilityObservation: Bool = false
    ) throws {
        guard finalDocumentGeneration == initialDocumentGeneration,
              finalTransactionRevision == initialTransactionRevision,
              finalPublicationSequence == initialPublicationSequence,
              finalWorkspaceRevision == initialWorkspaceRevision,
              requireCapabilityObservation == false || capabilityObservedThroughController,
              didPublish == false,
              commandCount == 0,
              sourceMutationCount == 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A sphere capability observation must preserve every project coordinate and perform zero mutation."
            )
        }
        guard cleanupCompleted,
              cleanupWallNanoseconds > 0,
              remainingRegistrationCount == 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Sphere observation cleanup must be measured and leave no registration."
            )
        }
    }
}
