import Foundation
import RupaCoreTypes

/// Immutable element outputs emitted by one executed plan step.
public struct MeshEditStepReceipt: Codable, Equatable, Sendable {
    public let stepID: MeshEditStepID
    public let outputs: [MeshEditOutputRole: [MeshSelectionElement]]

    public init(
        stepID: MeshEditStepID,
        outputs: [MeshEditOutputRole: [MeshSelectionElement]]
    ) throws {
        guard stepID.isStructurallyValid else {
            throw MeshEditError(
                code: .invalidStepID,
                message: "Mesh edit step IDs must be non-empty printable identifiers."
            )
        }
        var validated: [MeshEditOutputRole: [MeshSelectionElement]] = [:]
        for (role, elements) in outputs {
            guard elements.allSatisfy({ $0.domain == role.domain }),
                  Set(elements).count == elements.count else {
                throw MeshEditError(
                    code: .invalidReference,
                    message: "A Mesh edit output must contain unique elements from its role domain."
                )
            }
            validated[role] = elements
        }
        self.stepID = stepID
        self.outputs = validated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            stepID: container.decode(MeshEditStepID.self, forKey: .stepID),
            outputs: container.decode(
                [MeshEditOutputRole: [MeshSelectionElement]].self,
                forKey: .outputs
            )
        )
    }

    public func selection(for role: MeshEditOutputRole) throws -> MeshSelectionSet {
        guard let elements = outputs[role] else {
            throw MeshEditError(
                code: .inapplicableOutputRole,
                message: "The requested output role was not emitted by this step."
            )
        }
        return try MeshSelectionSet(elements: elements)
    }

    private enum CodingKeys: String, CodingKey {
        case stepID
        case outputs
    }
}
