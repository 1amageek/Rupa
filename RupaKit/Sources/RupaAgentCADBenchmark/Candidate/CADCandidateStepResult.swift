import Foundation

public struct CADCandidateStepResult: Codable, Equatable, Sendable {
    public let stepIndex: Int
    public let operation: String
    public let status: CADStepResultStatus
    public let primaryFeatureID: String?
    public let createdFeatureIDs: [String]
    public let diagnostics: [String]

    public init(
        stepIndex: Int,
        operation: String,
        status: CADStepResultStatus,
        primaryFeatureID: String? = nil,
        createdFeatureIDs: [String] = [],
        diagnostics: [String] = []
    ) {
        self.stepIndex = stepIndex
        self.operation = operation
        self.status = status
        self.primaryFeatureID = primaryFeatureID
        self.createdFeatureIDs = createdFeatureIDs
        self.diagnostics = diagnostics
    }

    public func validate() throws {
        guard stepIndex >= 0,
              !operation.isEmpty,
              operation.trimmingCharacters(in: .whitespacesAndNewlines) == operation,
              primaryFeatureID.map({ !$0.isEmpty }) ?? true,
              createdFeatureIDs.allSatisfy({ !$0.isEmpty }),
              Set(createdFeatureIDs).count == createdFeatureIDs.count,
              diagnostics.allSatisfy({ $0.isEmpty == false }) else {
            throw CADBenchmarkError.invalidInput(
                caseID: "T12.RESULT",
                reason: "Candidate step result must have unique created IDs; the primary ID may alias one created ID."
            )
        }
    }
}
