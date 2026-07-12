import Foundation
import RupaCoreTypes

public struct CapabilityInvocation: Codable, Equatable, Sendable {
    public var capabilityID: CapabilityID
    public var version: CapabilityVersion
    public var payload: CanonicalValue
    public var expectedTransactionRevision: DocumentTransactionRevision?
    public var dryRun: Bool

    public init(
        capabilityID: CapabilityID,
        version: CapabilityVersion,
        payload: CanonicalValue = .object([:]),
        expectedTransactionRevision: DocumentTransactionRevision? = nil,
        dryRun: Bool = false
    ) {
        self.capabilityID = capabilityID
        self.version = version
        self.payload = payload
        self.expectedTransactionRevision = expectedTransactionRevision
        self.dryRun = dryRun
    }

    public func validate() throws {
        do {
            try capabilityID.validate()
        } catch let error as EditorError {
            throw CapabilityRegistryError(code: .invalidDescriptor, message: error.message)
        }
        try payload.validate()
    }
}
