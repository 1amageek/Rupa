import Foundation

/// Launches or foregrounds the application that owns a live project.
@MainActor
public protocol LiveProjectApplicationLaunching: Sendable {
    /// The caller supplies the one absolute deadline for launch and readiness.
    func launch(
        projectURL: URL,
        deadline: ContinuousClock.Instant
    ) async throws
}
