import Foundation
import RupaEvaluation
import RupaGeometry
import RupaProjectModel
import SwiftCAD

public struct CADGeometrySourceProvider: GeometrySourceEvaluationProvider {
    public let providerID = "cad"
    private let document: CADDocument
    private let evaluator: DocumentEvaluator

    public init(
        document: CADDocument,
        tolerance: ModelingTolerance
    ) {
        self.init(
            document: document,
            evaluator: DocumentEvaluator(tolerance: tolerance)
        )
    }

    public init(
        document: CADDocument,
        evaluator: DocumentEvaluator
    ) {
        self.document = document
        self.evaluator = evaluator
    }

    public func evaluate(
        reference: GeometrySourceReference,
        in project: ProjectSourceModel
    ) throws -> GeometryEvaluationResult {
        guard case .external(let providerID, let sourceID, let outputID) = reference,
              providerID == self.providerID else {
            throw CADIntegrationError(
                code: .unsupportedReference,
                message: "CAD provider received a non-CAD geometry reference."
            )
        }
        guard sourceID == document.id.description else {
            throw CADIntegrationError(
                code: .documentMismatch,
                message: "CAD geometry reference does not identify the configured document."
            )
        }
        guard let outputID,
              UUID(uuidString: outputID) != nil else {
            throw CADIntegrationError(
                code: .bodyUnavailable,
                message: "CAD geometry references require a valid body or feature output ID."
            )
        }
        let evaluatedDocument: EvaluatedDocument
        do {
            evaluatedDocument = try evaluator.evaluate(document)
        } catch {
            throw CADIntegrationError(
                code: .evaluationFailed,
                message: "CAD document evaluation failed: \(error)"
            )
        }
        let bodyID = try resolveBodyID(
            outputID: outputID,
            in: evaluatedDocument
        )
        guard let mesh = evaluatedDocument.meshes[bodyID] else {
            throw CADIntegrationError(
                code: .bodyUnavailable,
                message: "CAD evaluation produced no mesh for body \(bodyID.description)."
            )
        }
        let source = try makeMeshSource(bodyID: bodyID, mesh: mesh)
        return GeometryEvaluationResult(
            reference: reference,
            mesh: source,
            localBounds: try source.bounds()
        )
    }

    private func resolveBodyID(
        outputID: String,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> BodyID {
        guard let uuid = UUID(uuidString: outputID) else {
            throw CADIntegrationError(
                code: .bodyUnavailable,
                message: "CAD output ID is not a valid body or feature identifier."
            )
        }

        var candidates: Set<BodyID> = []
        let directBodyID = BodyID(uuid)
        if evaluatedDocument.meshes[directBodyID] != nil {
            candidates.insert(directBodyID)
        }

        let featureID = FeatureID(uuid)
        let bodySubshapeID = SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )
        if case let .body(bodyID) = evaluatedDocument.subshapes[bodySubshapeID],
           evaluatedDocument.meshes[bodyID] != nil {
            candidates.insert(bodyID)
        }

        guard candidates.count == 1,
              let resolved = candidates.first else {
            let reason = candidates.isEmpty ? "no live body" : "more than one live body"
            throw CADIntegrationError(
                code: .bodyUnavailable,
                message: "CAD evaluation resolved \(reason) for output \(outputID)."
            )
        }
        return resolved
    }

    private func makeMeshSource(bodyID: BodyID, mesh: Mesh) throws -> MeshSource {
        guard mesh.positions.count > 0,
              mesh.indices.count >= 3,
              mesh.indices.count.isMultiple(of: 3) else {
            throw CADIntegrationError(
                code: .invalidMesh,
                message: "CAD body mesh must contain vertices and complete triangles."
            )
        }
        var builder = MeshSourceBuilder(
            identity: MeshSourceID(rawValue: "cad.\(bodyID.description)")
        )
        var vertices: [MeshVertexID] = []
        vertices.reserveCapacity(mesh.positions.count)
        for position in mesh.positions {
            vertices.append(
                try builder.addVertex(
                    GeometryPoint3D(x: position.x, y: position.y, z: position.z)
                )
            )
        }
        for triangleStart in stride(from: 0, to: mesh.indices.count, by: 3) {
            let triangle = mesh.indices[triangleStart..<(triangleStart + 3)]
            let vertexIDs = try triangle.map { index in
                guard Int(index) < vertices.count else {
                    throw CADIntegrationError(
                        code: .invalidMesh,
                        message: "CAD body mesh contains an out-of-range triangle index."
                    )
                }
                return vertices[Int(index)]
            }
            _ = try builder.addFace(vertexIDs: vertexIDs)
        }
        if mesh.normals.count == mesh.positions.count {
            try builder.setAttribute(
                GeometryAttributeLayer(
                    descriptor: GeometryAttributeDescriptor(
                        id: "cad.normal",
                        name: "CAD Normal",
                        domain: .vertex,
                        valueType: .vector3,
                        interpolation: .linear
                    ),
                    values: .vector3(GeometryBuffer(mesh.normals.map {
                        GeometryPoint3D(x: $0.x, y: $0.y, z: $0.z)
                    }))
                )
            )
        }
        if mesh.textureCoordinates.count == mesh.positions.count {
            try builder.setAttribute(
                GeometryAttributeLayer(
                    descriptor: GeometryAttributeDescriptor(
                        id: "cad.uv",
                        name: "CAD UV",
                        domain: .vertex,
                        valueType: .vector2,
                        interpolation: .linear
                    ),
                    values: .vector2(GeometryBuffer(mesh.textureCoordinates.map {
                        GeometryVector2D(x: $0.x, y: $0.y)
                    }))
                )
            )
        }
        return try builder.build()
    }
}
