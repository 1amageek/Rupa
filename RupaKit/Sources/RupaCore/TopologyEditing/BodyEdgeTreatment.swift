import SwiftCAD
import RupaCoreTypes

/// Native B-rep treatment; no display subdivision is part of this source intent.
public enum BodyEdgeTreatment: Codable, Equatable, Sendable, TopologyEditOperation {
    case fillet(radius: CADExpression)
    /// Fillet Shell's conic, chordal or curvature shape at `distance`, its tension where it takes one.
    case shapedFillet(distance: CADExpression, shape: FilletShape, tension: Double?)
    case chamfer(distance: CADExpression)
    case g2Blend(distance: CADExpression)
    /// Fillet Shell's Full shape: the round across the face between the target edge and `across`,
    /// tangent to it and both faces beside it; its size comes from those faces.
    case fullFillet(across: SelectionTarget)

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
