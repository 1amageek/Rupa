import SwiftCAD
import RupaCoreTypes

/// Native B-rep treatment; no display subdivision is part of this source intent.
public indirect enum BodyEdgeTreatment: Codable, Equatable, Sendable, TopologyEditOperation {
    case fillet(radius: CADExpression)
    /// Fillet Shell's conic, chordal or curvature shape at `distance`, its tension where it takes one.
    case shapedFillet(distance: CADExpression, shape: FilletShape, tension: Double?)
    case chamfer(distance: CADExpression)
    case g2Blend(distance: CADExpression)
    /// Fillet Shell's Full shape: the round across the face between the target edge and `across`,
    /// tangent to it and both faces beside it; its size comes from those faces.
    case fullFillet(across: SelectionTarget)
    /// `treatment` of the target edge and of `more` edges of the same body, which must not meet it
    /// or each other at a corner.
    case several(BodyEdgeTreatment, more: [SelectionTarget])

    static var selectionKind: TopologySummaryResult.Entry.Kind { .edge }

    func featureOperation(sourceID: FeatureID, reference: StableSubshapeReference,
                          in document: DesignDocument) throws -> FeatureOperation {
        let amount: CADExpression
        let operation: FeatureOperation
        switch self {
        case .fillet(let radius):
            amount = radius
            operation = .fillet(.init(target: .init(featureID: sourceID), edges: [reference], radius: radius))
        case .shapedFillet(let distance, let shape, let tension):
            amount = distance
            let fillet = FilletFeature(target: .init(featureID: sourceID), edges: [reference], radius: distance,
                                       shape: shape, tension: tension)
            do { try fillet.validate() } catch {
                throw EditorError(code: .commandInvalid, message: "The fillet is invalid: \(error).")
            }
            operation = .fillet(fillet)
        case .chamfer(let distance):
            amount = distance
            operation = .chamfer(.init(target: .init(featureID: sourceID), edges: [reference], distance: distance))
        case .g2Blend(let distance):
            amount = distance
            operation = .g2Blend(.init(target: .init(featureID: sourceID), edges: [reference], distance: distance))
        case .several:
            // The further edges are resolved by `DesignDocument.prepareBodyEdgeTreatment` into
            // `SeveralEdgeTreatment`, which builds the feature.
            throw EditorError(code: .commandInvalid, message: "Several edges are prepared with all of their edges.")
        case .fullFillet:
            // The second edge is resolved by `DesignDocument.prepareBodyEdgeTreatment` into a
            // `FullFilletEdges`, which builds the feature.
            throw EditorError(code: .commandInvalid, message: "A full fillet is prepared with both of its edges.")
        }
        guard try document.resolvedPositiveLengthValue(amount, owner: "Edge treatment amount") > document.modelingSettings.tolerance.distance else {
            throw EditorError(code: .commandInvalid, message: "Edge treatment amount must exceed modeling tolerance.")
        }
        return operation
    }
}

/// A full fillet with both of its edges resolved: the round across the face between them.
struct FullFilletEdges: TopologyEditOperation {
    let across: StableSubshapeReference
    /// The round's radius, which the faces fix (`FullFilletRadius`) and the feature states.
    let radius: Double

    static var selectionKind: TopologySummaryResult.Entry.Kind { .edge }

    func featureOperation(sourceID: FeatureID, reference: StableSubshapeReference,
                          in document: DesignDocument) throws -> FeatureOperation {
        let fillet = FilletFeature(target: .init(featureID: sourceID), edges: [reference, across],
                                   radius: .length(radius, .meter), shape: .full)
        do { try fillet.validate() } catch {
            throw EditorError(code: .commandInvalid, message: "The full fillet is invalid: \(error).")
        }
        return .fillet(fillet)
    }
}

/// An edge treatment with its further edges resolved: the same treatment of every edge.
struct SeveralEdgeTreatment: TopologyEditOperation {
    let base: BodyEdgeTreatment
    let more: [StableSubshapeReference]

    static var selectionKind: TopologySummaryResult.Entry.Kind { .edge }

    func featureOperation(sourceID: FeatureID, reference: StableSubshapeReference,
                          in document: DesignDocument) throws -> FeatureOperation {
        let edges = [reference] + more
        switch try base.featureOperation(sourceID: sourceID, reference: reference, in: document) {
        case .fillet(let fillet):
            let several = FilletFeature(target: fillet.target, edges: edges, radius: fillet.radius, shape: fillet.shape,
                                        tension: fillet.tension)
            do { try several.validate() } catch {
                throw EditorError(code: .commandInvalid, message: "The fillet is invalid: \(error).")
            }
            return .fillet(several)
        case .chamfer(let chamfer):
            return .chamfer(.init(target: chamfer.target, edges: edges, distance: chamfer.distance))
        case .g2Blend(let blend):
            return .g2Blend(.init(target: blend.target, edges: edges, distance: blend.distance))
        default:
            throw EditorError(code: .commandInvalid, message: "This edge treatment takes one edge.")
        }
    }
}
