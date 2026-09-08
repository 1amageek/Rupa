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
        return snapshots(evaluatedDocument: evaluatedDocument)
    }

    public func snapshots(
        evaluatedDocument: EvaluatedDocument
    ) -> [FeatureID: BodyDisplaySnapshot] {
        var snapshots: [FeatureID: BodyDisplaySnapshot] = [:]
        for featureID in identityResolver.bodyFeatureIDs(in: evaluatedDocument.subshapes) {
            guard let snapshot = snapshot(
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
    ) -> BodyDisplaySnapshot? {
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
            subshapeID: GeneratedSubshapeIdentity.string(for: identity.subshapeID),
            bounds: bounds,
            mesh: BodyDisplaySnapshot.Mesh(
                positions: mesh.positions,
                indices: mesh.indices
            ),
            topology: topology(
                for: featureID,
                mesh: mesh,
                in: evaluatedDocument
            )
        )
    }

    private func topology(
        for featureID: FeatureID,
        mesh: SwiftCAD.Mesh,
        in evaluatedDocument: EvaluatedDocument
    ) -> BodyDisplaySnapshot.Topology {
        let model = evaluatedDocument.brep
        var faces: [BodyDisplaySnapshot.Topology.Face] = []
        var edges: [BodyDisplaySnapshot.Topology.Edge] = []
        var vertices: [BodyDisplaySnapshot.Topology.Vertex] = []
        // Every generated face of this feature, whether or not it also has the
        // outer-loop polygon `faces` requires, so that mesh provenance is
        // resolved from the kernel's own record rather than from what a polygon
        // hit test happened to be able to represent.
        var faceComponentIDs: [FaceID: SelectionComponentID] = [:]

        for (subshapeID, reference) in evaluatedDocument.subshapes.entries.sorted(by: {
            GeneratedSubshapeIdentity.areInIncreasingOrder($0.key, $1.key)
        }) {
            guard subshapeID.featureID == featureID else {
                continue
            }
            let componentID = SelectionComponentID.generatedTopology(subshapeID)
            switch reference {
            case .body:
                continue
            case .face(let faceID):
                faceComponentIDs[faceID] = componentID
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
            vertices: vertices,
            meshFaceRuns: meshFaceRuns(for: mesh, componentIDs: faceComponentIDs)
        )
    }

    /// Converts the kernel's per-face triangle counts into triangle ranges.
    ///
    /// The kernel records the runs contiguously in emission order, so the range
    /// of a run starts where the previous one ended. A run whose face has no
    /// generated-topology identity is omitted: that face carries no stable name
    /// a selection can refer to, so reporting no component is the truthful
    /// answer for its triangles rather than a substituted one.
    private func meshFaceRuns(
        for mesh: SwiftCAD.Mesh,
        componentIDs: [FaceID: SelectionComponentID]
    ) -> [BodyDisplaySnapshot.Topology.MeshFaceRun] {
        var runs: [BodyDisplaySnapshot.Topology.MeshFaceRun] = []
        runs.reserveCapacity(mesh.faceRuns.count)
        var triangleStart = 0
        for run in mesh.faceRuns {
            let triangleEnd = triangleStart + run.triangleCount
            defer { triangleStart = triangleEnd }
            guard let componentID = componentIDs[run.faceID] else {
                continue
            }
            runs.append(BodyDisplaySnapshot.Topology.MeshFaceRun(
                componentID: componentID,
                triangleRange: triangleStart ..< triangleEnd
            ))
        }
        return runs
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
