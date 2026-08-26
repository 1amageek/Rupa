import RupaAutomation
import RupaCore

/// A validated interaction proposal that was never published to project authority.
public struct ProjectInteractionPreviewResult: Sendable {
    public let base: ProjectPreviewBaseCoordinate
    public let proposedSelection: SelectionModel
    public let proposedWorkspaceState: WorkspaceState
    public let wouldPublish: Bool
    public let automationExecution: AutomationBatchExecution?

    public init(
        base: ProjectPreviewBaseCoordinate,
        proposedSelection: SelectionModel,
        proposedWorkspaceState: WorkspaceState,
        wouldPublish: Bool,
        automationExecution: AutomationBatchExecution? = nil
    ) {
        self.base = base
        self.proposedSelection = proposedSelection
        self.proposedWorkspaceState = proposedWorkspaceState
        self.wouldPublish = wouldPublish
        self.automationExecution = automationExecution
    }
}
