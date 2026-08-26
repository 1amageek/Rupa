public protocol AutomationBatchPlanning: Sendable {
    func prepare(
        _ batch: AutomationBatch,
        in context: AutomationPlanningContext
    ) throws -> PreparedAutomationBatch
}
