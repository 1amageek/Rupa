import RupaCoreTypes

/// The ceiling a product states for each representation purpose.
///
/// The policy is the only seam through which a product narrows an evaluation.
/// It is validated at construction, and `EvaluationResourceLimits.validate()`
/// refuses anything above the module hard ceiling, so a policy can lower and
/// never widen what `RupaEvaluation` owns.
public struct EvaluationResourcePolicy: Equatable, Sendable {
    private let limitsByPurpose: [GeometryRepresentationPurpose: EvaluationResourceLimits]

    /// Requires a stated ceiling for every purpose, so no purpose is silently unbounded.
    public init(
        limitsByPurpose: [GeometryRepresentationPurpose: EvaluationResourceLimits]
    ) throws {
        var stated: [GeometryRepresentationPurpose: EvaluationResourceLimits] = [:]
        stated.reserveCapacity(GeometryRepresentationPurpose.allCases.count)
        for purpose in GeometryRepresentationPurpose.allCases {
            guard let limits = limitsByPurpose[purpose] else {
                throw EvaluationError(
                    code: .invalidLimit,
                    message: "An evaluation resource policy must state a limit for the "
                        + "\(purpose.rawValue) purpose."
                )
            }
            try limits.validate()
            stated[purpose] = limits
        }
        self.limitsByPurpose = stated
    }

    /// Applies one ceiling to every purpose.
    public init(everyPurpose limits: EvaluationResourceLimits) throws {
        try self.init(
            limitsByPurpose: Dictionary(
                uniqueKeysWithValues: GeometryRepresentationPurpose.allCases.map {
                    ($0, limits)
                }
            )
        )
    }

    /// The policy an evaluation uses when the product states no narrower one.
    ///
    /// `EvaluationResourceLimits.standard` is admissible by construction, which
    /// its own suite proves, so this initializer cannot fail.
    public static let standard = EvaluationResourcePolicy(
        validatedEveryPurpose: .standard
    )

    private init(validatedEveryPurpose limits: EvaluationResourceLimits) {
        self.limitsByPurpose = Dictionary(
            uniqueKeysWithValues: GeometryRepresentationPurpose.allCases.map { ($0, limits) }
        )
    }

    public func limits(for purpose: GeometryRepresentationPurpose) -> EvaluationResourceLimits {
        guard let limits = limitsByPurpose[purpose] else {
            // Construction states a limit for every purpose, so no purpose is missing.
            preconditionFailure(
                "An evaluation resource policy is missing the \(purpose.rawValue) purpose."
            )
        }
        return limits
    }

    /// A policy whose every purpose is narrowed to `limits`.
    public func lowered(to limits: EvaluationResourceLimits) throws -> EvaluationResourcePolicy {
        try EvaluationResourcePolicy(
            limitsByPurpose: limitsByPurpose.mapValues { $0.lowered(to: limits) }
        )
    }
}
