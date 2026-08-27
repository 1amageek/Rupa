import Foundation

/// The immutable source and receipt returned after one complete plan commit.
public struct MeshEditPlanExecution: Sendable {
    public let source: MeshSource
    public let receipt: MeshEditReceipt

    public init(source: MeshSource, receipt: MeshEditReceipt) {
        self.source = source
        self.receipt = receipt
    }
}
