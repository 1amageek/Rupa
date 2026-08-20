import RupaCoreTypes
import RupaProjectModel

/// A deterministic, de-duplicated unit of work for one geometry source provider.
public struct GeometrySourceEvaluationRequest: Sendable {
    public let references: [GeometrySourceReference]
    public let sourceRevision: DocumentTransactionRevision

    package init(
        references: [GeometrySourceReference],
        sourceRevision: DocumentTransactionRevision
    ) throws {
        guard let providerID = references.first?.providerID,
              references.allSatisfy({ $0.providerID == providerID }),
              Set(references).count == references.count else {
            throw EvaluationError(
                code: .invalidRequest,
                message: "A geometry evaluation request must contain unique references for exactly one provider."
            )
        }
        self.references = references
        self.sourceRevision = sourceRevision
    }
}
