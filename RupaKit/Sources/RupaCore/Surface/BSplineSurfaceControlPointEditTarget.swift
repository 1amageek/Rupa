import SwiftCAD

public struct BSplineSurfaceControlPointEditTarget: Equatable, Hashable, Sendable {
    public var featureID: FeatureID
    public var uIndex: Int
    public var vIndex: Int

    public init(
        featureID: FeatureID,
        uIndex: Int,
        vIndex: Int
    ) {
        self.featureID = featureID
        self.uIndex = uIndex
        self.vIndex = vIndex
    }
}
