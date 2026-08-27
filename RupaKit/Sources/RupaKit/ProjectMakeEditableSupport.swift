import Foundation
import RupaCore
import RupaCoreTypes
import RupaProject
import RupaProjectModel
import RupaViewportScene
import SwiftCAD

enum ProjectMakeEditableSupport {
    static func currentState(
        for snapshot: ProjectViewSnapshot,
        workspace: ProjectWorkspace,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot {
        do {
            return try await ProjectMeshReadSupport.state(
                for: snapshot,
                project: workspace.projectAuthorityOwner,
                operationGuard: operationGuard
            )
        } catch let error as ProjectMeshReadError {
            throw makeEditableError(from: error)
        }
    }

    static func validateRequest(_ request: ProjectMakeEditableRequest) throws {
        do {
            try request.authoredMeshSourceID.validate()
            try request.authoredMeshRepresentationID.validate()
        } catch let error as EditorError {
            throw ProjectMakeEditableError(
                code: .invalidRequest,
                message: error.message
            )
        }
        guard !request.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectMakeEditableError(
                code: .invalidRequest,
                message: "Make Editable request names must not be empty."
            )
        }
    }

    static func validateFullSnapshot(
        _ snapshot: ProjectViewSnapshot,
        against state: ProjectStateSnapshot
    ) throws {
        guard state.documentLifetimeID == snapshot.documentLifetimeID else {
            throw ProjectMakeEditableError(
                code: .documentLifetimeMismatch,
                message: "The project document lifetime no longer matches the supplied view."
            )
        }
        guard state.document.projectID == snapshot.projectID else {
            throw ProjectMakeEditableError(
                code: .projectMismatch,
                message: "The current project belongs to a different project ID."
            )
        }
        guard state.documentGeneration == snapshot.documentGeneration else {
            throw ProjectMakeEditableError(
                code: .documentGenerationMismatch,
                message: "The project document generation no longer matches the supplied view."
            )
        }
        guard state.transactionRevision == snapshot.transactionRevision else {
            throw ProjectMakeEditableError(
                code: .transactionRevisionMismatch,
                message: "The project transaction revision no longer matches the supplied view."
            )
        }
        guard state.publicationSequence == snapshot.publicationSequence else {
            throw ProjectMakeEditableError(
                code: .publicationSequenceMismatch,
                message: "The project publication sequence no longer matches the supplied view."
            )
        }
        guard state.workspaceState.revision == snapshot.workspaceState.revision else {
            throw ProjectMakeEditableError(
                code: .workspaceRevisionMismatch,
                message: "The project workspace revision no longer matches the supplied view."
            )
        }
        guard snapshot.projectName == state.evaluationSource.name,
              snapshot.isDirty == state.isDirty,
              snapshot.canUndo == state.canUndo,
              snapshot.canRedo == state.canRedo,
              snapshot.selection == state.selection,
              snapshot.evaluationSnapshot == state.evaluationSnapshot,
              snapshot.objectRegistry.orderedDefinitions == state.objectRegistry.orderedDefinitions else {
            throw ProjectMakeEditableError(
                code: .resultMismatch,
                message: "The supplied project view does not contain the current full authority snapshot."
            )
        }
        guard snapshot.document.document.modelingSettings == state.document.modelingSettings,
              snapshot.document.document.productMetadata == state.document.productMetadata,
              snapshot.document.document.authoredMeshAssets == state.document.authoredMeshAssets,
              try cadDocumentsMatch(
                snapshot.document.document.cadDocument,
                state.document.cadDocument,
                tolerance: state.document.modelingSettings.tolerance
              ) else {
            throw ProjectMakeEditableError(
                code: .resultMismatch,
                message: "The supplied project view contains forged or stale source authority."
            )
        }

        let expectedViewport: UniversalViewportScene
        do {
            expectedViewport = try UniversalViewportSceneBuilder().build(
                from: state.evaluation,
                project: state.evaluationSource
            )
        } catch {
            throw ProjectMakeEditableError(
                code: .resultMismatch,
                message: "The current presentation viewport could not be reconstructed: \(error)."
            )
        }
        guard snapshot.viewport == expectedViewport,
              snapshot.sceneNodeIDByOccurrenceID
                == DesignDocumentProjectBridge().sceneNodeNavigationIndex(for: state.document) else {
            throw ProjectMakeEditableError(
                code: .resultMismatch,
                message: "The supplied project view contains a forged presentation projection."
            )
        }
        if let cadInteraction = snapshot.cadInteraction {
            guard cadInteraction.matches(
                document: state.document,
                generation: state.documentGeneration
            ) else {
                throw ProjectMakeEditableError(
                    code: .resultMismatch,
                    message: "The supplied CAD interaction context is not bound to the current source."
                )
            }
        } else if state.cadInteraction != nil {
            throw ProjectMakeEditableError(
                code: .resultMismatch,
                message: "The supplied project view omitted the current CAD interaction context."
            )
        }
    }

