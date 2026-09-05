import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

public struct MeshSourcePresentationTriangle: Equatable, Sendable {
    public let occurrenceID: SceneOccurrenceID
    public let definitionID: ObjectDefinitionID
    public let representationID: GeometryRepresentationID
    public let sourceReference: GeometrySourceReference
    public let faceID: MeshFaceID
    public let firstVertexID: MeshVertexID
    public let secondVertexID: MeshVertexID
    public let thirdVertexID: MeshVertexID
    /// Original boundary identities for sides 0–1, 1–2 and 2–0; nil for diagonals.
    public let firstEdgeID: MeshEdgeID?
    public let secondEdgeID: MeshEdgeID?
    public let thirdEdgeID: MeshEdgeID?
    public let firstPosition: GeometryPoint3D
    public let secondPosition: GeometryPoint3D
    public let thirdPosition: GeometryPoint3D

    public init(
        occurrenceID: SceneOccurrenceID,
        definitionID: ObjectDefinitionID,
        representationID: GeometryRepresentationID,
        sourceReference: GeometrySourceReference,
        faceID: MeshFaceID,
        firstVertexID: MeshVertexID,
        secondVertexID: MeshVertexID,
        thirdVertexID: MeshVertexID,
        firstPosition: GeometryPoint3D,
        secondPosition: GeometryPoint3D,
        thirdPosition: GeometryPoint3D,
        firstEdgeID: MeshEdgeID? = nil,
        secondEdgeID: MeshEdgeID? = nil,
        thirdEdgeID: MeshEdgeID? = nil
    ) {
        self.occurrenceID = occurrenceID
        self.definitionID = definitionID
        self.representationID = representationID
        self.sourceReference = sourceReference
        self.faceID = faceID
        self.firstVertexID = firstVertexID
        self.secondVertexID = secondVertexID
        self.thirdVertexID = thirdVertexID
        self.firstEdgeID = firstEdgeID
        self.secondEdgeID = secondEdgeID
        self.thirdEdgeID = thirdEdgeID
        self.firstPosition = firstPosition
        self.secondPosition = secondPosition
        self.thirdPosition = thirdPosition
    }
}
