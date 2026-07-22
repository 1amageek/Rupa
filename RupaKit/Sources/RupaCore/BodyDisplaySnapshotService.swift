import Foundation
import SwiftCAD
import RupaCoreTypes

public struct BodyDisplaySnapshotService: Sendable {
    private let pipelineOverride: CADPipeline?
    private let identityResolver = GeneratedBodyIdentityResolver()

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
    }

    public func snapshots(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [FeatureID: BodyDisplaySnapshot] {
        let evaluatedDocument = try DocumentEvaluationContextResolver(
            pipeline: pipelineOverride
        ).evaluatedDocument(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration,
            failurePrefix: "Document must evaluate successfully before body display snapshots"
        )
        return try snapshots(evaluatedDocument: evaluatedDocument)
    }

    public func snapshots(
        evaluatedDocument: EvaluatedDocument
    ) throws -> [FeatureID: BodyDisplaySnapshot] {
        var snapshots: [FeatureID: BodyDisplaySnapshot] = [:]
        for featureID in identityResolver.bodyFeatureIDs(in: evaluatedDocument.subshapes) {
            guard let snapshot = try snapshot(
                for: featureID,
                in: evaluatedDocument
            ) else {
                continue
            }
            snapshots[featureID] = snapshot
        }
        return snapshots
    }

    private func snapshot(
        for featureID: FeatureID,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> BodyDisplaySnapshot? {
        guard let identity = identityResolver.firstBodyIdentity(
            for: featureID,
            in: evaluatedDocument.subshapes
        ),
              let mesh = evaluatedDocument.meshes[identity.bodyID],
              let bounds = bodyBounds(mesh.positions) else {
            return nil
        }

        return BodyDisplaySnapshot(
            featureID: featureID,
            bodyID: identity.bodyID.description,
            stableReference: try evaluatedDocument.stableSubshapeReference(
                for: identity.subshapeID
            ),
            bounds: bounds,
            mesh: BodyDisplaySnapshot.Mesh(
                positions: mesh.positions,
                indices: mesh.indices
            ),
            topology: try topology(
                for: featureID,
                in: evaluatedDocument
            )
        )
    }

    private func topology(
        for featureID: FeatureID,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> BodyDisplaySnapshot.Topology {
        let model = evaluatedDocument.brep
        var faces: [BodyDisplaySnapshot.Topology.Face] = []
        var edges: [BodyDisplaySnapshot.Topology.Edge] = []
        var vertices: [BodyDisplaySnapshot.Topology.Vertex] = []

        for (subshapeID, reference) in evaluatedDocument.subshapes.entries.sorted(by: {
            $0.key < $1.key
        }) {
            guard subshapeID.featureID == featureID else {
                continue
            }
            let componentID = try SelectionComponentID.stableTopology(
                evaluatedDocument.stableSubshapeReference(for: subshapeID)
            )
            switch reference {
            case .body:
                continue
            case .face(let faceID):
                guard let face = model.faces[faceID],
                      let points = orderedOuterLoopPoints(for: face, in: model),
                      points.count >= 3 else {
                    continue
                }
                faces.append(BodyDisplaySnapshot.Topology.Face(
                    componentID: componentID,
                    points: points
                ))
            case .edge(let edgeID):
                guard let edge = model.edges[edgeID],
                      let start = model.vertices[edge.startVertexID]?.point,
                      let end = model.vertices[edge.endVertexID]?.point else {
                    continue
                }
                edges.append(BodyDisplaySnapshot.Topology.Edge(
                    componentID: componentID,
                    start: start,
                    end: end
                ))
            case .vertex(let vertexID):
                guard let vertex = model.vertices[vertexID] else {
                    continue
                }
                vertices.append(BodyDisplaySnapshot.Topology.Vertex(
                    componentID: componentID,
                    point: vertex.point
                ))
            }
        }

        return BodyDisplaySnapshot.Topology(
            faces: faces,
            edges: edges,
            vertices: vertices
        )
    }

    private func orderedOuterLoopPoints(
        for face: CADFace,
        in model: CADBRepModel
    ) -> [Point3D]? {
        guard let loopID = face.loops.first(where: { loopID in
            model.loops[loopID]?.role == .outer
        }) else {
            return nil
        }
        do {
            return try model.orderedPoints(for: loopID)
        } catch {
            return nil
        }
    }

    private func bodyBounds(_ positions: [Point3D]) -> BodyDisplaySnapshot.Bounds? {
        guard let first = positions.first else {
            return nil
        }
        var bounds = BodyDisplaySnapshot.Bounds(
            minX: first.x,
            minY: first.y,
            minZ: first.z,
            maxX: first.x,
            maxY: first.y,
            maxZ: first.z
        )
        for point in positions.dropFirst() {
            bounds.minX = min(bounds.minX, point.x)
            bounds.minY = min(bounds.minY, point.y)
            bounds.minZ = min(bounds.minZ, point.z)
            bounds.maxX = max(bounds.maxX, point.x)
            bounds.maxY = max(bounds.maxY, point.y)
            bounds.maxZ = max(bounds.maxZ, point.z)
        }
        return bounds
    }

}
