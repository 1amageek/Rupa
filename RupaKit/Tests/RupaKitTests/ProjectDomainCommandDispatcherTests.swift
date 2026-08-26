import Foundation
import RupaAutomation
import RupaCore
import RupaDomainFoundation
import RupaProject
import Synchronization
import Testing
@testable import RupaKit

@Test(.timeLimit(.minutes(1)))
func projectDomainDispatcherLowersDocumentMutationToSourceAction() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.rename"
    let registry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: capabilityID,
            plan: .documentTransaction(
                DomainDocumentTransaction(
                    name: "domain.rename",
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
        effect: .documentMutation
    )
    let controller = try ProjectController(
        document: .empty(named: "Before"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let plan = try ProjectDomainCommandDispatcher(registry: registry).dispatch(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:]),
            expectedGeneration: snapshot.documentGeneration,
            expectedTransactionRevision: snapshot.transactionRevision
        ),
        from: snapshot
    )

    guard case .source(let actionPlan) = plan,
          case .source(let action) = actionPlan.action else {
        Issue.record("A document domain mutation must lower to a source project action.")
        return
    }
    #expect(actionPlan.route == .source)
    #expect(actionPlan.dryRun == false)
    #expect(actionPlan.capabilityID == capabilityID)
    #expect(action.expectedTransactionRevision == snapshot.transactionRevision)
    #expect(action.expectedPublicationSequence == snapshot.publicationSequence)
    #expect(Array(action.commands.dropLast()) == [.renameDocument(name: "After")])
    guard case .applyNamespacedSemanticExtensionMutations(
        let commandNamespace,
        let mutations
    ) = action.commands.last else {
        Issue.record("Domain semantic mutations must remain in the source action.")
        return
    }
    #expect(commandNamespace == namespace)
    #expect(mutations.count == 1)
}

@Test(.timeLimit(.minutes(1)))
func projectDomainDispatcherLowersWorkspaceMutationToInteractionAction() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.units"
    let registry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: capabilityID,
            plan: .automationBatch(
                AutomationBatch(commands: [.setDisplayUnit(.meter)])
            )
        ),
        effect: .documentMutation
    )
    let controller = try ProjectController(
        document: .empty(named: "Workspace"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let plan = try ProjectDomainCommandDispatcher(registry: registry).dispatch(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:]),
            expectedTransactionRevision: snapshot.transactionRevision
        ),
        from: snapshot
    )

    guard case .interaction(let actionPlan) = plan,
          case .interaction(let action) = actionPlan.action else {
        Issue.record("A workspace domain mutation must lower to an interaction project action.")
        return
    }
    #expect(actionPlan.route == .workspace)
    #expect(action.expectedTransactionRevision == snapshot.transactionRevision)
    #expect(action.expectedPublicationSequence == snapshot.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectDomainDispatcherKeepsReadPlansOutOfMutationActions() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.describe"
    let registry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: capabilityID,
            plan: .automationBatch(
                AutomationBatch(commands: [.describeDocument])
            )
        ),
        effect: .query
    )
    let controller = try ProjectController(
        document: .empty(named: "Read"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let plan = try ProjectDomainCommandDispatcher(registry: registry).dispatch(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:]),
            expectedGeneration: snapshot.documentGeneration
        ),
        from: snapshot
    )

    guard case .read(let resolution) = plan else {
        Issue.record("A read-only domain plan must not produce a project mutation action.")
        return
    }
    #expect(resolution.route == .readOnly)
    #expect(plan.action == nil)
}

