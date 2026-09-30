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

extension DesignDocument {
    /// Remove Fillets From Shell: the fillets of a solid object no wider than `maximumRadius`
    /// (any, when nil) and of `convexity` are taken out, and the faces they joined grow to meet
    /// (Swift-CAD `removeFillets`). The object shows the result in its place.
    @discardableResult
    public mutating func removeFillets(
        name: String = "Remove Fillets",
        target: SceneNodeID,
        maximumRadius: CADExpression?,
        convexity: FilletConvexity,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let operationName = "Remove Fillets"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        if let maximumRadius {
            guard try resolvedLengthValue(maximumRadius, owner: "\(operationName) maximum radius") > 0 else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) maximum radius must be positive.")
            }
        }
        let object = try offsetObject(for: [SelectionTarget(sceneNodeID: target)], operationName: operationName)
        guard productMetadata.sceneNodes[target]?.object?.geometryRole == .solid else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) works on solid objects.")
        }
        return try appendFeatureShownByObject(
            .removeFillets(RemoveFilletsFeature(
                target: PatternTargetReference(featureID: object.featureID), maximumRadius: maximumRadius, convexity: convexity
            )),
            name: trimmedName, object: object.nodeID, objectRegistry: objectRegistry
        )
    }
}

extension DesignDocument {
    /// Delete Redundant Topology on solid and sheet objects: each merges faces on one surface
    /// across the edges between them and edges on one curve across the vertices between them
    /// (Swift-CAD `removeRedundantTopology`), shown in its place, as one step.
    public mutating func removeRedundantTopology(targets: [SceneNodeID], objectRegistry: ObjectTypeRegistry = .builtIn) throws {
        let operationName = "Delete Redundant Topology"
        guard targets.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires solids or sheets.")
        }
        let previous = self
        var didCommit = false
        defer { if !didCommit { self = previous } }
        for target in targets {
            let object = try offsetObject(for: [SelectionTarget(sceneNodeID: target)], operationName: operationName)
            _ = try appendFeatureShownByObject(
                .removeRedundantTopology(RemoveRedundantTopologyFeature(target: PatternTargetReference(featureID: object.featureID))),
                name: operationName, object: object.nodeID, objectRegistry: objectRegistry
            )
        }
        didCommit = true
    }
}
