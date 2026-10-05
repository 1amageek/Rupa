import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

/// A geometry-buffer-free summary of one item visible in the published viewport.
public struct AgentProjectViewportItem: Codable, Equatable, Sendable {
    public let occurrenceID: SceneOccurrenceID
    public let presentationID: SceneOccurrenceID?
    public let sourceBodyID: String?
    public let sourceFeatureID: String?
    public let outputRole: String?
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
        triangleCount: UInt64,
        presentationID: SceneOccurrenceID? = nil,
        sourceBodyID: String? = nil, sourceFeatureID: String? = nil, outputRole: String? = nil
    ) {
        self.occurrenceID = occurrenceID
        self.presentationID = presentationID
        self.sourceBodyID = sourceBodyID
        self.sourceFeatureID = sourceFeatureID
        self.outputRole = outputRole
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
