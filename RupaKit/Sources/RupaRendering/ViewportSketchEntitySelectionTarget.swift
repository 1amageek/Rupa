import RupaCore
import SwiftCAD

public struct ViewportSketchEntitySelectionTarget: Equatable, Sendable {
    public var featureID: FeatureID
    public var entityID: SketchEntityID

    public init(featureID: FeatureID, entityID: SketchEntityID) {
        self.featureID = featureID
        self.entityID = entityID
    }
}
