import Synchronization

/// GPU completion and the mounted MainActor share only this isolated status.
final class OpticalVolumeFrameStatus: Sendable {
    private struct State: Sendable {
        var failure: MeshSourcePresentationRenderError?
        var completedFrameCount: UInt64 = 0
        var preparationPending = false
    }
    private let state = Mutex(State())

    func fail(_ error: MeshSourcePresentationRenderError) {
        state.withLock { if $0.failure == nil { $0.failure = error } }
    }

    func deferForPreparation() { state.withLock { $0.preparationPending = true } }

    func complete() {
        state.withLock {
            if $0.failure == nil, $0.completedFrameCount < UInt64.max {
                $0.completedFrameCount += 1; $0.preparationPending = false
            }
        }
    }

    var failure: MeshSourcePresentationRenderError? { state.withLock { $0.failure } }
    var isReady: Bool { state.withLock { $0.failure == nil && !$0.preparationPending && $0.completedFrameCount > 0 } }

    func check() throws {
        let error = state.withLock { $0.failure }
        if let error { throw error }
    }
}
