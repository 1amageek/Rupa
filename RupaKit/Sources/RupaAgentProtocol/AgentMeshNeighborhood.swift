import RupaKit

/// One bounded neighborhood element with its graph distance.
public struct AgentMeshNeighborhoodRecord: Codable, Equatable, Sendable {
    public let distance: Int
    public let element: ProjectMeshElementRecord

    public init(distance: Int, element: ProjectMeshElementRecord) {
        self.distance = distance
        self.element = element
    }
}

/// Wire-safe Mesh neighborhood projected from the project use case.
public struct AgentMeshNeighborhood: Codable, Equatable, Sendable {
    public let handle: ProjectMeshSourceHandle
    public let records: [AgentMeshNeighborhoodRecord]

    public init(
        handle: ProjectMeshSourceHandle,
        records: [AgentMeshNeighborhoodRecord]
    ) {
        self.handle = handle
        self.records = records
    }
}
