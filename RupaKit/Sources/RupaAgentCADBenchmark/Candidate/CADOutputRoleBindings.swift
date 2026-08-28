public struct CADOutputRoleBindings: Codable, Equatable, Hashable, Sendable {
    public let bindings: [CADOutputRoleBinding]

    public init(bindings: [CADOutputRoleBinding]) {
        self.bindings = bindings
    }

    public func validate(
        for challenge: CADChallenge,
        availableStepResults: [CADCandidateStepResult]
    ) throws {
        var resultsByStep = [Int: CADCandidateStepResult](minimumCapacity: availableStepResults.count)
        for result in availableStepResults {
            try result.validate()
            guard resultsByStep.updateValue(result, forKey: result.stepIndex) == nil else {
                throw CADBenchmarkError.invalidBinding(
                    caseID: challenge.id.rawValue,
                    role: "unknown",
                    reason: "Candidate response step indexes must be unique."
                )
            }
        }
        var names = Set<String>()
        var resolvedFeatureIDs = Set<String>()
        for binding in bindings {
            try binding.validate(caseID: challenge.id)
            guard names.insert(binding.role).inserted else {
                throw CADBenchmarkError.duplicateRole(caseID: challenge.id.rawValue, role: binding.role)
            }
            guard let result = resultsByStep[binding.stepIndex] else {
                throw CADBenchmarkError.invalidBinding(
                    caseID: challenge.id.rawValue,
                    role: binding.role,
                    reason: "Step index is outside the candidate response sequence."
                )
            }
            guard result.status == .published else {
                throw CADBenchmarkError.invalidBinding(
                    caseID: challenge.id.rawValue,
                    role: binding.role,
                    reason: "Output roles must reference a published candidate step."
                )
            }
            let featureID = try binding.selector.resolveFeatureID(
                from: result,
                caseID: challenge.id,
                role: binding.role
            )
            guard resolvedFeatureIDs.insert(featureID).inserted else {
                throw CADBenchmarkError.invalidBinding(
                    caseID: challenge.id.rawValue,
                    role: binding.role,
                    reason: "The resolved FeatureID is already bound to another output role."
                )
            }
        }
        let declared = Set(challenge.outputRoles.map(\.name))
        let supplied = Set(bindings.map(\.role))
        guard supplied == declared else {
            throw CADBenchmarkError.invalidBinding(
                caseID: challenge.id.rawValue,
                role: supplied.symmetricDifference(declared).sorted().first ?? "unknown",
                reason: "Bindings must cover exactly the declared output roles."
            )
        }
    }
}
