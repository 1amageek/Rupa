import CoreGraphics
import Observation
import RupaRendering

/// Retains the latest command frame without invalidating workspace chrome on pan.
@MainActor
@Observable
final class WorkspaceViewportCameraState {
    @ObservationIgnored private(set) var frame: ViewportCameraFrame?
    private(set) var zoom: CGFloat?
    private(set) var isReady = false

    func update(_ frame: ViewportCameraFrame?) {
        self.frame = frame
        let zoom = frame?.camera.zoom
        if self.zoom != zoom { self.zoom = zoom }
        if isReady != (frame != nil) { isReady = frame != nil }
    }
}
