import RupaKit

/// Bounded catalog result with the exact view coordinates used for the read.
public struct AgentMeshCatalogResult: Codable, Equatable, Sendable {
    public let coordinates: AgentProjectViewCoordinates
    public let catalog: ProjectMeshCatalog

    public init(
        coordinates: AgentProjectViewCoordinates,
        catalog: ProjectMeshCatalog
    ) {
        self.coordinates = coordinates
        self.catalog = catalog
    }
}

/// Bounded page result with the exact view coordinates used for the read.
public struct AgentMeshPageResult: Codable, Equatable, Sendable {
    public let coordinates: AgentProjectViewCoordinates
    public let page: AgentMeshPage

    public init(
        coordinates: AgentProjectViewCoordinates,
        page: AgentMeshPage
    ) {
        self.coordinates = coordinates
        self.page = page
    }
}

/// Bounded neighborhood result with the exact view coordinates used for the read.
public struct AgentMeshNeighborhoodResult: Codable, Equatable, Sendable {
    public let coordinates: AgentProjectViewCoordinates
    public let neighborhood: AgentMeshNeighborhood

    public init(
        coordinates: AgentProjectViewCoordinates,
        neighborhood: AgentMeshNeighborhood
    ) {
        self.coordinates = coordinates
        self.neighborhood = neighborhood
    }
}
