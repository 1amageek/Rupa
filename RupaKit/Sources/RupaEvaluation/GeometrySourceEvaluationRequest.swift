import RupaCoreTypes
import RupaProjectModel

/// A deterministic, de-duplicated unit of work for one geometry source provider.
///
/// The request states the representation `purpose` the results are produced for
/// and the `allowance` still open when the provider is called, so a provider can
/// narrow its own generation and refuse predicted growth before it allocates.
/// The allowance is advisory to the provider and binding at the engine, which
/// charges every returned mesh against the same budget, so a provider that
/// ignores it is still refused.
public struct GeometrySourceEvaluationRequest: Sendable {
    public let references: [GeometrySourceReference]
    public let sourceRevision: DocumentTransactionRevision
    public let purpose: GeometryRepresentationPurpose
    public let allowance: EvaluationAllowance

    package init(
        references: [GeometrySourceReference],
        sourceRevision: DocumentTransactionRevision,
        purpose: GeometryRepresentationPurpose,
        allowance: EvaluationAllowance
    ) throws {
        guard let providerID = references.first?.providerID,
              references.allSatisfy({ $0.providerID == providerID }),
              Set(references).count == references.count else {
            throw EvaluationError(
                code: .invalidRequest,
                message: "A geometry evaluation request must contain unique references for exactly one provider."
            )
        }
        try allowance.validate()
        self.references = references
        self.sourceRevision = sourceRevision
        self.purpose = purpose
        self.allowance = allowance
    }
}
