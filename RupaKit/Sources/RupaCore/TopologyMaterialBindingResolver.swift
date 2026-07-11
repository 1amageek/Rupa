import SwiftCAD

struct TopologyMaterialBindingResolver: Sendable {
    struct ResolvedBinding: Equatable, Sendable {
        var persistentName: String
        var bodyID: BodyID
        var faceID: FaceID
        var materialID: MaterialID?
        var process: TopologyMaterialBinding.Process?
    }

    func resolvedBindings(
        evaluatedDocument: EvaluatedDocument,
        metadata: ProductMetadata
    ) -> [ResolvedBinding] {
        let faceIDByPersistentName = faceIDMap(in: evaluatedDocument.generatedNames)
        let bodyIDByFaceID = bodyIDMap(in: evaluatedDocument.brep)
        var bindings: [ResolvedBinding] = []
        for binding in metadata.topologyMaterialBindings.values.sorted(by: bindingSortKey) {
            guard let persistentName = binding.persistentName,
                  let faceID = faceIDByPersistentName[persistentName],
                  let bodyID = bodyIDByFaceID[faceID] else {
                continue
            }
            bindings.append(
                ResolvedBinding(
                    persistentName: persistentName,
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
        let leftName = lhs.persistentName ?? ""
        let rightName = rhs.persistentName ?? ""
        if leftName == rightName {
            return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
        return leftName < rightName
    }

    private func faceIDMap(
        in generatedNames: PersistentMap<PersistentName, TopologyReference>
    ) -> [String: FaceID] {
        var result: [String: FaceID] = [:]
        for (name, reference) in generatedNames {
            guard case .face(let faceID) = reference else {
                continue
            }
            result[persistentNameString(name)] = faceID
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

    private func persistentNameString(_ name: PersistentName) -> String {
        name.components.map { component in
            switch component {
            case .feature(let featureID):
                return "feature:\(featureID.description)"
            case .generated(let value):
                return "generated:\(value)"
            case .subshape(let value):
                return "subshape:\(value)"
            case .index(let index):
                return "index:\(index)"
            }
        }
        .joined(separator: "/")
    }
}
