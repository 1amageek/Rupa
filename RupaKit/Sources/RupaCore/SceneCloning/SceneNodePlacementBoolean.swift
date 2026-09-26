import SwiftCAD

/// A Boolean each placed copy makes with the body it was placed on; the copy is the tool and is
/// consumed.
public struct SceneNodePlacementBoolean: Codable, Hashable, Sendable {
    public var operation: BooleanOperation
    /// The scene node presenting the body the copies are combined with.
    public var targetSceneNodeID: SceneNodeID

    public init(operation: BooleanOperation, targetSceneNodeID: SceneNodeID) {
        self.operation = operation
        self.targetSceneNodeID = targetSceneNodeID
    }
}