@Test(.timeLimit(.minutes(1)))
func projectDomainDispatcherRejectsStaleGenerationBeforeLoweringAction() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.rename"
    let registry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: capabilityID,
            plan: .documentTransaction(
                DomainDocumentTransaction(
                    name: "domain.rename",
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
        effect: .documentMutation
    )
    let controller = try ProjectController(
        document: .empty(named: "Stale"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()

    var caught: ProjectDomainCommandDispatchError?
    do {
        _ = try ProjectDomainCommandDispatcher(registry: registry).dispatch(
            DomainCommandRequest(
                capabilityID: capabilityID,
                namespace: namespace,
                payload: .object([:]),
                expectedGeneration: DocumentGeneration(snapshot.documentGeneration.value + 1)
            ),
            from: snapshot
        )
    } catch let error as ProjectDomainCommandDispatchError {
        caught = error
    }

    #expect(caught?.code == .generationMismatch)
}

@Test(.timeLimit(.minutes(1)))
func projectDomainDispatcherRejectsActionPlannedFromAnotherProject() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.rename.foreign-action"
    let registry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: capabilityID,
            plan: .documentTransaction(
                DomainDocumentTransaction(
                    name: "domain.rename.foreign-action",
                    sourceCommands: [.renameDocument(name: "After")],
                    semanticMutations: [
                        .upsert(
                            SemanticExtensionEnvelope(
                                namespace: namespace,
                                schemaVersion: SemanticSchemaVersion(
                                    major: 0,
                                    minor: 1,
                                    patch: 0
                                ),
                                payload: .object([:])
                            )
                        ),
                    ]
                )
            )
        ),
        effect: .documentMutation
    )
    let sourceController = try makeDomainController(document: .empty(named: "Source"))
    let foreignController = try makeDomainController(document: .empty(named: "Foreign"))
    let sourceSnapshot = try await ProjectWorkspace(project: sourceController).evaluate()
    let foreignSnapshot = try await ProjectWorkspace(project: foreignController).evaluate()
    let dispatcher = ProjectDomainCommandDispatcher(
        registry: registry,
        actionPlanner: ForeignSnapshotActionPlanner(snapshot: foreignSnapshot)
    )

    var caught: ProjectDomainCommandDispatchError?
    do {
        _ = try dispatcher.dispatch(
            DomainCommandRequest(
                capabilityID: capabilityID,
                namespace: namespace,
                payload: .object([:])
            ),
            from: sourceSnapshot
        )
    } catch let error as ProjectDomainCommandDispatchError {
        caught = error
    }

    #expect(sourceSnapshot.projectID != foreignSnapshot.projectID)
    #expect(sourceSnapshot.transactionRevision == foreignSnapshot.transactionRevision)
    #expect(sourceSnapshot.publicationSequence == foreignSnapshot.publicationSequence)
    #expect(caught?.code == .projectMismatch)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceExecutesDomainSourcePlanAndPreservesResultPayload() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.rename.execute"
    let extensionID = SemanticExtensionID()
    let payload: SemanticJSONValue = .object(["renamed": .bool(true)])
    let registry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: capabilityID,
            plan: .documentTransaction(
                DomainDocumentTransaction(
                    name: "domain.rename.execute",
                    sourceCommands: [.renameDocument(name: "After")],
                    semanticMutations: [
                        .upsert(
                            SemanticExtensionEnvelope(
                                id: extensionID,
                                namespace: namespace,
                                schemaVersion: SemanticSchemaVersion(
                                    major: 0,
                                    minor: 1,
                                    patch: 0
                                ),
                                payload: .object([:])
                            )
                        ),
                    ],
                    resultPayload: payload
                )
            )
        ),
        effect: .documentMutation
    )
    let controller = try ProjectController(
        document: .empty(named: "Before"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let plan = try ProjectDomainCommandDispatcher(registry: registry).dispatch(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:]),
            expectedGeneration: snapshot.documentGeneration,
            expectedTransactionRevision: snapshot.transactionRevision
        ),
        from: snapshot
    )

    let result = try await workspace.execute(plan)
    let state = try await controller.currentState()

    #expect(result.didMutate)
    #expect(result.wouldMutate)
    #expect(!result.dryRun)
    #expect(result.payload == payload)
    #expect(result.commandName == "domain.rename.execute")
    #expect(result.sourceCommandResults.count == 1)
    #expect(!state.evaluationSnapshot.diagnostics.isEmpty)
    #expect(state.evaluationSnapshot.diagnostics.allSatisfy(result.diagnostics.contains))
    #expect(state.document.cadDocument.metadata.name == "After")
    #expect(state.document.productMetadata.semanticExtensions[extensionID] != nil)
    #expect(result.generation == state.documentGeneration)
    #expect(result.transactionRevision == state.transactionRevision)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceDomainDryRunReturnsProposalWithoutPublishing() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.rename.preview"
    let registry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: capabilityID,
            plan: .documentTransaction(
                DomainDocumentTransaction(
                    name: "domain.rename.preview",
                    sourceCommands: [.renameDocument(name: "After")],
                    semanticMutations: [
                        .upsert(
                            SemanticExtensionEnvelope(
                                namespace: namespace,
                                schemaVersion: SemanticSchemaVersion(
                                    major: 0,
                                    minor: 1,
                                    patch: 0
                                ),
                                payload: .object([:])
                            )
                        ),
                    ]
                )
            )
        ),
        effect: .documentMutation
    )
    let controller = try ProjectController(
        document: .empty(named: "Before"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let plan = try ProjectDomainCommandDispatcher(registry: registry).dispatch(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:]),
            dryRun: true
        ),
        from: snapshot
    )

    let result = try await workspace.execute(plan)
    let retained = try await controller.currentState()

    #expect(result.dryRun)
    #expect(!result.didMutate)
    #expect(result.wouldMutate)
    #expect(result.generation == snapshot.documentGeneration)
    #expect(result.proposedGeneration.value > result.generation.value)
    #expect(!result.diagnostics.isEmpty)
    #expect(retained.evaluationSnapshot.diagnostics.isEmpty)
    #expect(retained.document.cadDocument.metadata.name == "Before")
    #expect(retained.documentGeneration == snapshot.documentGeneration)
    #expect(retained.transactionRevision == snapshot.transactionRevision)
    #expect(retained.publicationSequence == snapshot.publicationSequence)
    #expect(await workspace.view?.publicationSequence == snapshot.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceExecutesReadOnlyAutomationDomainPlanWithoutPublishing() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.describe.execute"
    let registry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: capabilityID,
            plan: .automationBatch(
                AutomationBatch(commands: [.describeDocument])
            )
        ),
        effect: .query
    )
    let controller = try ProjectController(
        document: .empty(named: "Read Route"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let plan = try ProjectDomainCommandDispatcher(registry: registry).dispatch(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:])
        ),
        from: snapshot
    )

    let result = try await workspace.execute(plan)
    let retained = try await controller.currentState()

    #expect(!result.didMutate)
    #expect(!result.wouldMutate)
    #expect(result.automationResults.count == 1)
    #expect(result.automationResults[0].message.contains("mm display units"))
    #expect(retained.publicationSequence == snapshot.publicationSequence)
    #expect(retained.documentGeneration == snapshot.documentGeneration)
    #expect(retained.workspaceState.revision == snapshot.workspaceState.revision)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceExecutesImmutableDomainQueryAndRejectsStalePlan() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.query.execute"
    let registry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: capabilityID,
            plan: .query(DispatcherQuery())
        ),
        effect: .query
    )
    let controller = try ProjectController(
        document: .empty(named: "Query Route"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let dispatcher = ProjectDomainCommandDispatcher(registry: registry)
    let currentPlan = try dispatcher.dispatch(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:])
        ),
        from: snapshot
    )

    let currentResult = try await workspace.execute(currentPlan)
    #expect(currentResult.message == "Query Route")
    #expect(currentResult.payload == .string("Query Route"))
    #expect(!currentResult.didMutate)

    _ = try await workspace.applyWorkspace(.setDisplayUnit(.meter))
    var caught: ProjectDomainCommandDispatchError?
    do {
        _ = try await workspace.execute(currentPlan)
    } catch let error as ProjectDomainCommandDispatchError {
        caught = error
    }
    #expect(caught?.code == .publicationSequenceMismatch)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceRejectsCrossProjectQueryAndReadOnlyAutomationPlans() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let queryCapabilityID: DomainCapabilityID = "fixture.query.cross-project"
    let readCapabilityID: DomainCapabilityID = "fixture.read.cross-project"
    let sourceController = try makeDomainController(document: .empty(named: "Source"))
    let targetController = try makeDomainController(document: .empty(named: "Target"))
    let sourceWorkspace = await ProjectWorkspace(project: sourceController)
    let targetWorkspace = await ProjectWorkspace(project: targetController)
    let sourceSnapshot = try await sourceWorkspace.evaluate()
    let targetSnapshot = try await targetWorkspace.evaluate()
    let queryRegistry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: queryCapabilityID,
            plan: .query(DispatcherQuery())
        ),
        effect: .query
    )
    let readRegistry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: readCapabilityID,
            plan: .automationBatch(AutomationBatch(commands: [.describeDocument]))
        ),
        effect: .query
    )
    let queryPlan = try ProjectDomainCommandDispatcher(registry: queryRegistry).dispatch(
        DomainCommandRequest(
            capabilityID: queryCapabilityID,
            namespace: namespace,
            payload: .object([:])
        ),
        from: sourceSnapshot
    )
    let readPlan = try ProjectDomainCommandDispatcher(registry: readRegistry).dispatch(
        DomainCommandRequest(
            capabilityID: readCapabilityID,
            namespace: namespace,
            payload: .object([:])
        ),
        from: sourceSnapshot
    )

    var failures: [ProjectDomainCommandDispatchError.Code] = []
    do {
        _ = try await targetWorkspace.execute(queryPlan)
    } catch let error as ProjectDomainCommandDispatchError {
        failures.append(error.code)
    }
    do {
        _ = try await targetWorkspace.execute(readPlan)
    } catch let error as ProjectDomainCommandDispatchError {
        failures.append(error.code)
    }

    #expect(sourceSnapshot.projectID != targetSnapshot.projectID)
    #expect(sourceSnapshot.documentGeneration == targetSnapshot.documentGeneration)
    #expect(sourceSnapshot.transactionRevision == targetSnapshot.transactionRevision)
    #expect(sourceSnapshot.publicationSequence == targetSnapshot.publicationSequence)
    #expect(failures == [.projectMismatch, .projectMismatch])
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceRejectsQueryResultPublishedAfterItsBaseCoordinates() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.query.late"
    let gate = DomainExecutionGate()
    let registry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: capabilityID,
            plan: .query(GatedDispatcherQuery(gate: gate))
        ),
        effect: .query
    )
    let controller = try makeDomainController(document: .empty(named: "Before"))
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let plan = try ProjectDomainCommandDispatcher(registry: registry).dispatch(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:])
        ),
        from: snapshot
    )
    let queryTask = Task {
        try await workspace.execute(plan)
    }
    while !gate.didStart {
        await Task.yield()
    }

    _ = try await workspace.applyWorkspace(.setDisplayUnit(.meter))
    gate.release()
    var caught: ProjectDomainCommandDispatchError?
    do {
        _ = try await queryTask.value
    } catch let error as ProjectDomainCommandDispatchError {
        caught = error
    }

    #expect(caught?.code == .publicationSequenceMismatch)
    #expect(try await controller.currentState().publicationSequence > snapshot.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceDomainReadsObservePreCancellation() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let queryCapabilityID: DomainCapabilityID = "fixture.query.cancelled"
    let readCapabilityID: DomainCapabilityID = "fixture.read.cancelled"
    let controller = try makeDomainController(document: .empty(named: "Cancel"))
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let queryRegistry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: queryCapabilityID,
            plan: .query(DispatcherQuery())
        ),
        effect: .query
    )
    let readRegistry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: readCapabilityID,
            plan: .automationBatch(AutomationBatch(commands: [.describeDocument]))
        ),
        effect: .query
    )
    let queryPlan = try ProjectDomainCommandDispatcher(registry: queryRegistry).dispatch(
        DomainCommandRequest(
            capabilityID: queryCapabilityID,
            namespace: namespace,
            payload: .object([:])
        ),
        from: snapshot
    )
    let readPlan = try ProjectDomainCommandDispatcher(registry: readRegistry).dispatch(
        DomainCommandRequest(
            capabilityID: readCapabilityID,
            namespace: namespace,
            payload: .object([:])
        ),
        from: snapshot
    )
    let queryTask = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await workspace.execute(queryPlan)
    }
    let readTask = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await workspace.execute(readPlan)
    }

    var cancellationCount = 0
    do {
        _ = try await queryTask.value
    } catch is CancellationError {
        cancellationCount += 1
    }
    do {
        _ = try await readTask.value
    } catch is CancellationError {
        cancellationCount += 1
    }

    #expect(cancellationCount == 2)
    #expect(try await controller.currentState().publicationSequence == snapshot.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceReadOnlyAutomationObservesMidExecutionCancellation() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.read.mid-cancel"
    let gate = DomainExecutionGate()
    let controller = try ProjectController(
        document: .empty(named: "Cancel"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge(),
        automationExecutor: GatedAutomationStagedBatchExecutor(gate: gate)
    )
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let registry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: capabilityID,
            plan: .automationBatch(AutomationBatch(commands: [.describeDocument]))
        ),
        effect: .query
    )
    let plan = try ProjectDomainCommandDispatcher(registry: registry).dispatch(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:])
        ),
        from: snapshot
    )
    let readTask = Task {
        try await workspace.execute(plan)
    }
    while !gate.didStart {
        await Task.yield()
    }

    readTask.cancel()
    gate.release()
    var didCancel = false
    do {
        _ = try await readTask.value
    } catch is CancellationError {
        didCancel = true
    }

    #expect(didCancel)
    #expect(try await controller.currentState().publicationSequence == snapshot.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceReportsCommittedDomainStateWhenResultProjectionFails() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.domain.post-commit"
    let registry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: capabilityID,
            plan: .documentTransaction(
                DomainDocumentTransaction(
                    name: "domain.post-commit",
                    sourceCommands: [.renameDocument(name: "After")],
                    semanticMutations: [
                        .upsert(
                            SemanticExtensionEnvelope(
                                namespace: namespace,
                                schemaVersion: SemanticSchemaVersion(
                                    major: 0,
                                    minor: 1,
                                    patch: 0
                                ),
                                payload: .object([:])
                            )
                        ),
                    ]
                )
            )
        ),
        effect: .documentMutation
    )
    let controller = try makeDomainController(document: .empty(named: "Before"))
    let workspace = await ProjectWorkspace(
        project: controller,
        domainResultProjector: FailingDomainCommandResultProjector()
    )
    let snapshot = try await workspace.evaluate()
    let plan = try ProjectDomainCommandDispatcher(registry: registry).dispatch(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:])
        ),
        from: snapshot
    )

    var caught: ProjectWorkspacePostCommitError?
    do {
        _ = try await workspace.execute(plan)
    } catch let error as ProjectWorkspacePostCommitError {
        caught = error
    }
    let error = try #require(caught)
    let committedState = error.commit.state
    let current = try await controller.currentState()

    #expect(error.stage == .domainResultProjection)
    #expect(committedState.document.cadDocument.metadata.name == "After")
    #expect(current.publicationSequence == committedState.publicationSequence)
    #expect(current.publicationSequence > snapshot.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectDomainSemanticIdentityUsesDocumentAfterPriorSourceCommands() async throws {
    let namespace: SemanticNamespaceID = "fixture"
    let capabilityID: DomainCapabilityID = "fixture.semantic.afterSource"
    let session = EditorSession(document: .empty(named: "Semantic"))
    let created = try #require(session.createDefaultExtrudedRectangle())
    let featureID = try #require(created.primaryFeatureID)
    let extensionID = SemanticExtensionID()
    let entityID: SemanticEntityID = "source-feature"
    let envelope = SemanticExtensionEnvelope(
        id: extensionID,
        namespace: namespace,
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object(["source": .bool(true)]),
        projection: ProjectionManifest(
            semanticEntities: [
                ProjectionSemanticEntity(
                    id: entityID,
                    ownership: .classified,
                    sourcePaths: [SemanticPayloadPath([.key("source")])]
                ),
            ],
            sourceReferences: [
                ProjectionManifest.SourceReference(
                    semanticEntityID: entityID,
                    featureID: featureID,
                    ownership: .classified
                ),
            ]
        )
    )
    let registry = try makeDispatcherRegistry(
        namespace: namespace,
        lowering: DispatcherLowering(
            capabilityID: capabilityID,
            plan: .documentTransaction(
                DomainDocumentTransaction(
                    name: "domain.semantic.afterSource",
                    sourceCommands: [
                        .setExtrudeDistance(
                            featureID: featureID,
                            distance: .length(20.0, .millimeter)
                        ),
                    ],
                    semanticMutations: [.upsert(envelope)]
                )
            )
        ),
        effect: .documentMutation
    )
    let controller = try ProjectController(
        document: session.document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let plan = try ProjectDomainCommandDispatcher(registry: registry).dispatch(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:])
        ),
        from: snapshot
    )

    _ = try await workspace.execute(plan)
    let state = try await controller.currentState()
    let committedEnvelope = try #require(
        state.document.productMetadata.semanticExtensions[extensionID]
    )
    let semanticEntity = try #require(
        committedEnvelope.projection.semanticEntities.first
    )
    let expectedIdentity = try ProjectionDependencyIdentityBuilder().identity(
        for: entityID,
        in: committedEnvelope,
        document: state.document,
        generation: state.documentGeneration
    )

    guard case .extrude(let extrude) = state.document.cadDocument.designGraph
        .nodes[featureID]?.operation else {
        Issue.record("Expected the source feature to remain an extrusion.")
        return
    }
    #expect(extrude.distance == .length(20.0, .millimeter))
    #expect(semanticEntity.dependencyIdentity == expectedIdentity)
}

