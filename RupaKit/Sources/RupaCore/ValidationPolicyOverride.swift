import Foundation

public struct ValidationPolicyOverride: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var policyID: String
    public var actorID: String
    public var recordedAt: Date
    public var reason: String
    public var inputIdentity: ValidationInputIdentity
    public var findingIdentities: [ValidationFindingIdentity]

    public init(
        id: UUID = UUID(),
        policyID: String,
        actorID: String,
        recordedAt: Date,
        reason: String,
        inputIdentity: ValidationInputIdentity,
        findingIdentities: [ValidationFindingIdentity]
    ) {
        self.id = id
        self.policyID = policyID
        self.actorID = actorID
        self.recordedAt = recordedAt
        self.reason = reason
        self.inputIdentity = inputIdentity
        self.findingIdentities = findingIdentities
    }

    public func validate() throws {
        guard !policyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !actorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Validation overrides require policy, actor, and reason identities."
            )
        }
        try inputIdentity.validate()
        guard !findingIdentities.isEmpty,
              Set(findingIdentities).count == findingIdentities.count else {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Validation overrides must reference unique findings."
            )
        }
    }
}
