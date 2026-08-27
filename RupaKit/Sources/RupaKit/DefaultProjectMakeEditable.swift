import Foundation
import RupaCore
import RupaProject

/// Default exact-snapshot CAD Make Editable adapter over one project workspace.
@MainActor
public struct DefaultProjectMakeEditable: ProjectMakeEditable, Sendable {
    private let workspace: ProjectWorkspace

    public init(workspace: ProjectWorkspace) {
        self.workspace = workspace
    }

    public func makeEditable(
        _ request: ProjectMakeEditableRequest,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMakeEditableResult {
        do {
            try ProjectMakeEditableSupport.validateRequest(request)
            let state = try await ProjectMakeEditableSupport.currentState(
                for: request.snapshot,
                workspace: workspace,
                operationGuard: operationGuard
            )
            try ProjectMakeEditableSupport.validateFullSnapshot(
                request.snapshot,
                against: state
            )
            try ProjectMakeEditableSupport.validateTarget(
                request,
                in: state.document
            )
            try Task.checkCancellation()
            try operationGuard()

            let command = try await workspace.projectAuthorityOwner
                .prepareMakeCADRepresentationEditableCommand(
                    sceneNodeID: request.sceneNodeID,
                    authoredMeshSourceID: request.authoredMeshSourceID,
                    authoredMeshRepresentationID: request.authoredMeshRepresentationID,
                    switchesPresentationSelection: request.switchesPresentationSelection,
                    expectedTransactionRevision: request.snapshot.transactionRevision
                )
            guard case .makeCADRepresentationEditable(let makeEditableCommand) = command else {
                throw ProjectMakeEditableError(
                    code: .resultMismatch,
                    message: "The project authority returned a non-Make Editable command."
                )
            }
            try Task.checkCancellation()
            try operationGuard()
            let transaction = try ProjectMakeEditableSupport.transaction(
                request: request,
                command: command
            )
            let actionResult: ProjectWorkspaceActionResult
            do {
                actionResult = try await workspace.perform(
                    .source(transaction),
                    operationGuard: operationGuard
                )
            } catch let error as ProjectWorkspacePostCommitError {
                throw error
            }
            guard case .source(let commit, let view) = actionResult else {
                throw ProjectMakeEditableError(
                    code: .resultMismatch,
                    message: "The Make Editable action returned a non-source project result."
                )
            }

            do {
                guard commit.geometrySourceCommandResults.count == 1,
                      let result = commit.geometrySourceCommandResults.first else {
                    throw ProjectMakeEditableError(
                        code: .resultMismatch,
                        message: "The Make Editable transaction must return exactly one result."
                    )
                }
                try ProjectMakeEditableSupport.validateFullSnapshot(
                    view,
                    against: commit.state
                )
                let projected = try ProjectMakeEditableSupport.makeResult(
                    from: result,
                    commit: commit,
                    view: view,
                    request: request,
                    command: makeEditableCommand
                )
                _ = try await workspace.withValidatedAuthority(
                    from: view,
                    operationGuard: operationGuard
                ) {
                    true
                }
                try Task.checkCancellation()
                return projected
            } catch let error as ProjectWorkspacePostCommitError {
                throw error
            } catch {
                throw ProjectWorkspacePostCommitError(
                    stage: .domainResultProjection,
                    commit: .source(commit),
                    message: "The Make Editable mutation published, but its exact result could not be projected: \(error)."
                )
            }
        } catch let error as ProjectWorkspacePostCommitError {
            // Project authority has already published this mutation. The
            // caller receives the exact committed state and must not retry.
            throw error
        } catch let error as ProjectMakeEditableError {
            throw error
        } catch is CancellationError {
            throw ProjectMakeEditableError(
                code: .cancelled,
                message: "The Make Editable operation was cancelled."
            )
        } catch let error as ProjectMeshReadError {
            throw ProjectMakeEditableSupport.makeEditableError(from: error)
        } catch let error as ProjectControllerError {
            throw ProjectMakeEditableSupport.makeEditableError(from: error)
        } catch {
            throw ProjectMakeEditableError(
                code: .resultMismatch,
                message: "The Make Editable operation failed: \(error)."
            )
        }
    }
}
