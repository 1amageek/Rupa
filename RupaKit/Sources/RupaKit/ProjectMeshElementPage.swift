import RupaCoreTypes

public struct ProjectMeshElementPageRequest: Sendable {
    public let handle: ProjectMeshSourceHandle
    public let domain: ProjectMeshElementDomain
    public let cursor: ProjectMeshElementCursor?
    public let limits: ProjectMeshReadLimits

    public init(
        handle: ProjectMeshSourceHandle,
        domain: ProjectMeshElementDomain,
        cursor: ProjectMeshElementCursor? = nil,
        limits: ProjectMeshReadLimits = .standard
    ) {
        self.handle = handle
        self.domain = domain
        self.cursor = cursor
        self.limits = limits
    }
}

public struct ProjectMeshElementPage: Sendable, Equatable {
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

    public var elements: [ProjectMeshElementRecord] {
        records
    }
}
