import SwiftCAD

public struct PolySplineSurfaceControlPointEditTarget: Equatable, Hashable, Sendable {
    public var featureID: FeatureID
    public var patchID: Int
    public var uIndex: Int
    public var vIndex: Int

    public init(
        featureID: FeatureID,
        patchID: Int,
        uIndex: Int,
        vIndex: Int
    ) {
        self.featureID = featureID
        self.patchID = patchID
        self.uIndex = uIndex
        self.vIndex = vIndex
    }

    public var address: PolySplineSurfaceControlPointAddress {
        PolySplineSurfaceControlPointAddress(
            patchID: patchID,
            uIndex: uIndex,
            vIndex: vIndex
        )
    }
}
