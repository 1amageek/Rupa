import RupaGeometry

/// The cumulative charge one project evaluation has made against its ceiling.
///
/// A budget is invocation-local: it is created for one `evaluate` call, charged
/// as that call resolves sources and receives meshes, and discarded with it. It
/// is a value, so no two evaluations share a remainder and no lock is needed to
/// charge one.
public struct EvaluationBudget: Equatable, Sendable {
    public let limits: EvaluationResourceLimits
    public private(set) var remaining: EvaluationAllowance

    /// Starts a budget at the full allowance `limits` admits.
    public init(limits: EvaluationResourceLimits) throws {
        try limits.validate()
        self.limits = limits
        self.remaining = EvaluationAllowance(limits)
    }

    /// Charges one distinct geometry source.
    public mutating func chargeSource() throws {
        guard remaining.sourceCount >= 1 else {
            throw Self.exhausted(.sourceCount, requested: 1, limits: limits)
        }
        remaining.sourceCount -= 1
    }

    /// Charges one materialized mesh in every element dimension.
    ///
    /// The mesh already exists when it is charged, so this reports what the
    /// evaluation has committed rather than predicting it. A provider that
    /// refuses predicted growth before allocating keeps the commitment bounded;
    /// this charge refuses a provider that did not.
    public mutating func charge(_ usage: MeshResourceUsage) throws {
        if let exceeded = remaining.firstResourceExceeded(by: usage) {
            throw Self.exhausted(
                exceeded,
                requested: usage.amount(for: exceeded),
                limits: limits
            )
        }
        remaining.vertexCount -= usage.vertexCount
        remaining.faceCount -= usage.faceCount
        remaining.cornerCount -= usage.cornerCount
        remaining.triangleCount -= usage.triangleCount
        remaining.byteCount -= usage.byteCount
    }

    private static func exhausted(
        _ resource: EvaluationResource,
        requested: Int,
        limits: EvaluationResourceLimits
    ) -> EvaluationError {
        EvaluationError(
            code: .resourceExhausted,
            message: "Project evaluation exhausted \(resource.rawValue): a further "
                + "\(requested) does not fit the remaining allowance under a limit of "
                + "\(limits.limit(for: resource))."
        )
    }
}
