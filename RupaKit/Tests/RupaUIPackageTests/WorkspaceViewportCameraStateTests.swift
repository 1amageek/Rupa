import Observation
import Synchronization
import RupaCore
import RupaRendering
import Testing
@testable import RupaUI

@MainActor
@Test
func workspaceCameraPanRetainsLatestFrameWithoutInvalidatingChrome() {
    let state = WorkspaceViewportCameraState()
    let changed = Mutex(false)
    var frame = ViewportCameraFrame(target: .origin, visibleHeightMeters: 1, camera: .identity)
    state.update(frame)
    withObservationTracking {
        #expect(state.zoom == 1)
    } onChange: {
        changed.withLock { $0 = true }
    }
    frame.target.x = 2
    frame.camera.pan.width = 40
    state.update(frame)
    #expect(state.frame == frame)
    #expect(!changed.withLock { $0 })
    frame.camera.zoom = 2
    state.update(frame)
    #expect(changed.withLock { $0 })
    #expect(state.zoom == 2)
    let readinessChanged = Mutex(false)
    withObservationTracking {
        #expect(state.isReady)
    } onChange: {
        readinessChanged.withLock { $0 = true }
    }
    frame.camera.zoom = 3
    state.update(frame)
    #expect(!readinessChanged.withLock { $0 })
    state.update(nil)
    #expect(readinessChanged.withLock { $0 })
    #expect(!state.isReady)
    #expect(state.frame == nil)
    #expect(state.zoom == nil)
}
