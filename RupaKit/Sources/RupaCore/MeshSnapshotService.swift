import Foundation
import SwiftCAD
import RupaCoreTypes

public struct MeshSnapshotService: Sendable {
    private let pipelineOverride: CADPipeline?

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
    }

    public func snapshot(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> MeshSnapshot {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before mesh snapshot: \(String(describing: error))"
            )
        }

        guard document.cadDocument.hasActiveRenderableTopologyFeatures else {
            return MeshSnapshot()
        }

        let rawEvaluatedDocument = try DocumentEvaluationContextResolver(
            pipeline: pipelineOverride
        ).evaluatedDocument(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration,
            failurePrefix: "Document must evaluate successfully before mesh snapshot"
        )
        let evaluatedDocument = try SceneMaterialAssignmentResolver().applyingSceneMaterials(
            to: rawEvaluatedDocument,
            metadata: document.productMetadata
        )

        var accumulator = MeshBoundsAccumulator()
        var bodies: [MeshSummaryResult.Body] = []
        var vertexCount = 0
        var normalCount = 0
        var triangleCount = 0
        var indexedElementCount = 0
        let topologyMaterialResolver = TopologyMaterialBindingResolver()
        let faceBindingsByBodyID = topologyMaterialResolver.resolvedBindingsByBodyID(
            evaluatedDocument: evaluatedDocument,
            metadata: document.productMetadata
        )
        let faceCountByBodyID = topologyMaterialResolver.faceCountByBodyID(in: evaluatedDocument.brep)

        for (bodyID, mesh) in evaluatedDocument.meshes.sorted(by: { $0.key.description < $1.key.description }) {
            var bodyBounds = MeshBoundsAccumulator()
            for position in mesh.positions {
                bodyBounds.include(position)
                accumulator.include(position)
            }
            guard let bounds = bodyBounds.bounds else {
                continue
            }

            let bodyVertexCount = mesh.positions.count
            let bodyNormalCount = mesh.normals.count
            let bodyIndexedElementCount = mesh.indices.count
            let bodyTriangleCount = bodyIndexedElementCount / 3
            vertexCount += bodyVertexCount
            normalCount += bodyNormalCount
            indexedElementCount += bodyIndexedElementCount
            triangleCount += bodyTriangleCount
            let faceBindings = faceBindingsByBodyID[bodyID] ?? []
            let faceBindingSummaries = faceBindings.map { binding in
                MeshSummaryResult.FaceMaterialBinding(
                    persistentName: binding.persistentName,
                    faceID: binding.faceID.description,
                    materialID: binding.materialID?.description,
                    processNamespace: binding.process?.namespace,
                    processID: binding.process?.processID
                )
            }
            let generatedFaceCount = faceCountByBodyID[bodyID]
            let assignedMaterialFaceCount = Set(
                faceBindings.compactMap { binding -> FaceID? in
                    binding.materialID == nil ? nil : binding.faceID
                }
            ).count
            let unassignedFaceMaterialCount = generatedFaceCount.map {
                max($0 - assignedMaterialFaceCount, 0)
            }
            bodies.append(
                MeshSummaryResult.Body(
                    bodyID: bodyID.description,
                    vertexCount: bodyVertexCount,
                    normalCount: bodyNormalCount,
                    triangleCount: bodyTriangleCount,
                    indexedElementCount: bodyIndexedElementCount,
                    materialID: mesh.material?.description,
                    materialCoverage: materialCoverage(
                        bodyMaterialID: mesh.material,
                        faceBindings: faceBindings,
                        generatedFaceCount: generatedFaceCount
                    ),
                    generatedFaceCount: generatedFaceCount,
                    unassignedFaceMaterialCount: unassignedFaceMaterialCount,
                    faceMaterialBindings: faceBindingSummaries.isEmpty ? nil : faceBindingSummaries,
                    bounds: bounds
                )
            )
        }

        return MeshSnapshot(
            bodyCount: bodies.count,
            vertexCount: vertexCount,
            normalCount: normalCount,
            triangleCount: triangleCount,
            indexedElementCount: indexedElementCount,
            bounds: accumulator.bounds,
            bodies: bodies
        )
    }

    private func materialCoverage(
        bodyMaterialID: MaterialID?,
        faceBindings: [TopologyMaterialBindingResolver.ResolvedBinding],
        generatedFaceCount: Int?
    ) -> MeshMaterialCoverage {
        if bodyMaterialID != nil {
            return .body
        }
        guard let generatedFaceCount,
              generatedFaceCount > 0 else {
            return .missing
        }
        let assignedFaceIDs = Set(faceBindings.compactMap { binding -> FaceID? in
            binding.materialID == nil ? nil : binding.faceID
        })
        guard !assignedFaceIDs.isEmpty else {
            return .missing
        }
        guard assignedFaceIDs.count == generatedFaceCount else {
            return .partialFace
        }
        let materialIDs = Set(faceBindings.compactMap { $0.materialID })
        return materialIDs.count <= 1 ? .completeFace : .mixedFace
    }
}

private struct MeshBoundsAccumulator {
    private(set) var bounds: MeasurementResult.Bounds?

    mutating func include(_ point: Point3D) {
        let next = MeasurementResult.Bounds(
            minX: point.x,
            minY: point.y,
            minZ: point.z,
            maxX: point.x,
            maxY: point.y,
            maxZ: point.z
        )
        guard let current = bounds else {
            bounds = next
            return
        }
        bounds = MeasurementResult.Bounds(
            minX: min(current.minX, next.minX),
            minY: min(current.minY, next.minY),
            minZ: min(current.minZ, next.minZ),
            maxX: max(current.maxX, next.maxX),
            maxY: max(current.maxY, next.maxY),
            maxZ: max(current.maxZ, next.maxZ)
        )
    }
}
