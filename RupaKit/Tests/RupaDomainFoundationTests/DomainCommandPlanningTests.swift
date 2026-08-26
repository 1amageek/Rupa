import RupaAutomation
import RupaCore
import RupaCoreTypes
import Testing
@testable import RupaDomainFoundation

@Test(.timeLimit(.minutes(1)))
func defaultDomainCommandPlanResolverClassifiesMutationAndReadRoutes() throws {
    let namespace: SemanticNamespaceID = "fixture"
    let sourceID: DomainCapabilityID = "fixture.source"
    let workspaceID: DomainCapabilityID = "fixture.workspace"
    let readOnlyID: DomainCapabilityID = "fixture.readOnly"
    let queryID: DomainCapabilityID = "fixture.query"
    let registry = try makePlanningRegistry(
        namespace: namespace,
        lowerings: [
            PlanningLowering(
                capabilityID: sourceID,
                plan: .documentTransaction(
                    DomainDocumentTransaction(
                        name: "source",
                        sourceCommands: [.renameDocument(name: "After")],
                        semanticMutations: [
                            .upsert(
                                SemanticExtensionEnvelope(
                                    namespace: namespace,
                                    schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
                                    payload: .object([:])
                                )
                            ),
                        ]
                    )
                )
            ),
            PlanningLowering(
                capabilityID: workspaceID,
                plan: .automationBatch(
                    AutomationBatch(commands: [.setDisplayUnit(.meter)])
                )
            ),
            PlanningLowering(
                capabilityID: readOnlyID,
                plan: .automationBatch(
                    AutomationBatch(commands: [.describeDocument])
                )
            ),
            PlanningLowering(
                capabilityID: queryID,
                plan: .query(PlanningQuery())
            ),
        ]
    )
    let resolver = DefaultDomainCommandPlanResolver(registry: registry)

    let source = try resolver.resolve(request(for: sourceID, namespace: namespace))
    let workspace = try resolver.resolve(request(for: workspaceID, namespace: namespace))
    let readOnly = try resolver.resolve(request(for: readOnlyID, namespace: namespace))
    let query = try resolver.resolve(request(for: queryID, namespace: namespace))

    #expect(source.route == .source)
    #expect(workspace.route == .workspace)
    #expect(readOnly.route == .readOnly)
    #expect(query.route == .query)
    #expect(source.expectedGeneration == nil)
    #expect(workspace.automationEffect == .workspaceMutation)
    #expect(readOnly.automationEffect == .readOnly)
}

@Test(.timeLimit(.minutes(1)))
func defaultDomainCommandPlanResolverRejectsEffectRouteMismatch() throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.invalid"
    let registry = try makePlanningRegistry(
        namespace: namespace,
        lowerings: [
            PlanningLowering(
                capabilityID: capabilityID,
                plan: .automationBatch(
                    AutomationBatch(commands: [.describeDocument])
                )
            ),
        ],
        effects: [.documentMutation]
    )

    var caught: DomainRegistryError?
    do {
        _ = try DefaultDomainCommandPlanResolver(registry: registry).resolve(
            request(for: capabilityID, namespace: namespace)
        )
    } catch let error as DomainRegistryError {
        caught = error
    }

    #expect(caught?.code == .invalidRegistration)
    #expect(caught?.message == "Domain capability effect is incompatible with its lowered execution plan.")
}

@Test(.timeLimit(.minutes(1)))
func domainDocumentTransactionExecutionCommandRetainsNamespaceAndMutations() throws {
    let namespace: SemanticNamespaceID = "fixture"
    let envelope = SemanticExtensionEnvelope(
        namespace: namespace,
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object([:])
    )
    let transaction = DomainDocumentTransaction(
        name: "canonical",
        sourceCommands: [],
        semanticMutations: [.upsert(envelope)]
    )
    let commands = transaction.executionEditorCommands(namespace: namespace)

    guard case .applyNamespacedSemanticExtensionMutations(
        let commandNamespace,
        let mutations
    ) = commands.last else {
        Issue.record("Domain transactions must retain semantic ownership until execution.")
        return
    }
    #expect(commandNamespace == namespace)
    #expect(mutations == [.upsert(envelope)])
}