    static func validateTarget(
        _ request: ProjectMakeEditableRequest,
        in document: DesignDocument
    ) throws {
        guard let sceneNode = document.productMetadata.sceneNodes[request.sceneNodeID],
              let object = sceneNode.object,
              object.category == .body else {
            throw ProjectMakeEditableError(
                code: .representationMissing,
                message: "Make Editable requires an existing CAD body scene node."
            )
        }
        guard let selection = object.geometryRepresentations.selection,
              let modeling = object.geometryRepresentations.representations[selection.modeling] else {
            throw ProjectMakeEditableError(
                code: .representationMissing,
                message: "Make Editable requires a selected modeling representation."
            )
        }
        guard case .cad = modeling.source else {
            throw ProjectMakeEditableError(
                code: .nonCADModelingSource,
                message: "Make Editable requires the target modeling representation to be CAD."
            )
        }
        guard document.authoredMeshAssets[request.authoredMeshSourceID] == nil else {
            throw ProjectMakeEditableError(
                code: .duplicateIdentity,
                message: "The requested Authored Mesh source identity is already retained."
            )
        }
        guard object.geometryRepresentations.representations[
            request.authoredMeshRepresentationID
        ] == nil else {
            throw ProjectMakeEditableError(
                code: .duplicateIdentity,
                message: "The target object already retains the requested Authored Mesh representation identity."
            )
        }
    }

    static func transaction(
        request: ProjectMakeEditableRequest,
        command: GeometrySourceCommand
    ) throws -> ProjectSourceTransaction {
        do {
            return try ProjectSourceTransaction(
                name: request.name,
                geometrySourceCommands: [command],
                expectedProjectID: request.snapshot.projectID,
                expectedTransactionRevision: request.snapshot.transactionRevision,
                expectedPublicationSequence: request.snapshot.publicationSequence
            )
        } catch let error as ProjectControllerError {
            throw ProjectMakeEditableError(
                code: .invalidRequest,
                message: error.message
            )
        } catch {
            throw ProjectMakeEditableError(
                code: .invalidRequest,
                message: "The Make Editable transaction could not be created: \(error)."
            )
        }
    }

