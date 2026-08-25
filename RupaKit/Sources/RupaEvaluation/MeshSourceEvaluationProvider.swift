import RupaGeometry
import RupaProjectModel

public struct MeshSourceEvaluationProvider: GeometrySourceEvaluationProvider {
    public static let identifier = GeometrySourceReference.authoredMeshProviderID
    public let providerID = Self.identifier

    public init() {}

    public func evaluate(
        _ request: GeometrySourceEvaluationRequest,
        in project: ProjectSourceModel
    ) throws -> [GeometrySourceReference: GeometryEvaluationResult] {
        var results: [GeometrySourceReference: GeometryEvaluationResult] = [:]
        results.reserveCapacity(request.references.count)

        for reference in request.references {
            guard case .authoredMesh(let sourceID) = reference else {
                throw EvaluationError(
                    code: .invalidResult,
                    message: "Mesh source provider received a non-mesh reference."
                )
            }
            guard let mesh = project.authoredMeshAssets[sourceID]?.source else {
                throw EvaluationError(
                    code: .sourceUnavailable,
                    message: "Mesh source \(sourceID.rawValue) is not present in the project."
                )
            }
            results[reference] = GeometryEvaluationResult(
                reference: reference,
                mesh: mesh,
                localBounds: try mesh.bounds()
            )
        }
        return results
    }
}
