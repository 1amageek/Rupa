import SwiftCAD

/// The two curve ends a Fillet or Chamfer treats at one corner: the selected end and the end it
/// meets. Fillet's viewport handle sits between them.
public struct SketchCornerTreatmentEnds: Equatable, Sendable {
    public struct End: Equatable, Sendable {
        public var entityID: SketchEntityID
        public var handle: SketchEntityPointHandle

        public init(entityID: SketchEntityID, handle: SketchEntityPointHandle) {
            self.entityID = entityID
            self.handle = handle
        }
    }

    public var featureID: FeatureID
    public var selected: End
    public var adjacent: End

    public init(featureID: FeatureID, selected: End, adjacent: End) {
        self.featureID = featureID
        self.selected = selected
        self.adjacent = adjacent
    }
}
