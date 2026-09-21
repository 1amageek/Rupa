struct CADCompoundChallengeInput: Codable, Equatable, Hashable, Sendable {
    let members: [CADCompoundMemberInput]

    init(members: [CADCompoundMemberInput]) {
        self.members = members
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        guard !members.isEmpty else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A compound must contain at least one member."
            )
        }
        var roles = Set<String>()
        for member in members {
            try member.validate(caseID: caseID)
            guard roles.insert(member.role).inserted else {
                throw CADBenchmarkError.duplicateRole(caseID: caseID.rawValue, role: member.role)
            }
        }
    }
}
