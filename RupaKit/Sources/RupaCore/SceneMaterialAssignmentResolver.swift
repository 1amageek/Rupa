import SwiftCAD

struct SceneMaterialAssignmentResolver: Sendable {
    func applyingSceneMaterials(
        to evaluatedDocument: EvaluatedDocument,
        metadata: ProductMetadata
    ) -> EvaluatedDocument {
        let assignments = materialAssignmentsByBodyID(
            evaluatedDocument: evaluatedDocument,
            metadata: metadata
        )
        guard assignments.isEmpty == false else {
            return evaluatedDocument
        }

        var result = evaluatedDocument
        for (bodyID, materialID) in assignments {
            if result.meshes[bodyID]?.material == nil {
                result.meshes[bodyID]?.material = materialID
            }
            if result.brep.bodies[bodyID]?.material == nil {
                result.brep.bodies[bodyID]?.material = materialID
            }
        }
        return result
    }

    func materialID(
        for bodyID: BodyID,
        evaluatedDocument: EvaluatedDocument,
        metadata: ProductMetadata
    ) -> MaterialID? {
        evaluatedDocument.meshes[bodyID]?.material
            ?? evaluatedDocument.brep.bodies[bodyID]?.material
            ?? materialAssignmentsByBodyID(
                evaluatedDocument: evaluatedDocument,
                metadata: metadata
            )[bodyID]
    }

    private func materialAssignmentsByBodyID(
        evaluatedDocument: EvaluatedDocument,
        metadata: ProductMetadata
    ) -> [BodyID: MaterialID] {
        let identitiesByBodyID = GeneratedBodyIdentityResolver()
            .bodyIdentityByBodyID(in: evaluatedDocument.generatedNames)
        var assignments: [BodyID: MaterialID] = [:]
        for (bodyID, identity) in identitiesByBodyID {
            guard let materialID = sceneMaterialID(
                for: identity.sourceFeatureID,
                metadata: metadata
            ) else {
                continue
            }
            assignments[bodyID] = materialID
        }
        return assignments
    }

    private func sceneMaterialID(
        for sourceFeatureID: FeatureID,
        metadata: ProductMetadata
    ) -> MaterialID? {
        metadata.sceneNodes.values.first {
            $0.reference == .body(sourceFeatureID)
        }?.materialID
    }
}