private struct DispatcherLowering: DomainCommandLowering {
    let capabilityID: DomainCapabilityID
    let plan: DomainCommandPlan

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        plan
    }
}

private struct ForeignSnapshotActionPlanner: ProjectWorkspaceActionPlanning {
    let snapshot: ProjectViewSnapshot

    func source(
        name: String,
        commands: [EditorCommand],
        geometrySourceCommands: [GeometrySourceCommand],
        from snapshot: ProjectViewSnapshot
    ) throws -> ProjectWorkspaceAction {
        try DefaultProjectWorkspaceActionPlanner().source(
            name: name,
            commands: commands,
            geometrySourceCommands: geometrySourceCommands,
            from: self.snapshot
        )
    }

    func interaction(
        selection: ProjectSelectionOperation?,
        workspaceCommands: [WorkspaceCommand],
        from snapshot: ProjectViewSnapshot
    ) throws -> ProjectWorkspaceAction {
        try DefaultProjectWorkspaceActionPlanner().interaction(
            selection: selection,
            workspaceCommands: workspaceCommands,
            from: self.snapshot
        )
    }

    func automation(
        _ batch: AutomationBatch,
        from snapshot: ProjectViewSnapshot
    ) throws -> ProjectWorkspaceAction {
        try DefaultProjectWorkspaceActionPlanner().automation(
            batch,
            from: self.snapshot
        )
    }
}

