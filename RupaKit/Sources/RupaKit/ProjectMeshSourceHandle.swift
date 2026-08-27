import RupaCoreTypes
import RupaProject

/// An immutable source coordinate for one retained Authored Mesh asset.
public struct ProjectMeshSourceHandle: Codable, Equatable, Hashable, Sendable {
    public let projectAuthorityCoordinate: ProjectAuthorityCoordinate
    public let sourceID: GeometrySourceID
    public let contentIdentity: ContentIdentity

    public init(
        projectAuthorityCoordinate: ProjectAuthorityCoordinate,
        sourceID: GeometrySourceID,
        contentIdentity: ContentIdentity
    ) {
        self.projectAuthorityCoordinate = projectAuthorityCoordinate
        self.sourceID = sourceID
        self.contentIdentity = contentIdentity
    }

    public var authority: ProjectAuthorityCoordinate {
        projectAuthorityCoordinate
    }

    public var coordinate: ProjectAuthorityCoordinate {
        projectAuthorityCoordinate
    }

    private enum CodingKeys: String, CodingKey {
        case projectID
        case transactionRevision
        case publicationSequence
        case sourceID
        case contentIdentity
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
            sourceID: try container.decode(GeometrySourceID.self, forKey: .sourceID),
            contentIdentity: try container.decode(ContentIdentity.self, forKey: .contentIdentity)
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
        try container.encode(sourceID, forKey: .sourceID)
        try container.encode(contentIdentity, forKey: .contentIdentity)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.projectAuthorityCoordinate.projectID == rhs.projectAuthorityCoordinate.projectID
            && lhs.projectAuthorityCoordinate.transactionRevision
                == rhs.projectAuthorityCoordinate.transactionRevision
            && lhs.projectAuthorityCoordinate.publicationSequence
                == rhs.projectAuthorityCoordinate.publicationSequence
            && lhs.sourceID == rhs.sourceID
            && lhs.contentIdentity == rhs.contentIdentity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(projectAuthorityCoordinate.projectID)
        hasher.combine(projectAuthorityCoordinate.transactionRevision)
        hasher.combine(projectAuthorityCoordinate.publicationSequence)
        hasher.combine(sourceID)
        hasher.combine(contentIdentity)
    }
}
