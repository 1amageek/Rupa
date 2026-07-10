import Foundation

public struct ValidationPolicy: Codable, Equatable, Sendable {
    public var id: String
    public var requirements: [ValidationRuleRequirement]

    public init(
        id: String,
        requirements: [ValidationRuleRequirement] = []
    ) {
        self.id = id
        self.requirements = requirements
    }

    public func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Validation policy IDs must not be empty."
            )
        }
        guard Set(requirements.map(\.ruleID)).count == requirements.count else {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Validation policies must declare each rule once."
            )
        }
        for requirement in requirements {
            try requirement.validate()
        }
    }

    public func evaluate(
        _ findings: [ValidationFinding],
        currentInputIdentity: ValidationInputIdentity? = nil,
        overrides: [ValidationPolicyOverride] = []
    ) throws -> ValidationPolicyEvaluation {
        try validate()
        for finding in findings {
            try finding.validate()
        }
        for override in overrides {
            try override.validate()
        }

        let findingsByID = Dictionary(grouping: findings, by: \.id)
        var failures: [ValidationPolicyFailure] = []
        var overriddenRuleIDs: [String] = []
        var appliedOverrideIDs: Set<UUID> = []

        for requirement in requirements.sorted(by: { $0.ruleID < $1.ruleID }) {
            guard let ruleFindings = findingsByID[requirement.ruleID],
                  !ruleFindings.isEmpty else {
                failures.append(
                    ValidationPolicyFailure(
                        ruleID: requirement.ruleID,
                        reasons: [.missingRule]
                    )
                )
                continue
            }

            let blockingFindings = ruleFindings.filter { finding in
                !failureReasons(
                    for: finding,
                    requirement: requirement,
                    currentInputIdentity: currentInputIdentity
                ).isEmpty
            }
            guard !blockingFindings.isEmpty else {
                continue
            }

            if let override = applicableOverride(
                for: blockingFindings,
                requirement: requirement,
                currentInputIdentity: currentInputIdentity,
                overrides: overrides
            ) {
                overriddenRuleIDs.append(requirement.ruleID)
                appliedOverrideIDs.insert(override.id)
                continue
            }

            let reasons = Set(blockingFindings.flatMap { finding in
                failureReasons(
                    for: finding,
                    requirement: requirement,
                    currentInputIdentity: currentInputIdentity
                )
            })
            failures.append(
                ValidationPolicyFailure(
                    ruleID: requirement.ruleID,
                    reasons: reasons.sorted { $0.rawValue < $1.rawValue }
                )
            )
        }

        let decision: ValidationPolicyDecision
        if !failures.isEmpty {
            decision = .block
        } else if !overriddenRuleIDs.isEmpty {
            decision = .override
        } else {
            decision = .allow
        }
        return ValidationPolicyEvaluation(
            policyID: id,
            decision: decision,
            failures: failures,
            overriddenRuleIDs: overriddenRuleIDs.sorted(),
            appliedOverrideIDs: appliedOverrideIDs.sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func failureReasons(
        for finding: ValidationFinding,
        requirement: ValidationRuleRequirement,
        currentInputIdentity: ValidationInputIdentity?
    ) -> Set<ValidationPolicyFailureReason> {
        var reasons: Set<ValidationPolicyFailureReason> = []
        if !requirement.acceptedOutcomes.contains(finding.outcome) {
            reasons.insert(.unacceptableOutcome)
        }
        if let acceptedFidelities = requirement.acceptedFidelities,
           !acceptedFidelities.contains(finding.fidelity) {
            reasons.insert(.unacceptableFidelity)
        }
        if let acceptedCompleteness = requirement.acceptedRegionCompleteness,
           !(finding.outcome == .passed && finding.regions.isEmpty),
           !acceptedCompleteness.contains(finding.regionCompleteness) {
            reasons.insert(.insufficientRegionCompleteness)
        }
        if requirement.requiresCurrentInput {
            guard let currentInputIdentity,
                  finding.inputIdentity.matchesCurrentInput(currentInputIdentity) else {
                reasons.insert(.staleInput)
                return reasons
            }
        }
        return reasons
    }

    private func applicableOverride(
        for blockingFindings: [ValidationFinding],
        requirement: ValidationRuleRequirement,
        currentInputIdentity: ValidationInputIdentity?,
        overrides: [ValidationPolicyOverride]
    ) -> ValidationPolicyOverride? {
        guard requirement.allowsOverride,
              let currentInputIdentity else {
            return nil
        }
        let requiredFindingIdentities = Set(blockingFindings.map(\.identity))
        return overrides.first { override in
            guard override.policyID == id,
                  override.inputIdentity.matchesCurrentInput(currentInputIdentity),
                  blockingFindings.allSatisfy({
                      $0.inputIdentity.matchesCurrentInput(override.inputIdentity)
                  }) else {
                return false
            }
            return requiredFindingIdentities.isSubset(of: Set(override.findingIdentities))
        }
    }
}
