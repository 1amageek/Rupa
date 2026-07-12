import RupaGeometry
import RupaProjectModel

public struct EvaluatedOccurrenceSnapshot: Sendable {
    public let occurrenceID: SceneOccurrenceID
    public let definitionID: ObjectDefinitionID
    public let reference: GeometrySourceReference
    public let mesh: MeshSource
    public let worldTransform: GeometryTransform3D
    public let worldBounds: GeometryBounds3D

    public init(
        occurrenceID: SceneOccurrenceID,
        definitionID: ObjectDefinitionID,
        reference: GeometrySourceReference,
        mesh: MeshSource,
        worldTransform: GeometryTransform3D,
        worldBounds: GeometryBounds3D
    ) {
        self.occurrenceID = occurrenceID
        self.definitionID = definitionID
        self.reference = reference
        self.mesh = mesh
        self.worldTransform = worldTransform
        self.worldBounds = worldBounds
    }
}
