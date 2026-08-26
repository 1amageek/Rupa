import Foundation

/// Identifies one in-memory document lifetime within a project authority.
///
/// Source mutations keep this identity. Loading or replacing the document
/// creates a new identity even when the persisted project ID is unchanged.
public struct ProjectDocumentLifetimeID: Hashable, Sendable {
    private let rawValue: UUID

    public init() {
        rawValue = UUID()
    }
}
