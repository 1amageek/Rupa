import Foundation
import RupaCoreTypes

@MainActor
protocol ApplicationAgentProjectLifecycle: AnyObject {
    func save(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    ) async throws -> ApplicationAgentSaveOutcome
}
