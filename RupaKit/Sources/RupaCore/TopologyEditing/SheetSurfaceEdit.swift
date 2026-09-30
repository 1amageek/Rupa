import SwiftCAD

public enum SheetSurfaceEdit: Codable, Equatable, Sendable, TopologyEditOperation {
    case offset(distance: CADExpression)
    case extend(uDomain: ParameterDomain, vDomain: ParameterDomain)
    /// Thicken: the sheet grown `front` along its normal and `back` against it.
    case thicken(front: CADExpression, back: CADExpression)

    static var selectionKind: TopologySummaryResult.Entry.Kind { .face }

    func featureOperation(sourceID: FeatureID, reference: StableSubshapeReference,
                          in document: DesignDocument) throws -> FeatureOperation {
        let target = SurfaceOperationTargetReference(featureID: sourceID, face: reference)
        switch self {
        case .offset(let distance):
            return .surfaceOffset(.init(target: target, distance: distance))
        case .extend(let uDomain, let vDomain):
            return .surfaceExtend(.init(target: target, uDomain: uDomain, vDomain: vDomain))
        case .thicken(let front, let back):
            return .thicken(.init(target: .init(featureID: sourceID), front: front, back: back))
        }
    }
}
