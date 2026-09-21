import Foundation

struct CADCanonicalChallengeDefinition: Sendable {
    let id: CADBenchmarkCaseID
    let category: CADBenchmarkCategory
    let input: CADChallengeInput
    let outputRoles: [CADOutputRole]
    let requiredCapability: CADCapabilityRequirement
    let budget: CADCandidateBudget

    init(
        id: CADBenchmarkCaseID,
        category: CADBenchmarkCategory,
        input: CADChallengeInput,
        outputRoles: [CADOutputRole],
        requiredCapability: CADCapabilityRequirement,
        budget: CADCandidateBudget = CADCandidateBudget()
    ) {
        self.id = id
        self.category = category
        self.input = input
        self.outputRoles = outputRoles
        self.requiredCapability = requiredCapability
        self.budget = budget
    }

    func validate() throws {
        try id.validate()
        guard id.category == category, input.category == category else {
            throw CADBenchmarkError.invalidInput(
                caseID: id.rawValue,
                reason: "Canonical case identity, category, and input category must agree."
            )
        }
        try CADChallengeGeometryValidator.validate(input, caseID: id)
        try requiredCapability.validate(caseID: id)
        guard requiredCapability.id == category.capabilityID else {
            throw CADBenchmarkError.invalidCapability(
                caseID: id.rawValue,
                capabilityID: requiredCapability.id
            )
        }
        guard !outputRoles.isEmpty else {
            throw CADBenchmarkError.invalidInput(caseID: id.rawValue, reason: "No output role is declared.")
        }
        var roleNames = Set<String>()
        for role in outputRoles {
            try role.validate(caseID: id)
            guard roleNames.insert(role.name).inserted else {
                throw CADBenchmarkError.duplicateRole(caseID: id.rawValue, role: role.name)
            }
        }
        try budget.validate()
    }

    func projectChallenge() throws -> CADChallenge {
        try validate()
        let challenge = CADChallenge(
            id: id,
            category: category,
            instruction: CADChallengeInstruction.make(id: id, category: category, input: input),
            requiredCapability: requiredCapability,
            outputRoles: outputRoles,
            budget: budget
        )
        try challenge.validate()
        return challenge
    }
}
