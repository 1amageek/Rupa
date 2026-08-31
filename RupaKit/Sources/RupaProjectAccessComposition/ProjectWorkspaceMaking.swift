import RupaKit

/// Supplies the temporary workspace used by a closed project access session.
///
/// The composition owns this seam so tests can exercise load, command, and
/// save failures without introducing a second project or package authority.
@MainActor
public protocol ProjectWorkspaceMaking: Sendable {
    func makeWorkspace() throws -> ProjectWorkspace
}
