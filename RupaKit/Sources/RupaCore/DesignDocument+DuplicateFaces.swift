import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Alternative Duplicate on faces: the chosen faces of each body are copied beside it as an
    /// object of its own, where the body is displayed, and the body stays as it is. Faces that
    /// close (every face of each shell they lie on) are copied as a solid, others as a sheet,
    /// through one Swift-CAD `extract` per body.
    @discardableResult
    public mutating func duplicateBodyFaces(
        name: String = "Alternative Duplicate",
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [FeatureID] {
        let operationName = "Alternative Duplicate"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        guard targets.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires at least one face.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let entriesBySubshapeID = Dictionary(uniqueKeysWithValues: topology.entries.map { ($0.subshapeID, $0) })
        // The faces of each body, bodies in the order their first face was chosen.
        var groups: [(featureID: FeatureID, sceneNodeID: SceneNodeID, faces: [StableSubshapeReference])] = []
        var seen: Set<String> = []
        for target in targets {
            guard case .face(let componentID) = target.component,
                  let subshapeID = componentID.generatedTopologySubshapeID else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) copies faces of bodies.")
            }
            guard productMetadata.sceneNodes[target.sceneNodeID]?.reference?.kind == .body else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) copies faces of a body object; realize an instance before copying its faces."
                )
            }
            let identity = GeneratedSubshapeIdentity.string(for: subshapeID)
            guard seen.insert(identity).inserted else { continue }
            let resolved = try editableBodyTargetResolution(for: target, operationName: operationName)
            guard let entry = entriesBySubshapeID[identity], entry.kind == .face,
                  entry.sceneNodeID == resolved.sceneNodeID.description,
                  let reference = entry.stableReference else {
                throw EditorError(code: .referenceUnresolved, message: "\(operationName) could not resolve a chosen face.")
            }
            if let index = groups.firstIndex(where: { $0.featureID == resolved.featureID && $0.sceneNodeID == resolved.sceneNodeID }) {
                groups[index].faces.append(reference)
            } else {
                groups.append((resolved.featureID, resolved.sceneNodeID, [reference]))
            }
        }
        let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(
            document: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration,
            failurePrefix: "\(operationName) requires its bodies evaluated"
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
        var copies: [FeatureID] = []
        for group in groups {
            let closes = try ExtractFaceClosure().closes(faces: group.faces, source: group.featureID, in: evaluated)
            let featureID = FeatureID()
            try appendFeature(try FeatureNodeFactory.make(
                operation: .extract(ExtractFeature(
                    target: PatternTargetReference(featureID: group.featureID),
                    selection: closes ? .solidFaces(group.faces) : .faces(group.faces)
                )),
                id: featureID, name: trimmedName, in: cadDocument, tolerance: modelingSettings.tolerance
            ))
            try insertBooleanResultNode(
                name: trimmedName, featureID: featureID, geometryRole: closes ? .solid : .surface,
                besideTargetNode: group.sceneNodeID, hierarchy: try SceneNodeHierarchy(metadata: productMetadata),
                objectRegistry: objectRegistry
            )
            copies.append(featureID)
        }
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return copies
    }
}
