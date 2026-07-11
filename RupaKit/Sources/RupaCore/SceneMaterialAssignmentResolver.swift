import SwiftCAD

struct SceneMaterialAssignmentResolver: Sendable {
    func applyingSceneMaterials(
        to evaluatedDocument: EvaluatedDocument,
        metadata: ProductMetadata
    ) throws -> EvaluatedDocument {
        let assignments = materialAssignmentsByBodyID(
            evaluatedDocument: evaluatedDocument,
            metadata: metadata
        )
        guard assignments.isEmpty == false else {
            return evaluatedDocument
        }

        var meshes = evaluatedDocument.meshes
        var brep = evaluatedDocument.brep
        for (bodyID, materialID) in assignments {
            if meshes[bodyID]?.material == nil {
                meshes[bodyID]?.material = materialID
            }
            if brep.bodies[bodyID]?.material == nil {
                brep.bodies[bodyID]?.material = materialID
            }
        }
        let result = EvaluatedDocument(
            document: evaluatedDocument.document,
            parameters: evaluatedDocument.parameters,
            brep: brep,
            meshes: meshes,
            curves: evaluatedDocument.curves,
            caches: DocumentCaches(),
            generatedNames: evaluatedDocument.generatedNames,
            configuration: evaluatedDocument.configuration,
            evaluationMetrics: evaluatedDocument.evaluationMetrics
        )
        guard evaluatedDocument.caches.brep != nil else {
            return result
        }
        return try DocumentCacheMaterializer().materializedDocument(from: result)
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
