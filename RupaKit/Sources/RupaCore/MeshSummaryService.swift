import Foundation
import SwiftCAD

public struct MeshSummaryService: Sendable {
    private let pipelineOverride: CADPipeline?

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
    }

    public func summarize(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> MeshSummaryResult {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before mesh summary: \(String(describing: error))"
            )
        }

        guard document.cadDocument.hasActiveBodyProducingFeatures else {
            return MeshSummaryResult(
                displayUnit: document.displayUnit,
                diagnostics: [
                    EditorDiagnostic(
                        severity: .info,
                        message: "Document source is valid. No generated body meshes."
                    ),
                ]
            )
        }

        let evaluatedDocument: EvaluatedDocument
        do {
            let pipeline = pipelineOverride ?? .modelingDefault(
                for: document,
                objectRegistry: objectRegistry
            )
            evaluatedDocument = try pipeline.evaluate(document.cadDocument)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must evaluate successfully before mesh summary: \(String(describing: error))"
            )
        }

        var accumulator = MeshBoundsAccumulator()
        var bodies: [MeshSummaryResult.Body] = []
        var vertexCount = 0
        var normalCount = 0
        var triangleCount = 0
        var indexedElementCount = 0

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
            bodies.append(
                MeshSummaryResult.Body(
                    bodyID: bodyID.description,
                    vertexCount: bodyVertexCount,
                    normalCount: bodyNormalCount,
                    triangleCount: bodyTriangleCount,
                    indexedElementCount: bodyIndexedElementCount,
                    materialID: mesh.material?.description,
                    bounds: bounds
                )
            )
        }

        return MeshSummaryResult(
            displayUnit: document.displayUnit,
            bodyCount: bodies.count,
            vertexCount: vertexCount,
            normalCount: normalCount,
            triangleCount: triangleCount,
            indexedElementCount: indexedElementCount,
            bounds: accumulator.bounds,
            bodies: bodies,
            diagnostics: [
                EditorDiagnostic(
                    severity: .info,
                    message: "Mesh summary completed with \(bodies.count) generated body meshes."
                ),
            ]
        )
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

private extension CADDocument {
    var hasActiveBodyProducingFeatures: Bool {
        designGraph.order.contains { featureID in
            guard let feature = designGraph.nodes[featureID], !feature.isSuppressed else {
                return false
            }
            switch feature.operation {
            case .sketch:
                return false
            case .extrude:
                return true
            case .sweep:
                return true
            case .polySpline:
                return true
            case .faceLoopOffset:
                return true
            case .edgeOffset:
                return true
            case .faceKnife:
                return true
            }
        }
    }
}