    static func makeResult(
        from result: GeometrySourceCommandResult,
        commit: ProjectSourceCommitResult,
        view: ProjectViewSnapshot,
        request: ProjectMakeEditableRequest,
        command: MakeCADRepresentationEditableCommand
    ) throws -> ProjectMakeEditableResult {
        guard case .makeEditable(let makeResult) = result else {
            throw ProjectMakeEditableError(
                code: .resultMismatch,
                message: "The Make Editable transaction returned a different geometry result."
            )
        }
        guard commit.geometrySourceCommandResults.count == 1,
              makeResult.sceneNodeID == request.sceneNodeID,
              makeResult.sourceRepresentationID == command.sourceRepresentationID,
              makeResult.authoredMeshSourceID == request.authoredMeshSourceID,
              makeResult.authoredMeshRepresentationID == request.authoredMeshRepresentationID,
              makeResult.evaluationSnapshotID == command.evaluationSnapshotID,
              makeResult.cadSourceIdentity == command.sourceIdentity,
              makeResult.copyTelemetry == command.evaluationCopyTelemetry,
              makeResult.switchedPresentationSelection == request.switchesPresentationSelection else {
            throw ProjectMakeEditableError(
                code: .resultMismatch,
                message: "The Make Editable result does not match the identity-only request."
            )
        }
        guard commit.state.documentLifetimeID == view.documentLifetimeID,
              commit.state.document.projectID == view.projectID,
              commit.state.documentGeneration == view.documentGeneration,
              commit.state.transactionRevision == view.transactionRevision,
              commit.state.publicationSequence == view.publicationSequence,
              commit.state.workspaceState.revision == view.workspaceState.revision else {
            throw ProjectMakeEditableError(
                code: .resultMismatch,
                message: "The committed authority and exact project view disagree."
            )
        }
        guard let originalSceneNode = request.snapshot.document.document.productMetadata.sceneNodes[
                request.sceneNodeID
            ],
              let originalObject = originalSceneNode.object,
              let originalSelection = originalObject.geometryRepresentations.selection,
              let sceneNode = view.document.document.productMetadata.sceneNodes[request.sceneNodeID],
              let object = sceneNode.object,
              let selection = object.geometryRepresentations.selection,
              let modelingRepresentation = object.geometryRepresentations
                .representations[selection.modeling],
              let authoredRepresentation = object.geometryRepresentations
                .representations[request.authoredMeshRepresentationID],
              modelingRepresentation.id == command.sourceRepresentationID,
              modelingRepresentation.source == command.sourceReference,
              authoredRepresentation.source == .authoredMesh(request.authoredMeshSourceID),
              selection.modeling == command.sourceRepresentationID,
              (request.switchesPresentationSelection
                ? selection.presentation == request.authoredMeshRepresentationID
                : selection.presentation == originalSelection.presentation) else {
            throw ProjectMakeEditableError(
                code: .resultMismatch,
                message: "The committed Product Object did not retain the CAD/Mesh authority pairing."
            )
        }
        guard let asset = view.document.document.authoredMeshAssets[
            request.authoredMeshSourceID
        ],
              asset.id == request.authoredMeshSourceID,
              asset.source.identity == request.authoredMeshSourceID,
              asset.contentIdentity == makeResult.authoredMeshContentIdentity,
              asset.provenance == .derivedFromCAD(
                representationID: command.sourceRepresentationID,
                sourceIdentity: command.sourceIdentity
            ) else {
            throw ProjectMakeEditableError(
                code: .resultMismatch,
                message: "The committed Authored Mesh asset has invalid identity or provenance."
            )
        }
        let expectedCoordinate = ProjectAuthorityCoordinate(
            projectID: view.projectID,
            transactionRevision: view.transactionRevision,
            publicationSequence: view.publicationSequence
        )
        let expectedRevision: DocumentTransactionRevision
        do {
            expectedRevision = try request.snapshot.transactionRevision.advanced()
        } catch {
            throw ProjectMakeEditableError(
                code: .resultMismatch,
                message: "Make Editable could not compute the next transaction revision: \(error)."
            )
        }
        guard view.transactionRevision == expectedRevision else {
            throw ProjectMakeEditableError(
                code: .resultMismatch,
                message: "Make Editable did not advance the project transaction revision."
            )
        }
        let handle = ProjectMeshSourceHandle(
            projectAuthorityCoordinate: expectedCoordinate,
            sourceID: request.authoredMeshSourceID,
            contentIdentity: asset.contentIdentity
        )
        return ProjectMakeEditableResult(
            view: view,
            handle: handle,
            sceneNodeID: request.sceneNodeID,
            sourceRepresentationID: command.sourceRepresentationID,
            authoredMeshSourceID: request.authoredMeshSourceID,
            authoredMeshRepresentationID: request.authoredMeshRepresentationID,
            evaluationSnapshotID: makeResult.evaluationSnapshotID,
            cadSourceIdentity: makeResult.cadSourceIdentity,
            authoredMeshContentIdentity: makeResult.authoredMeshContentIdentity,
            provenance: asset.provenance,
            switchedPresentationSelection: makeResult.switchedPresentationSelection,
            copyTelemetry: makeResult.copyTelemetry
        )
    }

    static func makeEditableError(
        from error: ProjectMeshReadError
    ) -> ProjectMakeEditableError {
        ProjectMakeEditableError(
            code: makeEditableCode(for: error.code),
            message: error.message
        )
    }

    static func makeEditableError(
        from error: ProjectControllerError
    ) -> ProjectMakeEditableError {
        ProjectMakeEditableError(
            code: makeEditableCode(for: error.code),
            message: error.message
        )
    }

    private static func cadDocumentsMatch(
        _ lhs: SwiftCAD.CADDocument,
        _ rhs: SwiftCAD.CADDocument,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard lhs.id == rhs.id,
              lhs.metadata.name == rhs.metadata.name,
              lhs.metadata.createdAt == rhs.metadata.createdAt,
              lhs.metadata.updatedAt == rhs.metadata.updatedAt,
              lhs.designGraph.revision == rhs.designGraph.revision,
              lhs.parameters.revision == rhs.parameters.revision,
              lhs.selectionDimensions.map(\.id) == rhs.selectionDimensions.map(\.id) else {
            return false
        }
        return try lhs.sourceFingerprint(tolerance: tolerance)
            == rhs.sourceFingerprint(tolerance: tolerance)
    }

    private static func makeEditableCode(
        for code: ProjectMeshReadError.Code
    ) -> ProjectMakeEditableError.Code {
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

    private static func makeEditableCode(
        for code: ProjectControllerError.Code
    ) -> ProjectMakeEditableError.Code {
        switch code {
        case .projectMismatch:
            .projectMismatch
        case .revisionConflict:
            .transactionRevisionMismatch
        case .publicationConflict:
            .publicationSequenceMismatch
        case .sourceInvalid:
            .invalidSource
        case .sourceMismatch:
            .sourceIdentityMismatch
        case .transactionInvalid:
            .invalidRequest
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
