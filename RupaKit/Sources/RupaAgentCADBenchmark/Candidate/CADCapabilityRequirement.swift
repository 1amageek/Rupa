import Foundation

public struct CADCapabilityRequirement: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let version: String

    public init(id: String, version: String = "1") {
        self.id = id
        self.version = version
    }

    public func validate(caseID: CADBenchmarkCaseID) throws {
        let validID = id.split(separator: ".", omittingEmptySubsequences: false).count >= 2
            && id.trimmingCharacters(in: .whitespacesAndNewlines) == id
            && !id.isEmpty
        let validVersion = version.trimmingCharacters(in: .whitespacesAndNewlines) == version
            && !version.isEmpty
        guard validID, validVersion else {
            throw CADBenchmarkError.invalidCapability(caseID: caseID.rawValue, capabilityID: id)
        }
    }
}
