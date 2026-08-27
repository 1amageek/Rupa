import Foundation

/// The immutable source and receipt returned after one complete plan commit.
///
/// This value is constructed only by the package-owned executor after the
/// staging buffer has validated every step, receipt, and commit boundary.
package struct MeshEditPlanExecution: Sendable {
    package let source: MeshSource
    package let receipt: MeshEditReceipt

    init(source: MeshSource, receipt: MeshEditReceipt) {
        self.source = source
        self.receipt = receipt
    }
}
