import Foundation
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectPackage

/// The source-authority operations exposed by one isolated project owner.
public protocol ProjectOperating: Actor {
    func currentTransactionRevision() -> DocumentTransactionRevision

    func currentAuthorityCoordinate() -> ProjectAuthorityCoordinate

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

    /// Prepares a CAD-to-Authored-Mesh source command from the current
    /// modeling-purpose evaluation. The operation accepts identity intent only;
    /// evaluated Mesh payloads are owned and produced by the project authority.
    func prepareMakeCADRepresentationEditableCommand(
        sceneNodeID: SceneNodeID,
        authoredMeshSourceID: GeometrySourceID,
        authoredMeshRepresentationID: GeometryRepresentationID,
        switchesPresentationSelection: Bool,
        expectedTransactionRevision: DocumentTransactionRevision
    ) async throws -> GeometrySourceCommand

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

    func replace(
        with document: DesignDocument,
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot

    func load(
        from url: URL,
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot

    func save(
        to url: URL,
        expectedTransactionRevision: DocumentTransactionRevision
    ) throws -> ProjectPackageSaveResult

    func save(
        to url: URL,
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) throws -> ProjectSaveCommitResult
}
