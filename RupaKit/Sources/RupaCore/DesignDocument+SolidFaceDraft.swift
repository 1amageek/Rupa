import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func draftBodyFaces(
        targets: [SelectionTarget],
        neutralTarget: SelectionTarget,
        angle: CADExpression,
        name: String = "Draft Face",
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let operationName = "Draft Face"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        let angleRadians = try resolvedAngleValue(angle, owner: "\(operationName) angle")
        guard abs(angleRadians) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) angle must not be zero."
            )
        }
        guard abs(angleRadians) < (Double.pi / 2.0) - 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) angle must be smaller than 90 degrees."
            )
        }
        guard targets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires at least one generated face target."
            )
        }

        let topology = try TopologySummaryService().summarize(
            document: self,
            objectRegistry: objectRegistry
        )
        let entriesByPersistentName = Dictionary(
            uniqueKeysWithValues: topology.entries.map { ($0.persistentName, $0) }
        )
        let parser = GeneratedTopologyPersistentNameParser()
        let targetResolutions = try targets.map { target in
            try generatedFaceDraftTarget(
                target,
                entriesByPersistentName: entriesByPersistentName,
                parser: parser,
                operationName: operationName
            )
        }
        let neutralResolution = try generatedFaceDraftTarget(
            neutralTarget,
            entriesByPersistentName: entriesByPersistentName,
            parser: parser,
            operationName: operationName
        )
        guard targetResolutions.allSatisfy({ $0.featureID == neutralResolution.featureID }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target and neutral faces must belong to one body feature."
            )
        }
        guard targetResolutions.allSatisfy({ $0.sceneNodeID == neutralResolution.sceneNodeID }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target and neutral faces must belong to one scene body."
            )
        }
        let targetPersistentNames = targetResolutions.map(\.persistentName)
        guard Set(targetPersistentNames).count == targetPersistentNames.count else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target faces must be distinct."
            )
        }
        guard targetPersistentNames.contains(neutralResolution.persistentName) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target face and neutral face must be distinct."
            )
        }
        guard let targetFeature = cadDocument.designGraph.nodes[neutralResolution.featureID],
              targetFeature.outputs.contains(where: { $0.role == .body }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a body-producing target feature."
            )
        }

        let faceDraft = FaceDraftFeature(
            target: FaceDraftTargetReference(featureID: neutralResolution.featureID),
            facePersistentNames: targetPersistentNames,
            neutralFacePersistentName: neutralResolution.persistentName,
            angle: angle
        )
        try faceDraft.validate()

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .faceDraft(faceDraft),
            inputs: [FeatureInput(featureID: neutralResolution.featureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: nil,
                typeID: nil,
                geometryRole: .solid,
                properties: ObjectPropertySet(),
                ruler: ruler,
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        do {
            _ = try CADPipeline
                .modelingDefault(for: self, objectRegistry: objectRegistry)
                .evaluate(cadDocument)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) produced unsupported or invalid geometry: \(error)."
            )
        }
        didCommit = true
        return featureID
    }

    private struct FaceDraftTargetResolution {
        var sceneNodeID: SceneNodeID
        var featureID: FeatureID
        var persistentName: PersistentName
    }

    private func generatedFaceDraftTarget(
        _ target: SelectionTarget,
        entriesByPersistentName: [String: TopologySummaryResult.Entry],
        parser: GeneratedTopologyPersistentNameParser,
        operationName: String
    ) throws -> FaceDraftTargetResolution {
        guard case .face(let componentID) = target.component,
              let persistentNameString = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires generated topology face targets."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: operationName
        )
        guard let entry = entriesByPersistentName[persistentNameString] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology face was not found in the current evaluation."
            )
        }
        guard entry.kind == .face,
              entry.sceneNodeID == resolvedTarget.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) targets must reference faces on the selected body."
            )
        }
        return FaceDraftTargetResolution(
            sceneNodeID: resolvedTarget.sceneNodeID,
            featureID: resolvedTarget.featureID,
            persistentName: try parser.parse(persistentNameString, operationName: operationName)
        )
    }
}
