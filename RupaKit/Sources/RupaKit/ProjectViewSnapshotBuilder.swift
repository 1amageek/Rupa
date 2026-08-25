import RupaCoreTypes
import RupaProject
import RupaViewportScene

public struct ProjectViewSnapshotBuilder: Sendable {
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

        let viewport = try viewportBuilder.build(
            from: state.evaluation,
            project: state.evaluationSource
        )
        let sceneNodeIDByOccurrenceID = bridge.sceneNodeNavigationIndex(
            for: state.document
        )
        for item in viewport.items {
            guard let sourceOccurrence = state.evaluationSource.occurrences[item.id],
                  sourceOccurrence.definitionID == item.definitionID,
                  let definition = state.evaluationSource.objectDefinitions[item.definitionID],
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

        return ProjectViewSnapshot(
            projectID: state.evaluationSource.id,
            projectName: state.evaluationSource.name,
            documentGeneration: state.documentGeneration,
            transactionRevision: state.transactionRevision,
            publicationSequence: state.publicationSequence,
            isDirty: state.isDirty,
            canUndo: state.canUndo,
            canRedo: state.canRedo,
            selection: state.selection,
            workspaceState: state.workspaceState,
            viewport: viewport,
            cadInteraction: state.cadInteraction,
            sceneNodeIDByOccurrenceID: sceneNodeIDByOccurrenceID
        )
    }
}
