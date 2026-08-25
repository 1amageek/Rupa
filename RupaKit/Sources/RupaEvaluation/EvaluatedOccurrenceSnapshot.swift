import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

public struct EvaluatedOccurrenceSnapshot: Sendable {
    public let occurrenceID: SceneOccurrenceID
    public let definitionID: ObjectDefinitionID
    public let representationID: GeometryRepresentationID
    public let reference: GeometrySourceReference
    public let mesh: MeshSource
    public let copyTelemetry: GeometryCopyTelemetry
    public let worldTransform: GeometryTransform3D
    public let worldBounds: GeometryBounds3D

    public init(
        occurrenceID: SceneOccurrenceID,
        definitionID: ObjectDefinitionID,
        representationID: GeometryRepresentationID,
        reference: GeometrySourceReference,
        mesh: MeshSource,
        copyTelemetry: GeometryCopyTelemetry = GeometryCopyTelemetry(),
        worldTransform: GeometryTransform3D,
        worldBounds: GeometryBounds3D
    ) {
        self.occurrenceID = occurrenceID
        self.definitionID = definitionID
        self.representationID = representationID
        self.reference = reference
        self.mesh = mesh
        self.copyTelemetry = copyTelemetry
        self.worldTransform = worldTransform
        self.worldBounds = worldBounds
    }
}
