import Foundation
import RupaAutomation
import RupaCapabilities
import RupaCoreTypes
import RupaDomainFoundation

public struct AgentCapabilityExecutionResult: Codable, Equatable, Sendable {
    public var capabilityID: CapabilityID
    public var version: CapabilityVersion
    public var sessionID: UUID
    public var automation: AutomationResult?
    public var domain: DomainExecutionResult?

    private enum CodingKeys: String, CodingKey {
        case capabilityID
        case version
        case sessionID
        case automation
        case domain
    }

    public init(
        capabilityID: CapabilityID,
        version: CapabilityVersion,
        sessionID: UUID,
        automation: AutomationResult? = nil,
        domain: DomainExecutionResult? = nil
    ) throws {
        guard (automation == nil) != (domain == nil) else {
            throw AgentCapabilityExecutionError(
                code: .invalidResult,
                message: "Capability execution results must contain exactly one outcome."
            )
        }
        self.capabilityID = capabilityID
        self.version = version
        self.sessionID = sessionID
        self.automation = automation
        self.domain = domain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            capabilityID: container.decode(CapabilityID.self, forKey: .capabilityID),
            version: container.decode(CapabilityVersion.self, forKey: .version),
            sessionID: container.decode(UUID.self, forKey: .sessionID),
            automation: container.decodeIfPresent(AutomationResult.self, forKey: .automation),
            domain: container.decodeIfPresent(DomainExecutionResult.self, forKey: .domain)
        )
    }

    public func validate() throws {
        try capabilityID.validate()
        guard (automation == nil) != (domain == nil) else {
            throw AgentCapabilityExecutionError(
                code: .invalidResult,
                message: "Capability execution results must contain exactly one outcome."
            )
        }
    }
}
