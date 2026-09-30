import Foundation
import SwiftCAD
import RupaCoreTypes

/// Dimensions a body's own feature carries, beside the extruded-profile sizes: a sphere's diameter
/// and a solid fillet's radius.
package enum ObjectFeatureDimension: Equatable, Sendable {
    case sphere(featureID: FeatureID, sceneNodeID: SceneNodeID, radius: Double)
    case fillet(featureID: FeatureID, sceneNodeID: SceneNodeID, radius: Double)

    /// The feature dimension `target` names: a sphere object or face, or a face a fillet made. A
    /// fillet re-identifies every face of its body; its lineage records a blend face as merged from
    /// the faces beside the rounded edge (or generated, with no parent face), while every other face
    /// is preserved or split from one parent. `topology` is asked for only for a fillet's face.
    package static func resolve(
        target: SelectionTarget,
        in document: DesignDocument,
        topology: () throws -> TopologySnapshot?
    ) throws -> ObjectFeatureDimension? {
        if case .face(let componentID) = target.component,
           let subshapeID = componentID.generatedTopologySubshapeID,
           let feature = document.cadDocument.designGraph.nodes[subshapeID.featureID],
           case .fillet(let fillet) = feature.operation,
           let relation = try topology()?.evaluatedDocument?.lineage[subshapeID]?.relation,
           relation == .merged || relation == .generated {
            return .fillet(
                featureID: feature.id, sceneNodeID: target.sceneNodeID,
                radius: try resolvedLength(fillet.radius, in: document)
            )
        }
        switch target.component {
        case .object, .face: break
        default: return nil
        }
        guard let featureID = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference?.featureID,
              let feature = document.cadDocument.designGraph.nodes[featureID],
              case .primitive(let primitive) = feature.operation,
              case .sphere(let sphere) = primitive.definition else {
            return nil
        }
        return .sphere(featureID: featureID, sceneNodeID: target.sceneNodeID, radius: try resolvedLength(sphere.radius, in: document))
    }

    package func entries(for target: SelectionTarget) -> [ObjectDimensionSummaryResult.Entry] {
        func entry(_ sourceKind: ObjectDimensionSummaryResult.SourceKind, _ featureID: FeatureID, _ nodeID: SceneNodeID,
                   _ kind: ObjectDimensionKind, _ label: String, _ meters: Double, primary: Bool) -> ObjectDimensionSummaryResult.Entry {
            ObjectDimensionSummaryResult.Entry(
                target: target, sceneNodeID: nodeID.description, sourceFeatureID: featureID.description,
                sourceKind: sourceKind, kind: kind, label: label, inputExpression: .length(meters, .meter),
                resolvedMeters: meters, isPrimaryForTarget: primary
            )
        }
        switch self {
        case .sphere(let featureID, let nodeID, let radius):
            return [
                entry(.sphere, featureID, nodeID, .diameter, "Diameter", radius * 2, primary: true),
                entry(.sphere, featureID, nodeID, .radius, "Radius", radius, primary: false),
            ]
        case .fillet(let featureID, let nodeID, let radius):
            return [entry(.fillet, featureID, nodeID, .radius, "Fillet Radius", radius, primary: true)]
        }
    }

    private static func resolvedLength(_ expression: CADExpression, in document: DesignDocument) throws -> Double {
        let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .length, quantity.value.isFinite, quantity.value > 0 else {
            throw EditorError(code: .commandInvalid, message: "A dimension must resolve to a positive length.")
        }
        return quantity.value
    }
}

extension DesignDocument {
    /// Applies a sphere or fillet dimension; `false` when `target` carries neither.
    mutating func setFeatureDimension(
        target: SelectionTarget,
        kind: ObjectDimensionKind,
        value: CADExpression,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) throws -> Bool {
        let document = self
        guard let dimension = try ObjectFeatureDimension.resolve(target: target, in: self, topology: {
            try TopologySnapshotService().snapshot(
                document: document, objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation, currentGeneration: currentGeneration, metricPolicy: .omit
            )
        }) else { return false }
        let meters = try resolvedPositiveLengthValue(value, owner: "Dimension")
        var updated = self
        switch dimension {
        case .sphere(let featureID, let nodeID, _):
            guard kind == .diameter || kind == .radius else {
                throw EditorError(code: .commandInvalid, message: "A sphere is dimensioned by its diameter or radius.")
            }
            let radius = kind == .diameter ? meters / 2 : meters
            guard var feature = cadDocument.designGraph.nodes[featureID],
                  case .primitive(let primitive) = feature.operation,
                  case .sphere(let sphere) = primitive.definition else {
                throw EditorError(code: .referenceUnresolved, message: "The sphere's source is missing.")
            }
            feature.operation = .primitive(PrimitiveFeature(definition: .sphere(SpherePrimitive(
                placement: sphere.placement, radius: .length(radius, .meter)
            ))))
            try updated.cadDocument.replaceFeature(feature, tolerance: modelingSettings.tolerance)
            updated.productMetadata.sceneNodes[nodeID]?.object?.properties["radius"] = .length(radius)
        case .fillet(let featureID, _, _):
            guard kind == .radius else {
                throw EditorError(code: .commandInvalid, message: "A fillet is dimensioned by its radius.")
            }
            guard var feature = cadDocument.designGraph.nodes[featureID], case .fillet(let fillet) = feature.operation else {
                throw EditorError(code: .referenceUnresolved, message: "The fillet's source is missing.")
            }
            feature.operation = .fillet(FilletFeature(
                target: fillet.target, edges: fillet.edges, radius: .length(meters, .meter), allEdges: fillet.allEdges
            ))
            try updated.cadDocument.replaceFeature(feature, tolerance: modelingSettings.tolerance)
        }
        try updated.validate(objectRegistry: objectRegistry)
        self = updated
        return true
    }
}
