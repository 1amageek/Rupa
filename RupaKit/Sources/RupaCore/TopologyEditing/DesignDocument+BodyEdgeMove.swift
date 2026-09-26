import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Move Edges: moves the selected edges of one body by `distance` along `direction`
    /// (world-aligned in the body's own frame), one kernel `EdgeMoveFeature` per edge, chained so
    /// each moves the body the previous one made.
    ///
    /// The kernel owns what moves: a straight edge of a line-only planar solid re-solves its faces,
    /// and a circular edge moves along its axis with the planar cap it bounds. The candidate is
    /// evaluated before it is kept, so an edge the kernel cannot move refuses the command and the
    /// document stays as it was.
    public mutating func moveBodyEdges(
        targets: [SelectionTarget],
        direction: Vector3D,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws {
        guard let first = targets.first else {
            throw EditorError(code: .commandInvalid, message: "Move Edges needs at least one edge.")
        }
        guard targets.allSatisfy({ $0.sceneNodeID == first.sceneNodeID }) else {
            throw EditorError(code: .commandInvalid, message: "Move Edges moves the edges of one body at a time.")
        }
        let unit: Vector3D
        do {
            unit = try direction.normalized(tolerance: modelingSettings.tolerance.distance)
        } catch {
            throw EditorError(code: .commandInvalid, message: "Move Edges needs a direction.")
        }

        var features: [FeatureNode] = []
        var bodyFeatureID: FeatureID?
        var seen: Set<SubshapeID> = []
        for target in targets {
            let selection = try topologyEditSelection(
                target, kind: .edge, objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
            )
            guard seen.insert(selection.reference.subshapeID).inserted else { continue }
            // Each move acts on the body the previous one made; the kernel follows the edge's
            // lineage from the source body.
            let move = EdgeMoveFeature(
                target: EdgeMoveTargetReference(featureID: bodyFeatureID ?? selection.sourceID),
                edge: selection.reference,
                translation: DirectMoveVector(direction: unit, distance: distance)
            )
            var candidate = cadDocument
            for feature in features {
                try candidate.appendFeature(feature, tolerance: modelingSettings.tolerance)
            }
            var feature = try FeatureNodeFactory.make(
                operation: .edgeMove(move), id: FeatureID(), in: candidate, tolerance: modelingSettings.tolerance
            )
            feature.name = targets.count == 1 ? "Move Edge" : "Move Edges"
            features.append(feature)
            bodyFeatureID = feature.id
        }
        guard let primaryFeatureID = bodyFeatureID else {
            throw EditorError(code: .commandInvalid, message: "Move Edges needs at least one edge.")
        }

        let previous = self
        var didCommit = false
        defer { if !didCommit { self = previous } }
        try appendTopologyEdit(
            FeatureGraphTransaction(features: features, primaryFeatureID: primaryFeatureID),
            replacing: first, objectRegistry: objectRegistry
        )
        do {
            _ = try DocumentEvaluationContextResolver().exactEvaluatedDocument(
                document: self, objectRegistry: objectRegistry,
                currentEvaluation: nil, currentGeneration: nil,
                failurePrefix: "Move Edges"
            )
        } catch let error as EditorError {
            throw EditorError(code: .commandInvalid, message: error.message)
        }
        didCommit = true
    }
}

extension DesignDocument {
    /// The edges `targets` became after the features up to `featureID` changed their body,
    /// followed through the kernel's lineage, so a selection survives Move Edges. An edge with no
    /// single descendant is left out.
    public func edgeTargets(
        following targets: [SelectionTarget],
        to featureID: FeatureID,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SelectionTarget] {
        let evaluated = try DocumentEvaluationContextResolver().exactEvaluatedDocument(
            document: self, objectRegistry: objectRegistry, failurePrefix: "Move Edges selection"
        )
        var children: [SubshapeID: [SubshapeID]] = [:]
        for lineage in evaluated.lineage.values {
            for parent in lineage.parents { children[parent, default: []].append(lineage.output) }
        }
        return targets.compactMap { target in
            guard case .edge(let componentID) = target.component,
                  var current = componentID.generatedTopologySubshapeID else { return nil }
            var visited: Set<SubshapeID> = [current]
            while current.featureID != featureID {
                guard let next = children[current], next.count == 1, visited.insert(next[0]).inserted else { return nil }
                current = next[0]
            }
            return SelectionTarget(sceneNodeID: target.sceneNodeID, component: .edge(.generatedTopology(current)))
        }
    }
}
