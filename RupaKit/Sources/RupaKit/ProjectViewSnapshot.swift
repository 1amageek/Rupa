import RupaCore
import RupaCoreTypes
import RupaViewportScene

/// The immutable, read-only state consumed by project UI.
///
/// Source bytes and mutation authority remain owned by `ProjectOperating`.
public struct ProjectViewSnapshot: Sendable {
    public let projectID: ProjectID
    public let projectName: String
    public let documentGeneration: DocumentGeneration
    public let transactionRevision: DocumentTransactionRevision
    public let publicationSequence: UInt64
    public let isDirty: Bool
    public let canUndo: Bool
    public let canRedo: Bool
    public let selection: SelectionModel
    public let workspaceState: WorkspaceState
    public let viewport: UniversalViewportScene
    public let cadInteraction: DocumentEvaluationContext?
    public let sceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]

    public func sceneNodeID(for occurrenceID: SceneOccurrenceID) -> SceneNodeID? {
        sceneNodeIDByOccurrenceID[occurrenceID]
    }
}
