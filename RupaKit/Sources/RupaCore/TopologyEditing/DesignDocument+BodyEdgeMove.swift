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

    /// What the targets are called: "Edges", "Faces" or "Vertices".
    public var noun: String {
        switch self {
        case .edges: "Edges"
        case .faces: "Faces"
        case .vertices: "Vertices"
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

    /// Moves edges, faces or vertices of one body through the kernel's direct edits.
    ///
    /// One target becomes that kind's own kernel move. Several become one kernel topology
    /// transform, so a vertex they share moves once. The kernel owns what can move: it re-solves
    /// the faces around the moved vertices (planes, or bilinear patches where a four-sided face
    /// warps) and moves a circular edge along its axis with the cap it bounds. The candidate is
    /// evaluated before it is kept, so a move the kernel cannot make refuses the command and the
    /// document stays as it was.
    public mutating func moveBodyTopology(
        _ kind: BodyTopologyMoveKind,
        targets: [SelectionTarget],
        direction: Vector3D,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws {
        let unit: Vector3D
        do {
            unit = try direction.normalized(tolerance: modelingSettings.tolerance.distance)
        } catch {
            throw EditorError(code: .commandInvalid, message: "\(kind.title) needs a direction.")
        }
        let translation = DirectMoveVector(direction: unit, distance: distance)
        if let surfaceID = directSurfaceSource(for: targets) {
            try editSurfaceBoundary(
                kind, targets: targets, featureID: surfaceID,
                motion: try TopologyMotionDecomposition.transform(.translation(translation), parameters: cadDocument.parameters),
                objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
            )
            return
        }
        let selections = try topologySelections(
            kind, targets: targets, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        guard selections.references.count == 1, let reference = selections.references.first else {
            try appendTopologyTransform(
                selections, motion: .translation(translation), name: kind.title, objectRegistry: objectRegistry
            )
            return
        }
        let source = selections.sourceID
        let operation: FeatureOperation = switch kind {
        case .edges:
            .edgeMove(EdgeMoveFeature(target: EdgeMoveTargetReference(featureID: source), edge: reference, translation: translation))
        case .faces:
            .faceMove(FaceMoveFeature(target: FaceMoveTargetReference(featureID: source), face: reference, translation: translation))
        case .vertices:
            .vertexMove(VertexMoveFeature(target: VertexMoveTargetReference(featureID: source), vertex: reference, translation: translation))
        }
        try appendDirectEdit(operation, name: kind.singularTitle, selections: selections, objectRegistry: objectRegistry)
    }

    /// Rotates or scales (or moves) edges, faces or vertices of one body together by `motion`, in
    /// the body's own frame, through one kernel topology transform.
    public mutating func transformBodyTopology(
        _ kind: BodyTopologyMoveKind,
        targets: [SelectionTarget],
        motion: TopologyMotion,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws {
        if let surfaceID = directSurfaceSource(for: targets) {
            try editSurfaceBoundary(
                kind, targets: targets, featureID: surfaceID,
                motion: try TopologyMotionDecomposition.transform(motion, parameters: cadDocument.parameters),
                objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
            )
            return
        }
        let selections = try topologySelections(
            kind, targets: targets, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let verb = switch motion {
        case .translation: "Move"
        case .rotation: "Rotate"
        case .scale: "Scale"
        }
        try appendTopologyTransform(selections, motion: motion, name: "\(verb) \(kind.noun)", objectRegistry: objectRegistry)
    }

    private struct TopologySelections {
        var first: SelectionTarget
        var sourceID: FeatureID
        var references: [StableSubshapeReference]
    }

    /// The kernel references of `targets`, which must all be `kind` on one body, without repeats.
    private func topologySelections(
        _ kind: BodyTopologyMoveKind,
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) throws -> TopologySelections {
        guard let first = targets.first else {
            throw EditorError(code: .commandInvalid, message: "\(kind.title) needs at least one target.")
        }
        guard targets.allSatisfy({ $0.sceneNodeID == first.sceneNodeID }) else {
            throw EditorError(code: .commandInvalid, message: "\(kind.title) moves the parts of one body at a time.")
        }
        var sourceID: FeatureID?
        var references: [StableSubshapeReference] = []
        var seen: Set<SubshapeID> = []
        for target in targets {
            let selection = try topologyEditSelection(
                target, kind: kind.componentKind, objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
            )
            sourceID = sourceID ?? selection.sourceID
            guard seen.insert(selection.reference.subshapeID).inserted else { continue }
            references.append(selection.reference)
        }
        guard let sourceID else {
            throw EditorError(code: .commandInvalid, message: "\(kind.title) needs at least one target.")
        }
        return TopologySelections(first: first, sourceID: sourceID, references: references)
    }

    private mutating func appendTopologyTransform(
        _ selections: TopologySelections,
        motion: TopologyMotion,
        name: String,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        try appendDirectEdit(
            .topologyTransform(TopologyTransformFeature(
                target: TopologyTransformTargetReference(featureID: selections.sourceID),
                subshapes: selections.references,
                motion: motion
            )),
            name: name, selections: selections, objectRegistry: objectRegistry
        )
    }

    /// Appends one direct-edit feature on the selections' body and keeps it only if the document
    /// still evaluates.
    private mutating func appendDirectEdit(
        _ operation: FeatureOperation,
        name: String,
        selections: TopologySelections,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        var feature = try FeatureNodeFactory.make(
            operation: operation, id: FeatureID(), in: cadDocument, tolerance: modelingSettings.tolerance
        )
        feature.name = name
        let previous = self
        var didCommit = false
        defer { if !didCommit { self = previous } }
        try appendTopologyEdit(
            FeatureGraphTransaction(features: [feature], primaryFeatureID: feature.id),
            replacing: selections.first, objectRegistry: objectRegistry
        )
        do {
            _ = try DocumentEvaluationContextResolver().exactEvaluatedDocument(
                document: self, objectRegistry: objectRegistry,
                currentEvaluation: nil, currentGeneration: nil,
                failurePrefix: name
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
