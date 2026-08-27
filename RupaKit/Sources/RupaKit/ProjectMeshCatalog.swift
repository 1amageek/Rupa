import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProject
import RupaProjectModel

public struct ProjectMeshElementCounts: Codable, Equatable, Sendable {
    public let vertices: Int
    public let edges: Int
    public let faces: Int
    public let corners: Int

    public init(vertices: Int, edges: Int, faces: Int, corners: Int) {
        self.vertices = vertices
        self.edges = edges
        self.faces = faces
        self.corners = corners
    }
}

public struct ProjectMeshCatalogReference: Codable, Equatable, Sendable {
    public let sceneNodeID: SceneNodeID
    public let representationID: GeometryRepresentationID
    public let selectedPurposes: [GeometryRepresentationPurpose]

    public init(
        sceneNodeID: SceneNodeID,
        representationID: GeometryRepresentationID,
        selectedPurposes: [GeometryRepresentationPurpose]
    ) {
        self.sceneNodeID = sceneNodeID
        self.representationID = representationID
        self.selectedPurposes = GeometryRepresentationPurpose.allCases.filter {
            selectedPurposes.contains($0)
        }
    }
}

public struct ProjectMeshCatalogSource: Codable, Equatable, Sendable {
    public let handle: ProjectMeshSourceHandle
    public let provenance: AuthoredMeshProvenance
    public let counts: ProjectMeshElementCounts
    public let bounds: GeometryBounds3D?
    public let references: [ProjectMeshCatalogReference]

    public var sourceID: GeometrySourceID {
        handle.sourceID
    }

    public var contentIdentity: ContentIdentity {
        handle.contentIdentity
    }

    public init(
        handle: ProjectMeshSourceHandle,
        provenance: AuthoredMeshProvenance,
        counts: ProjectMeshElementCounts,
        bounds: GeometryBounds3D?,
        references: [ProjectMeshCatalogReference]
    ) {
        self.handle = handle
        self.provenance = provenance
        self.counts = counts
        self.bounds = bounds
        self.references = references
    }
}

public struct ProjectMeshCatalog: Codable, Equatable, Sendable {
    public let projectAuthorityCoordinate: ProjectAuthorityCoordinate
    public let sources: [ProjectMeshCatalogSource]

    public init(
        projectAuthorityCoordinate: ProjectAuthorityCoordinate,
        sources: [ProjectMeshCatalogSource]
    ) {
        self.projectAuthorityCoordinate = projectAuthorityCoordinate
        self.sources = sources
    }

    public var coordinate: ProjectAuthorityCoordinate {
        projectAuthorityCoordinate
    }

    public func source(for sourceID: GeometrySourceID) -> ProjectMeshCatalogSource? {
        sources.first { $0.sourceID == sourceID }
    }

    private enum CodingKeys: String, CodingKey {
        case projectID
        case transactionRevision
        case publicationSequence
        case sources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            projectAuthorityCoordinate: ProjectAuthorityCoordinate(
                projectID: try container.decode(ProjectID.self, forKey: .projectID),
                transactionRevision: try container.decode(
                    DocumentTransactionRevision.self,
                    forKey: .transactionRevision
                ),
                publicationSequence: try container.decode(
                    UInt64.self,
                    forKey: .publicationSequence
                )
            ),
            sources: try container.decode([ProjectMeshCatalogSource].self, forKey: .sources)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectAuthorityCoordinate.projectID, forKey: .projectID)
        try container.encode(
            projectAuthorityCoordinate.transactionRevision,
            forKey: .transactionRevision
        )
        try container.encode(
            projectAuthorityCoordinate.publicationSequence,
            forKey: .publicationSequence
        )
        try container.encode(sources, forKey: .sources)
    }
}
