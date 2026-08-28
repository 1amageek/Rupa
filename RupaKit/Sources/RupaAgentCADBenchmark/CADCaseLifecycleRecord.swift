import Foundation
import RupaAgentProtocol
import RupaCore
import RupaKit

/// The category-neutral result produced after one production route and cleanup.
/// Category facades add their own candidate and oracle evidence to this record.
struct CADCaseLifecycleRecord: Sendable {
    enum Outcome: Equatable, Sendable {
        case invalidSubmission
        case executionFailure
        case timeout
        case cancellation
        case infrastructureFailure
        case published
        case cancelledAfterPublication
    }

    struct RouteEvidence: Equatable, Sendable {
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

        static let empty = RouteEvidence()

        init(from initial: ProjectViewSnapshot, to final: ProjectViewSnapshot) {
            self.init(
                initialDocumentGeneration: initial.documentGeneration,
                finalDocumentGeneration: final.documentGeneration,
                initialTransactionRevision: initial.transactionRevision,
                finalTransactionRevision: final.transactionRevision,
                initialPublicationSequence: initial.publicationSequence,
                finalPublicationSequence: final.publicationSequence,
                initialWorkspaceRevision: initial.workspaceState.revision,
                finalWorkspaceRevision: final.workspaceState.revision,
                didPublish: final.publicationSequence > initial.publicationSequence
            )
        }

        func withCleanup(
            cleanupWallNanoseconds: UInt64,
            remainingRegistrationCount: Int
        ) -> RouteEvidence {
            RouteEvidence(
                initialDocumentGeneration: initialDocumentGeneration,
                finalDocumentGeneration: finalDocumentGeneration,
                initialTransactionRevision: initialTransactionRevision,
                finalTransactionRevision: finalTransactionRevision,
                initialPublicationSequence: initialPublicationSequence,
                finalPublicationSequence: finalPublicationSequence,
                initialWorkspaceRevision: initialWorkspaceRevision,
                finalWorkspaceRevision: finalWorkspaceRevision,
                didPublish: didPublish,
                cleanupCompleted: remainingRegistrationCount == 0,
                cleanupWallNanoseconds: cleanupWallNanoseconds,
                remainingRegistrationCount: remainingRegistrationCount
            )
        }
    }

    struct Telemetry: Equatable, Sendable {
        let planningWallNanoseconds: UInt64
        let routeWallNanoseconds: UInt64
        let totalWallNanoseconds: UInt64
        let actionCount: Int
        let commandCount: Int
        let timeoutWallNanoseconds: UInt64
        let cancellationCheckpointCount: Int

        init(
            planningWallNanoseconds: UInt64,
            routeWallNanoseconds: UInt64,
            totalWallNanoseconds: UInt64,
            actionCount: Int,
            commandCount: Int,
            timeoutWallNanoseconds: UInt64,
            cancellationCheckpointCount: Int
        ) {
            self.planningWallNanoseconds = planningWallNanoseconds
            self.routeWallNanoseconds = routeWallNanoseconds
            self.totalWallNanoseconds = totalWallNanoseconds
            self.actionCount = actionCount
            self.commandCount = commandCount
            self.timeoutWallNanoseconds = timeoutWallNanoseconds
            self.cancellationCheckpointCount = cancellationCheckpointCount
        }
    }

    let caseID: CADBenchmarkCaseID
    let outcome: Outcome
    let initialView: ProjectViewSnapshot?
    let finalView: ProjectViewSnapshot?
    let response: AgentResponse?
    let routeEvidence: RouteEvidence
    let telemetry: Telemetry
    let deadline: CADCaseDeadline
    let diagnostics: [String]

    init(
        caseID: CADBenchmarkCaseID,
        outcome: Outcome,
        initialView: ProjectViewSnapshot? = nil,
        finalView: ProjectViewSnapshot? = nil,
        response: AgentResponse? = nil,
        routeEvidence: RouteEvidence = .empty,
        telemetry: Telemetry,
        deadline: CADCaseDeadline,
        diagnostics: [String] = []
    ) {
        self.caseID = caseID
        self.outcome = outcome
        self.initialView = initialView
        self.finalView = finalView
        self.response = response
        self.routeEvidence = routeEvidence
        self.telemetry = telemetry
        self.deadline = deadline
        self.diagnostics = diagnostics
    }

    func withCleanup(
        cleanupWallNanoseconds: UInt64,
        remainingRegistrationCount: Int,
        totalWallNanoseconds: UInt64
    ) -> CADCaseLifecycleRecord {
        CADCaseLifecycleRecord(
            caseID: caseID,
            outcome: outcome,
            initialView: initialView,
            finalView: finalView,
            response: response,
            routeEvidence: routeEvidence.withCleanup(
                cleanupWallNanoseconds: cleanupWallNanoseconds,
                remainingRegistrationCount: remainingRegistrationCount
            ),
            telemetry: Telemetry(
                planningWallNanoseconds: telemetry.planningWallNanoseconds,
                routeWallNanoseconds: telemetry.routeWallNanoseconds,
                totalWallNanoseconds: max(1, totalWallNanoseconds),
                actionCount: telemetry.actionCount,
                commandCount: telemetry.commandCount,
                timeoutWallNanoseconds: telemetry.timeoutWallNanoseconds,
                cancellationCheckpointCount: telemetry.cancellationCheckpointCount
            ),
            deadline: deadline,
            diagnostics: diagnostics
        )
    }
}
