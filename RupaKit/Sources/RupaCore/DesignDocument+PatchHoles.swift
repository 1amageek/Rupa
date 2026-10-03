import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Patch on a sheet object: every hole of the sheet (each loop of its open edges) is filled by a
    /// surface fill, and the sheet and its fills are joined into one object, a solid when they
    /// close (Plasticity's "Holes are patched and made Solid"). The sheet's object shows the result.
    @discardableResult
    public mutating func patchHoles(
        name: String = "Patch",
        target: SceneNodeID,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Patch"
        let sheet = SelectionTarget(sceneNodeID: target)
        let open = try BoundaryEdgeSelectionService().boundaryEdges(
            of: [sheet], in: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        guard open.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName): the sheet has no holes to fill.")
        }
        // One seed edge per loop: open edges joined end to end into loops.
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let tolerance = modelingSettings.tolerance.distance
        var ends: [(SelectionTarget, Point3D, Point3D)] = []
        for edge in open {
            guard let entry = topology.entries.first(where: { $0.kind == .edge && $0.selectionTarget() == edge }),
                  let start = entry.start, let end = entry.end else {
                throw EditorError(code: .referenceUnresolved, message: "\(operationName) cannot read an open edge's ends.")
            }
            ends.append((edge, Point3D(x: start.x, y: start.y, z: start.z), Point3D(x: end.x, y: end.y, z: end.z)))
        }
        var loopOf = Array(ends.indices)
        func find(_ index: Int) -> Int {
            var root = index
            while loopOf[root] != root { root = loopOf[root] }
            return root
        }
        for a in ends.indices {
            for b in ends.indices where b > a {
                let touches = [ends[a].1, ends[a].2].contains { p in [ends[b].1, ends[b].2].contains { ($0 - p).length <= tolerance } }
                if touches { loopOf[find(b)] = find(a) }
            }
        }
        var seeds: [SelectionTarget] = []
        var seen = Set<Int>()
        for index in ends.indices where seen.insert(find(index)).inserted { seeds.append(ends[index].0) }
        // Every fill prepared on the sheet as it is, then appended and joined in one step.
        let transactions = try seeds.map { seed in
            try prepareSurfaceFill(name: "\(name) Fill", target: seed, objectRegistry: objectRegistry,
                                   currentEvaluation: currentEvaluation, currentGeneration: currentGeneration)
        }
        var updated = self
        for transaction in transactions {
            _ = try updated.appendFeatureGraph(transaction, objectRegistry: objectRegistry)
        }
        let fills = transactions.flatMap(\.presentations).map { SelectionTarget(sceneNodeID: $0.sceneNodeID) }
        let joined = try updated.joinSheets(name: name, targets: [sheet] + fills, objectRegistry: objectRegistry)
        self = updated
        return joined
    }
}
