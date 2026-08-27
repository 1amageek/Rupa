import RupaKit

/// Wire-safe Mesh element page projected from the project use case.
public struct AgentMeshPage: Codable, Equatable, Sendable {
    public let handle: ProjectMeshSourceHandle
    public let domain: ProjectMeshElementDomain
    public let records: [ProjectMeshElementRecord]
    public let nextCursor: ProjectMeshElementCursor?

    public init(
        handle: ProjectMeshSourceHandle,
        domain: ProjectMeshElementDomain,
        records: [ProjectMeshElementRecord],
        nextCursor: ProjectMeshElementCursor?
    ) {
        self.handle = handle
        self.domain = domain
        self.records = records
        self.nextCursor = nextCursor
    }
}
