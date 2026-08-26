import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaDomainFoundation
import RupaKit
import RupaProject
import Testing

@MainActor
@Test(.timeLimit(.minutes(1)))
func productionMainViewActionMatrixExecutesEveryProjectBoundaryProof() async throws {
    let rows = ProductionMainViewActionManifest.rows
    let representedProofs = Set(rows.map(\.boundaryProof))

    #expect(representedProofs == Set(ProductionMainViewActionManifest.BoundaryProof.allCases))

    try await proveImmutableSnapshotBoundary()
    try await proveSourceActionBoundary()
    try await proveInteractionActionBoundary()
    try await proveDomainPlanBoundary()

    let transientRows = rows.filter { $0.boundaryProof == .mainActorTransient }
    #expect(!transientRows.isEmpty)
    #expect(transientRows.allSatisfy { $0.route == .mainActorTransient })
}

@MainActor
private func proveImmutableSnapshotBoundary() async throws {
    let controller = try makeBoundaryController(document: .empty(named: "Snapshot"))
    let workspace = ProjectWorkspace(project: controller)
    let view = try await workspace.evaluate()
    let state = try await controller.currentState()

    #expect(view.projectID == state.document.projectID)
    #expect(view.documentGeneration == state.documentGeneration)
    #expect(view.transactionRevision == state.transactionRevision)
    #expect(view.publicationSequence == state.publicationSequence)
    #expect(view.evaluationSnapshot == state.evaluationSnapshot)
}

@MainActor
private func proveSourceActionBoundary() async throws {
    let controller = try makeBoundaryController(document: .empty(named: "Before"))
    let workspace = ProjectWorkspace(project: controller)
    let base = try await workspace.evaluate()
    let action = try DefaultProjectWorkspaceActionPlanner().source(
        name: "matrix.source",
        commands: [.renameDocument(name: "After")],
        from: base
    )

    let preview = try await workspace.preview(action)
    guard case .source(let proposal) = preview else {
        Issue.record("The source boundary returned an interaction preview.")
        return
    }
    #expect(proposal.base.publicationSequence == base.publicationSequence)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Before")

    let result = try await workspace.perform(action)
    guard case .source(let commit, let view) = result else {
        Issue.record("The source boundary returned an interaction commit.")
        return
    }
    #expect(commit.state.publicationSequence == view.publicationSequence)
    #expect(view.document.name == "After")
    #expect(view.transactionRevision.value == base.transactionRevision.value + 1)
}

@MainActor
private func proveInteractionActionBoundary() async throws {
    let controller = try makeBoundaryController(document: .empty(named: "Interaction"))
    let workspace = ProjectWorkspace(project: controller)
    let base = try await workspace.evaluate()
    let action = try DefaultProjectWorkspaceActionPlanner().interaction(
        selection: .clear,
        workspaceCommands: [.setDisplayUnit(.meter)],
        from: base
    )

    let preview = try await workspace.preview(action)
    guard case .interaction(let proposal) = preview else {
        Issue.record("The interaction boundary returned a source preview.")
        return
    }
    #expect(proposal.proposedWorkspaceState.displayUnit == .meter)
    #expect(try await controller.currentState().publicationSequence == base.publicationSequence)

    let result = try await workspace.perform(action)
    guard case .interaction(let commit, let view) = result else {
        Issue.record("The interaction boundary returned a source commit.")
        return
    }
    #expect(commit.state.publicationSequence == view.publicationSequence)
    #expect(view.workspaceState.displayUnit == .meter)
    #expect(view.transactionRevision == base.transactionRevision)
    #expect(view.publicationSequence > base.publicationSequence)
}

