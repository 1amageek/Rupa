import SwiftCAD

/// The curve along an edge of a body that a pipe follows or an extrusion sweeps, under the identity
/// the consumer's reference names. It is added without an object of its own: its consumer shows it.
public struct EdgeCurveSource: Codable, Hashable, Sendable {
    public var id: FeatureID
    public var feature: EdgeCurveFeature

    public init(id: FeatureID, feature: EdgeCurveFeature) {
        self.id = id
        self.feature = feature
    }
}
