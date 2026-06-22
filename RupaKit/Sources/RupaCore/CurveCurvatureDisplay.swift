import Foundation
import SwiftCAD

public struct CurveCurvatureDisplay: Codable, Hashable, Sendable {
    public static let defaultCombScale = 0.1

    public var componentID: SelectionComponentID
    public var combScale: Double

    public init(
        componentID: SelectionComponentID,
        combScale: Double = Self.defaultCombScale
    ) {
        self.componentID = componentID
        self.combScale = combScale
    }

    public func validate(against cadDocument: CADDocument) throws {
        guard combScale.isFinite,
              combScale > 0.0 else {
            throw DocumentValidationError.invalidProductMetadata(
                "Curve curvature display comb scale must be positive and finite."
            )
        }
        guard let reference = componentID.sketchEntityReference,
              let feature = cadDocument.designGraph.nodes[reference.featureID],
              case .sketch(let sketch) = feature.operation,
              let entity = sketch.entities[reference.entityID] else {
            throw DocumentValidationError.invalidProductMetadata(
                "Curve curvature displays must point to existing source sketch entities."
            )
        }
        switch entity {
        case .line,
             .circle,
             .arc,
             .spline:
            return
        case .point:
            throw DocumentValidationError.invalidProductMetadata(
                "Curve curvature displays require source curve entities, not points."
            )
        }
    }
}
