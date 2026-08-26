import RupaAutomation
import RupaCore

/// A validated, immutable domain request and its concrete execution plan.
public struct DomainCommandPlanResolution: Sendable {
    public let request: DomainCommandRequest
    public let descriptor: DomainCapabilityDescriptor
    public let plan: DomainCommandPlan
    public let route: DomainCommandRoute
    public let expectedGeneration: DocumentGeneration?
    public let expectedTransactionRevision: DocumentTransactionRevision?
    public let automationEffect: AutomationCommandEffect?

    public init(
        request: DomainCommandRequest,
        descriptor: DomainCapabilityDescriptor,
        plan: DomainCommandPlan,
        route: DomainCommandRoute,
        expectedGeneration: DocumentGeneration?,
        expectedTransactionRevision: DocumentTransactionRevision?,
        automationEffect: AutomationCommandEffect? = nil
    ) {
        self.request = request
        self.descriptor = descriptor
        self.plan = plan
        self.route = route
        self.expectedGeneration = expectedGeneration
        self.expectedTransactionRevision = expectedTransactionRevision
        self.automationEffect = automationEffect
    }
}
