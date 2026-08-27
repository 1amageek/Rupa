import Foundation
import RupaCoreTypes

/// Selects retained source elements or output elements from a prior step.
public enum MeshElementSelector: Codable, Equatable, Sendable {
    case explicit(MeshSelectionSet)
    case output(stepID: MeshEditStepID, role: MeshEditOutputRole)

    var explicitElements: [MeshSelectionElement]? {
        guard case .explicit(let selection) = self else {
            return nil
        }
        return selection.elements
    }
}
