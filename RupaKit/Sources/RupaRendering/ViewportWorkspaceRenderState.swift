import RupaCore
import RupaViewportScene

public struct ViewportWorkspaceRenderState: Equatable, Sendable {
    public let revision: WorkspaceRevision
    public let ruler: RulerConfiguration
    public let sceneOverlayState: ViewportSceneOverlayState

    public init(
        revision: WorkspaceRevision,
        ruler: RulerConfiguration,
        sceneOverlayState: ViewportSceneOverlayState = .empty
    ) {
        self.revision = revision
        self.ruler = ruler.normalizedForWorkspaceScale()
        self.sceneOverlayState = sceneOverlayState
    }
}
