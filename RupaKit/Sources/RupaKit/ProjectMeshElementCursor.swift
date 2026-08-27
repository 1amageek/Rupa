import RupaCoreTypes

/// A page cursor bound to one exact source content and element domain.
public struct ProjectMeshElementCursor: Codable, Equatable, Hashable, Sendable {
    public let sourceID: GeometrySourceID
    public let contentIdentity: ContentIdentity
    public let domain: ProjectMeshElementDomain
    public let nextIndex: Int

    public init(
        sourceID: GeometrySourceID,
        contentIdentity: ContentIdentity,
        domain: ProjectMeshElementDomain,
        nextIndex: Int
    ) {
        self.sourceID = sourceID
        self.contentIdentity = contentIdentity
        self.domain = domain
        self.nextIndex = nextIndex
    }
}
