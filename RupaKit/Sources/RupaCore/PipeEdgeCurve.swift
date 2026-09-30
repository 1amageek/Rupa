import SwiftCAD

/// The curve along an edge of a body that a pipe follows, under the identity the pipe's path names.
public struct PipeEdgeCurve: Codable, Hashable, Sendable {
    public var id: FeatureID
    public var feature: EdgeCurveFeature

    public init(id: FeatureID, feature: EdgeCurveFeature) {
        self.id = id
        self.feature = feature
    }
}
