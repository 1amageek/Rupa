import Foundation

/// Executes a validated plan against one immutable Mesh source.
public protocol MeshEditPlanExecuting: Sendable {
    func execute(
        plan: MeshEditPlan,
        source: MeshSource
    ) throws -> MeshEditPlanExecution
}
