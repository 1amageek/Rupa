import RupaCore

public enum ViewportConstructionPlaneHandleKind: String, Equatable, Sendable {
    case origin
    case normal
}

public struct ViewportConstructionPlaneDragTarget: Equatable, Sendable {
    public var constructionPlaneID: ConstructionPlaneSourceID
    public var sceneNodeID: SceneNodeID
    public var handle: ViewportConstructionPlaneHandleKind
    public var origin: Point3D
    public var normal: Vector3D

    public init(
        constructionPlaneID: ConstructionPlaneSourceID,
        sceneNodeID: SceneNodeID,
        handle: ViewportConstructionPlaneHandleKind,
        origin: Point3D,
        normal: Vector3D
    ) {
        self.constructionPlaneID = constructionPlaneID
        self.sceneNodeID = sceneNodeID
        self.handle = handle
        self.origin = origin
        self.normal = normal
    }
}
