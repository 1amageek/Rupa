import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Offset Edge on edges of one object: Swift-CAD `edgeOffset` offsets them over `supportFace`
    /// by `distance`, and with symmetry over the face across each edge too, joining neighbouring
    /// offsets as `gapFill` says. The object shows the result in its place.
    @discardableResult
    public mutating func offsetEdges(
        name: String = "Offset Edge",
        targets: [SelectionTarget],
        supportFace: SelectionTarget,
        distance: CADExpression,
        isSymmetric: Bool,
        gapFill: OffsetCurveGapFill,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Offset Edge"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        guard try resolvedLengthValue(distance, owner: "\(operationName) distance") > 0 else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) distance must be positive.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let object = try offsetObject(for: targets + [supportFace], operationName: operationName)
        let edges = try targets.map { try stableReference(of: $0, kind: .edge, in: topology, operationName: operationName) }
        let face = try stableReference(of: supportFace, kind: .face, in: topology, operationName: operationName)
        // Every edge is offset over the support face, so each must bound it.
        guard let evaluated = topology.evaluatedDocument,
              case .face(let faceID) = evaluated.subshapes[face.subshapeID],
              let supportFaceModel = evaluated.brep.faces[faceID] else {
            throw EditorError(code: .referenceUnresolved, message: "\(operationName) could not resolve the support face.")
        }
        let bounding = Set(supportFaceModel.loops.flatMap { evaluated.brep.loops[$0]?.edges.map(\.edgeID) ?? [] })
        for edge in edges {
            guard case .edge(let edgeID) = evaluated.subshapes[edge.subshapeID], bounding.contains(edgeID) else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) offsets edges over a support face they bound; an edge does not bound it.")
            }
        }
        return try appendFeatureShownByObject(
            .edgeOffset(EdgeOffsetFeature(
                target: PatternTargetReference(featureID: object.featureID), edges: edges, supportFace: face,
                distance: distance, isSymmetric: isSymmetric, gapFill: gapFill.kernelGapFill
            )),
            name: trimmedName, object: object.nodeID, objectRegistry: objectRegistry
        )
    }

    /// Offset Face Loop on faces of one object: Swift-CAD `faceLoopOffset` offsets their outlines
    /// by the distance's size into the faces when it is positive, over the faces around them when
    /// it is negative, or both ways when symmetric; individually each face's own outline, combined
    /// the outline of the faces together. The object shows the result in its place.
    @discardableResult
    public mutating func offsetFaceLoops(
        name: String = "Offset Face Loop",
        targets: [SelectionTarget],
        distance: CADExpression,
        isSymmetric: Bool,
        gapFill: OffsetCurveGapFill,
        isIndividual: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Offset Face Loop"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        let meters = try resolvedLengthValue(distance, owner: "\(operationName) distance")
        guard abs(meters) > 1e-12 else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) distance must not be zero.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let object = try offsetObject(for: targets, operationName: operationName)
        let faces = try targets.map { try stableReference(of: $0, kind: .face, in: topology, operationName: operationName) }
        // The kernel takes a positive distance and the side apart.
        let size: CADExpression = meters < 0 ? .multiply(distance, .constant(.scalar(-1))) : distance
        let side: FaceLoopOffsetSide = isSymmetric ? .symmetric : (meters > 0 ? .inward : .outward)
        return try appendFeatureShownByObject(
            .faceLoopOffset(FaceLoopOffsetFeature(
                target: PatternTargetReference(featureID: object.featureID), faces: faces, distance: size,
                side: side, gapFill: gapFill.kernelGapFill, isIndividual: isIndividual
            )),
            name: trimmedName, object: object.nodeID, objectRegistry: objectRegistry
        )
    }

    /// The one object every target lies on, which must show a body of its own.
    func offsetObject(for targets: [SelectionTarget], operationName: String) throws -> (nodeID: SceneNodeID, featureID: FeatureID) {
        guard let nodeID = targets.first?.sceneNodeID else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires a selection.")
        }
        guard targets.allSatisfy({ $0.sceneNodeID == nodeID }) else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) works on one object at a time.")
        }
        guard let reference = productMetadata.sceneNodes[nodeID]?.reference, reference.kind == .body, let featureID = reference.featureID else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) works on solid and sheet objects; realize an instance first.")
        }
        return (nodeID, featureID)
    }

    /// The stable reference of the edge, face or vertex a target selects.
    func stableReference(
        of target: SelectionTarget, kind: TopologySummaryResult.Entry.Kind, in topology: TopologySnapshot, operationName: String
    ) throws -> StableSubshapeReference {
        let componentID: SelectionComponentID
        let noun = kind == .edge ? "edge" : kind == .face ? "face" : "vertex"
        switch (target.component, kind) {
        case (.edge(let id), .edge), (.face(let id), .face), (.vertex(let id), .vertex): componentID = id
        default:
            throw EditorError(code: .commandInvalid, message: "\(operationName) needs a \(noun) of the object.")
        }
        guard let entry = topology.entries.first(where: {
            $0.kind == kind && $0.sceneNodeID == target.sceneNodeID.description && $0.selectionComponentID == componentID.rawValue
        }), let reference = entry.stableReference else {
            throw EditorError(code: .referenceUnresolved, message: "\(operationName) could not resolve a selected \(noun).")
        }
        return reference
    }
}

extension OffsetCurveGapFill {
    /// The kernel's gap fill of the same name.
    var kernelGapFill: OffsetGapFill {
        switch self {
        case .round: .round
        case .linear: .linear
        case .natural: .natural
        }
    }
}
