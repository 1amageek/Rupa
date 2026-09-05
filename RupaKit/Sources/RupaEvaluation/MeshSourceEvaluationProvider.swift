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
        try Task.checkCancellation()
        var results: [GeometrySourceReference: GeometryEvaluationResult] = [:]
        results.reserveCapacity(request.references.count)

        for reference in request.references {
            try Task.checkCancellation()
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
            // An authored mesh the allowance cannot admit is refused before the
            // result is built, so an oversized asset never reaches the caller as
            // a coarser or partial result. The engine charges the accumulated
            // total, so this only rejects a single mesh that cannot fit at all.
            let usage: MeshResourceUsage
            do {
                usage = try mesh.resourceUsage()
            } catch {
                throw EvaluationError(
                    code: .invalidResult,
                    message: "Authored mesh \(sourceID.rawValue) has resource usage that cannot be accounted: \(error)"
                )
            }
            if let resource = request.allowance.firstResourceExceeded(by: usage) {
                throw EvaluationError(
                    code: .resourceExhausted,
                    message: "Authored mesh \(sourceID.rawValue) needs \(usage.amount(for: resource)) \(resource.rawValue) for the \(request.purpose.rawValue) purpose, which exceeds the \(request.allowance.amount(for: resource)) still available."
                )
            }
            results[reference] = GeometryEvaluationResult(
                reference: reference,
                mesh: mesh,
                localBounds: try mesh.bounds()
            )
        }
        try Task.checkCancellation()
        return results
    }
}
