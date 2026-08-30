import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

/// A geometry-buffer-free summary of one item visible in the published viewport.
public struct AgentProjectViewportItem: Codable, Equatable, Sendable {
    public let occurrenceID: SceneOccurrenceID
    public let sceneNodeID: SceneNodeID
    public let definitionID: ObjectDefinitionID
    public let displayName: String
    public let representationID: GeometryRepresentationID
    public let sourceReference: GeometrySourceReference
    public let worldTransform: GeometryTransform3D
    public let worldBounds: GeometryBounds3D
    public let vertexCount: UInt64
    public let faceCount: UInt64
    public let cornerCount: UInt64
    public let triangleCount: UInt64

    public init(
        occurrenceID: SceneOccurrenceID,
        sceneNodeID: SceneNodeID,
        definitionID: ObjectDefinitionID,
        displayName: String,
        representationID: GeometryRepresentationID,
        sourceReference: GeometrySourceReference,
        worldTransform: GeometryTransform3D,
        worldBounds: GeometryBounds3D,
        vertexCount: UInt64,
        faceCount: UInt64,
        cornerCount: UInt64,
        triangleCount: UInt64
    ) {
        self.occurrenceID = occurrenceID
        self.sceneNodeID = sceneNodeID
        self.definitionID = definitionID
        self.displayName = displayName
        self.representationID = representationID
        self.sourceReference = sourceReference
        self.worldTransform = worldTransform
        self.worldBounds = worldBounds
        self.vertexCount = vertexCount
        self.faceCount = faceCount
        self.cornerCount = cornerCount
        self.triangleCount = triangleCount
    }
}
