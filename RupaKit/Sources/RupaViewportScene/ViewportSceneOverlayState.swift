import RupaCore

public struct ViewportSceneOverlayState: Equatable, Sendable {
    public var curveCurvatureDisplays: [SelectionComponentID: CurveCurvatureDisplay]
    public var pointDisplays: [SelectionComponentID: PointDisplay]
    public var surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay]
    public var surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay]

    public init(
        curveCurvatureDisplays: [SelectionComponentID: CurveCurvatureDisplay] = [:],
        pointDisplays: [SelectionComponentID: PointDisplay] = [:],
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay] = [:],
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay] = [:]
    ) {
        self.curveCurvatureDisplays = curveCurvatureDisplays
        self.pointDisplays = pointDisplays
        self.surfaceControlPointDisplays = surfaceControlPointDisplays
        self.surfaceFrameDisplays = surfaceFrameDisplays
    }

    public static let empty = ViewportSceneOverlayState()
}