private struct DispatcherQuery: DomainCommandQuery {
    func execute(
        _ request: DomainCommandRequest,
        in context: DomainQueryContext
    ) throws -> DomainQueryResult {
        let name = context.document.cadDocument.metadata.name ?? "Untitled"
        return DomainQueryResult(
            message: name,
            payload: .string(name)
        )
    }
}

private struct GatedDispatcherQuery: DomainCommandQuery {
    let gate: DomainExecutionGate

    func execute(
        _ request: DomainCommandRequest,
        in context: DomainQueryContext
    ) throws -> DomainQueryResult {
        gate.markStarted()
        gate.waitUntilReleased()
        try Task.checkCancellation()
        let name = context.document.cadDocument.metadata.name ?? "Untitled"
        return DomainQueryResult(message: name, payload: .string(name))
    }
}

private final class DomainExecutionGate: Sendable {
    private struct State {
        var didStart = false
        var isReleased = false
    }

    private let state = Mutex(State())

    var didStart: Bool {
        state.withLock { $0.didStart }
    }

    func markStarted() {
        state.withLock { $0.didStart = true }
    }

    func waitUntilReleased() {
        while !state.withLock({ $0.isReleased }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func release() {
        state.withLock { $0.isReleased = true }
    }
}

private struct GatedAutomationStagedBatchExecutor: AutomationStagedBatchExecuting {
    let gate: DomainExecutionGate

    func execute(
        _ prepared: PreparedAutomationBatch,
        in stagedSession: EditorSession
    ) throws -> AutomationBatchExecution {
        gate.markStarted()
        gate.waitUntilReleased()
        try Task.checkCancellation()
        return try AutomationStagedBatchExecutor().execute(
            prepared,
            in: stagedSession
        )
    }

    func finalizingSourceMetrics(
        _ execution: AutomationBatchExecution,
        initialEvaluationPassCount: UInt64,
        initialHistoryEntryCount: Int,
        in stagedSession: EditorSession
    ) -> AutomationBatchExecution {
        AutomationStagedBatchExecutor().finalizingSourceMetrics(
            execution,
            initialEvaluationPassCount: initialEvaluationPassCount,
            initialHistoryEntryCount: initialHistoryEntryCount,
            in: stagedSession
        )
    }
}

private struct FailingDomainCommandResultProjector: DomainCommandResultProjecting {
    func project(
        resolution: DomainCommandPlanResolution,
        record: DomainCommandExecutionRecord,
        currentGeneration: DocumentGeneration,
        currentTransactionRevision: DocumentTransactionRevision
    ) throws -> DomainExecutionResult {
        throw ProjectDomainCommandDispatcherTestError.resultProjectionFailed
    }
}

private enum ProjectDomainCommandDispatcherTestError: Error {
    case resultProjectionFailed
}

private func makeDomainController(document: DesignDocument) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
}

private func makeDispatcherRegistry(
    namespace: SemanticNamespaceID,
    lowering: DispatcherLowering,
    effect: DomainCapabilityEffect
) throws -> DomainRegistry {
    try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: namespace,
                supportedSchemaVersions: [
                    SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
                ]
            ),
        ],
        capabilityDescriptors: [
            DomainCapabilityDescriptor(
                id: lowering.capabilityID,
                namespace: namespace,
                name: lowering.capabilityID.rawValue,
                summary: "Fixture capability.",
                effect: effect,
                resultKind: effect == .query ? .semanticPayload : .documentTransaction,
                supportsDryRun: true,
                failureMode: "Returns typed failures."
            ),
        ],
        commandLowerings: [lowering]
    )
}
