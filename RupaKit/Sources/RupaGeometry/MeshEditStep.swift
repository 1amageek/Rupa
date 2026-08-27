import Foundation

/// An ordered, uniquely identified operation in a Mesh edit plan.
public struct MeshEditStep: Codable, Equatable, Sendable {
    public let id: MeshEditStepID
    public let operation: MeshEditOperation

    public init(id: MeshEditStepID, operation: MeshEditOperation) {
        self.id = id
        self.operation = operation
    }
}
