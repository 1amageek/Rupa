import RupaAgentProtocol
import RupaCapabilities
import RupaCoreTypes
import RupaDomainFoundation

public extension AgentCapabilityDescriptor {
    func capabilityDescriptor() throws -> CapabilityDescriptor {
        let descriptor = CapabilityDescriptor(
            id: CapabilityID(rawValue: "agent.\(name)"),
            version: CapabilityVersion(major: 1, minor: 0, patch: 0),
            category: CapabilityCategoryID(rawValue: "agent.\(category.rawValue)"),
            name: name,
            summary: summary,
            effect: capabilityEffect,
            result: capabilityResult,
            targets: targets.map {
                CapabilityTargetDescriptor(
                    id: $0.rawValue,
                    name: $0.rawValue,
                    summary: "Agent target kind \($0.rawValue)."
                )
            },
            parameters: try inputParameters.map { try $0.capabilityParameterDescriptor() },
            execution: CapabilityExecutionContract(
                supportsDryRun: supportsDryRun,
                supportsCancellation: domainContract?.supportsCancellation ?? false,
                reportsProgress: domainContract?.reportsProgress ?? false,
                determinism: capabilityDeterminism,
                requiresTransactionRevision: requiresExpectedSourceGeneration,
                requiresWorkspaceRevision: requiresExpectedWorkspaceRevision,
                retrySafe: stateEffect == .readOnly
            ),
            availability: CapabilityAvailability(surfaces: [.agent]),
            knownErrorCodes: domainContract?.knownErrorCodes.map(\.rawValue) ?? ["command.invalid"],
            failureMode: failureMode
        )
        try descriptor.validate()
        return descriptor
    }

    private var capabilityEffect: CapabilityEffect {
        if let domainContract {
            switch domainContract.effect {
            case .query:
                return .query
            case .documentMutation:
                return .sourceMutation
            case .artifactGeneration:
                return .artifactGeneration
            case .export:
                return .export
            case .externalJob:
                return .externalJob
            }
        }
        switch stateEffect {
        case .readOnly:
            return .query
        case .sourceMutation:
            return .sourceMutation
        case .workspaceMutation:
            return .workspaceMutation
        }
    }

    private var capabilityResult: CapabilityResultDescriptor {
        if let domainContract {
            return CapabilityResultDescriptor(
                kind: capabilityResultKind(domainContract.resultKind),
                maximumFidelity: domainContract.resultFidelity?.rawValue
            )
        }
        switch stateEffect {
        case .readOnly:
            return CapabilityResultDescriptor(kind: .semanticPayload)
        case .sourceMutation:
            return CapabilityResultDescriptor(kind: .sourceTransaction)
        case .workspaceMutation:
            return CapabilityResultDescriptor(kind: .workspaceTransaction)
        }
    }

    private var capabilityDeterminism: CapabilityDeterminism {
        switch domainContract?.determinism {
        case .deterministic:
            return .deterministic
        case .deterministicWithDeclaredEnvironment:
            return .deterministicWithDeclaredEnvironment
        case .nondeterministic:
            return .nondeterministic
        case nil:
            return .deterministic
        }
    }

    private func capabilityResultKind(
        _ resultKind: DomainCapabilityResultKind
    ) -> CapabilityResultKind {
        switch resultKind {
        case .semanticPayload:
            return .semanticPayload
        case .documentTransaction:
            return .sourceTransaction
        case .validationReport:
            return .validationReport
        case .artifactReference:
            return .artifactReference
        case .exportArtifact:
            return .exportArtifact
        case .externalJob:
            return .externalJob
        }
    }
}
