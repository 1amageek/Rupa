import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Match Face: faces of one object take the surface of a reference face, of that object or of
    /// another where it is shown, and the faces around them are re-solved to meet them (Swift-CAD
    /// `faceMatch`). With `front`, each face faces out the way the reference face does. The
    /// object shows the result in its place.
    @discardableResult
    public mutating func matchFaces(
        name: String = "Match Face",
        targets: [SelectionTarget],
        reference: SelectionTarget,
        front: Bool,
        grow: FaceEditGrow = .moving,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Match Face"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let object = try offsetObject(for: targets, operationName: operationName)
        let source = try offsetObject(for: [reference], operationName: operationName)
        let faces = try targets.map { try stableReference(of: $0, kind: .face, in: topology, operationName: operationName) }
        let referenceFace = try stableReference(of: reference, kind: .face, in: topology, operationName: operationName)
        guard faces.contains(referenceFace) == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) cannot match a face to itself.")
        }
        let placement = source.nodeID == object.nodeID ? nil : try relativeRigidPlacement(
            of: source.nodeID, inFrameOf: object.nodeID, owner: "The reference face's object", relation: "the matched object"
        )
        return try appendFeatureShownByObject(
            .faceMatch(FaceMatchFeature(
                target: PatternTargetReference(featureID: object.featureID), faces: faces,
                source: PatternTargetReference(featureID: source.featureID), referenceFace: referenceFace,
                sourcePlacement: placement, front: front, grow: grow
            )),
            name: trimmedName, object: object.nodeID, objectRegistry: objectRegistry
        )
    }
}
