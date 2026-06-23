import Foundation
import SwiftCAD

public struct BodyDisplaySnapshotService: Sendable {
    private let pipelineOverride: CADPipeline?

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
    }

    public func snapshots(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [FeatureID: BodyDisplaySnapshot] {
        let pipeline = pipelineOverride ?? .modelingDefault(
            for: document,
            objectRegistry: objectRegistry
        )
        let evaluatedDocument = try pipeline.evaluate(document.cadDocument)
        var snapshots: [FeatureID: BodyDisplaySnapshot] = [:]
        for featureID in bodyFeatureIDs(in: evaluatedDocument.generatedNames) {
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
        guard let bodyID = generatedBodyID(
            for: featureID,
            in: evaluatedDocument.generatedNames
        ),
              let mesh = evaluatedDocument.meshes[bodyID],
              let bounds = bodyBounds(mesh.positions) else {
            return nil
        }

        return BodyDisplaySnapshot(
            featureID: featureID,
            bounds: bounds,
            mesh: BodyDisplaySnapshot.Mesh(
                positions: mesh.positions,
                indices: mesh.indices
            ),
            topology: topology(
                for: featureID,
                in: evaluatedDocument
            )
        )
    }

    private func bodyFeatureIDs(
        in generatedNames: [PersistentName: TopologyReference]
    ) -> [FeatureID] {
        var seen: Set<FeatureID> = []
        return generatedNames
            .sorted { persistentNameString($0.key) < persistentNameString($1.key) }
            .compactMap { name, reference -> FeatureID? in
                guard case .body = reference,
                      let featureID = persistentNameSourceFeatureID(name),
                      seen.insert(featureID).inserted else {
                    return nil
                }
                return featureID
            }
    }

    private func generatedBodyID(
        for featureID: FeatureID,
        in generatedNames: [PersistentName: TopologyReference]
    ) -> BodyID? {
        generatedNames
            .sorted { persistentNameString($0.key) < persistentNameString($1.key) }
            .compactMap { entry -> BodyID? in
                guard persistentNameSourceFeatureID(entry.key) == featureID,
                      case .body(let bodyID) = entry.value else {
                    return nil
                }
                return bodyID
            }
            .first
    }

    private func topology(
        for featureID: FeatureID,
        in evaluatedDocument: EvaluatedDocument
    ) -> BodyDisplaySnapshot.Topology {
        let model = evaluatedDocument.brep
        var faces: [BodyDisplaySnapshot.Topology.Face] = []
        var edges: [BodyDisplaySnapshot.Topology.Edge] = []
        var vertices: [BodyDisplaySnapshot.Topology.Vertex] = []

        for (name, reference) in evaluatedDocument.generatedNames.sorted(by: {
            persistentNameString($0.key) < persistentNameString($1.key)
        }) {
            guard persistentNameSourceFeatureID(name) == featureID else {
                continue
            }
            let componentID = SelectionComponentID.generatedTopology(
                persistentNameString(name)
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

    private func persistentNameSourceFeatureID(_ name: PersistentName) -> FeatureID? {
        for component in name.components {
            if case .feature(let featureID) = component {
                return featureID
            }
        }
        return nil
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
