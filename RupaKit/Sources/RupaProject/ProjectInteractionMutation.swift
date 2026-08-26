import RupaAutomation
import RupaCore

/// One session-independent non-source mutation payload.
public enum ProjectInteractionMutation: Sendable {
    case direct(
        selection: ProjectSelectionOperation?,
        workspaceCommands: [WorkspaceCommand]
    )
    case automation(PreparedAutomationBatch)
}
