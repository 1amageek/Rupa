import Foundation

public struct CADChallenge: Codable, Equatable, Sendable {
    public let id: CADBenchmarkCaseID
    public let category: CADBenchmarkCategory
    public let instruction: String
    public let requiredCapability: CADCapabilityRequirement
    public let outputRoles: [CADOutputRole]
    public let budget: CADCandidateBudget

    public init(
        id: CADBenchmarkCaseID,
        category: CADBenchmarkCategory,
        instruction: String,
        requiredCapability: CADCapabilityRequirement,
        outputRoles: [CADOutputRole],
        budget: CADCandidateBudget = CADCandidateBudget()
    ) {
        self.id = id
        self.category = category
        self.instruction = instruction
        self.requiredCapability = requiredCapability
        self.outputRoles = outputRoles
        self.budget = budget
    }

    public func validate() throws {
        try id.validate()
        guard id.category == category else {
            throw CADBenchmarkError.invalidInput(
                caseID: id.rawValue,
                reason: "Case ID category does not match challenge category."
            )
        }
        guard requiredCapability.id == category.capabilityID else {
            throw CADBenchmarkError.invalidCapability(
                caseID: id.rawValue,
                capabilityID: requiredCapability.id
            )
        }
        guard !instruction.isEmpty,
              instruction.trimmingCharacters(in: .whitespacesAndNewlines) == instruction else {
            throw CADBenchmarkError.invalidInput(caseID: id.rawValue, reason: "Instruction is invalid.")
        }
        try requiredCapability.validate(caseID: id)
        guard !outputRoles.isEmpty else {
            throw CADBenchmarkError.invalidInput(caseID: id.rawValue, reason: "No output role is declared.")
        }
        var names = Set<String>()
        for role in outputRoles {
            try role.validate(caseID: id)
            guard names.insert(role.name).inserted else {
                throw CADBenchmarkError.duplicateRole(caseID: id.rawValue, role: role.name)
            }
        }
        try budget.validate()
    }
}
