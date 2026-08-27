import Foundation
import RupaCoreTypes

/// Immutable proof of one plan's ordered outputs, deletions, and copy work.
public struct MeshEditReceipt: Codable, Equatable, Sendable {
    public let stepReceipts: [MeshEditStepReceipt]
    public let deletedElements: [MeshSelectionElement]
    public let didChange: Bool
    public let telemetry: GeometryCopyTelemetry

    public init(
        stepReceipts: [MeshEditStepReceipt],
        deletedElements: [MeshSelectionElement] = [],
        didChange: Bool,
        telemetry: GeometryCopyTelemetry
    ) throws {
        guard Set(stepReceipts.map(\.stepID)).count == stepReceipts.count else {
            throw MeshEditError(
                code: .duplicateStepID,
                message: "Mesh edit receipts must contain one result per step ID."
            )
        }
        guard Set(deletedElements).count == deletedElements.count else {
            throw MeshEditError(
                code: .invalidReference,
                message: "Mesh edit receipts must not repeat deleted element IDs."
            )
        }
        self.stepReceipts = stepReceipts
        self.deletedElements = deletedElements
        self.didChange = didChange
        self.telemetry = telemetry
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            stepReceipts: container.decode([MeshEditStepReceipt].self, forKey: .stepReceipts),
            deletedElements: container.decode(
                [MeshSelectionElement].self,
                forKey: .deletedElements
            ),
            didChange: container.decode(Bool.self, forKey: .didChange),
            telemetry: container.decode(GeometryCopyTelemetry.self, forKey: .telemetry)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case stepReceipts
        case deletedElements
        case didChange
        case telemetry
    }
}
