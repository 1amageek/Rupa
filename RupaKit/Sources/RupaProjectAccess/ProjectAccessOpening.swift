import Foundation

public protocol ProjectAccessOpening: Sendable {
    func open(
        _ target: ProjectAccessTarget,
        deadline: ContinuousClock.Instant
    ) async throws -> any ProjectAccessSession
}
