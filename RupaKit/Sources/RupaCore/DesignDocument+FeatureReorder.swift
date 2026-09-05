import SwiftCAD

public extension DesignDocument {
    /// Reorders the complete feature history after validating the candidate graph.
    ///
    /// The caller supplies a permutation of the current feature IDs. The
    /// candidate is validated before it replaces the document, so invalid
    /// orderings cannot publish a partial graph.
    @discardableResult
    func reorderedFeatureGraph(
        featureIDs: [FeatureID],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> DesignDocument {
        let currentOrder = cadDocument.designGraph.order
        guard featureIDs != currentOrder else {
            return self
        }
        guard featureIDs.count == currentOrder.count else {
            throw FeatureEvaluationError.invalidGraph(
                "Feature reorder must include every existing feature exactly once."
            )
        }
        guard Set(featureIDs).count == featureIDs.count else {
            throw FeatureEvaluationError.invalidGraph(
                "Feature reorder cannot contain duplicate IDs."
            )
        }
        guard Set(featureIDs) == Set(currentOrder) else {
            throw FeatureEvaluationError.invalidGraph(
                "Feature reorder must use the existing feature IDs."
            )
        }

        var updatedDocument = self
        updatedDocument.cadDocument.designGraph.order = featureIDs
        updatedDocument.cadDocument.designGraph.revision =
            updatedDocument.cadDocument.designGraph.revision.advanced()
        try updatedDocument.validate(objectRegistry: objectRegistry)
        return updatedDocument
    }
}
