import Foundation
import RupaAgentUI
import RupaKit

@MainActor
protocol ApplicationAgentSessionRegistering: AnyObject {
    func register(
        workspace: ProjectWorkspace,
        path: URL?,
        id: UUID
    ) async throws -> UUID

    func updatePath(id: UUID, path: URL?) async throws

    func unregister(id: UUID) async
}

extension AgentHost: ApplicationAgentSessionRegistering {}
