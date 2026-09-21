import RupaCore

/// Immutable publication and cleanup evidence for one compound attempt.
struct CADCompoundRouteEvidence: Codable, Equatable, Sendable {
    let initialDocumentGeneration: DocumentGeneration
    let finalDocumentGeneration: DocumentGeneration
    let initialTransactionRevision: DocumentTransactionRevision
    let finalTransactionRevision: DocumentTransactionRevision
    let initialPublicationSequence: UInt64
    let finalPublicationSequence: UInt64
    let initialWorkspaceRevision: WorkspaceRevision
    let finalWorkspaceRevision: WorkspaceRevision
    let didPublish: Bool
    let memberCount: Int
    let commandCount: Int
    let evaluationPassCount: UInt64
    let historyEntryCount: Int
    let cleanupCompleted: Bool
    let cleanupWallNanoseconds: UInt64
    let remainingRegistrationCount: Int

    init(
        from evidence: CADCaseLifecycleRecord.RouteEvidence,
        memberCount: Int = 0,
        commandCount: Int = 0,
        evaluationPassCount: UInt64 = 0,
        historyEntryCount: Int = 0
    ) {
        initialDocumentGeneration = evidence.initialDocumentGeneration
        finalDocumentGeneration = evidence.finalDocumentGeneration
        initialTransactionRevision = evidence.initialTransactionRevision
        finalTransactionRevision = evidence.finalTransactionRevision
        initialPublicationSequence = evidence.initialPublicationSequence
        finalPublicationSequence = evidence.finalPublicationSequence
        initialWorkspaceRevision = evidence.initialWorkspaceRevision
        finalWorkspaceRevision = evidence.finalWorkspaceRevision
        didPublish = evidence.didPublish
        self.memberCount = memberCount
        self.commandCount = commandCount
        self.evaluationPassCount = evaluationPassCount
        self.historyEntryCount = historyEntryCount
        cleanupCompleted = evidence.cleanupCompleted
        cleanupWallNanoseconds = evidence.cleanupWallNanoseconds
        remainingRegistrationCount = evidence.remainingRegistrationCount
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        guard memberCount >= 0,
              commandCount >= 0,
              evaluationPassCount >= 0,
              historyEntryCount >= 0,
              finalDocumentGeneration >= initialDocumentGeneration,
              finalTransactionRevision >= initialTransactionRevision,
              finalPublicationSequence >= initialPublicationSequence,
              finalWorkspaceRevision >= initialWorkspaceRevision else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Compound route coordinates and batch counts cannot move backwards."
            )
        }
        if didPublish {
            let generationIncrement = UInt64(memberCount == 0 ? 1 : memberCount)
            guard initialPublicationSequence < UInt64.max,
                  initialDocumentGeneration.value <= UInt64.max - generationIncrement,
                  initialTransactionRevision.value < UInt64.max,
                  finalPublicationSequence == initialPublicationSequence + 1,
                  finalDocumentGeneration.value
                      == initialDocumentGeneration.value + generationIncrement,
                  finalTransactionRevision.value == initialTransactionRevision.value + 1 else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A published compound must commit one ordered batch exactly once."
                )
            }
            let hasBatchMetrics = memberCount > 0
            if hasBatchMetrics {
                guard commandCount == memberCount,
                      evaluationPassCount == 1,
                      historyEntryCount == 1 else {
                    throw CADBenchmarkError.invalidInput(
                        caseID: caseID.rawValue,
                        reason: "Published compound batch metrics must match the member count."
                    )
                }
            } else {
                guard commandCount == 0,
                      evaluationPassCount == 0,
                      historyEntryCount == 0 else {
                    throw CADBenchmarkError.invalidInput(
                        caseID: caseID.rawValue,
                        reason: "Unavailable published compound metrics must remain explicitly empty."
                    )
                }
            }
        } else {
            guard commandCount == 0,
                  evaluationPassCount == 0,
                  historyEntryCount == 0,
                  finalDocumentGeneration == initialDocumentGeneration,
                  finalTransactionRevision == initialTransactionRevision,
                  finalPublicationSequence == initialPublicationSequence,
                  finalWorkspaceRevision == initialWorkspaceRevision else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A non-published compound route must preserve authority coordinates."
                )
            }
        }
        guard cleanupCompleted,
              cleanupWallNanoseconds > 0,
              remainingRegistrationCount == 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Compound cleanup must be measured and leave no registration."
            )
        }
    }
}
