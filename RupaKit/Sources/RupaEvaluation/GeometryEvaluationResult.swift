import RupaGeometry
import RupaProjectModel

public struct GeometryEvaluationResult: Sendable {
    public let reference: GeometrySourceReference
    public let mesh: MeshSource
    public let localBounds: GeometryBounds3D

    public init(
        reference: GeometrySourceReference,
        mesh: MeshSource,
        localBounds: GeometryBounds3D
    ) {
        self.reference = reference
        self.mesh = mesh
        self.localBounds = localBounds
    }
}
