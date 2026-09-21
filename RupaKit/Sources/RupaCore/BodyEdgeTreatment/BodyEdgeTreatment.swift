import SwiftCAD

/// Native B-rep treatment; no display subdivision is part of this source intent.
public enum BodyEdgeTreatment: Codable, Equatable, Sendable {
    case fillet(radius: CADExpression)
    case chamfer(distance: CADExpression)
    case g2Blend(distance: CADExpression)
}
