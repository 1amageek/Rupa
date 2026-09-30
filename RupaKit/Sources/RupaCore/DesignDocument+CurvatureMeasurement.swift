import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// The comb scale a new curvature measurement starts with.
    public static let defaultCurvatureCombScale = CurveCurvatureDisplay.defaultCombScale

    /// Toggle Curvature on generated edges and sketch curves: a curvature measurement combing
    /// exactly these curves is taken away when there is one; otherwise a new one is saved under
    /// Measurements. Returns the measurement added, or nil when one was taken away.
    @discardableResult
    public mutating func toggleCurvatureMeasurement(
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> MeasurementAnnotationID? {
        let operationName = "Toggle Curvature"
        guard targets.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires edges or curves.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        var anchors: [MeasurementAnchor] = []
        for target in targets {
            let anchor = try curvatureAnchor(for: target, topology: topology, operationName: operationName)
            if anchors.contains(anchor) == false { anchors.append(anchor) }
        }
        if let existing = productMetadata.measurements.values.first(where: {
            $0.kind == .curvature && Set($0.anchors) == Set(anchors)
        }) {
            guard let sceneNodeID = existing.sceneNodeID else {
                throw EditorError(code: .referenceUnresolved, message: "\(operationName) found a curvature measurement with no object to remove.")
            }
            try deleteSceneNodes(ids: [sceneNodeID], objectRegistry: objectRegistry)
            return nil
        }
        let count = productMetadata.measurements.values.filter { $0.kind == .curvature }.count
        let annotation = MeasurementAnnotation(
            name: "Curvature \(count + 1)",
            kind: .curvature,
            anchors: anchors,
            combScale: Self.defaultCurvatureCombScale
        )
        // A measurement that cannot comb its curves is refused rather than saved unresolved.
        _ = try CurvatureCombService().combs(
            for: annotation, in: self, topology: topology,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        return try addMeasurementAnnotation(annotation, objectRegistry: objectRegistry)
    }

    /// Sets how long a curvature measurement's comb teeth are drawn.
    public mutating func setMeasurementCombScale(
        id: MeasurementAnnotationID,
        combScale: Double,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var measurement = productMetadata.measurements[id], measurement.kind == .curvature else {
            throw EditorError(code: .referenceUnresolved, message: "Comb Scale applies to a curvature measurement.")
        }
        guard combScale.isFinite, combScale > 0 else {
            throw EditorError(code: .commandInvalid, message: "Comb Scale must be positive.")
        }
        measurement.combScale = combScale
        var metadata = productMetadata
        metadata.measurements[id] = measurement
        try metadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        productMetadata = metadata
    }

    /// The anchor naming the whole curve `target` selects: a generated edge, or a sketch curve.
    private func curvatureAnchor(
        for target: SelectionTarget,
        topology: TopologySnapshot,
        operationName: String
    ) throws -> MeasurementAnchor {
        switch target.component {
        case .edge(let componentID):
            guard let entry = topology.entries.first(where: {
                $0.kind == .edge && $0.sceneNodeID == target.sceneNodeID.description
                    && $0.selectionComponentID == componentID.rawValue
            }) else {
                throw EditorError(code: .referenceUnresolved, message: "\(operationName) could not resolve a selected edge.")
            }
            return .topologyReference(
                sceneNodeID: target.sceneNodeID, component: target.component, kind: .edge,
                subshapeID: entry.subshapeID, referenceID: entry.referenceID
            )
        case .sketchEntity(let componentID):
            guard let reference = componentID.sketchEntityReference,
                  componentID.sketchPointHandleReference == nil,
                  componentID.sketchControlPointReference == nil,
                  case .sketch(let sketch) = cadDocument.designGraph.nodes[reference.featureID]?.operation,
                  let entity = sketch.entities[reference.entityID] else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) combs whole curves, not their points.")
            }
            if case .point = entity {
                throw EditorError(code: .commandInvalid, message: "\(operationName) combs curves; a point has no curvature.")
            }
            return .sketchReference(
                featureID: reference.featureID, reference: .entity(reference.entityID), sceneNodeID: target.sceneNodeID
            )
        default:
            throw EditorError(code: .commandInvalid, message: "\(operationName) combs edges and curves.")
        }
    }
}
