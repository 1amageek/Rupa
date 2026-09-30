import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Reverse on sheets: each selected sheet object is turned over in its place (Swift-CAD
    /// `reverseSheet`), every face facing the other way with its surface and trim unchanged. The
    /// object keeps its name and placement and shows the reversed sheet. Solids are refused,
    /// because a solid's faces face out of it.
    @discardableResult
    public mutating func reverseSheets(
        name: String = "Reverse",
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [FeatureID] {
        let operationName = "Reverse"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        var sheets: [(nodeID: SceneNodeID, featureID: FeatureID)] = []
        for target in targets where sheets.contains(where: { $0.nodeID == target.sceneNodeID }) == false {
            guard target.component == .object,
                  let node = productMetadata.sceneNodes[target.sceneNodeID],
                  let reference = node.reference, reference.kind == .body, let featureID = reference.featureID else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) turns over whole sheet objects; realize an instance first."
                )
            }
            guard try bodyOrSheetPort(of: featureID, owner: operationName) == .sheet else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) turns over sheets; a solid's faces face out of it.")
            }
            sheets.append((target.sceneNodeID, featureID))
        }
        guard sheets.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires a sheet.")
        }
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        var reversed: [FeatureID] = []
        for sheet in sheets {
            let featureID = FeatureID()
            try appendFeature(try FeatureNodeFactory.make(
                operation: .reverseSheet(ReverseSheetFeature(target: PatternTargetReference(featureID: sheet.featureID))),
                id: featureID, name: trimmedName, in: cadDocument, tolerance: modelingSettings.tolerance
            ))
            let objectName = productMetadata.sceneNodes[sheet.nodeID]?.name ?? trimmedName
            try retargetBodyNode(sheet.nodeID, to: featureID, name: objectName, geometryRole: .surface)
            reversed.append(featureID)
        }
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return reversed
    }
}
