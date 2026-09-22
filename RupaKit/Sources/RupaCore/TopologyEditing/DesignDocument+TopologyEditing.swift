import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Resolves current topology without changing the source. The command store
    /// owns candidate evaluation and rollback of the returned transaction.
    public func prepareBodyEdgeTreatment(
        name: String,
        target: SelectionTarget,
        treatment: BodyEdgeTreatment,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureGraphTransaction {
        try prepareTopologyEdit(name: name, target: target, operation: treatment, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration)
    }

    public func prepareSheetSurfaceEdit(
        name: String, target: SelectionTarget, edit: SheetSurfaceEdit,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureGraphTransaction {
        try prepareTopologyEdit(name: name, target: target, operation: edit, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration)
    }

    public func prepareBodyShell(
        name: String, target: SelectionTarget, thickness: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureGraphTransaction {
        try prepareTopologyEdit(name: name, target: target, operation: BodyShellOperation(thickness: thickness),
            objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration)
    }

    private func prepareTopologyEdit<Operation: TopologyEditOperation>(
        name: String, target: SelectionTarget, operation: Operation,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?, currentGeneration: DocumentGeneration?
    ) throws -> FeatureGraphTransaction {
        let selection = try topologyEditSelection(target, kind: Operation.selectionKind,
            objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration)
        return try topologyEditTransaction(name: name, operation: operation.featureOperation(
            sourceID: selection.sourceID, reference: selection.reference, in: self))
    }

    package mutating func appendTopologyEdit(
        _ transaction: FeatureGraphTransaction, replacing target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard let featureID = transaction.primaryFeatureID,
              let feature = transaction.features.first(where: { $0.id == featureID }),
              var node = productMetadata.sceneNodes[target.sceneNodeID],
              var object = node.object else {
            throw EditorError(code: .commandInvalid, message: "Topology edit has no current presentation target.")
        }
        _ = try appendFeatureGraph(transaction, objectRegistry: objectRegistry)
        node.name = feature.name ?? node.name
        node.reference = .body(featureID)
        try object.retargetModelingCADRepresentation(to: featureID)
        object.sourceSection = nil
        object.typeID = nil
        object.geometryRole = feature.outputs.contains(where: { $0.role == .sheet }) ? .surface : .solid
        node.object = object
        productMetadata.sceneNodes[node.id] = node
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    private func topologyEditSelection(
        _ target: SelectionTarget, kind: TopologySummaryResult.Entry.Kind,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?, currentGeneration: DocumentGeneration?
    ) throws -> (sourceID: FeatureID, reference: StableSubshapeReference) {
        let subshapeID: SubshapeID?
        switch target.component {
        case .edge(let component) where kind == .edge: subshapeID = component.generatedTopologySubshapeID
        case .face(let component) where kind == .face: subshapeID = component.generatedTopologySubshapeID
        default: subshapeID = nil
        }
        guard let subshapeID,
              let node = productMetadata.sceneNodes[target.sceneNodeID],
              !node.isLocked,
              node.reference?.kind == .body,
              let sourceID = node.reference?.featureID,
              node.object?.sourceFeatureID == sourceID else {
            throw EditorError(code: .commandInvalid,
                message: "Topology editing requires a generated CAD subshape on an unlocked source body.")
        }
        var visited: Set<SceneNodeID> = [node.id]
        var childID = node.id
        while let parent = productMetadata.sceneNodes.values.first(where: { $0.childIDs.contains(childID) }) {
            guard visited.insert(parent.id).inserted, !parent.isLocked else {
                throw EditorError(code: .commandInvalid, message: "Topology editing cannot edit a locked or cyclic hierarchy.")
            }
            childID = parent.id
        }
        let evaluated = try DocumentEvaluationContextResolver().exactEvaluatedDocument(
            document: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration,
            failurePrefix: "Topology edit requires current evaluated geometry")
        let matchesKind: Bool
        switch evaluated.subshapes.entries[subshapeID] {
        case .edge: matchesKind = kind == .edge
        case .face: matchesKind = kind == .face
        default: matchesKind = false
        }
        guard subshapeID.featureID == sourceID, matchesKind else {
            throw EditorError(code: .referenceUnresolved,
                message: "The selected subshape is absent from current body topology. Select it again.")
        }
        let reference = try evaluated.stableSubshapeReference(for: subshapeID)
        return (sourceID, reference)
    }

    private func topologyEditTransaction(
        name: String, operation: FeatureOperation
    ) throws -> FeatureGraphTransaction {
        let name = try normalizedMetadataName(name, owner: "Topology edit")
        let feature = try FeatureNodeFactory.make(
            operation: operation, id: FeatureID(), in: cadDocument, tolerance: modelingSettings.tolerance
        )
        var namedFeature = feature
        namedFeature.name = name
        return FeatureGraphTransaction(features: [namedFeature], primaryFeatureID: feature.id)
    }
}
