import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCapabilities
import RupaCore
import RupaDomainFoundation
import RupaKit
import RupaProject

/// Executes capability mutations through the shared project authority.
public struct ProjectAgentCapabilityInvocationExecutor: Sendable {
    private let domainRegistry: DomainRegistry

    public init(domainRegistry: DomainRegistry = DomainRegistry()) {
        self.domainRegistry = domainRegistry
    }

    @MainActor
    public func execute(
        _ invocation: CapabilityInvocation,
        descriptor: CapabilityDescriptor,
        agentDescriptor: AgentCapabilityDescriptor,
        sessionID: UUID,
        expectedWorkspaceRevision: WorkspaceRevision?,
        workspace: ProjectWorkspace,
        snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> AgentCapabilityExecutionResult {
        try invocation.validate()
        guard invocation.dryRun == false || descriptor.execution.supportsDryRun else {
            throw AgentCapabilityExecutionError(
                code: .unsupportedRoute,
                message: "Capability \(descriptor.id.rawValue) does not support dry-run execution."
            )
        }
        if descriptor.execution.requiresTransactionRevision {
            guard invocation.expectedTransactionRevision == snapshot.transactionRevision else {
                throw AgentCapabilityExecutionError(
                    code: .staleRevision,
                    message: "Capability \(descriptor.id.rawValue) requires the current document transaction revision."
                )
            }
        }
        if descriptor.execution.requiresWorkspaceRevision {
            guard expectedWorkspaceRevision == snapshot.workspaceState.revision else {
                throw AgentCapabilityExecutionError(
                    code: .staleWorkspaceRevision,
                    message: "Capability \(descriptor.id.rawValue) requires the current workspace revision."
                )
            }
        }

        switch agentDescriptor.access {
        case .automationCommand:
            return try await executeAutomationCommand(
                invocation,
                descriptor: descriptor,
                sessionID: sessionID,
                expectedWorkspaceRevision: expectedWorkspaceRevision,
                workspace: workspace,
                snapshot: snapshot,
                operationGuard: operationGuard
            )
        case .domainCapability:
            return try await executeDomainCapability(
                invocation,
                descriptor: descriptor,
                agentDescriptor: agentDescriptor,
                sessionID: sessionID,
                workspace: workspace,
                snapshot: snapshot,
                operationGuard: operationGuard
            )
        case .agentRequest:
            throw AgentCapabilityExecutionError(
                code: .unsupportedRoute,
                message: "Capability \(descriptor.id.rawValue) is exposed through its typed Agent request route."
            )
        }
    }

    @MainActor
    private func executeAutomationCommand(
        _ invocation: CapabilityInvocation,
        descriptor: CapabilityDescriptor,
        sessionID: UUID,
        expectedWorkspaceRevision: WorkspaceRevision?,
        workspace: ProjectWorkspace,
        snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> AgentCapabilityExecutionResult {
        let command: AutomationCommand
        do {
            command = try JSONDecoder().decode(
                AutomationCommand.self,
                from: invocation.payload.canonicalJSONData()
            )
        } catch {
            throw AgentCapabilityExecutionError(
                code: .invalidPayload,
                message: "Capability \(descriptor.id.rawValue) payload is not a valid Automation command: \(error)."
            )
        }
        guard case .object(let commandEnvelope) = invocation.payload,
              commandEnvelope.count == 1,
              commandEnvelope[descriptor.name] != nil else {
            throw AgentCapabilityExecutionError(
                code: .effectMismatch,
                message: "Automation command identity does not match capability \(descriptor.id.rawValue)."
            )
        }
        guard effect(for: command.effect) == descriptor.effect else {
            throw AgentCapabilityExecutionError(
                code: .effectMismatch,
                message: "Automation command effect does not match capability \(descriptor.id.rawValue)."
            )
        }
        let execution = try await workspace.executeAutomation(
            AutomationBatch(
                commands: [command],
                expectedGeneration: snapshot.documentGeneration,
                expectedTransactionRevision: snapshot.transactionRevision,
                expectedWorkspaceRevision: expectedWorkspaceRevision
            ),
            from: snapshot,
            operationGuard: operationGuard,
            dryRun: invocation.dryRun
        ).execution
        guard let result = execution.results.first else {
            throw AgentCapabilityExecutionError(
                code: .invalidResult,
                message: "Automation capability \(descriptor.id.rawValue) produced no result."
            )
        }
        return try AgentCapabilityExecutionResult(
            capabilityID: invocation.capabilityID,
            version: invocation.version,
            sessionID: sessionID,
            automation: result
        )
    }

    @MainActor
    private func executeDomainCapability(
        _ invocation: CapabilityInvocation,
        descriptor: CapabilityDescriptor,
        agentDescriptor: AgentCapabilityDescriptor,
        sessionID: UUID,
        workspace: ProjectWorkspace,
        snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> AgentCapabilityExecutionResult {
        let domainID = DomainCapabilityID(rawValue: agentDescriptor.name)
        guard let domainDescriptor = domainRegistry.capabilityDescriptor(for: domainID) else {
            throw AgentCapabilityExecutionError(
                code: .unsupportedRoute,
                message: "Domain capability \(domainID.rawValue) is not registered."
            )
        }
        let payload: SemanticJSONValue
        do {
            payload = try JSONDecoder().decode(
                SemanticJSONValue.self,
                from: invocation.payload.canonicalJSONData()
            )
        } catch {
            throw AgentCapabilityExecutionError(
                code: .invalidPayload,
                message: "Domain capability \(descriptor.id.rawValue) payload is invalid: \(error)."
            )
        }
        let request = DomainCommandRequest(
            capabilityID: domainDescriptor.id,
            namespace: domainDescriptor.namespace,
            payload: payload,
            expectedGeneration: snapshot.documentGeneration,
            expectedTransactionRevision: invocation.expectedTransactionRevision,
            dryRun: invocation.dryRun
        )
        let plan = try ProjectDomainCommandDispatcher(registry: domainRegistry)
            .dispatch(request, from: snapshot)
        let result = try await workspace.execute(
            plan,
            operationGuard: operationGuard
        )
        return try AgentCapabilityExecutionResult(
            capabilityID: invocation.capabilityID,
            version: invocation.version,
            sessionID: sessionID,
            domain: result
        )
    }

    private func effect(for effect: AutomationCommandEffect) -> CapabilityEffect {
        switch effect {
        case .readOnly:
            .query
        case .sourceMutation:
            .sourceMutation
        case .workspaceMutation:
            .workspaceMutation
        }
    }
}
