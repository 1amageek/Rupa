import RupaAutomation
import RupaProject

public protocol ProjectSemanticResultProjecting: Sendable {
    func project(
        plan: ProjectResultProjectionPlan,
        receipt: PreparedAutomationExecutionReceipt,
        state: ProjectStateSnapshot
    ) throws -> [ProjectSemanticOutputBinding]
}
