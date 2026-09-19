import Foundation
import RupaCoreTypes

/// Saves the application-owned project through the owner that holds it.
///
/// The protocol refines `Sendable` so a control-plane adapter that is not
/// isolated to a global actor can retain one and suspend into it explicitly.
/// Conformers are `MainActor`-isolated classes, which already satisfy that
/// requirement.
@MainActor
protocol ApplicationAgentProjectLifecycle: AnyObject, Sendable {
    func save(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    ) async throws -> ApplicationAgentSaveOutcome
}
