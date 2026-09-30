import Foundation
import SwiftCAD
import RupaCoreTypes

/// Find Boundary Edges: the open edges of the selected objects, each used by exactly one face of
/// its body, as edge selections. A sheet's openings and loose edges are found this way; a closed
/// solid has none. The document is not changed.
public struct BoundaryEdgeSelectionService: Sendable {
    public init() {}

    public func boundaryEdges(
        of targets: [SelectionTarget],
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [SelectionTarget] {
        let operationName = "Find Boundary Edges"
        var objects: [(nodeID: SceneNodeID, featureID: FeatureID)] = []
        for target in targets where objects.contains(where: { $0.nodeID == target.sceneNodeID }) == false {
            guard target.component == .object,
                  let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
                  reference.kind == .body, let featureID = reference.featureID else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) looks at whole sheet or solid objects.")
            }
            objects.append((target.sceneNodeID, featureID))
        }
        guard objects.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires a sheet.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: document, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        guard let evaluated = topology.evaluatedDocument else {
            throw EditorError(code: .evaluationFailed, message: "\(operationName) requires the evaluated bodies.")
        }
        let resolver = OpenBoundaryLoopResolver()
        var result: [SelectionTarget] = []
        for object in objects {
            let bodySubshape = SubshapeID(featureID: object.featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)
            guard case .body(let bodyID) = evaluated.subshapes[bodySubshape],
                  let body = evaluated.brep.bodies[bodyID] else {
                throw EditorError(code: .referenceUnresolved, message: "\(operationName) found no evaluated body for the object.")
            }
            let open = resolver.boundaryEdgeIDs(in: body, model: evaluated.brep)
            for entry in topology.entries where entry.kind == .edge && entry.sceneNodeID == object.nodeID.description {
                guard let reference = entry.stableReference,
                      case .edge(let edgeID) = evaluated.subshapes[reference.subshapeID],
                      open.contains(edgeID) else {
                    continue
                }
                guard let target = entry.selectionTarget() else {
                    throw EditorError(code: .referenceUnresolved, message: "\(operationName) found an open edge that cannot be selected.")
                }
                result.append(target)
            }
        }
        return result
    }
}
