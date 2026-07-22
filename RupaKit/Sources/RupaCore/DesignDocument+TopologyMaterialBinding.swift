import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func setTopologyMaterialBinding(
        target: SelectionTarget,
        materialID: MaterialID?,
        process: TopologyMaterialBinding.Process? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let stableReference = try topologyMaterialStableReference(for: target)
        guard productMetadata.sceneNodes[target.sceneNodeID] != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Topology material binding requires an existing scene node."
            )
        }
        guard PatternArrayOwnershipResolver().sourceID(
            containingGeneratedOutputSceneNode: target.sceneNodeID,
            in: productMetadata
        ) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output topology materials are controlled by the pattern source."
            )
        }
        if let materialID,
           productMetadata.materialLibrary.materials[materialID] == nil {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Topology material binding requires an existing material."
            )
        }
        try process?.validate()
        let topology = try TopologySnapshotService().snapshot(
            document: self,
            objectRegistry: objectRegistry
        )
        guard topology.entries.contains(where: {
            $0.kind == .face
                && $0.stableReference == stableReference
                && $0.sceneNodeID == target.sceneNodeID.description
        }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Topology material binding target was not found in the current generated face topology."
            )
        }

        productMetadata.topologyMaterialBindings = productMetadata.topologyMaterialBindings
            .filter { $0.value.target != target }
        if materialID != nil || process != nil {
            let binding = TopologyMaterialBinding(
                target: target,
                materialID: materialID,
                process: process
            )
            productMetadata.topologyMaterialBindings[binding.id] = binding
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    private func topologyMaterialStableReference(
        for target: SelectionTarget
    ) throws -> StableSubshapeReference {
        guard case .face(let componentID) = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "Topology material binding requires a stable face target."
            )
        }
        return try componentID.stableTopologyReference(
            operationName: "Topology material binding"
        )
    }
}
