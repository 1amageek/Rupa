import SwiftCAD
import RupaCoreTypes

/// Native B-rep treatment; no display subdivision is part of this source intent.
public indirect enum BodyEdgeTreatment: Codable, Equatable, Sendable, TopologyEditOperation {
    case fillet(radius: CADExpression)
    /// Fillet Shell's conic, chordal or curvature shape at `distance`, its tension where it takes one.
    case shapedFillet(distance: CADExpression, shape: FilletShape, tension: Double?)
    /// A chamfer at `distance` by `mode`, or at `angle` from its reference face (each edge's
    /// first face, its second when `flipped`), over the stretch of the edge between its `limits`
    /// when it has them.
    case chamfer(distance: CADExpression, mode: ChamferMode = .offset, angle: CADExpression? = nil, flipped: Bool = false,
                 limits: EdgeBlendLimits? = nil)
    case g2Blend(distance: CADExpression)
    /// Fillet Shell's Full shape: the round across the face between the target edge and `across`,
    /// tangent to it and both faces beside it; its size comes from those faces.
    case fullFillet(across: SelectionTarget)
    /// A fillet of `shape` (tension where it takes one) varying from `radius` at the edge's start to
    /// `endRadius` at its end.
    /// `points` set the radius between the ends, the radius following the natural cubic law through them.
    case variableFillet(radius: CADExpression, endRadius: CADExpression, shape: FilletShape, tension: Double?,
                        points: [FilletVariablePoint] = [])
    /// A constant fillet of `shape` (tension where it takes one) over the stretch of the edge
    /// between its `limits`, the edge left sharp beyond them.
    case limitedFillet(distance: CADExpression, shape: FilletShape, tension: Double?, limits: EdgeBlendLimits)
    /// `treatment` of the target edge and of `more` edges of the same body, which must not meet it
    /// or each other at a corner.
    case several(BodyEdgeTreatment, more: [SelectionTarget])
    /// A fillet or chamfer `treatment` with Fillet Shell's Tangent Edges off: only the selected
    /// edges, not the edges continuing them tangentially.
    case tangentEdgesOff(BodyEdgeTreatment)

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
        case .chamfer(let distance, let mode, let angle, let flipped, let limits):
            amount = distance
            let chamfer = ChamferFeature(target: .init(featureID: sourceID), edges: [reference], distance: distance,
                                         mode: mode, angle: angle, flipped: flipped, limits: limits)
            do { try chamfer.validate() } catch {
                throw EditorError(code: .commandInvalid, message: "The chamfer is invalid: \(error).")
            }
            if let angle {
                let value = try document.resolvedAngleValue(angle, owner: "Chamfer angle")
                guard value > 0, value < .pi else {
                    throw EditorError(code: .commandInvalid, message: "A chamfer's angle lies strictly between 0° and 180°.")
                }
            }
            operation = .chamfer(chamfer)
        case .g2Blend(let distance):
            amount = distance
            operation = .g2Blend(.init(target: .init(featureID: sourceID), edges: [reference], distance: distance))
        case .variableFillet(let radius, let endRadius, let shape, let tension, let points):
            amount = radius
            let fillet = FilletFeature(target: .init(featureID: sourceID), edges: [reference], radius: radius,
                                       shape: shape, tension: tension, endRadius: endRadius, variablePoints: points)
            for point in points {
                guard try document.resolvedPositiveLengthValue(point.radius, owner: "Fillet variable point radius")
                        > document.modelingSettings.tolerance.distance else {
                    throw EditorError(code: .commandInvalid, message: "A fillet's variable point radius must exceed modeling tolerance.")
                }
            }
            do { try fillet.validate() } catch {
                throw EditorError(code: .commandInvalid, message: "The fillet is invalid: \(error).")
            }
            guard try document.resolvedPositiveLengthValue(endRadius, owner: "Fillet end radius") > document.modelingSettings.tolerance.distance else {
                throw EditorError(code: .commandInvalid, message: "Fillet end radius must exceed modeling tolerance.")
            }
            operation = .fillet(fillet)
        case .limitedFillet(let distance, let shape, let tension, let limits):
            amount = distance
            let fillet = FilletFeature(target: .init(featureID: sourceID), edges: [reference], radius: distance,
                                       shape: shape, tension: tension, limits: limits)
            do { try fillet.validate() } catch {
                throw EditorError(code: .commandInvalid, message: "The fillet is invalid: \(error).")
            }
            operation = .fillet(fillet)
        case .several:
            // The further edges are resolved by `DesignDocument.prepareBodyEdgeTreatment` into
            // `SeveralEdgeTreatment`, which builds the feature.
            throw EditorError(code: .commandInvalid, message: "Several edges are prepared with all of their edges.")
        case .tangentEdgesOff(let base):
            switch try base.featureOperation(sourceID: sourceID, reference: reference, in: document) {
            case .fillet(let fillet) where fillet.shape != .full:
                return .fillet(fillet.with(tangentEdges: false))
            case .chamfer(let chamfer):
                return .chamfer(chamfer.with(tangentEdges: false))
            default:
                throw EditorError(code: .commandInvalid, message: "Tangent Edges turns off for fillets and chamfers.")
            }
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
            let several = fillet.with(edges: edges)
            do { try several.validate() } catch {
                throw EditorError(code: .commandInvalid, message: "The fillet is invalid: \(error).")
            }
            return .fillet(several)
        case .chamfer(let chamfer):
            return .chamfer(chamfer.with(edges: edges))
        case .g2Blend(let blend):
            return .g2Blend(.init(target: blend.target, edges: edges, distance: blend.distance))
        default:
            throw EditorError(code: .commandInvalid, message: "This edge treatment takes one edge.")
        }
    }
}
