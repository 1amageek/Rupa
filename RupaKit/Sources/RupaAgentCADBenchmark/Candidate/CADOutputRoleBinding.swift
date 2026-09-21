import Foundation

public struct CADOutputRoleBinding: Codable, Equatable, Hashable, Sendable {
    public let role: String
    public let stepIndex: Int
    public let selector: CADOutputRoleSelector

    public init(role: String, stepIndex: Int, selector: CADOutputRoleSelector) {
        self.role = role
        self.stepIndex = stepIndex
        self.selector = selector
    }

    public func validate(caseID: CADBenchmarkCaseID) throws {
        guard !role.isEmpty,
              role.trimmingCharacters(in: .whitespacesAndNewlines) == role,
              stepIndex >= 0 else {
            throw CADBenchmarkError.invalidBinding(
                caseID: caseID.rawValue,
                role: role,
                reason: "Role names must be unpadded and step indexes must be non-negative."
            )
        }
        try selector.validate(caseID: caseID, role: role)
    }
}
