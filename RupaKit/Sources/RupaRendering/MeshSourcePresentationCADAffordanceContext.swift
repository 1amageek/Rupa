import SwiftCAD
import RupaCore
import RupaCoreTypes
import RupaProjectModel

public struct MeshSourcePresentationCADAffordanceContext: Equatable, Sendable {
    public let occurrenceID: SceneOccurrenceID
    public let sceneNodeID: SceneNodeID
    public let featureID: FeatureID
    public let bodyID: BodyID
    public let generation: DocumentGeneration
    public let representationID: GeometryRepresentationID
    public let sourceReference: GeometrySourceReference

    public init(
        occurrenceID: SceneOccurrenceID,
        sceneNodeID: SceneNodeID,
        featureID: FeatureID,
        bodyID: BodyID,
        generation: DocumentGeneration,
        representationID: GeometryRepresentationID,
        sourceReference: GeometrySourceReference
    ) {
        self.occurrenceID = occurrenceID
        self.sceneNodeID = sceneNodeID
        self.featureID = featureID
        self.bodyID = bodyID
        self.generation = generation
        self.representationID = representationID
        self.sourceReference = sourceReference
    }
}
