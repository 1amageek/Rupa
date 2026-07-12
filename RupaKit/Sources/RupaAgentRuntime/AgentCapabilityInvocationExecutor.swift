import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCapabilities
import RupaCore
import RupaDomainFoundation

public struct AgentCapabilityInvocationExecutor: Sendable {
    private let runner: AutomationRunner
    private let domainRegistry: DomainRegistry

    public init(
        runner: AutomationRunner = AutomationRunner(),
        domainRegistry: DomainRegistry = DomainRegistry()
    ) {
        self.runner = runner
        self.domainRegistry = domainRegistry
    }

    public func execute(
        _ invocation: CapabilityInvocation,
        descriptor: CapabilityDescriptor,
        agentDescriptor: AgentCapabilityDescriptor,
        sessionID: UUID,
        expectedWorkspaceRevision: WorkspaceRevision?,
        in session: EditorSession
    ) throws -> AgentCapabilityExecutionResult {
        try invocation.validate()
        guard invocation.dryRun == false || descriptor.execution.supportsDryRun else {
            throw AgentCapabilityExecutionError(
                code: .unsupportedRoute,
                message: "Capability \(descriptor.id.rawValue) does not support dry-run execution."
            )
        }
        if descriptor.execution.requiresTransactionRevision {
            guard let expected = invocation.expectedTransactionRevision,
                  expected.value == session.generation.value else {
                throw AgentCapabilityExecutionError(
                    code: .staleRevision,
                    message: "Capability \(descriptor.id.rawValue) requires the current document transaction revision."
                )
            }
        }
        if descriptor.execution.requiresWorkspaceRevision {
            guard let expectedWorkspaceRevision,
                  expectedWorkspaceRevision == session.workspaceState.revision else {
                throw AgentCapabilityExecutionError(
                    code: .staleRevision,
                    message: "Capability \(descriptor.id.rawValue) requires the current workspace revision."
                )
            }
        }

        switch agentDescriptor.access {
        case .automationCommand:
            return try executeAutomationCommand(
                invocation,
                descriptor: descriptor,
                sessionID: sessionID,
                expectedWorkspaceRevision: expectedWorkspaceRevision,
                in: session
            )
        case .domainCapability:
            return try executeDomainCapability(
                invocation,
                descriptor: descriptor,
                agentDescriptor: agentDescriptor,
                sessionID: sessionID,
                in: session
            )
        case .agentRequest:
            throw AgentCapabilityExecutionError(
                code: .unsupportedRoute,
                message: "Capability \(descriptor.id.rawValue) is still exposed through its typed Agent request route."
            )
        }
    }

    private func executeAutomationCommand(
        _ invocation: CapabilityInvocation,
        descriptor: CapabilityDescriptor,
        sessionID: UUID,
        expectedWorkspaceRevision: WorkspaceRevision?,
        in session: EditorSession
    ) throws -> AgentCapabilityExecutionResult {
        let command: AutomationCommand
        do {
            command = try JSONDecoder().decode(
                AutomationCommand.self,
                from: invocation.payload.canonicalJSONData()
            )
        } catch {
            throw AgentCapabilityExecutionError(
                code: .invalidPayload,
                message: "Capability \(descriptor.id.rawValue) payload is not a valid automation command: \(error)."
            )
        }
        guard effect(for: command.effect) == descriptor.effect else {
            throw AgentCapabilityExecutionError(
                code: .effectMismatch,
                message: "Automation command effect does not match capability \(descriptor.id.rawValue)."
            )
        }
        let batch = AutomationBatch(
            commands: [command],
            expectedGeneration: invocation.expectedTransactionRevision.map {
                DocumentGeneration($0.value)
            },
            expectedWorkspaceRevision: expectedWorkspaceRevision
        )
        let execution = try runner.executeBatchTransaction(
            batch,
            in: session,
            commits: !invocation.dryRun
        )
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

    private func executeDomainCapability(
        _ invocation: CapabilityInvocation,
        descriptor: CapabilityDescriptor,
        agentDescriptor: AgentCapabilityDescriptor,
        sessionID: UUID,
        in session: EditorSession
    ) throws -> AgentCapabilityExecutionResult {
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
            expectedGeneration: invocation.expectedTransactionRevision.map {
                DocumentGeneration($0.value)
            },
            dryRun: invocation.dryRun
        )
        let result = try DomainCommandExecutor(
            registry: domainRegistry,
            automationRunner: runner
        ).execute(request, in: session)
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