@Test(.timeLimit(.minutes(1)))
func domainCommandExecutorReportsExactCommittedContextWhenProjectionFails() throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.postCommit"
    let registry = try makePlanningRegistry(
        namespace: namespace,
        lowerings: [
            PlanningLowering(
                capabilityID: capabilityID,
                plan: .automationBatch(
                    AutomationBatch(commands: [.renameDocument(name: "After")])
                )
            ),
        ]
    )
    let session = EditorSession(document: .empty(named: "Before"))
    let executor = DomainCommandExecutor(
        registry: registry,
        resultProjector: FailingPlanningResultProjector()
    )

    var caught: DomainCommandPostCommitError?
    do {
        _ = try executor.execute(
            request(for: capabilityID, namespace: namespace),
            in: session
        )
    } catch let error as DomainCommandPostCommitError {
        caught = error
    }
    let error = try #require(caught)

    #expect(error.record.didMutate)
    #expect(error.finalContext.document.cadDocument.metadata.name == "After")
    #expect(error.finalContext.generation == session.generation)
    #expect(error.finalContext.transactionRevision == session.transactionRevision)
    #expect(session.document.cadDocument.metadata.name == "After")
    #expect(session.commandStack.canUndo)
}

private struct PlanningLowering: DomainCommandLowering {
    let capabilityID: DomainCapabilityID
    let plan: DomainCommandPlan

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        plan
    }
}

private struct PlanningQuery: DomainCommandQuery {
    func execute(
        _ request: DomainCommandRequest,
        in context: DomainQueryContext
    ) throws -> DomainQueryResult {
        DomainQueryResult(message: "query")
    }
}

private struct FailingPlanningResultProjector: DomainCommandResultProjecting {
    func project(
        resolution: DomainCommandPlanResolution,
        record: DomainCommandExecutionRecord,
        currentGeneration: DocumentGeneration,
        currentTransactionRevision: DocumentTransactionRevision
    ) throws -> DomainExecutionResult {
        throw PlanningTestError.resultProjectionFailed
    }
}

private enum PlanningTestError: Error {
    case resultProjectionFailed
}

private func request(
    for capabilityID: DomainCapabilityID,
    namespace: SemanticNamespaceID
) -> DomainCommandRequest {
    DomainCommandRequest(
        capabilityID: capabilityID,
        namespace: namespace,
        payload: .object([:])
    )
}

private func makePlanningRegistry(
    namespace: SemanticNamespaceID,
    lowerings: [PlanningLowering],
    effects: [DomainCapabilityEffect]? = nil
) throws -> DomainRegistry {
    let descriptors = try lowerings.enumerated().map { index, lowering in
        let effect: DomainCapabilityEffect
        if let explicitEffect = effects?[safe: index] {
            effect = explicitEffect
        } else {
            switch lowering.plan {
            case .query:
                effect = .query
            case .documentTransaction:
                effect = .documentMutation
            case .automationBatch(let batch):
                switch try batch.validatedEffect() {
                case .readOnly:
                    effect = .query
                case .sourceMutation, .workspaceMutation:
                    effect = .documentMutation
                }
            }
        }
        let resultKind: DomainCapabilityResultKind = effect == .query
            ? .semanticPayload
            : .documentTransaction
        return DomainCapabilityDescriptor(
            id: lowering.capabilityID,
            namespace: namespace,
            name: lowering.capabilityID.rawValue,
            summary: "Fixture capability.",
            effect: effect,
            resultKind: resultKind,
            supportsDryRun: true,
            failureMode: "Returns typed failures."
        )
    }
    return try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: namespace,
                supportedSchemaVersions: [
                    SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
                ]
            ),
        ],
        capabilityDescriptors: descriptors,
        commandLowerings: lowerings
    )
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
