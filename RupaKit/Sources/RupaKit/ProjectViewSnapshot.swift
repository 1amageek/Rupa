import RupaCore
import RupaCoreTypes
import RupaProject
import RupaViewportScene

/// The immutable, read-only state consumed by project UI.
///
/// Source bytes and mutation authority remain owned by `ProjectOperating`.
public struct ProjectViewSnapshot: Sendable {
    public let documentLifetimeID: ProjectDocumentLifetimeID
    public let projectID: ProjectID
    public let projectName: String
    public let document: ProjectReadDocument
    public let documentGeneration: DocumentGeneration
    public let transactionRevision: DocumentTransactionRevision
    public let publicationSequence: UInt64
    public let isDirty: Bool
    public let canUndo: Bool
    public let canRedo: Bool
    public let selection: SelectionModel
    public let workspaceState: WorkspaceState
    public let objectRegistry: ObjectTypeRegistry
    public let evaluationSnapshot: EvaluationSnapshot
    public let viewport: UniversalViewportScene
    public let cadInteraction: DocumentEvaluationContext?
    public let sceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]
    /// The stored object property values opening this document retired.
    ///
    /// Carried unchanged from `ProjectStateSnapshot` so the only state the UI
    /// observes can report them. See `RupaKit/DESIGN.md`.
    public let retiredObjectProperties: [RetiredObjectProperty]

    public var authorityCoordinate: ProjectAuthorityCoordinate {
        ProjectAuthorityCoordinate(
            projectID: projectID,
            documentGeneration: documentGeneration,
            transactionRevision: transactionRevision,
            publicationSequence: publicationSequence,
            workspaceRevision: workspaceState.revision
        )
    }

    public func sceneNodeID(for occurrenceID: SceneOccurrenceID) -> SceneNodeID? {
        sceneNodeIDByOccurrenceID[occurrenceID]
    }
}
