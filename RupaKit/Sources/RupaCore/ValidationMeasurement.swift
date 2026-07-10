import Foundation

public struct ValidationMeasurement: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var value: ValidationQuantity
    public var requirement: ValidationMeasurementRequirement?

    public init(
        id: String,
        value: ValidationQuantity,
        requirement: ValidationMeasurementRequirement? = nil
    ) {
        self.id = id
        self.value = value
        self.requirement = requirement
    }

    public func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Validation measurement IDs must not be empty."
            )
        }
        try value.validate()
        try requirement?.validate(for: value)
    }
}
