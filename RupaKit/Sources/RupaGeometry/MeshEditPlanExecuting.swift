import Foundation

/// Executes a validated plan against one immutable Mesh source.
package protocol MeshEditPlanExecuting: Sendable {
    func execute(
        plan: MeshEditPlan,
        source: MeshSource
    ) throws -> MeshEditPlanExecution
}
