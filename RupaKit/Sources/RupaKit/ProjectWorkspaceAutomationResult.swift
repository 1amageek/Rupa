import RupaAutomation

/// The exact Automation execution and view observed through one project operation.
public struct ProjectWorkspaceAutomationResult: Sendable {
    public let execution: AutomationBatchExecution
    public let view: ProjectViewSnapshot
    public let didPublish: Bool

    public init(
        execution: AutomationBatchExecution,
        view: ProjectViewSnapshot,
        didPublish: Bool
    ) {
        self.execution = execution
        self.view = view
        self.didPublish = didPublish
    }
}
