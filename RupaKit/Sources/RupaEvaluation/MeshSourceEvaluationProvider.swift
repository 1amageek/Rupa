import RupaGeometry
import RupaProjectModel

public struct MeshSourceEvaluationProvider: GeometrySourceEvaluationProvider {
    public let providerID = "mesh"

    public init() {}

    public func evaluate(
        reference: GeometrySourceReference,
        in project: ProjectSourceModel
    ) throws -> GeometryEvaluationResult {
        guard case .mesh(let sourceID) = reference else {
            throw EvaluationError(
                code: .invalidResult,
                message: "Mesh source provider received a non-mesh reference."
            )
        }
        guard let mesh = project.meshSources[sourceID] else {
            throw EvaluationError(
                code: .sourceUnavailable,
                message: "Mesh source \(sourceID.rawValue) is not present in the project."
            )
        }
        return GeometryEvaluationResult(
            reference: reference,
            mesh: mesh,
            localBounds: try mesh.bounds()
        )
    }
}
