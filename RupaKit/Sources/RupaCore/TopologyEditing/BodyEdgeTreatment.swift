import SwiftCAD
import RupaCoreTypes

/// Native B-rep treatment; no display subdivision is part of this source intent.
public enum BodyEdgeTreatment: Codable, Equatable, Sendable, TopologyEditOperation {
    case fillet(radius: CADExpression)
    case chamfer(distance: CADExpression)
    case g2Blend(distance: CADExpression)

    static var selectionKind: TopologySummaryResult.Entry.Kind { .edge }

    func featureOperation(sourceID: FeatureID, reference: StableSubshapeReference,
                          in document: DesignDocument) throws -> FeatureOperation {
        let amount: CADExpression
        let operation: FeatureOperation
        switch self {
        case .fillet(let radius):
            amount = radius
            operation = .fillet(.init(target: .init(featureID: sourceID), edges: [reference], radius: radius))
        case .chamfer(let distance):
            amount = distance
            operation = .chamfer(.init(target: .init(featureID: sourceID), edges: [reference], distance: distance))
        case .g2Blend(let distance):
            amount = distance
            operation = .g2Blend(.init(target: .init(featureID: sourceID), edges: [reference], distance: distance))
        }
        guard try document.resolvedPositiveLengthValue(amount, owner: "Edge treatment amount") > document.modelingSettings.tolerance.distance else {
            throw EditorError(code: .commandInvalid, message: "Edge treatment amount must exceed modeling tolerance.")
        }
        return operation
    }
}
