import SwiftCAD

public struct PatternArrayExplodeResult: Codable, Equatable, Sendable {
    public var componentInstanceIDs: [ComponentInstanceID]
    public var sceneNodeIDs: [SceneNodeID]
    public var featureIDs: [FeatureID]

    public init(
        componentInstanceIDs: [ComponentInstanceID] = [],
        sceneNodeIDs: [SceneNodeID] = [],
        featureIDs: [FeatureID] = []
    ) {
        self.componentInstanceIDs = componentInstanceIDs
        self.sceneNodeIDs = sceneNodeIDs
        self.featureIDs = featureIDs
    }
}
