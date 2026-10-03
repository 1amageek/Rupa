import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Patch on a sheet object: every hole of the sheet (each loop of its open edges) is filled by a
    /// surface fill, and the sheet and its fills are joined into one object, a solid when they
    /// close (Plasticity's "Holes are patched and made Solid"). The sheet's object shows the result.
    @discardableResult
    public mutating func patchHoles(
        name: String = "Patch",
        target: SceneNodeID,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Patch"
        let sheet = SelectionTarget(sceneNodeID: target)
        let loops = try OpenBoundaryLoopService().loops(
            of: target, in: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        guard loops.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName): the sheet has no holes to fill.")
        }
        let seeds = loops.compactMap(\.first)
        // Every fill prepared on the sheet as it is, then appended and joined in one step.
        let transactions = try seeds.map { seed in
            try prepareSurfaceFill(name: "\(name) Fill", target: seed, objectRegistry: objectRegistry,
                                   currentEvaluation: currentEvaluation, currentGeneration: currentGeneration)
        }
        var updated = self
        for transaction in transactions {
            _ = try updated.appendFeatureGraph(transaction, objectRegistry: objectRegistry)
        }
        let fills = transactions.flatMap(\.presentations).map { SelectionTarget(sceneNodeID: $0.sceneNodeID) }
        let joined = try updated.joinSheets(name: name, targets: [sheet] + fills, objectRegistry: objectRegistry)
        self = updated
        return joined
    }
}
