import RupaGeometry
import RupaProjectModel

public struct GeometryEvaluationResult: Sendable {
    public let reference: GeometrySourceReference
    public let mesh: MeshSource
    public let localBounds: GeometryBounds3D
    public let copyTelemetry: GeometryCopyTelemetry

    public init(
        reference: GeometrySourceReference,
        mesh: MeshSource,
        localBounds: GeometryBounds3D,
        copyTelemetry: GeometryCopyTelemetry = GeometryCopyTelemetry()
    ) {
        self.reference = reference
        self.mesh = mesh
        self.localBounds = localBounds
        self.copyTelemetry = copyTelemetry
    }
}
