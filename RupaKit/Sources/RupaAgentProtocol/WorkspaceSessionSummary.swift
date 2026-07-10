import Foundation
import RupaCore

public struct WorkspaceSessionSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var path: String?
    public var displayName: String
    public var dirty: Bool
    public var generation: DocumentGeneration
    public var workspaceRevision: WorkspaceRevision

    public init(
        id: UUID,
        path: String?,
        displayName: String,
        dirty: Bool,
        generation: DocumentGeneration,
        workspaceRevision: WorkspaceRevision
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.dirty = dirty
        self.generation = generation
        self.workspaceRevision = workspaceRevision
    }
}
