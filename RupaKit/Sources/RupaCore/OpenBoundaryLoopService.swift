import Foundation
import SwiftCAD
import RupaCoreTypes

/// The open edges of a sheet object grouped into loops — its holes and its outer boundary — each
/// loop the open edges that meet end to end.
public struct OpenBoundaryLoopService: Sendable {
    public init() {}

    /// The loops of open edges of `object`, each in no particular order.
    public func loops(
        of object: SceneNodeID,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [[SelectionTarget]] {
        let open = try BoundaryEdgeSelectionService().boundaryEdges(
            of: [SelectionTarget(sceneNodeID: object)], in: document, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let topology = try TopologySnapshotService().snapshot(
            document: document, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let tolerance = document.modelingSettings.tolerance.distance
        var ends: [(SelectionTarget, Point3D, Point3D)] = []
        for edge in open {
            guard let entry = topology.entries.first(where: { $0.kind == .edge && $0.selectionTarget() == edge }),
                  let start = entry.start, let end = entry.end else {
                throw EditorError(code: .referenceUnresolved, message: "An open edge's ends cannot be read.")
            }
            ends.append((edge, Point3D(x: start.x, y: start.y, z: start.z), Point3D(x: end.x, y: end.y, z: end.z)))
        }
        var parent = Array(ends.indices)
        func find(_ index: Int) -> Int {
            var root = index
            while parent[root] != root { root = parent[root] }
            return root
        }
        for a in ends.indices {
            for b in ends.indices where b > a {
                let touches = [ends[a].1, ends[a].2].contains { p in [ends[b].1, ends[b].2].contains { ($0 - p).length <= tolerance } }
                if touches { parent[find(b)] = find(a) }
            }
        }
        var groups: [Int: [SelectionTarget]] = [:]
        var order: [Int] = []
        for index in ends.indices {
            let root = find(index)
            if groups[root] == nil { order.append(root) }
            groups[root, default: []].append(ends[index].0)
        }
        return order.compactMap { groups[$0] }
    }

    /// The loop of open edges through `edge`.
    public func loop(
        through edge: SelectionTarget,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [SelectionTarget] {
        let loops = try loops(of: edge.sceneNodeID, in: document, objectRegistry: objectRegistry,
                              currentEvaluation: currentEvaluation, currentGeneration: currentGeneration)
        guard let loop = loops.first(where: { $0.contains(edge) }) else {
            throw EditorError(code: .commandInvalid, message: "The edge is not an open edge of its sheet.")
        }
        return loop
    }
}
