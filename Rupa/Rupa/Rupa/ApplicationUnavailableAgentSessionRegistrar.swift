import Foundation
import RupaKit

@MainActor
final class ApplicationUnavailableAgentSessionRegistrar:
    ApplicationAgentSessionRegistering
{
    func register(
        workspace _: ProjectWorkspace,
        path _: URL?,
        id _: UUID
    ) async throws -> UUID {
        throw ApplicationProjectFailure(
            kind: .launch,
            message: "The application project authority is unavailable."
        )
    }

    func unregister(id _: UUID) async {}

    func updatePath(id _: UUID, path _: URL?) async throws {
        throw ApplicationProjectFailure(
            kind: .launch,
            message: "The application project authority is unavailable."
        )
    }
}
