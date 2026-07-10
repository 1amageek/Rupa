public enum ValidationRegionKind: String, Codable, Equatable, Sendable {
    case body
    case bodyPair
    case generatedTopology
    case meshTriangles
    case semanticEntities
    case sampledArtifact
    case drawingItems
}