@MainActor
private func proveDomainPlanBoundary() async throws {
    let namespace: SemanticNamespaceID = "matrix"
    let sourceID: DomainCapabilityID = "matrix.source"
    let workspaceID: DomainCapabilityID = "matrix.workspace"
    let readID: DomainCapabilityID = "matrix.read"
    let queryID: DomainCapabilityID = "matrix.query"
    let version = SemanticSchemaVersion(major: 0, minor: 1, patch: 0)
    let semanticMutation = SemanticExtensionMutation.upsert(
        SemanticExtensionEnvelope(
            namespace: namespace,
            schemaVersion: version,
            payload: .object([:])
        )
    )
    let registry = try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: namespace,
                supportedSchemaVersions: [version]
            ),
        ],
        capabilityDescriptors: [
            boundaryDescriptor(id: sourceID, namespace: namespace, effect: .documentMutation),
            boundaryDescriptor(id: workspaceID, namespace: namespace, effect: .documentMutation),
            boundaryDescriptor(id: readID, namespace: namespace, effect: .query),
            boundaryDescriptor(id: queryID, namespace: namespace, effect: .query),
        ],
        commandLowerings: [
            BoundaryDomainLowering(
                capabilityID: sourceID,
                plan: .documentTransaction(
                    DomainDocumentTransaction(
                        name: "matrix.domain.source",
                        sourceCommands: [.renameDocument(name: "Domain")],
                        semanticMutations: [semanticMutation]
                    )
                )
            ),
            BoundaryDomainLowering(
                capabilityID: workspaceID,
                plan: .automationBatch(
                    AutomationBatch(commands: [.setDisplayUnit(.meter)])
                )
            ),
            BoundaryDomainLowering(
                capabilityID: readID,
                plan: .automationBatch(
                    AutomationBatch(commands: [.describeDocument])
                )
            ),
            BoundaryDomainLowering(
                capabilityID: queryID,
                plan: .query(BoundaryDomainQuery())
            ),
        ]
    )
    let dispatcher = ProjectDomainCommandDispatcher(registry: registry)
    let controller = try makeBoundaryController(document: .empty(named: "Domain Before"))
    let workspace = ProjectWorkspace(project: controller)

    let sourceBase = try await workspace.evaluate()
    let sourceResult = try await workspace.execute(
        try dispatcher.dispatch(
            boundaryRequest(id: sourceID, namespace: namespace, from: sourceBase),
            from: sourceBase
        )
    )
    #expect(sourceResult.didMutate)
    #expect(sourceResult.generation > sourceBase.documentGeneration)

    let workspaceBase = try #require(workspace.view)
    let workspaceResult = try await workspace.execute(
        try dispatcher.dispatch(
            boundaryRequest(id: workspaceID, namespace: namespace, from: workspaceBase),
            from: workspaceBase
        )
    )
    #expect(workspaceResult.didMutate)
    #expect(try #require(workspace.view).workspaceState.displayUnit == .meter)

    let readBase = try #require(workspace.view)
    let readPublication = readBase.publicationSequence
    let readResult = try await workspace.execute(
        try dispatcher.dispatch(
            boundaryRequest(id: readID, namespace: namespace, from: readBase),
            from: readBase
        )
    )
    #expect(!readResult.didMutate)
    #expect(try #require(workspace.view).publicationSequence == readPublication)

    let queryBase = try #require(workspace.view)
    let queryResult = try await workspace.execute(
        try dispatcher.dispatch(
            boundaryRequest(id: queryID, namespace: namespace, from: queryBase),
            from: queryBase
        )
    )
    #expect(!queryResult.didMutate)
    #expect(queryResult.payload == .string("Domain"))
    #expect(try #require(workspace.view).publicationSequence == readPublication)
}

private struct BoundaryDomainLowering: DomainCommandLowering {
    let capabilityID: DomainCapabilityID
    let plan: DomainCommandPlan

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        plan
    }
}

private struct BoundaryDomainQuery: DomainCommandQuery {
    func execute(
        _ request: DomainCommandRequest,
        in context: DomainQueryContext
    ) throws -> DomainQueryResult {
        let name = context.document.cadDocument.metadata.name ?? "Untitled"
        return DomainQueryResult(message: name, payload: .string(name))
    }
}

private func makeBoundaryController(document: DesignDocument) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
}

private func boundaryDescriptor(
    id: DomainCapabilityID,
    namespace: SemanticNamespaceID,
    effect: DomainCapabilityEffect
) -> DomainCapabilityDescriptor {
    DomainCapabilityDescriptor(
        id: id,
        namespace: namespace,
        name: id.rawValue,
        summary: "Project boundary fixture.",
        effect: effect,
        resultKind: effect == .query ? .semanticPayload : .documentTransaction,
        supportsDryRun: true,
        failureMode: "Returns typed failures."
    )
}

private func boundaryRequest(
    id: DomainCapabilityID,
    namespace: SemanticNamespaceID,
    from snapshot: ProjectViewSnapshot
) -> DomainCommandRequest {
    DomainCommandRequest(
        capabilityID: id,
        namespace: namespace,
        payload: .object([:]),
        expectedGeneration: snapshot.documentGeneration,
        expectedTransactionRevision: snapshot.transactionRevision
    )
}
