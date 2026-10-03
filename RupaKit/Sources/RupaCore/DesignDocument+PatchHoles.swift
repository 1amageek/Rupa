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

    /// Insert Sheet (Patch with a hole's edge and another sheet, Plasticity's Trim to hole): the
    /// sheet trimmed to the hole through `hole` (a surface fill taking the sheet's enclosed part)
    /// is joined with the holed sheet's object, a solid when it closes; the inserted sheet's object
    /// is taken away.
    @discardableResult
    public mutating func insertSheet(
        name: String = "Patch",
        hole: SelectionTarget,
        sheet: SceneNodeID,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Patch"
        guard case .edge = hole.component, hole.sceneNodeID != sheet else {
            throw EditorError(code: .commandInvalid, message: "\(operationName): select a hole's edge and another sheet to insert.")
        }
        let inserted = try bodyObject(SelectionTarget(sceneNodeID: sheet), operationName: operationName)
        guard try bodyOrSheetPort(of: inserted.featureID, owner: operationName) == .sheet else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) inserts a sheet; a solid is not trimmed into a hole.")
        }
        guard try relativeRigidPlacement(of: sheet, inFrameOf: hole.sceneNodeID, owner: "The inserted sheet", relation: "the holed sheet") == nil else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) inserts a sheet shown where it was made, as the holed sheet is.")
        }
        let transaction = try prepareSurfaceFill(name: "\(name) Insert", target: hole, insertedSheet: inserted.featureID,
                                                 objectRegistry: objectRegistry,
                                                 currentEvaluation: currentEvaluation, currentGeneration: currentGeneration)
        var updated = self
        _ = try updated.appendFeatureGraph(transaction, objectRegistry: objectRegistry)
        let fills = transaction.presentations.map { SelectionTarget(sceneNodeID: $0.sceneNodeID) }
        let joined = try updated.joinSheets(name: name, targets: [SelectionTarget(sceneNodeID: hole.sceneNodeID)] + fills,
                                            objectRegistry: objectRegistry)
        try updated.removeSceneNodes(presenting: [inserted.featureID])
        self = updated
        return joined
    }
}
