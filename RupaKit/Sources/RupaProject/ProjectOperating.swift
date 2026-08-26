import Foundation
import RupaAutomation
import RupaCoreTypes
import RupaEvaluation
import RupaProjectPackage

/// The source-authority operations exposed by one isolated project owner.
public protocol ProjectOperating: Actor {
    func currentTransactionRevision() -> DocumentTransactionRevision

    func currentState() throws -> ProjectStateSnapshot

    func applyInteraction(
        _ transaction: ProjectInteractionTransaction
    ) async throws -> ProjectInteractionCommitResult

    func previewInteraction(
        _ transaction: ProjectInteractionTransaction
    ) async throws -> ProjectInteractionPreviewResult

    func evaluateCurrent() async throws -> EvaluatedProjectSnapshot

    func commit(
        _ transaction: ProjectSourceTransaction
    ) async throws -> ProjectSourceCommitResult

    func previewSource(
        _ transaction: ProjectSourceTransaction
    ) async throws -> ProjectSourcePreviewResult

    func executeReadOnlyAutomation(
        _ automation: PreparedAutomationBatch,
        expectedProjectID: ProjectID,
        expectedPublicationSequence: UInt64
    ) throws -> AutomationBatchExecution

    func undo(
        expectedTransactionRevision: DocumentTransactionRevision
    ) async throws -> ProjectStateSnapshot

    func redo(
        expectedTransactionRevision: DocumentTransactionRevision
    ) async throws -> ProjectStateSnapshot

    func load(
        from url: URL,
        expectedTransactionRevision: DocumentTransactionRevision
    ) async throws -> ProjectStateSnapshot

    func save(
        to url: URL,
        expectedTransactionRevision: DocumentTransactionRevision
    ) throws -> ProjectPackageSaveResult
}
