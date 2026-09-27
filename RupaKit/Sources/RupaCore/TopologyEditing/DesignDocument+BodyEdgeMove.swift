import SwiftCAD
import RupaCoreTypes

/// The topology a Move Edges, Move Faces or Move Vertices command moves.
public enum BodyTopologyMoveKind: String, Codable, Equatable, Sendable {
    case edges
    case faces
    case vertices

    var componentKind: TopologySummaryResult.Entry.Kind {
        switch self {
        case .edges: .edge
        case .faces: .face
        case .vertices: .vertex
        }
    }

    public var title: String {
        switch self {
        case .edges: "Move Edges"
        case .faces: "Move Faces"
        case .vertices: "Move Vertices"
        }
    }

    public var singularTitle: String {
        switch self {
        case .edges: "Move Edge"
        case .faces: "Move Face"
        case .vertices: "Move Vertex"
        }
    }
}

extension DesignDocument {
    /// Move Edges: moves the selected edges of one body by `distance` along `direction`
    /// (world-aligned in the body's own frame), one kernel `EdgeMoveFeature` per edge, chained so
    /// each moves the body the previous one made.
    public mutating func moveBodyEdges(
        targets: [SelectionTarget],
        direction: Vector3D,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws {
        try moveBodyTopology(
            .edges, targets: targets, direction: direction, distance: distance, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
    }

    /// Move Faces: moves the selected planar faces of one body, one kernel `FaceMoveFeature` each.
    public mutating func moveBodyFaces(
        targets: [SelectionTarget],
        direction: Vector3D,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws {
        try moveBodyTopology(
            .faces, targets: targets, direction: direction, distance: distance, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
    }

    /// Move Vertices: moves the selected vertices of one body, one kernel `VertexMoveFeature` each.
    public mutating func moveBodyVertices(
        targets: [SelectionTarget],
        direction: Vector3D,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws {
        try moveBodyTopology(
            .vertices, targets: targets, direction: direction, distance: distance, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
    }

    /// Moves edges, faces or vertices of one body through the kernel's direct edits, one feature
    /// per target chained so each moves the body the previous one made.
    ///
    /// The kernel owns what moves: it re-solves the faces around the moved vertices (planes, or
    /// bilinear patches where a four-sided face warps) and moves a circular edge along its axis
    /// with the cap it bounds. The candidate is evaluated before it is kept, so a move the kernel
    /// cannot make refuses the command and the document stays as it was.
    public mutating func moveBodyTopology(
        _ kind: BodyTopologyMoveKind,
        targets: [SelectionTarget],
        direction: Vector3D,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws {
        guard let first = targets.first else {
            throw EditorError(code: .commandInvalid, message: "\(kind.title) needs at least one target.")
        }
        guard targets.allSatisfy({ $0.sceneNodeID == first.sceneNodeID }) else {
            throw EditorError(code: .commandInvalid, message: "\(kind.title) moves the parts of one body at a time.")
        }
        let unit: Vector3D
        do {
            unit = try direction.normalized(tolerance: modelingSettings.tolerance.distance)
        } catch {
            throw EditorError(code: .commandInvalid, message: "\(kind.title) needs a direction.")
        }

        var features: [FeatureNode] = []
        var bodyFeatureID: FeatureID?
        var seen: Set<SubshapeID> = []
        for target in targets {
            let selection = try topologyEditSelection(
                target, kind: kind.componentKind, objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
            )
            guard seen.insert(selection.reference.subshapeID).inserted else { continue }
            // Each move acts on the body the previous one made; the kernel follows the subshape's
            // lineage from the source body.
            let source = bodyFeatureID ?? selection.sourceID
            let translation = DirectMoveVector(direction: unit, distance: distance)
            let operation: FeatureOperation = switch kind {
            case .edges:
                .edgeMove(EdgeMoveFeature(
                    target: EdgeMoveTargetReference(featureID: source), edge: selection.reference, translation: translation
                ))
            case .faces:
                .faceMove(FaceMoveFeature(
                    target: FaceMoveTargetReference(featureID: source), face: selection.reference, translation: translation
                ))
            case .vertices:
                .vertexMove(VertexMoveFeature(
                    target: VertexMoveTargetReference(featureID: source), vertex: selection.reference, translation: translation
                ))
            }
            var candidate = cadDocument
            for feature in features {
                try candidate.appendFeature(feature, tolerance: modelingSettings.tolerance)
            }
            var feature = try FeatureNodeFactory.make(
                operation: operation, id: FeatureID(), in: candidate, tolerance: modelingSettings.tolerance
            )
            feature.name = targets.count == 1 ? kind.singularTitle : kind.title
            features.append(feature)
            bodyFeatureID = feature.id
        }
        guard let primaryFeatureID = bodyFeatureID else {
            throw EditorError(code: .commandInvalid, message: "\(kind.title) needs at least one target.")
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
                failurePrefix: kind.title
            )
        } catch let error as EditorError {
            throw EditorError(code: .commandInvalid, message: error.message)
        }
        didCommit = true
    }
}

extension DesignDocument {
    /// The edges, faces or vertices `targets` became after the features up to `featureID` changed
    /// their body, followed through the kernel's lineage, so a selection survives a move. A target
    /// with no single descendant is left out.
    public func topologyTargets(
        following targets: [SelectionTarget],
        to featureID: FeatureID,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SelectionTarget] {
        let evaluated = try DocumentEvaluationContextResolver().exactEvaluatedDocument(
            document: self, objectRegistry: objectRegistry, failurePrefix: "Move selection"
        )
        var children: [SubshapeID: [SubshapeID]] = [:]
        for lineage in evaluated.lineage.values {
            for parent in lineage.parents { children[parent, default: []].append(lineage.output) }
        }
        return targets.compactMap { target in
            let componentID: SelectionComponentID
            let component: (SelectionComponentID) -> SelectionComponent
            switch target.component {
            case .edge(let id): componentID = id; component = { .edge($0) }
            case .face(let id): componentID = id; component = { .face($0) }
            case .vertex(let id): componentID = id; component = { .vertex($0) }
            default: return nil
            }
            guard var current = componentID.generatedTopologySubshapeID else { return nil }
            var visited: Set<SubshapeID> = [current]
            while current.featureID != featureID {
                guard let next = children[current], next.count == 1, visited.insert(next[0]).inserted else { return nil }
                current = next[0]
            }
            return SelectionTarget(sceneNodeID: target.sceneNodeID, component: component(.generatedTopology(current)))
        }
    }
}
