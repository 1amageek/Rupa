import RupaCoreTypes

public struct ProjectMeshNeighborhoodRequest: Sendable {
    public let handle: ProjectMeshSourceHandle
    public let origin: ProjectMeshElementReference
    public let depth: Int
    public let limits: ProjectMeshReadLimits

    public init(
        handle: ProjectMeshSourceHandle,
        origin: ProjectMeshElementReference,
        depth: Int,
        limits: ProjectMeshReadLimits = .standard
    ) {
        self.handle = handle
        self.origin = origin
        self.depth = depth
        self.limits = limits
    }

    public init(
        handle: ProjectMeshSourceHandle,
        element: ProjectMeshElementReference,
        maxDepth: Int,
        limits: ProjectMeshReadLimits = .standard
    ) {
        self.init(handle: handle, origin: element, depth: maxDepth, limits: limits)
    }
}

public struct ProjectMeshNeighborhoodRecord: Sendable, Equatable {
    public let distance: Int
    public let element: ProjectMeshElementRecord

    public init(distance: Int, element: ProjectMeshElementRecord) {
        self.distance = distance
        self.element = element
    }
}

public struct ProjectMeshNeighborhood: Sendable, Equatable {
    public let handle: ProjectMeshSourceHandle
    public let records: [ProjectMeshNeighborhoodRecord]

    public init(
        handle: ProjectMeshSourceHandle,
        records: [ProjectMeshNeighborhoodRecord]
    ) {
        self.handle = handle
        self.records = records
    }

    public var elements: [ProjectMeshNeighborhoodRecord] {
        records
    }
}
