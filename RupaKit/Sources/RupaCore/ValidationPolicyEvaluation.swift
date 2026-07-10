import Foundation

public struct ValidationPolicyEvaluation: Codable, Equatable, Sendable {
    public var policyID: String
    public var decision: ValidationPolicyDecision
    public var failures: [ValidationPolicyFailure]
    public var overriddenRuleIDs: [String]
    public var appliedOverrideIDs: [UUID]

    public init(
        policyID: String,
        decision: ValidationPolicyDecision,
        failures: [ValidationPolicyFailure],
        overriddenRuleIDs: [String] = [],
        appliedOverrideIDs: [UUID] = []
    ) {
        self.policyID = policyID
        self.decision = decision
        self.failures = failures
        self.overriddenRuleIDs = overriddenRuleIDs
        self.appliedOverrideIDs = appliedOverrideIDs
    }

    public var blockingRuleIDs: [String] {
        failures.compactMap { failure in
            failure.reasons == [.missingRule] ? nil : failure.ruleID
        }
    }

    public var missingRuleIDs: [String] {
        failures.compactMap { failure in
            failure.reasons.contains(.missingRule) ? failure.ruleID : nil
        }
    }
}
