import RupaAutomation
import RupaCore
import RupaProject

public protocol ProjectWorkspaceActionPlanning: Sendable {
    func source(
        name: String,
        commands: [EditorCommand],
        geometrySourceCommands: [GeometrySourceCommand],
        from snapshot: ProjectViewSnapshot
    ) throws -> ProjectWorkspaceAction

    func interaction(
        selection: ProjectSelectionOperation?,
        workspaceCommands: [WorkspaceCommand],
        from snapshot: ProjectViewSnapshot
    ) throws -> ProjectWorkspaceAction

    func automation(
        _ batch: AutomationBatch,
        from snapshot: ProjectViewSnapshot
    ) throws -> ProjectWorkspaceAction
}
