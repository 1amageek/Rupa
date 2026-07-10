import Foundation

public struct ValidationRuleRequirement: Codable, Equatable, Sendable {
    public var ruleID: String
    public var acceptedOutcomes: Set<ValidationOutcome>
    public var acceptedFidelities: Set<ValidationFidelity>?
    public var acceptedRegionCompleteness: Set<ValidationRegionCompleteness>?
    public var requiresCurrentInput: Bool
    public var allowsOverride: Bool

    public init(
        ruleID: String,
        acceptedOutcomes: Set<ValidationOutcome> = [.passed],
        acceptedFidelities: Set<ValidationFidelity>? = nil,
        acceptedRegionCompleteness: Set<ValidationRegionCompleteness>? = nil,
        requiresCurrentInput: Bool = true,
        allowsOverride: Bool = false
    ) {
        self.ruleID = ruleID
        self.acceptedOutcomes = acceptedOutcomes
        self.acceptedFidelities = acceptedFidelities
        self.acceptedRegionCompleteness = acceptedRegionCompleteness
        self.requiresCurrentInput = requiresCurrentInput
        self.allowsOverride = allowsOverride
    }

    public func validate() throws {
        guard !ruleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Validation policy rule IDs must not be empty."
            )
        }
        guard !acceptedOutcomes.isEmpty else {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Validation policy rules must accept at least one outcome."
            )
        }
        if let acceptedFidelities, acceptedFidelities.isEmpty {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Validation policy fidelity sets must not be empty."
            )
        }
        if let acceptedRegionCompleteness, acceptedRegionCompleteness.isEmpty {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Validation policy region completeness sets must not be empty."
            )
        }
    }
}
