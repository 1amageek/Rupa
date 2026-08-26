import Foundation
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectPackage

/// The source-authority operations exposed by one isolated project owner.
public protocol ProjectOperating: Actor {
    func currentTransactionRevision() -> DocumentTransactionRevision

    func currentState() throws -> ProjectStateSnapshot

    func withValidatedCoordinates<Result: Sendable>(
        expectedProjectID: ProjectID,
        expectedDocumentGeneration: DocumentGeneration,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        expectedWorkspaceRevision: WorkspaceRevision,
        operationGuard: @escaping ProjectOperationGuard,
        _ body: @Sendable () throws -> Result
    ) throws -> Result

    func applyInteraction(
        _ transaction: ProjectInteractionTransaction,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectInteractionCommitResult

    func previewInteraction(
        _ transaction: ProjectInteractionTransaction,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectInteractionPreviewResult

    func evaluateCurrent(
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot

    func evaluateCurrent(
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot

    func commit(
        _ transaction: ProjectSourceTransaction,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectSourceCommitResult

    func previewSource(
        _ transaction: ProjectSourceTransaction,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectSourcePreviewResult

    func executeReadOnlyAutomation(
        _ automation: PreparedAutomationBatch,
        expectedProjectID: ProjectID,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) throws -> AutomationBatchExecution

    func undo(
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot

    func redo(
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
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
