import RupaCore

public protocol DomainCommandLowering: Sendable {
    var capabilityID: DomainCapabilityID { get }

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan
}
