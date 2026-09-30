import Foundation
import SwiftCAD
import RupaCoreTypes

/// A world motion of edges, faces or vertices of one body, read as the kernel's direct edit in the
/// body's own frame: a Move by how far it carries the pivot, a Rotate or Scale by the whole motion.
///
/// The Move/Rotate/Scale session builds its commands from it, and the viewport previews a gizmo
/// drag by applying it to a copy of the document, so a drag previews exactly what it commits.
public struct BodyTopologyWorldMotion: Equatable, Sendable {
    /// How the motion reaches the kernel.
    public enum Form: Equatable, Sendable {
        /// The pivot's translation, as a direct move of the targets.
        case translation
        /// The whole motion, as a topology transform of the targets.
        case transform
    }

    public var kind: BodyTopologyMoveKind
    public var targets: [SelectionTarget]
    /// The world transform of the targets' body.
    public var bodyWorldTransform: Transform3D
    /// The world point a Move's translation is read at.
    public var pivot: Point3D
    public var form: Form

    public init(kind: BodyTopologyMoveKind, targets: [SelectionTarget], bodyWorldTransform: Transform3D, pivot: Point3D, form: Form) {
        self.kind = kind
        self.targets = targets
        self.bodyWorldTransform = bodyWorldTransform
        self.pivot = pivot
        self.form = form
    }

    /// The command moving the targets by `worldDelta`.
    public func command(worldDelta: Transform3D) throws -> EditorCommand {
        guard targets.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(kind.title) needs something to move.")
        }
        switch form {
        case .transform:
            let local = try bodyWorldTransform.inverse().composed(with: worldDelta.composed(with: bodyWorldTransform))
            return .transformBodyTopology(kind: kind, targets: targets, motion: try TopologyMotionDecomposition.motion(local))
        case .translation:
            let world = try worldDelta.applied(to: pivot) - pivot
            let local = try bodyWorldTransform.inverseApplyingLinearPart(to: world)
            guard local.length > ModelingTolerance.standard.distance else {
                throw EditorError(code: .commandInvalid, message: "\(kind.title) needs a motion.")
            }
            let direction = try local.normalized(tolerance: ModelingTolerance.standard.distance)
            let distance = CADExpression.length(local.length, .meter)
            switch kind {
            case .edges: return .moveBodyEdges(targets: targets, direction: direction, distance: distance)
            case .faces: return .moveBodyFaces(targets: targets, direction: direction, distance: distance)
            case .vertices: return .moveBodyVertices(targets: targets, direction: direction, distance: distance)
            }
        }
    }

    /// `document` with the targets moved by `worldDelta`, as `command(worldDelta:)` would leave it.
    public func apply(
        worldDelta: Transform3D,
        to document: inout DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws {
        switch try command(worldDelta: worldDelta) {
        case .moveBodyEdges(let targets, let direction, let distance),
             .moveBodyFaces(let targets, let direction, let distance),
             .moveBodyVertices(let targets, let direction, let distance):
            try document.moveBodyTopology(
                kind, targets: targets, direction: direction, distance: distance, objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
            )
        case .transformBodyTopology(let kind, let targets, let motion):
            try document.transformBodyTopology(
                kind, targets: targets, motion: motion, objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
            )
        default:
            throw EditorError(code: .commandInvalid, message: "A topology motion made a command that is not a topology edit.")
        }
    }
}
