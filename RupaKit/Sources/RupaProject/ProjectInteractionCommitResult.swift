import RupaAutomation

public struct ProjectInteractionCommitResult: Sendable {
    public let state: ProjectStateSnapshot
    public let automationExecution: AutomationBatchExecution?

    public init(
        state: ProjectStateSnapshot,
        automationExecution: AutomationBatchExecution? = nil
    ) {
        self.state = state
        self.automationExecution = automationExecution
    }
}
