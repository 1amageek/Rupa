import RupaCoreTypes
import RupaEvaluation
import RupaProject
import RupaProjectModel
import RupaViewportScene

public struct ProjectViewSnapshotBuilder:
    ProjectViewSnapshotBuilding,
    ProjectPreviewRenderPayloadBuilding,
    Sendable
{
    private let bridge: DesignDocumentProjectBridge
    private let viewportBuilder: UniversalViewportSceneBuilder

    public init(
        bridge: DesignDocumentProjectBridge = DesignDocumentProjectBridge(),
        viewportBuilder: UniversalViewportSceneBuilder = UniversalViewportSceneBuilder()
    ) {
        self.bridge = bridge
        self.viewportBuilder = viewportBuilder
    }

    public func build(from state: ProjectStateSnapshot) throws -> ProjectViewSnapshot {
        guard state.evaluationSource.id == state.document.projectID,
              state.evaluation.projectID == state.evaluationSource.id,
              state.evaluation.id.projectID == state.evaluationSource.id else {
            throw ProjectViewSnapshotError(
                code: .sourceMismatch,
                message: "The presentation evaluation belongs to a different project source."
            )
        }
        guard state.evaluation.id.sourceRevision == state.transactionRevision else {
            throw ProjectViewSnapshotError(
                code: .revisionMismatch,
                message: "The presentation evaluation does not match the project transaction revision."
            )
        }
        guard state.evaluation.id.purpose == .presentation else {
            throw ProjectViewSnapshotError(
                code: .purposeMismatch,
                message: "The project view requires a presentation-purpose evaluation."
            )
        }
        if let cadInteraction = state.cadInteraction,
           !cadInteraction.matches(
               document: state.document,
               generation: state.documentGeneration
           ) {
            throw ProjectViewSnapshotError(
                code: .staleCADInteraction,
                message: "The CAD interaction context does not match the project document generation."
            )
        }

        let previewProjection = try buildPreviewProjection(
            document: state.document,
            evaluationSource: state.evaluationSource,
            evaluation: state.evaluation
        )
        let document = try ProjectReadDocument(
            document: state.document,
            objectRegistry: state.objectRegistry
        )

        return ProjectViewSnapshot(
            documentLifetimeID: state.documentLifetimeID,
            projectID: state.evaluationSource.id,
            projectName: state.evaluationSource.name,
            document: document,
            documentGeneration: state.documentGeneration,
            transactionRevision: state.transactionRevision,
            publicationSequence: state.publicationSequence,
            isDirty: state.isDirty,
            canUndo: state.canUndo,
            canRedo: state.canRedo,
            selection: state.selection,
            workspaceState: state.workspaceState,
            objectRegistry: state.objectRegistry,
            evaluationSnapshot: state.evaluationSnapshot,
            viewport: previewProjection.scene,
            cadInteraction: state.cadInteraction,
            sceneNodeIDByOccurrenceID: previewProjection.sceneNodeIDByOccurrenceID,
            retiredObjectProperties: state.retiredObjectProperties
        )
    }

    public func build(
        from payload: ProjectSourcePreviewRenderPayload
    ) throws -> ProjectPreviewRenderPayload {
        let projection = try buildPreviewProjection(
            document: payload.document,
            evaluationSource: payload.evaluationSource,
            evaluation: payload.evaluation
        )
        return ProjectPreviewRenderPayload(
            document: payload.document,
            presentationScene: projection.scene,
            presentationSceneNodeIDByOccurrenceID: projection.sceneNodeIDByOccurrenceID
        )
    }

    private func buildPreviewProjection(
        document: DesignDocument,
        evaluationSource: ProjectSourceModel,
        evaluation: EvaluatedProjectSnapshot
    ) throws -> (
        scene: UniversalViewportScene,
        sceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]
    ) {
        guard evaluationSource.id == document.projectID,
              evaluation.projectID == evaluationSource.id,
              evaluation.id.projectID == evaluationSource.id else {
            throw ProjectViewSnapshotError(
                code: .sourceMismatch,
                message: "The presentation evaluation belongs to a different project source."
            )
        }
        guard evaluation.id.purpose == .presentation else {
            throw ProjectViewSnapshotError(
                code: .purposeMismatch,
                message: "A project preview requires a presentation-purpose evaluation."
            )
        }

        let evaluatedViewport: UniversalViewportScene
        do {
            evaluatedViewport = try viewportBuilder.build(
                from: evaluation,
                project: evaluationSource
            )
        } catch let error as UniversalViewportSceneError {
            throw projectViewError(for: error)
        }
        let sceneNodeIDByOccurrenceID = bridge.sceneNodeNavigationIndex(for: document)
        for item in evaluatedViewport.items {
            guard let sourceOccurrence = evaluationSource.occurrences[item.id],
                  sourceOccurrence.definitionID == item.definitionID,
                  let definition = evaluationSource.objectDefinitions[item.definitionID],
                  let presentation = definition.representations.representation(for: .presentation),
                  presentation.id == item.representationID,
                  presentation.source == item.reference else {
                throw ProjectViewSnapshotError(
                    code: .sourceMismatch,
                    message: "A viewport occurrence does not match its selected presentation authority."
                )
            }
            guard sceneNodeIDByOccurrenceID[item.id] != nil else {
                throw ProjectViewSnapshotError(
                    code: .missingNavigation,
                    message: "A viewport occurrence has no explicit scene-node navigation target."
                )
            }
        }
        let effectivelyVisibleSceneNodeIDs = document.productMetadata
            .effectivelyVisibleSceneNodeIDs()
        let scene = UniversalViewportScene(
            snapshotID: evaluatedViewport.snapshotID,
            projectID: evaluatedViewport.projectID,
            items: evaluatedViewport.items.filter { item in
                guard let sceneNodeID = sceneNodeIDByOccurrenceID[item.id] else {
                    return false
                }
                return effectivelyVisibleSceneNodeIDs.contains(sceneNodeID)
            },
            copyTelemetry: evaluatedViewport.copyTelemetry
        )
        return (scene, sceneNodeIDByOccurrenceID)
    }

    private func projectViewError(
        for error: UniversalViewportSceneError
    ) -> ProjectViewSnapshotError {
        switch error.code {
        case .purposeMismatch:
            return ProjectViewSnapshotError(
                code: .purposeMismatch,
                message: error.message
            )
        case .missingDefinition,
             .projectMismatch,
             .occurrenceMismatch,
             .sourceMismatch,
             .invalidIdentifier,
             .sourceIdentityMismatch:
            return ProjectViewSnapshotError(
                code: .sourceMismatch,
                message: error.message
            )
        }
    }
}
