import Foundation
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProject

/// Default Mesh preview and commit adapter over an existing ProjectWorkspace.
@MainActor
public struct DefaultProjectMeshEditor: ProjectMeshEditing, Sendable {
    private let workspace: ProjectWorkspace

    public init(workspace: ProjectWorkspace) {
        self.workspace = workspace
    }

    public func preview(
        _ request: ProjectMeshEditRequest,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshEditPreviewResult {
        do {
            try ProjectMeshEditSupport.validate(request)
            _ = try await workspace.withValidatedAuthority(
                from: request.snapshot,
                operationGuard: operationGuard
            ) {
                true
            }
            let transaction = try ProjectMeshEditSupport.transaction(for: request)
            let result = try await workspace.preview(
                .source(transaction),
                operationGuard: operationGuard
            )
            guard case .source(let proposal) = result else {
                throw ProjectMeshEditError(
                    code: .resultMismatch,
                    message: "The Mesh preview returned a non-source project result."
                )
            }
            let editResult = try ProjectMeshEditSupport.authoredMeshResult(
                from: proposal.geometrySourceCommandResults
            )
            try ProjectMeshEditSupport.validate(
                proposal: proposal,
                request: request,
                result: editResult
            )
            _ = try await workspace.withValidatedAuthority(
                from: request.snapshot,
                operationGuard: operationGuard
            ) {
                true
            }
            return ProjectMeshEditPreviewResult(
                baseSnapshot: request.snapshot,
                sourceID: editResult.sourceID,
                previousContentIdentity: editResult.previousSourceIdentity,
                proposedContentIdentity: editResult.sourceIdentity,
                receipt: editResult.receipt,
                didMutate: editResult.didMutate,
                proposedTransactionRevision: proposal.proposedTransactionRevision,
                proposedDocumentGeneration: proposal.proposedDocumentGeneration,
                diagnostics: proposal.diagnostics
            )
        } catch let error as ProjectMeshEditError {
            throw error
        } catch is CancellationError {
            throw ProjectMeshEditError(
                code: .cancelled,
                message: "The Mesh preview was cancelled."
            )
        } catch let error as ProjectMeshReadError {
            throw ProjectMeshEditSupport.editError(from: error)
        } catch let error as ProjectControllerError {
            throw ProjectMeshEditSupport.editError(from: error)
        } catch {
            throw ProjectMeshEditError(
                code: .resultMismatch,
                message: "The Mesh preview failed: \(error)."
            )
        }
    }

    public func commit(
        _ request: ProjectMeshEditRequest,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshEditCommitResult {
        do {
            try ProjectMeshEditSupport.validate(request)
            _ = try await workspace.withValidatedAuthority(
                from: request.snapshot,
                operationGuard: operationGuard
            ) {
                true
            }
            let transaction = try ProjectMeshEditSupport.transaction(for: request)
            let result = try await workspace.perform(
                .source(transaction),
                operationGuard: operationGuard
            )
            guard case .source(let commit, let view) = result else {
                throw ProjectWorkspacePostCommitError(
                    stage: .domainResultProjection,
                    commit: result.commit,
                    message: "The Mesh commit published, but returned a non-source project result."
                )
            }
            do {
                let editResult = try ProjectMeshEditSupport.authoredMeshResult(
                    from: commit.geometrySourceCommandResults
                )
                guard editResult.sourceID == request.handle.sourceID,
                      editResult.previousSourceIdentity == request.handle.contentIdentity else {
                    throw ProjectMeshEditError(
                        code: .resultMismatch,
                        message: "The committed Mesh result does not match the requested source handle."
                    )
                }
                guard commit.state.documentLifetimeID == view.documentLifetimeID,
                      commit.state.document.projectID == view.projectID,
                      commit.state.documentGeneration == view.documentGeneration,
                      commit.state.transactionRevision == view.transactionRevision,
                      commit.state.publicationSequence == view.publicationSequence,
                      commit.state.workspaceState.revision == view.workspaceState.revision else {
                    throw ProjectMeshEditError(
                        code: .resultMismatch,
                        message: "The committed Mesh result and exact project view disagree."
                    )
                }
                guard let asset = view.document.document.authoredMeshAssets[editResult.sourceID],
                      asset.contentIdentity == editResult.sourceIdentity else {
                    throw ProjectMeshEditError(
                        code: .resultMismatch,
                        message: "The exact committed view does not contain the committed Mesh source identity."
                    )
                }
                let handle = ProjectMeshSourceHandle(
                    projectAuthorityCoordinate: ProjectAuthorityCoordinate(
                        projectID: view.projectID,
                        transactionRevision: view.transactionRevision,
                        publicationSequence: view.publicationSequence
                    ),
                    sourceID: editResult.sourceID,
                    contentIdentity: editResult.sourceIdentity
                )
                _ = try await workspace.withValidatedAuthority(
                    from: view,
                    operationGuard: operationGuard
                ) {
                    true
                }
                try Task.checkCancellation()
                return ProjectMeshEditCommitResult(
                    view: view,
                    handle: handle,
                    sourceID: editResult.sourceID,
                    previousContentIdentity: editResult.previousSourceIdentity,
                    contentIdentity: editResult.sourceIdentity,
                    receipt: editResult.receipt,
                    didMutate: editResult.didMutate
                )
            } catch let error as ProjectWorkspacePostCommitError {
                throw error
            } catch {
                throw ProjectWorkspacePostCommitError(
                    stage: .domainResultProjection,
                    commit: .source(commit),
                    message: "The Mesh commit published, but its domain result could not be projected: \(error)."
                )
            }
        } catch let error as ProjectWorkspacePostCommitError {
            // The project authority has already published this edit. Preserve the
            // no-retry error contract and never replay the source transaction.
            throw error
        } catch let error as ProjectMeshEditError {
            throw error
        } catch is CancellationError {
            throw ProjectMeshEditError(
                code: .cancelled,
                message: "The Mesh commit was cancelled."
            )
        } catch let error as ProjectMeshReadError {
            throw ProjectMeshEditSupport.editError(from: error)
        } catch let error as ProjectControllerError {
            throw ProjectMeshEditSupport.editError(from: error)
        } catch {
            throw ProjectMeshEditError(
                code: .resultMismatch,
                message: "The Mesh commit failed: \(error)."
            )
        }
    }
}

enum ProjectMeshEditSupport {
    static func validate(_ request: ProjectMeshEditRequest) throws {
        let snapshotCoordinate = ProjectAuthorityCoordinate(
            projectID: request.snapshot.projectID,
            transactionRevision: request.snapshot.transactionRevision,
            publicationSequence: request.snapshot.publicationSequence
        )
        guard request.handle.projectAuthorityCoordinate.projectID == snapshotCoordinate.projectID else {
            throw ProjectMeshEditError(
                code: .projectMismatch,
                message: "The Mesh edit handle and supplied project view belong to different projects."
            )
        }
        guard request.handle.projectAuthorityCoordinate.transactionRevision
                == snapshotCoordinate.transactionRevision else {
            throw ProjectMeshEditError(
                code: .transactionRevisionMismatch,
                message: "The Mesh edit handle and supplied project view coordinates disagree."
            )
        }
        guard request.handle.projectAuthorityCoordinate.publicationSequence
                == snapshotCoordinate.publicationSequence else {
            throw ProjectMeshEditError(
                code: .publicationSequenceMismatch,
                message: "The Mesh edit handle and supplied project view publication disagree."
            )
        }
        guard request.snapshot.document.document.authoredMeshAssets[request.handle.sourceID]
                != nil else {
            throw ProjectMeshEditError(
                code: .sourceMissing,
                message: "The Mesh edit source is not retained by the supplied project view."
            )
        }
        guard request.snapshot.document.document.authoredMeshAssets[request.handle.sourceID]?
                .contentIdentity == request.handle.contentIdentity else {
            throw ProjectMeshEditError(
                code: .sourceIdentityMismatch,
                message: "The Mesh edit source identity does not match the supplied project view."
            )
        }
    }

    static func transaction(
        for request: ProjectMeshEditRequest
    ) throws -> ProjectSourceTransaction {
        let command = AuthoredMeshEditCommand(
            target: AuthoredMeshEditTarget(
                sourceID: request.handle.sourceID,
                expectedSourceIdentity: request.handle.contentIdentity
            ),
            plan: request.plan
        )
        do {
            return try ProjectSourceTransaction(
                name: request.name,
                geometrySourceCommands: [.editAuthoredMesh(command)],
                expectedProjectID: request.snapshot.projectID,
                expectedTransactionRevision: request.snapshot.transactionRevision,
                expectedPublicationSequence: request.snapshot.publicationSequence
            )
        } catch let error as ProjectControllerError {
            throw ProjectMeshEditError(
                code: .invalidPlan,
                message: error.message
            )
        } catch {
            throw ProjectMeshEditError(
                code: .invalidPlan,
                message: "The Mesh edit transaction could not be created: \(error)."
            )
        }
    }

    static func authoredMeshResult(
        from results: [GeometrySourceCommandResult]
    ) throws -> GeometrySourceCommandResult.AuthoredMeshEdit {
        guard results.count == 1,
              case .authoredMeshEdit(let result) = results[0] else {
            throw ProjectMeshEditError(
                code: .resultMismatch,
                message: "A Mesh edit transaction must return exactly one Authored Mesh result."
            )
        }
        return result
    }

    static func validate(
        proposal: ProjectSourcePreviewResult,
        request: ProjectMeshEditRequest,
        result: GeometrySourceCommandResult.AuthoredMeshEdit
    ) throws {
        guard proposal.base.projectID == request.snapshot.projectID,
              proposal.base.transactionRevision == request.snapshot.transactionRevision,
              proposal.base.publicationSequence == request.snapshot.publicationSequence,
              proposal.base.documentGeneration == request.snapshot.documentGeneration,
              result.sourceID == request.handle.sourceID,
              result.previousSourceIdentity == request.handle.contentIdentity else {
            throw ProjectMeshEditError(
                code: .resultMismatch,
                message: "The Mesh preview result does not match the requested source coordinates."
            )
        }
    }

    static func editError(from error: ProjectMeshReadError) -> ProjectMeshEditError {
        ProjectMeshEditError(
            code: editCode(for: error.code),
            message: error.message
        )
    }

    static func editError(from error: ProjectControllerError) -> ProjectMeshEditError {
        ProjectMeshEditError(
            code: editCode(for: error.code),
            message: error.message
        )
    }

    private static func editCode(
        for code: ProjectMeshReadError.Code
    ) -> ProjectMeshEditError.Code {
        switch code {
        case .cancelled:
            .cancelled
        case .projectMismatch:
            .projectMismatch
        case .documentLifetimeMismatch:
            .documentLifetimeMismatch
        case .documentGenerationMismatch:
            .documentGenerationMismatch
        case .transactionRevisionMismatch:
            .transactionRevisionMismatch
        case .publicationSequenceMismatch:
            .publicationSequenceMismatch
        case .workspaceRevisionMismatch:
            .workspaceRevisionMismatch
        case .sourceMissing:
            .sourceMissing
        case .sourceIdentityMismatch:
            .sourceIdentityMismatch
        case .invalidCursor,
             .invalidLimit,
             .limitExceeded,
             .elementNotFound,
             .invalidSource,
             .resultMismatch:
            .resultMismatch
        }
    }

    private static func editCode(
        for code: ProjectControllerError.Code
    ) -> ProjectMeshEditError.Code {
        switch code {
        case .projectMismatch:
            .projectMismatch
        case .revisionConflict:
            .transactionRevisionMismatch
        case .publicationConflict:
            .publicationSequenceMismatch
        case .sourceInvalid,
             .sourceMismatch:
            .sourceIdentityMismatch
        case .transactionInvalid:
            .invalidPlan
        case .historyUnavailable,
             .productSourceFailed,
             .cadSourceFailed,
             .projectionFailed,
             .packageFailed,
             .evaluationFailed,
             .snapshotUnavailable:
            .resultMismatch
        }
    }
}
