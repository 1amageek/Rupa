import Foundation

struct CADCompoundMemberInput: Codable, Equatable, Hashable, Sendable {
    let role: String
    let primitive: CADPrimitiveKind
    let box: CADBoxChallengeInput?
    let cylinder: CADCylinderChallengeInput?

    init(role: String, box: CADBoxChallengeInput) {
        self.role = role
        self.primitive = .box
        self.box = box
        self.cylinder = nil
    }

    init(role: String, cylinder: CADCylinderChallengeInput) {
        self.role = role
        self.primitive = .cylinder
        self.box = nil
        self.cylinder = cylinder
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRole.isEmpty, trimmedRole == role else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Compound member roles must be non-empty and unpadded."
            )
        }
        switch primitive {
        case .box:
            guard let box, cylinder == nil else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A box member must carry only box geometry."
                )
            }
            try box.validate(caseID: caseID)
        case .cylinder:
            guard let cylinder, box == nil else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A cylinder member must carry only cylinder geometry."
                )
            }
            try cylinder.validate(caseID: caseID)
        }
    }
}
