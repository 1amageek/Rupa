import Foundation

public struct CADUnsupportedDeclaration: Codable, Equatable, Hashable, Sendable {
    public let capabilityID: String
    public let capabilityVersion: String
    public let reason: CADUnsupportedReasonCode

    public init(capabilityID: String, capabilityVersion: String, reason: CADUnsupportedReasonCode) {
        self.capabilityID = capabilityID
        self.capabilityVersion = capabilityVersion
        self.reason = reason
    }

    public func validate(for challenge: CADChallenge, capabilities: CADCapabilitySnapshot) throws {
        guard capabilityID == challenge.requiredCapability.id,
              capabilityVersion == challenge.requiredCapability.version else {
            throw CADBenchmarkError.unsupportedCapabilityMismatch(
                caseID: challenge.id.rawValue,
                capabilityID: capabilityID,
                reason: "Declaration does not identify the required capability/version."
            )
        }
        guard let status = capabilities.status(for: challenge.requiredCapability), status.available == false else {
            throw CADBenchmarkError.unsupportedCapabilityMismatch(
                caseID: challenge.id.rawValue,
                capabilityID: capabilityID,
                reason: "The declared capability is available in the observed snapshot."
            )
        }
        if challenge.category == .sphere && reason != .analyticSphereUnavailable {
            throw CADBenchmarkError.unsupportedCapabilityMismatch(
                caseID: challenge.id.rawValue,
                capabilityID: capabilityID,
                reason: "Sphere absence must use the analyticSphereUnavailable reason."
            )
        }
        if challenge.category != .sphere && reason == .analyticSphereUnavailable {
            throw CADBenchmarkError.unsupportedCapabilityMismatch(
                caseID: challenge.id.rawValue,
                capabilityID: capabilityID,
                reason: "The analyticSphereUnavailable reason is reserved for sphere challenges."
            )
        }
    }
}
