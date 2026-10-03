import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// The comb scale the first curvature measurement starts with.
    public static let defaultCurvatureCombScale = CurveCurvatureDisplay.defaultCombScale

    /// The one comb scale every curvature measurement is drawn at (Plasticity's Curvature panel
    /// Comb scale): the measurements' shared scale, the default before there are any.
    public var curvatureCombScale: Double {
        productMetadata.measurements.values.filter { $0.kind == .curvature }.sorted { $0.id.description < $1.id.description }
            .first?.combScale ?? Self.defaultCurvatureCombScale
    }

    /// Toggle Curvature on generated edges and sketch curves, one curve at a time: a curvature
    /// measurement combing the curve is taken away when there is one; otherwise a new one combing
    /// it alone is saved under Measurements. Returns the measurements added.
    @discardableResult
    public mutating func toggleCurvatureMeasurement(
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [MeasurementAnnotationID] {
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
        // Each curve toggles its own measurement, as Plasticity adds one per selected edge.
        var updated = self
        var added: [MeasurementAnnotationID] = []
        for anchor in anchors {
            if let existing = updated.productMetadata.measurements.values.first(where: {
                $0.kind == .curvature && $0.anchors.contains(anchor)
            }) {
                guard let sceneNodeID = existing.sceneNodeID else {
                    throw EditorError(code: .referenceUnresolved, message: "\(operationName) found a curvature measurement with no object to remove.")
                }
                try updated.deleteSceneNodes(ids: [sceneNodeID], objectRegistry: objectRegistry)
                continue
            }
            let count = updated.productMetadata.measurements.values.filter { $0.kind == .curvature }.count
            let annotation = MeasurementAnnotation(
                name: "Curvature \(count + 1)",
                kind: .curvature,
                anchors: [anchor],
                combScale: updated.curvatureCombScale
            )
            // A measurement that cannot comb its curve is refused rather than saved unresolved.
            _ = try CurvatureCombService().combs(
                for: annotation, in: updated, topology: topology,
                currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
            )
            added.append(try updated.addMeasurementAnnotation(annotation, objectRegistry: objectRegistry))
        }
        self = updated
        return added
    }

    /// Sets how long every curvature comb's teeth are drawn (Plasticity's Curvature panel: one Comb
    /// scale rescales all combs at once).
    public mutating func setCurvatureCombScale(
        _ combScale: Double,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard combScale.isFinite, combScale > 0 else {
            throw EditorError(code: .commandInvalid, message: "Comb Scale must be positive.")
        }
        var metadata = productMetadata
        let curvatures = metadata.measurements.filter { $0.value.kind == .curvature }
        guard curvatures.isEmpty == false else {
            throw EditorError(code: .referenceUnresolved, message: "Comb Scale applies to curvature measurements; there are none.")
        }
        for (id, var measurement) in curvatures {
            measurement.combScale = combScale
            metadata.measurements[id] = measurement
        }
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
