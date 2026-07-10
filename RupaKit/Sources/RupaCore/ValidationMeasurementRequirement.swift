public struct ValidationMeasurementRequirement: Codable, Hashable, Sendable {
    public var comparison: ValidationComparison
    public var target: ValidationQuantity
    public var upperBound: ValidationQuantity?
    public var tolerance: ValidationQuantity?

    public init(
        comparison: ValidationComparison,
        target: ValidationQuantity,
        upperBound: ValidationQuantity? = nil,
        tolerance: ValidationQuantity? = nil
    ) {
        self.comparison = comparison
        self.target = target
        self.upperBound = upperBound
        self.tolerance = tolerance
    }

    public func validate(for measuredValue: ValidationQuantity) throws {
        try measuredValue.validate()
        try target.validate()
        try upperBound?.validate()
        try tolerance?.validate()
        try requireCompatible(target, with: measuredValue)
        if comparison == .range {
            guard let upperBound else {
                throw invalidRequirement("Range validation requirements must contain an upper bound.")
            }
            try requireCompatible(upperBound, with: measuredValue)
            guard upperBound.value >= target.value else {
                throw invalidRequirement("Range validation requirements must order their bounds.")
            }
        } else if upperBound != nil {
            throw invalidRequirement("Only range validation requirements may contain an upper bound.")
        }
        if let tolerance {
            try requireCompatible(tolerance, with: measuredValue)
            guard tolerance.value >= 0.0 else {
                throw invalidRequirement("Validation measurement tolerance must not be negative.")
            }
        }
    }

    private func requireCompatible(
        _ quantity: ValidationQuantity,
        with measuredValue: ValidationQuantity
    ) throws {
        guard quantity.dimension == measuredValue.dimension,
              quantity.unit == measuredValue.unit else {
            throw invalidRequirement(
                "Validation measurement requirements must use the measured quantity dimension and unit."
            )
        }
    }

    private func invalidRequirement(_ message: String) -> ReferenceValidationError {
        ReferenceValidationError(code: .invalidShape, message: message)
    }
}
