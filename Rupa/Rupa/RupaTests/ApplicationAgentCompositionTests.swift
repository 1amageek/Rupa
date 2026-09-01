import Foundation
import RupaAgentProtocol
import RupaAgentRuntime
import RupaCADDomain
import RupaCoreTypes
import RupaDomainFoundation
import Testing
@testable import Rupa

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationDomainRegistryCompilerResolvesExactlyTwelveCADOperations() throws {
    let operationIDs = RupaCADSemanticOperationID.all
    #expect(operationIDs.count == 12)
    #expect(Set(operationIDs).count == 12)

    let compiler = try ApplicationDomainRegistry.makeCADSemanticCompiler()
    for operationID in operationIDs {
        do {
            _ = try compiler.compile(
                SemanticDirectRequest(
                    schemaVersion: .current,
                    invocation: SemanticOperationInvocation(
                        operationID: operationID,
                        operationVersion: RupaCADDomain.operationVersion
                    )
                ),
                context: SemanticCompilationContext(),
                limits: ProjectAgentSemanticProgramLimits.standard
            )
            Issue.record("A CAD operation without required arguments unexpectedly compiled: \(operationID).")
        } catch let error as SemanticCompilationError {
            guard case .missingArgument(let node, _) = error else {
                Issue.record("The App compiler did not resolve \(operationID): \(error).")
                continue
            }
            #expect(node == ProgramNodeSymbol("direct"))
        }
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationCapabilityDiscoveryProjectsTheCompilerRegistryExactly() throws {
    let compiler = try ApplicationDomainRegistry.makeCADSemanticCompiler()
    let controller = ProjectAgentCommandController(
        semanticProgramCompiler: compiler
    )
    let discovered = controller.capabilityDescriptors().filter {
        $0.name.hasPrefix("cad.")
    }
    let registered = compiler.semanticOperationRegistry.sortedDescriptors()

    #expect(discovered.map(\.name) == registered.map(\.operationID.rawValue))
    #expect(discovered.count == 12)
    for (capability, descriptor) in zip(discovered, registered) {
        let operation = try #require(capability.semanticOperation)
        #expect(capability.access == .agentRequest)
        #expect(operation.version == descriptor.version)
        #expect(operation.inputs.map(\.id) == descriptor.inputs.map(\.id.rawValue))
        #expect(operation.inputs.map(\.type) == descriptor.inputs.map(\.type))
        #expect(operation.outputs.map(\.id) == descriptor.outputs.map(\.id.rawValue))
        #expect(operation.outputs.map(\.type) == descriptor.outputs.map(\.type))
        #expect(operation.outputs.map(\.selector) == descriptor.outputs.map(\.selector))
        #expect(operation.route == descriptor.route)
        #expect(operation.effect == descriptor.effect)
        #expect(operation.invocationForms == [.direct, .program])
    }

    let codec = AgentMessageCodec()
    let encoded = try codec.encode(AgentResponse.capabilities(discovered))
    #expect(try codec.decodeResponse(from: encoded) == .capabilities(discovered))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationAgentRouterPreservesEnvelopeCorrelationForItsInjectedProjectHandler() async {
    let projectHandler = ApplicationAgentEnvelopeHandlerProbe(
        response: .ordinary(.status(AgentStatus(running: true, sessionCount: 1)))
    )
    let lifecycle = ApplicationAgentLifecycleProbe()
    let router = ApplicationAgentRequestRouter(
        projectHandler: projectHandler,
        lifecycle: lifecycle
    )
    let envelope = AgentRequestEnvelope(
        id: "app-router-correlation",
        params: .status
    )

    let handled = await router.handle(envelope)

    #expect(await projectHandler.handledEnvelopes() == [envelope])
    #expect(lifecycle.saveRequests.isEmpty)
    guard case .ordinary(.status(let status)) = handled else {
        Issue.record("The project handler response did not remain ordinary.")
        return
    }
    #expect(status == AgentStatus(running: true, sessionCount: 1))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationAgentRouterKeepsSaveAsAnOrdinaryResponse() async {
    let sessionID = UUID()
    let generation = DocumentGeneration(7)
    let result = SaveResult(
        message: "Saved by App authority.",
        path: "/tmp/app-authority.rupa",
        generation: generation,
        dirty: false,
        diagnostics: []
    )
    let projectHandler = ApplicationAgentEnvelopeHandlerProbe(
        response: .ordinary(.status(AgentStatus(running: true, sessionCount: 1)))
    )
    let lifecycle = ApplicationAgentLifecycleProbe(saveOutcome: .saved(result))
    let router = ApplicationAgentRequestRouter(
        projectHandler: projectHandler,
        lifecycle: lifecycle
    )
    let envelope = AgentRequestEnvelope(
        id: "app-save-correlation",
        params: .save(
            sessionID: sessionID,
            expectedGeneration: generation
        )
    )

    let handled = await router.handle(envelope)

    #expect(await projectHandler.handledEnvelopes().isEmpty)
    #expect(
        lifecycle.saveRequests == [
            ApplicationAgentSaveRequest(
                sessionID: sessionID,
                expectedGeneration: generation
            ),
        ]
    )
    guard case .ordinary(.save(let actual)) = handled else {
        Issue.record("Save did not remain an ordinary correlated response.")
        return
    }
    #expect(actual == result)
}

private actor ApplicationAgentEnvelopeHandlerProbe: AgentRequestHandling {
    private var envelopes: [AgentRequestEnvelope] = []
    private let response: AgentHandledResponse

    init(response: AgentHandledResponse) {
        self.response = response
    }

    func handle(_ envelope: AgentRequestEnvelope) async -> AgentHandledResponse {
        envelopes.append(envelope)
        return response
    }

    func handledEnvelopes() -> [AgentRequestEnvelope] {
        envelopes
    }
}

private struct ApplicationAgentSaveRequest: Equatable {
    let sessionID: UUID
    let expectedGeneration: DocumentGeneration?
}

@MainActor
private final class ApplicationAgentLifecycleProbe: ApplicationAgentProjectLifecycle {
    private(set) var saveRequests: [ApplicationAgentSaveRequest] = []
    private let saveOutcome: ApplicationAgentSaveOutcome

    init(
        saveOutcome: ApplicationAgentSaveOutcome = .saved(
            SaveResult(
                message: "Unused fixture save.",
                path: "/tmp/unused.rupa",
                generation: DocumentGeneration(1),
                dirty: false,
                diagnostics: []
            )
        )
    ) {
        self.saveOutcome = saveOutcome
    }

    func save(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    ) async throws -> ApplicationAgentSaveOutcome {
        saveRequests.append(
            ApplicationAgentSaveRequest(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        return saveOutcome
    }
}
