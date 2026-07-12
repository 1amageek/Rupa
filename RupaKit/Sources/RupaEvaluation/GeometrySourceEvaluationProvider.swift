import RupaProjectModel

public protocol GeometrySourceEvaluationProvider: Sendable {
    var providerID: String { get }

    func evaluate(
        reference: GeometrySourceReference,
        in project: ProjectSourceModel
    ) throws -> GeometryEvaluationResult
}
