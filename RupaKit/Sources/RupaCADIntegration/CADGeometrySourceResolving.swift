/// Resolves the CAD source named by an external geometry reference.
public protocol CADGeometrySourceResolving: Sendable {
    /// Returns the exact document/evaluator pair for `sourceID` or throws a
    /// source-resolution failure. The provider translates foreign failures at
    /// this boundary into `CADIntegrationError.sourceUnavailable`.
    func source(for sourceID: String) throws -> CADGeometryEvaluationSource
}
