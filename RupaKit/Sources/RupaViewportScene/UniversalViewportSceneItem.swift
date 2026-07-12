import RupaEvaluation
import RupaGeometry
import RupaProjectModel

public struct UniversalViewportSceneItem: Equatable, Sendable, Identifiable {
    public let id: SceneOccurrenceID
    public let definitionID: ObjectDefinitionID
    public let displayName: String
    public let reference: GeometrySourceReference
    public let mesh: MeshSource
    public let worldTransform: GeometryTransform3D
    public let worldBounds: GeometryBounds3D

    public init(
        id: SceneOccurrenceID,
        definitionID: ObjectDefinitionID,
        displayName: String,
        reference: GeometrySourceReference,
        mesh: MeshSource,
        worldTransform: GeometryTransform3D,
        worldBounds: GeometryBounds3D
    ) {
        self.id = id
        self.definitionID = definitionID
        self.displayName = displayName
        self.reference = reference
        self.mesh = mesh
        self.worldTransform = worldTransform
        self.worldBounds = worldBounds
    }

    public init(_ snapshot: EvaluatedOccurrenceSnapshot, displayName: String) {
        self.init(
            id: snapshot.occurrenceID,
            definitionID: snapshot.definitionID,
            displayName: displayName,
            reference: snapshot.reference,
            mesh: snapshot.mesh,
            worldTransform: snapshot.worldTransform,
            worldBounds: snapshot.worldBounds
        )
    }
}
