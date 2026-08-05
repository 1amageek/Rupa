import SwiftCAD

struct TopologyMaterialBindingResolver: Sendable {
    struct ResolvedBinding: Equatable, Sendable {
        var subshapeID: String
        var bodyID: BodyID
        var faceID: FaceID
        var materialID: MaterialID?
        var process: TopologyMaterialBinding.Process?
    }

    func resolvedBindings(
        evaluatedDocument: EvaluatedDocument,
        metadata: ProductMetadata
    ) -> [ResolvedBinding] {
        let faceIDBySubshapeID = faceIDMap(in: evaluatedDocument.subshapes)
        let bodyIDByFaceID = bodyIDMap(in: evaluatedDocument.brep)
        var bindings: [ResolvedBinding] = []
        for binding in metadata.topologyMaterialBindings.values.sorted(by: bindingSortKey) {
            guard let subshapeID = binding.subshapeID,
                  let faceID = faceIDBySubshapeID[subshapeID],
                  let bodyID = bodyIDByFaceID[faceID] else {
                continue
            }
            bindings.append(
                ResolvedBinding(
                    subshapeID: subshapeID,
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
    ) -> [BodyID: [ResolvedBinding]] {
        Dictionary(grouping: resolvedBindings(
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
        let leftName = lhs.subshapeID ?? ""
        let rightName = rhs.subshapeID ?? ""
        if leftName == rightName {
            return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
        return leftName < rightName
    }

    private func faceIDMap(
        in subshapes: SubshapeIndex
    ) -> [String: FaceID] {
        var result: [String: FaceID] = [:]
        for (subshapeID, reference) in subshapes.entries {
            guard case .face(let faceID) = reference else {
                continue
            }
            result[GeneratedSubshapeIdentity.string(for: subshapeID)] = faceID
        }
        return result
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
