import Foundation
import SwiftCAD

public struct BridgeCurveSource: Codable, Hashable, Identifiable, Sendable {
    public var id: BridgeCurveSourceID
    public var featureID: FeatureID
    public var entityID: SketchEntityID
    public var firstEndpoint: BridgeCurveEndpoint
    public var secondEndpoint: BridgeCurveEndpoint
    public var continuity: BridgeCurveContinuity
    public var trimsSourceCurves: Bool

    public init(
        id: BridgeCurveSourceID = BridgeCurveSourceID(),
        featureID: FeatureID,
        entityID: SketchEntityID,
        firstEndpoint: BridgeCurveEndpoint,
        secondEndpoint: BridgeCurveEndpoint,
        continuity: BridgeCurveContinuity,
        trimsSourceCurves: Bool = false
    ) {
        self.id = id
        self.featureID = featureID
        self.entityID = entityID
        self.firstEndpoint = firstEndpoint
        self.secondEndpoint = secondEndpoint
        self.continuity = continuity
        self.trimsSourceCurves = trimsSourceCurves
    }
}
