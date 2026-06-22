import Foundation

public struct SelectionTarget: Codable, Equatable, Hashable, Sendable {
    public var sceneNodeID: SceneNodeID
    public var component: SelectionComponent

    public init(
        sceneNodeID: SceneNodeID,
        component: SelectionComponent = .object
    ) {
        self.sceneNodeID = sceneNodeID
        self.component = component
    }
}
