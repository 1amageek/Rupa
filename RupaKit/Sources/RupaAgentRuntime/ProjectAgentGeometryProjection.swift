import Foundation
import RupaAgentProtocol
import RupaCore
import RupaKit

/// Projects process-local project results into the wire-safe Agent contract.
enum ProjectAgentGeometryProjection {
    static func coordinates(
        sessionID: UUID,
        view: ProjectViewSnapshot,
        diagnostics: [EditorDiagnostic]? = nil
    ) -> AgentProjectViewCoordinates {
        AgentProjectViewCoordinates(
            sessionID: sessionID,
            projectID: view.projectID,
            documentGeneration: view.documentGeneration,
            transactionRevision: view.transactionRevision,
            publicationSequence: view.publicationSequence,
            workspaceRevision: view.workspaceState.revision,
            isDirty: view.isDirty,
            canUndo: view.canUndo,
            canRedo: view.canRedo,
            diagnostics: diagnostics ?? view.evaluationSnapshot.diagnostics
        )
    }

    static func catalog(
        _ catalog: ProjectMeshCatalog,
        sessionID: UUID,
        view: ProjectViewSnapshot
    ) -> AgentMeshCatalogResult {
        AgentMeshCatalogResult(
            coordinates: coordinates(sessionID: sessionID, view: view),
            catalog: catalog
        )
    }

    static func page(
        _ page: ProjectMeshElementPage,
        sessionID: UUID,
        view: ProjectViewSnapshot
    ) -> AgentMeshPageResult {
        AgentMeshPageResult(
            coordinates: coordinates(sessionID: sessionID, view: view),
            page: AgentMeshPage(
                handle: page.handle,
                domain: page.domain,
                records: page.records,
                nextCursor: page.nextCursor
            )
        )
    }

    static func neighborhood(
        _ neighborhood: ProjectMeshNeighborhood,
        sessionID: UUID,
        view: ProjectViewSnapshot
    ) -> AgentMeshNeighborhoodResult {
        AgentMeshNeighborhoodResult(
            coordinates: coordinates(sessionID: sessionID, view: view),
            neighborhood: AgentMeshNeighborhood(
                handle: neighborhood.handle,
                records: neighborhood.records.map {
                    AgentMeshNeighborhoodRecord(
                        distance: $0.distance,
                        element: $0.element
                    )
                }
            )
        )
    }

    static func preview(
        _ result: ProjectMeshEditPreviewResult,
        sessionID: UUID
    ) -> AgentMeshEditPreviewResult {
        AgentMeshEditPreviewResult(
            coordinates: coordinates(
                sessionID: sessionID,
                view: result.baseSnapshot,
                diagnostics: result.diagnostics
            ),
            sourceID: result.sourceID,
            previousContentIdentity: result.previousContentIdentity,
            proposedContentIdentity: result.proposedContentIdentity,
            receipt: result.receipt,
            didMutate: result.didMutate,
            proposedTransactionRevision: result.proposedTransactionRevision,
            proposedDocumentGeneration: result.proposedDocumentGeneration
        )
    }

    static func commit(
        _ result: ProjectMeshEditCommitResult,
        sessionID: UUID
    ) -> AgentMeshEditCommitResult {
        AgentMeshEditCommitResult(
            coordinates: coordinates(sessionID: sessionID, view: result.view),
            handle: result.handle,
            sourceID: result.sourceID,
            previousContentIdentity: result.previousContentIdentity,
            contentIdentity: result.contentIdentity,
            receipt: result.receipt,
            didMutate: result.didMutate
        )
    }

    static func makeEditable(
        _ result: ProjectMakeEditableResult,
        sessionID: UUID
    ) -> AgentMakeEditableResult {
        AgentMakeEditableResult(
            coordinates: coordinates(sessionID: sessionID, view: result.view),
            handle: result.handle,
            sceneNodeID: result.sceneNodeID,
            sourceRepresentationID: result.sourceRepresentationID,
            authoredMeshSourceID: result.authoredMeshSourceID,
            authoredMeshRepresentationID: result.authoredMeshRepresentationID,
            evaluationSnapshotID: result.evaluationSnapshotID,
            cadSourceIdentity: result.cadSourceIdentity,
            authoredMeshContentIdentity: result.authoredMeshContentIdentity,
            provenance: result.provenance,
            switchedPresentationSelection: result.switchedPresentationSelection,
            copyTelemetry: result.copyTelemetry
        )
    }
}
