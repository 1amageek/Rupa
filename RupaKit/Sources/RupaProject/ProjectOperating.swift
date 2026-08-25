import Foundation
import RupaCoreTypes
import RupaEvaluation
import RupaProjectPackage

/// The source-authority operations exposed by one isolated project owner.
public protocol ProjectOperating: Actor {
    func currentState() throws -> ProjectStateSnapshot

    func evaluateCurrent() async throws -> EvaluatedProjectSnapshot

    func commit(
        _ transaction: ProjectSourceTransaction
    ) async throws -> ProjectSourceCommitResult

    func load(
        from url: URL,
        expectedTransactionRevision: DocumentTransactionRevision
    ) async throws -> ProjectStateSnapshot

    func save(
        to url: URL,
        expectedTransactionRevision: DocumentTransactionRevision
    ) throws -> ProjectPackageSaveResult
}
