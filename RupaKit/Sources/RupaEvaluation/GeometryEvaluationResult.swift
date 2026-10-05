import RupaGeometry
import RupaProjectModel

public struct GeometryEvaluationResult: Sendable {
    public let parts: [GeometryEvaluationPart]
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
        parts = [GeometryEvaluationPart(mesh: mesh, localBounds: localBounds, copyTelemetry: copyTelemetry)]
        self.reference = reference
        self.mesh = mesh
        self.localBounds = localBounds
        self.copyTelemetry = copyTelemetry
    }
    public init(reference: GeometrySourceReference, primary: GeometryEvaluationPart,
                additionalParts: [GeometryEvaluationPart]) {
        self.reference = reference
        parts = [primary] + additionalParts
        mesh = primary.mesh
        localBounds = primary.localBounds
        copyTelemetry = primary.copyTelemetry
    }
}
