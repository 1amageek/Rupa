import Foundation
import RupaAgentProtocol
import RupaCore
import RupaGeometry
import RupaKit
import RupaProjectModel

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

    static func viewportSnapshot(
        sessionID: UUID,
        view: ProjectViewSnapshot,
        limits: ProjectAgentViewportSnapshotLimits = .standard,
        operationGuard: @escaping @Sendable () throws -> Void = {
            try Task.checkCancellation()
        }
    ) throws -> AgentProjectViewportSnapshot {
        try operationGuard()
        try limits.validate()
        guard view.viewport.items.count <= limits.maxItems else {
            throw ProjectMeshReadError(
                code: .limitExceeded,
                message: "The project viewport snapshot exceeds the visible-item limit."
            )
        }
        var budget = ProjectAgentViewportSnapshotBudget(limits: limits)
        try budget.consumeAuxiliaryRecords(
            view.evaluationSnapshot.diagnostics.count
        )
        try budget.consumeAuxiliaryRecords(
            view.viewport.copyTelemetry.events.count
        )
        try budget.consumeString(view.projectID.rawValue)
        for diagnostic in view.evaluationSnapshot.diagnostics {
            try budget.consumeString(diagnostic.message)
        }
        for item in view.viewport.items {
            try operationGuard()
            guard let sceneNodeID = view.sceneNodeID(for: item.occurrenceID),
                  view.document.document.productMetadata.sceneNodes[sceneNodeID] != nil else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Viewport occurrence \(item.occurrenceID.rawValue) has no current scene-node navigation target."
                )
            }
            guard item.mesh.vertexIDs.count == item.mesh.vertexPositions.count,
                  item.mesh.edgeIDs.count == item.mesh.edgeEndpoints.count,
                  item.mesh.faceIDs.count == item.mesh.faceCornerRanges.count,
                  item.mesh.cornerIDs.count == item.mesh.cornerVertexIDs.count,
                  item.mesh.cornerIDs.count == item.mesh.cornerEdgeIDs.count else {
                throw EditorError(
                    code: .evaluationFailed,
                    message: "Viewport Mesh buffer counts are inconsistent."
                )
            }
            guard item.worldTransform.values.count == 16,
                  item.worldTransform.values.allSatisfy(\.isFinite) else {
                throw EditorError(
                    code: .evaluationFailed,
                    message: "Viewport occurrence \(item.occurrenceID.rawValue) has an invalid world transform."
                )
            }
            try budget.consumeElementRecords(
                try checkedElementRecordCount(
                    vertexCount: item.mesh.vertexIDs.count,
                    faceCount: item.mesh.faceIDs.count,
                    cornerCount: item.mesh.cornerIDs.count
                )
            )
            try budget.consumeString(item.occurrenceID.rawValue)
            try budget.consumeString(sceneNodeID.rawValue.uuidString)
            try budget.consumeString(item.definitionID.rawValue)
            try budget.consumeString(item.displayName)
            try budget.consumeString(item.representationID.rawValue)
            try consumeSourceReferenceStrings(item.sourceReference, budget: &budget)
        }
        try operationGuard()
        let orderedItems = view.viewport.items.sorted {
            $0.occurrenceID.rawValue < $1.occurrenceID.rawValue
        }
        var items: [AgentProjectViewportItem] = []
        items.reserveCapacity(orderedItems.count)
        for item in orderedItems {
            try operationGuard()
            guard let sceneNodeID = view.sceneNodeID(for: item.occurrenceID),
                  view.document.document.productMetadata.sceneNodes[sceneNodeID] != nil else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Viewport occurrence \(item.occurrenceID.rawValue) has no current scene-node navigation target."
                )
            }
            let triangleCount: UInt64
            do {
                triangleCount = try item.mesh.triangulatedTriangleCount(
                    tolerance: 1e-9,
                    limits: .standard,
                    checkCancellation: operationGuard
                )
            } catch let error as MeshTriangulationError {
                throw EditorError(code: .evaluationFailed, message: error.message)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as EditorError {
                throw error
            } catch {
                throw EditorError(
                    code: .evaluationFailed,
                    message: "Viewport occurrence \(item.occurrenceID.rawValue) could not be triangulated: \(error)"
                )
            }
            try budget.consumeTriangles(triangleCount)
            items.append(AgentProjectViewportItem(
                occurrenceID: item.occurrenceID,
                sceneNodeID: sceneNodeID,
                definitionID: item.definitionID,
                displayName: item.displayName,
                representationID: item.representationID,
                sourceReference: item.sourceReference,
                worldTransform: item.worldTransform,
                worldBounds: item.worldBounds,
                vertexCount: try checkedCount(
                    item.mesh.vertexIDs.count,
                    label: "vertex"
                ),
                faceCount: try checkedCount(
                    item.mesh.faceIDs.count,
                    label: "face"
                ),
                cornerCount: try checkedCount(
                    item.mesh.cornerIDs.count,
                    label: "corner"
                ),
                triangleCount: triangleCount
            ))
        }
        try operationGuard()
        return AgentProjectViewportSnapshot(
            coordinates: coordinates(sessionID: sessionID, view: view),
            evaluationSnapshotID: view.viewport.snapshotID,
            items: items,
            worldBounds: view.viewport.worldBounds,
            triangleCount: budget.triangleCount,
            copyTelemetry: view.viewport.copyTelemetry
        )
    }

    private static func checkedElementRecordCount(
        vertexCount: Int,
        faceCount: Int,
        cornerCount: Int
    ) throws -> Int {
        let vertexAndFaceCount = vertexCount.addingReportingOverflow(faceCount)
        guard !vertexAndFaceCount.overflow else {
            throw ProjectMeshReadError(
                code: .limitExceeded,
                message: "The project viewport source element count overflowed the supported range."
            )
        }
        let total = vertexAndFaceCount.partialValue.addingReportingOverflow(cornerCount)
        guard !total.overflow else {
            throw ProjectMeshReadError(
                code: .limitExceeded,
                message: "The project viewport source element count overflowed the supported range."
            )
        }
        return total.partialValue
    }

    private static func consumeSourceReferenceStrings(
        _ reference: GeometrySourceReference,
        budget: inout ProjectAgentViewportSnapshotBudget
    ) throws {
        switch reference {
        case .cad(let sourceID, let outputID):
            try budget.consumeString(sourceID)
            try budget.consumeString(outputID)
        case .authoredMesh(let sourceID):
            try budget.consumeString(sourceID.rawValue)
        case .external(let providerID, let sourceID, let outputID):
            try budget.consumeString(providerID)
            try budget.consumeString(sourceID)
            if let outputID {
                try budget.consumeString(outputID)
            }
        }
    }

    private static func checkedCount(_ count: Int, label: String) throws -> UInt64 {
        guard let result = UInt64(exactly: count) else {
            throw EditorError(
                code: .evaluationFailed,
                message: "Viewport \(label) count is outside the supported range."
            )
        }
        return result
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
