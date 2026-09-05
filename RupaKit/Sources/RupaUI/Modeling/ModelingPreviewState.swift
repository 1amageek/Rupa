import Foundation
import RupaKit

/// Local UI lifecycle only. Workspace retains all publication authority.
struct ModelingPreviewState {
    enum Request: Sendable {
        case source(ProjectWorkspaceAction)
        case mesh(ProjectMeshEditRequest)
    }

    enum Phase { case idle, evaluating, ready, applying }

    private(set) var token = UUID()
    private(set) var phase = Phase.idle
    private(set) var payload: ProjectPreviewRenderPayload?
    private var request: Request?
    var errorMessage: String?

    var isBusy: Bool { phase == .evaluating || phase == .applying }

    mutating func invalidate() {
        token = UUID()
        phase = .idle
        payload = nil
        request = nil
        errorMessage = nil
    }

    mutating func begin(_ request: Request) -> UUID {
        invalidate()
        self.request = request
        phase = .evaluating
        return token
    }

    mutating func complete(_ payload: ProjectPreviewRenderPayload, token: UUID) {
        guard self.token == token, phase == .evaluating else { return }
        self.payload = payload
        phase = .ready
    }

    mutating func fail(_ error: any Error, token: UUID) {
        guard self.token == token else { return }
        invalidate()
        errorMessage = error.localizedDescription
    }

    mutating func takeForApply() -> Request? {
        guard phase == .ready, let request else { return nil }
        self.request = nil
        phase = .applying
        return request
    }

    mutating func beginConfirmedApply() -> UUID {
        invalidate()
        phase = .applying
        return token
    }
}
