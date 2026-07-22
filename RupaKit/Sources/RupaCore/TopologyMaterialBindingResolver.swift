import CADTopology
import SwiftCAD

struct TopologyMaterialBindingResolver: Sendable {
    struct ResolvedBinding: Equatable, Sendable {
        var stableReference: StableSubshapeReference
        var bodyID: BodyID
        var faceID: FaceID
        var materialID: MaterialID?
        var process: TopologyMaterialBinding.Process?
    }

    func resolvedBindings(
        evaluatedDocument: EvaluatedDocument,
        metadata: ProductMetadata
    ) throws -> [ResolvedBinding] {
        let bodyIDByFaceID = bodyIDMap(in: evaluatedDocument.brep)
        var bindings: [ResolvedBinding] = []
        for binding in metadata.topologyMaterialBindings.values.sorted(by: bindingSortKey) {
            let stableReference = try binding.stableReference()
            guard case .face(let faceID) = try evaluatedDocument.topologyReference(
                for: stableReference
            ), let bodyID = bodyIDByFaceID[faceID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Topology material binding does not resolve to a face in an evaluated body."
                )
            }
            bindings.append(
                ResolvedBinding(
                    stableReference: stableReference,
                    bodyID: bodyID,
                    faceID: faceID,
                    materialID: binding.materialID,
                    process: binding.process
                )
            )
        }
        return bindings
    }

    func resolvedBindingsByBodyID(
        evaluatedDocument: EvaluatedDocument,
        metadata: ProductMetadata
    ) throws -> [BodyID: [ResolvedBinding]] {
        Dictionary(grouping: try resolvedBindings(
            evaluatedDocument: evaluatedDocument,
            metadata: metadata
        ), by: \.bodyID)
    }

    func faceCountByBodyID(in model: BRepModel) -> [BodyID: Int] {
        var result: [BodyID: Int] = [:]
        for body in model.bodies.values {
            var faceIDs: Set<FaceID> = []
            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else {
                    continue
                }
                faceIDs.formUnion(shell.faceIDs)
            }
            result[body.id] = faceIDs.count
        }
        return result
    }

    private func bindingSortKey(
        _ lhs: TopologyMaterialBinding,
        _ rhs: TopologyMaterialBinding
    ) -> Bool {
        let leftTarget = bindingTargetSortKey(lhs.target)
        let rightTarget = bindingTargetSortKey(rhs.target)
        if leftTarget == rightTarget {
            return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
        return leftTarget < rightTarget
    }

    private func bindingTargetSortKey(_ target: SelectionTarget) -> String {
        let component: String
        switch target.component {
        case .object:
            component = "object"
        case .face(let id):
            component = "face:\(id.rawValue)"
        case .edge(let id):
            component = "edge:\(id.rawValue)"
        case .vertex(let id):
            component = "vertex:\(id.rawValue)"
        case .sketchEntity(let id):
            component = "sketchEntity:\(id.rawValue)"
        case .region(let id):
            component = "region:\(id.rawValue)"
        case .constructionPlane(let id):
            component = "constructionPlane:\(id.description)"
        }
        return "\(target.sceneNodeID.description):\(component)"
    }

    private func bodyIDMap(in model: BRepModel) -> [FaceID: BodyID] {
        var result: [FaceID: BodyID] = [:]
        for body in model.bodies.values {
            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else {
                    continue
                }
                for faceID in shell.faceIDs where result[faceID] == nil {
                    result[faceID] = body.id
                }
            }
        }
        return result
    }
}
