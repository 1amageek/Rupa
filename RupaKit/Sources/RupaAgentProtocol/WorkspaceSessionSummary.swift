import Foundation
import RupaCore

public struct WorkspaceSessionSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let path: String?
    public let displayName: String
    public let dirty: Bool
    public let authority: AgentProjectAuthorityCoordinate

    public init(
        id: UUID,
        path: String?,
        displayName: String,
        dirty: Bool,
        authority: AgentProjectAuthorityCoordinate
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.dirty = dirty
        self.authority = authority
    }
}
