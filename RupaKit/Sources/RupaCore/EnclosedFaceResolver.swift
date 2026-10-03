import Foundation
import SwiftCAD
import RupaCoreTypes

/// The faces a closed loop of edges of a body encloses: the faces reached from one side of the
/// loop without crossing it, the side with fewer faces (Patch on a solid's edge loop makes a sheet
/// of them).
public struct EnclosedFaceResolver: Sendable {
    public init() {}

    public func faces(
        enclosedBy edges: [SelectionTarget],
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [SelectionTarget] {
        guard let object = edges.first?.sceneNodeID, edges.allSatisfy({ $0.sceneNodeID == object }) else {
            throw EditorError(code: .commandInvalid, message: "The loop's edges belong to one body.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: document, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        guard let evaluated = topology.evaluatedDocument else {
            throw EditorError(code: .referenceUnresolved, message: "The body's faces need the evaluated document.")
        }
        func reference(of target: SelectionTarget, kind: TopologySummaryResult.Entry.Kind) throws -> TopologyReference {
            guard let entry = topology.entries.first(where: { $0.kind == kind && $0.selectionTarget() == target }),
                  let stable = entry.stableReference else {
                throw EditorError(code: .referenceUnresolved, message: "A loop edge is no longer in the model.")
            }
            return try evaluated.topologyReference(for: stable)
        }
        let loopEdges = Set(try edges.map { target -> EdgeID in
            guard case let .edge(id) = try reference(of: target, kind: .edge) else {
                throw EditorError(code: .commandInvalid, message: "A loop member is not an edge.")
            }
            return id
        })
        // The body's faces and which faces each edge joins.
        let faceEntries = topology.entries.filter { $0.kind == .face && $0.sceneNodeID == object.description }
        var faceOf: [FaceID: SelectionTarget] = [:]
        for entry in faceEntries {
            guard let stable = entry.stableReference, let target = entry.selectionTarget(),
                  case let .face(id) = try evaluated.topologyReference(for: stable) else { continue }
            faceOf[id] = target
        }
        var facesOfEdge: [EdgeID: [FaceID]] = [:]
        for faceID in faceOf.keys {
            for loopID in evaluated.brep.faces[faceID]?.loops ?? [] {
                for coedge in evaluated.brep.loops[loopID]?.coedges ?? [] { facesOfEdge[coedge.edgeID, default: []].append(faceID) }
            }
        }
        // Flood the faces without crossing the loop; the loop splits them into two regions.
        var region: [FaceID: Int] = [:]
        var regions: [[FaceID]] = []
        for start in faceOf.keys.sorted() where region[start] == nil {
            var stack = [start]
            var members: [FaceID] = []
            region[start] = regions.count
            while let face = stack.popLast() {
                members.append(face)
                for loopID in evaluated.brep.faces[face]?.loops ?? [] {
                    for coedge in evaluated.brep.loops[loopID]?.coedges ?? [] where loopEdges.contains(coedge.edgeID) == false {
                        for neighbour in facesOfEdge[coedge.edgeID] ?? [] where region[neighbour] == nil {
                            region[neighbour] = regions.count
                            stack.append(neighbour)
                        }
                    }
                }
            }
            regions.append(members)
        }
        guard regions.count == 2 else {
            throw EditorError(code: .commandInvalid, message: "The edges do not close a loop that splits the body's faces in two.")
        }
        let enclosed = regions.min { $0.count < $1.count } ?? regions[0]
        return enclosed.sorted().compactMap { faceOf[$0] }
    }
}
