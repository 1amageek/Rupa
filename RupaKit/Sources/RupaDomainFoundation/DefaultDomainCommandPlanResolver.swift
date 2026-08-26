import RupaAutomation
import RupaCore

/// Resolves descriptor, namespace, dry-run, effect, and lowering contracts.
public struct DefaultDomainCommandPlanResolver: DomainCommandPlanResolving, Sendable {
    public let registry: DomainRegistry

    public init(registry: DomainRegistry) {
        self.registry = registry
    }

    public func resolve(_ request: DomainCommandRequest) throws -> DomainCommandPlanResolution {
        let descriptor = try descriptor(for: request)
        try validateDryRunSupport(request: request, descriptor: descriptor)
        let plan = try registry.lower(request)
        let routing = try route(for: plan)
        try validate(plan: plan, route: routing.route, descriptor: descriptor)
        let expectedGeneration = try Self.mergedExpectedGeneration(
            plan: routing.expectedGeneration,
            request: request.expectedGeneration
        )
        let expectedTransactionRevision = try Self.mergedExpectedTransactionRevision(
            plan: routing.expectedTransactionRevision,
            request: request.expectedTransactionRevision
        )
        return DomainCommandPlanResolution(
            request: request,
            descriptor: descriptor,
            plan: plan,
            route: routing.route,
            expectedGeneration: expectedGeneration,
            expectedTransactionRevision: expectedTransactionRevision,
            automationEffect: routing.automationEffect
        )
    }

    private func descriptor(
        for request: DomainCommandRequest
    ) throws -> DomainCapabilityDescriptor {
        guard let descriptor = registry.capabilityDescriptor(for: request.capabilityID) else {
            throw DomainRegistryError(
                code: .missingCapability,
                message: "No domain capability is registered for \(request.capabilityID.rawValue)."
            )
        }
        guard descriptor.namespace == request.namespace else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain command request namespace does not match the capability namespace."
            )
        }
        return descriptor
    }

    private func validateDryRunSupport(
        request: DomainCommandRequest,
        descriptor: DomainCapabilityDescriptor
    ) throws {
        guard !request.dryRun || descriptor.supportsDryRun else {
            throw EditorError(
                code: .commandInvalid,
                message: "Domain capability \(request.capabilityID.rawValue) does not support dry-run execution."
            )
        }
    }

    private func route(
        for plan: DomainCommandPlan
    ) throws -> (
        route: DomainCommandRoute,
        expectedGeneration: DocumentGeneration?,
        expectedTransactionRevision: DocumentTransactionRevision?,
        automationEffect: AutomationCommandEffect?
    ) {
        switch plan {
        case .query:
            return (.query, nil, nil, nil)
        case .documentTransaction(let transaction):
            try transaction.validate()
            return (
                .source,
                transaction.expectedGeneration,
                transaction.expectedTransactionRevision,
                nil
            )
        case .automationBatch(let batch):
            let effect = try batch.validatedEffect()
            let route: DomainCommandRoute
            switch effect {
            case .sourceMutation:
                route = .source
            case .workspaceMutation:
                route = .workspace
            case .readOnly:
                route = .readOnly
            }
            return (
                route,
                batch.expectedGeneration,
                batch.expectedTransactionRevision,
                effect
            )
        }
    }

    private func validate(
        plan: DomainCommandPlan,
        route: DomainCommandRoute,
        descriptor: DomainCapabilityDescriptor
    ) throws {
        let isCompatible: Bool
        switch (descriptor.effect, route, plan) {
        case (.query, .query, .query),
             (.query, .readOnly, .automationBatch):
            isCompatible = true
        case (.documentMutation, .source, .documentTransaction),
             (.documentMutation, .source, .automationBatch),
             (.documentMutation, .workspace, .automationBatch):
            isCompatible = true
        default:
            isCompatible = false
        }
        guard isCompatible else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain capability effect is incompatible with its lowered execution plan."
            )
        }
    }
}

public extension DefaultDomainCommandPlanResolver {
    static func mergedExpectedGeneration(
        plan: DocumentGeneration?,
        request: DocumentGeneration?
    ) throws -> DocumentGeneration? {
        if let plan, let request, plan != request {
            throw EditorError(
                code: .commandInvalid,
                message: "Domain command lowering returned an expected generation that conflicts with the request."
            )
        }
        return plan ?? request
    }

    static func mergedExpectedTransactionRevision(
        plan: DocumentTransactionRevision?,
        request: DocumentTransactionRevision?
    ) throws -> DocumentTransactionRevision? {
        if let plan, let request, plan != request {
            throw EditorError(
                code: .commandInvalid,
                message: "Domain command lowering returned a transaction revision that conflicts with the request."
            )
        }
        return plan ?? request
    }
}
