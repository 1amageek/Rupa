import RupaProjectModel

/// Evaluates all requested outputs for one source provider as a single atomic batch.
public protocol GeometrySourceEvaluationProvider: Sendable {
    var providerID: String { get }

    /// Returns exactly one result keyed by each reference in the request.
    func evaluate(
        _ request: GeometrySourceEvaluationRequest,
        in project: ProjectSourceModel
    ) throws -> [GeometrySourceReference: GeometryEvaluationResult]
}
