import Foundation

public struct CADOutputRole: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }

    public func validate(caseID: CADBenchmarkCaseID) throws {
        guard !name.isEmpty,
              name.trimmingCharacters(in: .whitespacesAndNewlines) == name,
              !description.isEmpty else {
            throw CADBenchmarkError.invalidInput(caseID: caseID.rawValue, reason: "Output role is invalid.")
        }
    }
}
