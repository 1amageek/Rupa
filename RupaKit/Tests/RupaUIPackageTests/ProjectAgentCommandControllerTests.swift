import Foundation
import RupaAgentProtocol
import RupaAgentRuntime
import RupaAutomation
import RupaCapabilities
import RupaCore
import RupaDomainFoundation
import RupaEvaluation
import RupaGeometry
import RupaKit
import RupaProject
import RupaProjectModel
import Synchronization
import Testing

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentAndUIShareOneWorkspaceAuthority() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: .empty(named: "Shared")
    )
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)

    let initial = try #require(workspace.view)
    let uiAction = try DefaultProjectWorkspaceActionPlanner().source(
        name: "ui.rename",
        commands: [.renameDocument(name: "UI Source")],
        from: initial
    )
    _ = try await workspace.perform(uiAction)

    let sessionsResponse = await controller.handle(.sessions)
    guard case .sessions(let summaries) = sessionsResponse else {
        Issue.record("Expected the Agent sessions read to observe the UI source commit.")
        return
    }
    #expect(summaries.first?.displayName == "UI Source")

    let uiCommitted = try #require(workspace.view)
    let agentResponse = await controller.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Agent Source"),
            expectedGeneration: uiCommitted.documentGeneration
        )
    )
    guard case .command(let agentResult) = agentResponse else {
        Issue.record("Expected the Agent source mutation to commit.")
        return
    }
    #expect(agentResult.didMutate)
    #expect(workspace.view?.projectName == "Agent Source")

    _ = try await workspace.applyWorkspace(.setDisplayUnit(.centimeter))
    let workspaceCommitted = try #require(workspace.view)
    let measureResponse = await controller.handle(
        .measure(
            sessionID: sessionID,
            expectedGeneration: workspaceCommitted.documentGeneration
        )
    )
    guard case .measurement(let measurement) = measureResponse else {
        Issue.record("Expected the Agent read to observe the UI workspace commit.")
        return
    }
    #expect(measurement.displayUnit == .centimeter)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func staleAgentMutationLosesToUICommitWithoutPartialPublication() async throws {
    let (project, workspace) = try await makeProjectWorkspace(
        document: .empty(named: "Initial")
    )
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let sharedBase = try #require(workspace.view)

    let uiAction = try DefaultProjectWorkspaceActionPlanner().source(
        name: "ui.wins",
        commands: [.renameDocument(name: "UI Winner")],
        from: sharedBase
    )
    _ = try await workspace.perform(uiAction)
    let committed = try await project.currentState()

    let staleResponse = await controller.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Agent Loser"),
            expectedGeneration: sharedBase.documentGeneration
        )
    )
    guard case .failure(let error) = staleResponse else {
        Issue.record("Expected the stale Agent mutation to fail.")
        return
    }
    #expect(error.code == .documentGenerationMismatch)

    let afterFailure = try await project.currentState()
    #expect(afterFailure.document.cadDocument.metadata.name == "UI Winner")
    #expect(afterFailure.documentGeneration == committed.documentGeneration)
    #expect(afterFailure.transactionRevision == committed.transactionRevision)
    #expect(afterFailure.publicationSequence == committed.publicationSequence)
    #expect(afterFailure.package.productSource == committed.package.productSource)
    #expect(afterFailure.package.cadSource == committed.package.cadSource)
    #expect(afterFailure.evaluationSnapshot == committed.evaluationSnapshot)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func staleAgentBatchTransactionRevisionIsNotRebasedOntoCurrentProject() async throws {
    let (project, workspace) = try await makeProjectWorkspace(
        document: .empty(named: "Initial")
    )
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let stale = try #require(workspace.view)

    let uiAction = try DefaultProjectWorkspaceActionPlanner().source(
        name: "ui.advancesTransaction",
        commands: [.renameDocument(name: "UI Winner")],
        from: stale
    )
    _ = try await workspace.perform(uiAction)
    let committed = try await project.currentState()
    #expect(committed.transactionRevision != stale.transactionRevision)

    let response = await controller.handle(
        .executeBatch(
            sessionID: sessionID,
            batch: AutomationBatch(
                commands: [.renameDocument(name: "Stale Batch")],
                expectedGeneration: committed.documentGeneration,
                expectedTransactionRevision: stale.transactionRevision
            )
        )
    )
    guard case .failure(let error) = response else {
        Issue.record("Expected a stale batch transaction revision to fail.")
        return
    }
    #expect(error.code == .documentTransactionRevisionMismatch)

    let afterFailure = try await project.currentState()
    #expect(afterFailure.document.cadDocument.metadata.name == "UI Winner")
    #expect(afterFailure.transactionRevision == committed.transactionRevision)
    #expect(afterFailure.publicationSequence == committed.publicationSequence)
    #expect(afterFailure.package.productSource == committed.package.productSource)
    #expect(afterFailure.package.cadSource == committed.package.cadSource)
    #expect(afterFailure.evaluationSnapshot == committed.evaluationSnapshot)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func registeredWorkspaceFollowsLoadAndRejectsItsOldAction() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    defer {
        do {
            try FileManager.default.removeItem(at: temporaryDirectory)
        } catch {
            Issue.record("Failed to remove Agent load fixture: \(error)")
        }
    }

    let (_, workspace) = try await makeProjectWorkspace(
        document: .empty(named: "Before Load")
    )
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let beforeLoad = try #require(workspace.view)
    let oldAction = try DefaultProjectWorkspaceActionPlanner().source(
        name: "queued.beforeLoad",
        commands: [.renameDocument(name: "Queued Old Action")],
        from: beforeLoad
    )

    let (_, replacement) = try await makeProjectWorkspace(
        document: .empty(named: "Loaded Project")
    )
    let packageURL = temporaryDirectory.appendingPathComponent("loaded.rupa")
    _ = try await replacement.save(to: packageURL)
    let loaded = try await workspace.load(from: packageURL)

    #expect(loaded.projectID != beforeLoad.projectID)
    guard case .sessions(let summaries) = await controller.handle(.sessions) else {
        Issue.record("Expected the registered session to follow the loaded project.")
        return
    }
    #expect(summaries.first?.id == sessionID)
    #expect(summaries.first?.displayName == "Loaded Project")

    await #expect(throws: ProjectControllerError.self) {
        _ = try await workspace.perform(oldAction)
    }
    #expect(workspace.view?.projectID == loaded.projectID)
    #expect(workspace.view?.projectName == "Loaded Project")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func registryRejectsDuplicateLoadedAuthorityUntilTheChangedSessionIsUnregistered() async throws {
    let temporaryDirectory = try makeProjectAgentTemporaryDirectory()
    defer { removeProjectAgentTemporaryDirectory(temporaryDirectory) }
    let (_, changedWorkspace) = try await makeProjectWorkspace(
        document: .empty(named: "Changed Session")
    )
    let (_, authoritativeWorkspace) = try await makeProjectWorkspace(
        document: .empty(named: "Authoritative Session")
    )
    let packageURL = temporaryDirectory.appendingPathComponent("authoritative.rupa")
    _ = try await authoritativeWorkspace.save(to: packageURL)

    let controller = ProjectAgentCommandController()
    let changedSessionID = try #require(
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")
    )
    let authoritativeSessionID = try #require(
        UUID(uuidString: "00000000-0000-0000-0000-000000000002")
    )
    try await controller.register(workspace: changedWorkspace, id: changedSessionID)
    try await controller.register(
        workspace: authoritativeWorkspace,
        id: authoritativeSessionID
    )
    _ = try await changedWorkspace.load(from: packageURL)
    let loadedState = try #require(changedWorkspace.view)

    let conflict = await controller.handle(.sessions)
    guard case .failure(let conflictError) = conflict else {
        Issue.record("Expected duplicate loaded project identity to invalidate the changed session.")
        return
    }
    #expect(conflictError.code == .documentOpenInApp)

    let rejectedMutation = await controller.handle(
        .execute(
            sessionID: changedSessionID,
            command: .renameDocument(name: "Must Not Mutate"),
            expectedGeneration: loadedState.documentGeneration
        )
    )
    guard case .failure(let rejectedError) = rejectedMutation else {
        Issue.record("Expected the invalidated session mutation to be rejected.")
        return
    }
    #expect(rejectedError.code == .documentOpenInApp)
    #expect(changedWorkspace.view?.projectName == "Authoritative Session")
    #expect(authoritativeWorkspace.view?.projectName == "Authoritative Session")

    await controller.unregister(id: changedSessionID)
    guard case .sessions(let retained) = await controller.handle(.sessions) else {
        Issue.record("Expected the original project authority to remain registered.")
        return
    }
    #expect(retained.map(\.id) == [authoritativeSessionID])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func registryDoesNotInvalidateFromAStaleVisibleIdentityDuringConsecutiveLoads() async throws {
    let temporaryDirectory = try makeProjectAgentTemporaryDirectory()
    defer { removeProjectAgentTemporaryDirectory(temporaryDirectory) }
    let (_, secondWorkspace) = try await makeProjectWorkspace(
        document: .empty(named: "Second Project")
    )
    let (_, thirdWorkspace) = try await makeProjectWorkspace(
        document: .empty(named: "Third Project")
    )
    let secondURL = temporaryDirectory.appendingPathComponent("second.rupa")
    let thirdURL = temporaryDirectory.appendingPathComponent("third.rupa")
    _ = try await secondWorkspace.save(to: secondURL)
    _ = try await thirdWorkspace.save(to: thirdURL)

    let gate = ProjectAgentViewBuildGate()
    defer { gate.release() }
    let firstProject = try ProjectController(
        document: .empty(named: "First Project"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let firstWorkspace = ProjectWorkspace(
        project: firstProject,
        viewBuilder: ProjectAgentGatedViewBuilder(gate: gate, blockedBuildNumber: 3)
    )
    _ = try await firstWorkspace.evaluate()
    let controller = ProjectAgentCommandController()
    let firstID = try await controller.register(workspace: firstWorkspace)
    let secondID = try await controller.register(workspace: secondWorkspace)
    _ = try await firstWorkspace.load(from: secondURL)
    let visibleSecond = try #require(firstWorkspace.view)

    let thirdLoad = Task {
        try await firstWorkspace.load(from: thirdURL)
    }
    while !gate.didStart {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(firstWorkspace.view?.projectID == visibleSecond.projectID)
    #expect(try await firstProject.currentState().document.projectID != visibleSecond.projectID)

    let duringGap = await controller.handle(
        .parameters(sessionID: firstID, expectedGeneration: visibleSecond.documentGeneration)
    )
    guard case .failure(let gapError) = duringGap else {
        Issue.record("Expected stale visible load identity to fail exact validation.")
        return
    }
    #expect(gapError.code == .projectMismatch)

    gate.release()
    let visibleThird = try await thirdLoad.value
    guard case .parameters = await controller.handle(
        .parameters(sessionID: firstID, expectedGeneration: visibleThird.documentGeneration)
    ) else {
        Issue.record("Expected the uniquely loaded session to remain registered.")
        return
    }
    let secondView = try #require(secondWorkspace.view)
    guard case .parameters = await controller.handle(
        .parameters(sessionID: secondID, expectedGeneration: secondView.documentGeneration)
    ) else {
        Issue.record("Expected the original second-project session to remain registered.")
        return
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentRegistryRejectsDuplicatesAndUnregistersExactly() async throws {
    let sharedDocument = DesignDocument.empty(named: "Shared Identity")
    let first = try DefaultProjectWorkspaceFactory().makeWorkspace(document: sharedDocument)
    let second = try DefaultProjectWorkspaceFactory().makeWorkspace(document: sharedDocument)
    let independent = try DefaultProjectWorkspaceFactory().makeWorkspace()
    _ = try await first.evaluate()
    _ = try await second.evaluate()
    _ = try await independent.evaluate()
    let controller = ProjectAgentCommandController()
    let sessionID = UUID()
    let path = URL(fileURLWithPath: "/tmp/rupa-project-agent-\(UUID().uuidString).rupa")

    try await controller.register(workspace: first, path: path, id: sessionID)
    await #expect(throws: EditorError.self) {
        try await controller.register(workspace: independent, id: sessionID)
    }
    await #expect(throws: EditorError.self) {
        try await controller.register(workspace: independent, path: path)
    }
    var duplicateProjectError: EditorError?
    do {
        try await controller.register(workspace: second)
    } catch let error as EditorError {
        duplicateProjectError = error
    }
    #expect(duplicateProjectError?.code == .documentOpenInApp)

    await controller.unregister(id: sessionID)
    let response = await controller.handle(
        .parameters(sessionID: sessionID, expectedGeneration: nil)
    )
    guard case .failure(let error) = response else {
        Issue.record("Expected an unregistered project session to be unavailable.")
        return
    }
    #expect(error.code == .sessionNotFound)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentRegistrationRejectsAStalePublishedView() async throws {
    let project = try ProjectController(
        document: .empty(named: "Registration Base"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(
        project: project,
        viewBuilder: ProjectAgentNthFailingViewBuilder(failingBuildNumber: 2)
    )
    _ = try await workspace.evaluate()
    let initial = try #require(workspace.view)
    let action = try DefaultProjectWorkspaceActionPlanner().source(
        name: "registration.stale-view",
        commands: [.renameDocument(name: "Committed Authority")],
        from: initial
    )
    do {
        _ = try await workspace.perform(action)
        Issue.record("Expected the registration fixture view projection to fail.")
    } catch is ProjectWorkspacePostCommitError {
        // The source authority committed while the published view stayed stale.
    }

    let controller = ProjectAgentCommandController()
    do {
        _ = try await controller.register(workspace: workspace)
        Issue.record("Expected stale workspace registration to fail.")
    } catch let error as ProjectControllerError {
        #expect(error.code == .revisionConflict)
    }
    guard case .status(let status) = await controller.handle(.status) else {
        Issue.record("Expected registry status after rejected registration.")
        return
    }
    #expect(status.sessionCount == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func staleViewCannotHideDuplicateCurrentProjectIdentityAtRegistration() async throws {
    let temporaryDirectory = try makeProjectAgentTemporaryDirectory()
    defer { removeProjectAgentTemporaryDirectory(temporaryDirectory) }
    let (_, authoritativeWorkspace) = try await makeProjectWorkspace(
        document: .empty(named: "Registered Authority")
    )
    let packageURL = temporaryDirectory.appendingPathComponent("registered.rupa")
    _ = try await authoritativeWorkspace.save(to: packageURL)
    let controller = ProjectAgentCommandController()
    let authoritativeID = try await controller.register(
        workspace: authoritativeWorkspace
    )

    let staleProject = try ProjectController(
        document: .empty(named: "Stale Visible Identity"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let staleWorkspace = ProjectWorkspace(
        project: staleProject,
        viewBuilder: ProjectAgentNthFailingViewBuilder(failingBuildNumber: 2)
    )
    _ = try await staleWorkspace.evaluate()
    let visibleBeforeLoad = try #require(staleWorkspace.view)
    do {
        _ = try await staleWorkspace.load(from: packageURL)
        Issue.record("Expected the loaded authority view projection to fail.")
    } catch is ProjectAgentTestError {
        // The old project ID remains visible while authority now owns the loaded ID.
    }
    #expect(staleWorkspace.view?.projectID == visibleBeforeLoad.projectID)

    do {
        _ = try await controller.register(workspace: staleWorkspace)
        Issue.record("Expected stale project identity registration to fail.")
    } catch let error as ProjectControllerError {
        #expect(error.code == .projectMismatch)
    }
    guard case .sessions(let sessions) = await controller.handle(.sessions) else {
        Issue.record("Expected the original registered authority to remain available.")
        return
    }
    #expect(sessions.map(\.id) == [authoritativeID])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentCapabilityInvocationUsesProjectTransactionAuthority() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let view = try #require(workspace.view)
    let capabilityID = CapabilityID(rawValue: "agent.createExtrudedRectangle")
    let descriptor = try #require(
        controller.capabilityRegistry().descriptor(for: capabilityID)
    )
    let command = AutomationCommand.createExtrudedRectangle(
        name: "Project Capability Box",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(12.0, .millimeter),
        depth: .length(6.0, .millimeter),
        direction: .normal
    )
    let invocation = CapabilityInvocation(
        capabilityID: capabilityID,
        version: descriptor.version,
        payload: try canonicalValue(for: command),
        expectedTransactionRevision: view.transactionRevision
    )

    let response = await controller.handle(
        .invokeCapability(
            sessionID: sessionID,
            invocation: invocation,
            expectedWorkspaceRevision: view.workspaceState.revision
        )
    )
    guard case .capabilityExecution(let result) = response else {
        Issue.record("Expected capability execution through the project authority.")
        return
    }
    #expect(result.automation?.didMutate == true)
    #expect(workspace.view?.documentGeneration.value == view.documentGeneration.value + 1)
    #expect(workspace.view?.evaluationSnapshot.bodyCount == 1)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentCapabilityRegistryDeclaresExportArtifactSideEffectsExactly() throws {
    let controller = ProjectAgentCommandController()
    let registry = try controller.capabilityRegistry()
    let export = try #require(registry.descriptor(for: "agent.exportDocument"))
    let validation = try #require(registry.descriptor(for: "agent.validateDocument"))

    #expect(export.effect == .export)
    #expect(export.result.kind == .exportArtifact)
    #expect(export.execution.retrySafe == false)
    #expect(export.execution.supportsDryRun)
    #expect(export.execution.supportsCancellation)
    #expect(validation.effect == .query)
    #expect(validation.execution.retrySafe)
    #expect(validation.summary.contains("without publishing project state"))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentCapabilityRejectsSameEffectDifferentCommandIdentity() async throws {
    let (project, workspace) = try await makeProjectWorkspace(
        document: .empty(named: "Capability Identity")
    )
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let view = try #require(workspace.view)
    let capabilityID = CapabilityID(rawValue: "agent.renameDocument")
    let descriptor = try #require(
        controller.capabilityRegistry().descriptor(for: capabilityID)
    )
    let spoofedCommand = AutomationCommand.createExtrudedRectangle(
        name: "Must Not Exist",
        plane: .xy,
        width: .length(10.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(10.0, .millimeter),
        direction: .normal
    )
    let before = try await project.currentState()

    let response = await controller.handle(
        .invokeCapability(
            sessionID: sessionID,
            invocation: CapabilityInvocation(
                capabilityID: capabilityID,
                version: descriptor.version,
                payload: try canonicalValue(for: spoofedCommand),
                expectedTransactionRevision: view.transactionRevision
            ),
            expectedWorkspaceRevision: view.workspaceState.revision
        )
    )
    guard case .failure(let error) = response else {
        Issue.record("Expected mismatched capability and Automation command identity to fail.")
        return
    }
    #expect(error.code == .commandInvalid)
    let after = try await project.currentState()
    #expect(after.document.cadDocument.metadata.name == "Capability Identity")
    #expect(after.evaluationSnapshot.bodyCount == 0)
    #expect(after.transactionRevision == before.transactionRevision)
    #expect(after.publicationSequence == before.publicationSequence)
    #expect(after.package.productSource == before.package.productSource)
    #expect(after.package.cadSource == before.package.cadSource)
    #expect(after.evaluationSnapshot == before.evaluationSnapshot)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentCapabilityInvocationReportsWorkspaceRevisionMismatchExactly() async throws {
    let (project, workspace) = try await makeProjectWorkspace(
        document: .empty(named: "Capability Workspace")
    )
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let view = try #require(workspace.view)
    let capabilityID = CapabilityID(rawValue: "agent.setDisplayUnit")
    let descriptor = try #require(
        controller.capabilityRegistry().descriptor(for: capabilityID)
    )
    let before = try await project.currentState()
    let response = await controller.handle(
        .invokeCapability(
            sessionID: sessionID,
            invocation: CapabilityInvocation(
                capabilityID: capabilityID,
                version: descriptor.version,
                payload: try canonicalValue(
                    for: AutomationCommand.setDisplayUnit(.centimeter)
                ),
                expectedTransactionRevision: view.transactionRevision
            ),
            expectedWorkspaceRevision: WorkspaceRevision(
                view.workspaceState.revision.value + 1
            )
        )
    )
    guard case .failure(let error) = response else {
        Issue.record("Expected stale capability workspace coordinates to fail.")
        return
    }
    #expect(error.code == .workspaceRevisionMismatch)
    let after = try await project.currentState()
    #expect(after.package.productSource == before.package.productSource)
    #expect(after.package.cadSource == before.package.cadSource)
    #expect(after.evaluation.id == before.evaluation.id)
    #expect(after.evaluation.occurrences.keys == before.evaluation.occurrences.keys)
    #expect(after.publicationSequence == before.publicationSequence)
    #expect(after.workspaceState.revision == before.workspaceState.revision)
    #expect(after.workspaceState.displayUnit == before.workspaceState.displayUnit)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentDynamicDomainRouteUsesProjectTransactionAuthority() async throws {
    let capabilityID: DomainCapabilityID = "architecture.renameProject"
    let registry = try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: "architecture",
                supportedSchemaVersions: [
                    SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
                ]
            ),
        ],
        capabilityDescriptors: [
            DomainCapabilityDescriptor(
                id: capabilityID,
                namespace: "architecture",
                name: "Rename Project",
                summary: "Renames the authored project source.",
                effect: .documentMutation,
                resultKind: .documentTransaction,
                supportsDryRun: true,
                targetKinds: ["document"],
                failureMode: "Rejects stale project coordinates."
            ),
        ],
        commandLowerings: [
            ProjectAgentDomainRenameLowering(capabilityID: capabilityID),
        ]
    )
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController(domainRegistry: registry)
    let sessionID = try await controller.register(workspace: workspace)
    let view = try #require(workspace.view)

    let response = await controller.handle(
        .executeDomain(
            sessionID: sessionID,
            request: DomainCommandRequest(
                capabilityID: capabilityID,
                namespace: "architecture",
                payload: .object([:]),
                expectedGeneration: view.documentGeneration,
                expectedTransactionRevision: view.transactionRevision
            )
        )
    )
    guard case .domainExecution(let result) = response else {
        Issue.record("Expected dynamic domain execution through the project authority.")
        return
    }
    #expect(result.didMutate)
    #expect(workspace.view?.projectName == "Domain Project")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentDynamicDomainCapabilityInvocationSupportsDryRunAndCommit() async throws {
    let capabilityID: DomainCapabilityID = "architecture.renameCapabilityProject"
    let registry = try projectAgentDomainRegistry(capabilityID: capabilityID)
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController(domainRegistry: registry)
    let sessionID = try await controller.register(workspace: workspace)
    let before = try #require(workspace.view)
    let agentCapabilityID = CapabilityID(rawValue: "agent.\(capabilityID.rawValue)")
    let descriptor = try #require(
        controller.capabilityRegistry().descriptor(for: agentCapabilityID)
    )

    let dryRun = await controller.handle(
        .invokeCapability(
            sessionID: sessionID,
            invocation: CapabilityInvocation(
                capabilityID: agentCapabilityID,
                version: descriptor.version,
                payload: .object([:]),
                expectedTransactionRevision: before.transactionRevision,
                dryRun: true
            ),
            expectedWorkspaceRevision: before.workspaceState.revision
        )
    )
    guard case .capabilityExecution(let dryRunResult) = dryRun else {
        Issue.record("Expected dynamic domain capability dry-run execution.")
        return
    }
    #expect(dryRunResult.domain?.wouldMutate == true)
    #expect(dryRunResult.domain?.didMutate == false)
    #expect(workspace.view?.publicationSequence == before.publicationSequence)

    let committed = await controller.handle(
        .invokeCapability(
            sessionID: sessionID,
            invocation: CapabilityInvocation(
                capabilityID: agentCapabilityID,
                version: descriptor.version,
                payload: .object([:]),
                expectedTransactionRevision: before.transactionRevision
            ),
            expectedWorkspaceRevision: before.workspaceState.revision
        )
    )
    guard case .capabilityExecution(let committedResult) = committed else {
        Issue.record("Expected dynamic domain capability commit execution.")
        return
    }
    #expect(committedResult.domain?.didMutate == true)
    #expect(workspace.view?.projectName == "Domain Project")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentReadOnlyAutomationObservesProjectWithoutPublishing() async throws {
    let (project, workspace) = try await makeProjectWorkspace(
        document: .empty(named: "Read Only")
    )
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let before = try #require(workspace.view)
    let beforeState = try await project.currentState()

    let response = await controller.handle(
        .execute(
            sessionID: sessionID,
            command: .describeDocument,
            expectedGeneration: before.documentGeneration
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Expected the read-only command to use the project snapshot.")
        return
    }
    #expect(!result.didMutate)
    let after = try #require(workspace.view)
    #expect(after.documentGeneration == before.documentGeneration)
    #expect(after.transactionRevision == before.transactionRevision)
    #expect(after.publicationSequence == before.publicationSequence)
    let afterState = try await project.currentState()
    #expect(afterState.package.productSource == beforeState.package.productSource)
    #expect(afterState.package.cadSource == beforeState.package.cadSource)
    #expect(after.evaluationSnapshot == before.evaluationSnapshot)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentFileLifecycleAndNonCADExportFailExplicitly() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: .empty(named: "Unsupported")
    )
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let view = try #require(workspace.view)

    let responses = [
        await controller.handle(.createDocument(name: "Created", outputPath: nil)),
        await controller.handle(.openDocument(path: "/tmp/unsupported.rupa")),
        await controller.handle(
            .closeDocument(
                sessionID: sessionID,
                expectedGeneration: view.documentGeneration,
                discardUnsavedChanges: false
            )
        ),
        await controller.handle(
            .save(
                sessionID: sessionID,
                expectedGeneration: view.documentGeneration
            )
        ),
        await controller.handle(
            .resetDocument(
                sessionID: sessionID,
                name: "Reset",
                expectedGeneration: view.documentGeneration
            )
        ),
        await controller.handle(
            .export(
                sessionID: sessionID,
                outputPath: "/tmp/unsupported.stl",
                expectedGeneration: view.documentGeneration,
                options: ExportOptions(),
                dryRun: true
            )
        ),
    ]

    for response in responses {
        guard case .failure(let error) = response else {
            Issue.record("Expected unavailable file ownership to return a typed failure.")
            continue
        }
        #expect(error.code == .commandUnsupported)
    }
    let after = try #require(workspace.view)
    #expect(after.documentGeneration == view.documentGeneration)
    #expect(after.transactionRevision == view.transactionRevision)
    #expect(after.publicationSequence == view.publicationSequence)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentExportsCADOnlyProjectThroughStagedPublication() async throws {
    let temporaryDirectory = try makeProjectAgentTemporaryDirectory()
    defer { removeProjectAgentTemporaryDirectory(temporaryDirectory) }
    var document = DesignDocument.empty(named: "CAD Export")
    _ = try document.createExtrudedRectangle(
        name: "Box",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(12.0, .millimeter),
        depth: .length(6.0, .millimeter),
        direction: .normal
    )
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(document: document)
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let view = try #require(workspace.view)
    let outputURL = temporaryDirectory.appendingPathComponent("box.stl")

    let response = await controller.handle(
        .export(
            sessionID: sessionID,
            outputPath: outputURL.path,
            expectedGeneration: view.documentGeneration,
            options: ExportOptions(destinationPolicy: .overwrite),
            dryRun: false
        )
    )
    guard case .export(let result) = response else {
        Issue.record("Expected CAD-only Agent export to succeed.")
        return
    }
    #expect(result.outputPath == outputURL.path)
    #expect(result.byteCount > 84)
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
    #expect(
        try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
            .allSatisfy { !$0.hasPrefix(".rupa-export-") }
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentRejectsExternalProviderNamedCADAsNonCADAuthority() async throws {
    var document = DesignDocument.empty(named: "External Spoof")
    _ = try document.createExtrudedRectangle(
        name: "Box",
        plane: .xy,
        width: .length(10.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(10.0, .millimeter),
        direction: .normal
    )
    let bodyNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body
    })
    var object = try #require(bodyNode.object)
    let spoofID: GeometryRepresentationID = "representation.external-cad-spoof"
    object.geometryRepresentations.representations[spoofID] = GeometryRepresentation(
        id: spoofID,
        source: .external(providerID: "cad", sourceID: "spoof", outputID: "body")
    )
    document.productMetadata.sceneNodes[bodyNode.id]?.object = object
    try document.validate()

    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(document: document)
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let view = try #require(workspace.view)
    let response = await controller.handle(
        .export(
            sessionID: sessionID,
            outputPath: "/tmp/external-spoof.stl",
            expectedGeneration: view.documentGeneration,
            options: ExportOptions(),
            dryRun: true
        )
    )
    guard case .failure(let error) = response else {
        Issue.record("Expected an external provider named cad to remain non-CAD authority.")
        return
    }
    #expect(error.code == .commandUnsupported)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentRejectsMeshOnlyAndMixedAuthorityWithoutSideEffects() async throws {
    let temporaryDirectory = try makeProjectAgentTemporaryDirectory()
    defer { removeProjectAgentTemporaryDirectory(temporaryDirectory) }
    let fixtures = [
        try projectAgentMeshOnlyDocument(named: "Mesh Only Export"),
        try projectAgentCADAndMeshDocument(named: "Mixed Export"),
    ]

    for (index, document) in fixtures.enumerated() {
        let (project, workspace) = try await makeProjectWorkspace(document: document)
        let controller = ProjectAgentCommandController()
        let sessionID = try await controller.register(workspace: workspace)
        let view = try #require(workspace.view)
        let before = try await project.currentState()
        let outputURL = temporaryDirectory.appendingPathComponent("unsupported-\(index).stl")

        let response = await controller.handle(
            .export(
                sessionID: sessionID,
                outputPath: outputURL.path,
                expectedGeneration: view.documentGeneration,
                options: ExportOptions(destinationPolicy: .overwrite),
                dryRun: false
            )
        )
        guard case .failure(let error) = response else {
            Issue.record("Expected non-CAD-only authority to reject Agent export.")
            continue
        }
        #expect(error.code == .commandUnsupported)
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
        let after = try await project.currentState()
        #expect(after.package.productSource == before.package.productSource)
        #expect(after.package.cadSource == before.package.cadSource)
        #expect(after.evaluation.id == before.evaluation.id)
        #expect(after.publicationSequence == before.publicationSequence)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentReportsCommittedMutationReceiptWhenViewProjectionFails() async throws {
    let project = try ProjectController(
        document: .empty(named: "Before Receipt"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(
        project: project,
        viewBuilder: ProjectAgentNthFailingViewBuilder(failingBuildNumber: 2)
    )
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let before = try #require(workspace.view)

    let response = await controller.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Committed Source"),
            expectedGeneration: before.documentGeneration
        )
    )
    guard case .committedMutation(let outcome) = response else {
        Issue.record("Expected a committed mutation receipt instead of a retryable failure.")
        return
    }
    let state = try await project.currentState()
    #expect(outcome.stage == .viewProjection)
    #expect(outcome.mutation == .source)
    #expect(outcome.retryDisposition == .mustNotRetry)
    #expect(outcome.projectID == state.document.projectID)
    #expect(outcome.transactionRevision == state.transactionRevision)
    #expect(outcome.publicationSequence == state.publicationSequence)
    #expect(state.document.cadDocument.metadata.name == "Committed Source")
    #expect(workspace.view?.projectName == "Committed Source")
    #expect(workspace.view?.publicationSequence == outcome.publicationSequence)
    guard case .sessions(let summaries) = await controller.handle(.sessions) else {
        Issue.record("Expected recovered session summary after committed receipt.")
        return
    }
    #expect(summaries.first?.displayName == "Committed Source")
    let nextResponse = await controller.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "After Recovery"),
            expectedGeneration: outcome.documentGeneration
        )
    )
    guard case .command(let nextResult) = nextResponse else {
        Issue.record("Expected exactly one next mutation after automatic recovery.")
        return
    }
    #expect(nextResult.generation.value == outcome.documentGeneration.value + 1)
    #expect(workspace.view?.projectName == "After Recovery")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentReportsCommittedUndoReceiptWithoutMovingHistoryTwice() async throws {
    let project = try ProjectController(
        document: .empty(named: "Undo Base"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(
        project: project,
        viewBuilder: ProjectAgentNthFailingViewBuilder(failingBuildNumber: 3)
    )
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let initial = try #require(workspace.view)
    guard case .command = await controller.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Undo Candidate"),
            expectedGeneration: initial.documentGeneration
        )
    ) else {
        Issue.record("Expected the history fixture source mutation to commit.")
        return
    }
    let renamed = try #require(workspace.view)

    let response = await controller.handle(
        .undo(
            sessionID: sessionID,
            expectedGeneration: renamed.documentGeneration
        )
    )
    guard case .committedMutation(let outcome) = response else {
        Issue.record("Expected a committed undo receipt after view projection failed.")
        return
    }
    let state = try await project.currentState()
    #expect(outcome.mutation == .undo)
    #expect(outcome.retryDisposition == .mustNotRetry)
    #expect(state.document.cadDocument.metadata.name == "Undo Base")
    #expect(state.canUndo == false)
    #expect(state.canRedo == true)
    #expect(outcome.transactionRevision == state.transactionRevision)
    #expect(outcome.publicationSequence == state.publicationSequence)
    #expect(workspace.view?.projectName == "Undo Base")
    #expect(workspace.view?.canRedo == true)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func staleCapturedCoordinatesRejectSelectionEvaluationAndHistory() async throws {
    let (_, workspace) = try await makeProjectWorkspace(
        document: .empty(named: "Coordinates")
    )
    let initial = try #require(workspace.view)
    let sourceAction = try DefaultProjectWorkspaceActionPlanner().source(
        name: "coordinate.history",
        commands: [.renameDocument(name: "History Source")],
        from: initial
    )
    _ = try await workspace.perform(sourceAction)
    let captured = try #require(workspace.view)
    _ = try await workspace.applyWorkspace(.setDisplayUnit(.centimeter))
    let retained = try #require(workspace.view)

    do {
        _ = try await workspace.applySelection(.clear, from: captured)
        Issue.record("Expected stale selection publication coordinates to fail.")
    } catch let error as ProjectControllerError {
        #expect(error.code == .publicationConflict)
    }
    do {
        _ = try await workspace.evaluate(from: captured)
        Issue.record("Expected stale evaluation publication coordinates to fail.")
    } catch let error as ProjectControllerError {
        #expect(error.code == .publicationConflict)
    }
    do {
        _ = try await workspace.undo(from: captured)
        Issue.record("Expected stale history publication coordinates to fail.")
    } catch let error as ProjectControllerError {
        #expect(error.code == .publicationConflict)
    }
    #expect(workspace.view?.projectName == "History Source")
    #expect(workspace.view?.publicationSequence == retained.publicationSequence)
    #expect(workspace.view?.workspaceState.displayUnit == .centimeter)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func agentUndoReturnsItsExactCommittedViewWhenANewerInteractionPublishesFirst() async throws {
    let gate = ProjectAgentViewBuildGate()
    defer { gate.release() }
    let project = try ProjectController(
        document: .empty(named: "Exact Undo Base"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(
        project: project,
        viewBuilder: ProjectAgentGatedViewBuilder(gate: gate, blockedBuildNumber: 3)
    )
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let initial = try #require(workspace.view)
    guard case .command = await controller.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Exact Undo Candidate"),
            expectedGeneration: initial.documentGeneration
        )
    ) else {
        Issue.record("Expected the history fixture mutation to commit.")
        return
    }
    let renamed = try #require(workspace.view)

    let undoTask = Task {
        await controller.handle(
            .undo(
                sessionID: sessionID,
                expectedGeneration: renamed.documentGeneration
            )
        )
    }
    while !gate.didStart {
        try await Task.sleep(for: .milliseconds(1))
    }
    let undoState = try await project.currentState()
    let interaction = try ProjectInteractionTransaction(
        workspaceCommands: [.setDisplayUnit(.centimeter)],
        expectedProjectID: undoState.document.projectID,
        expectedTransactionRevision: undoState.transactionRevision,
        expectedPublicationSequence: undoState.publicationSequence
    )
    let newerView = try await workspace.applyInteraction(interaction)
    gate.release()

    guard case .sessionOperation(let undoResult) = await undoTask.value else {
        Issue.record("Expected the Agent undo response to retain its exact committed view.")
        return
    }
    #expect(undoResult.operation == .undo)
    #expect(undoResult.session.workspaceRevision == undoState.workspaceState.revision)
    #expect(undoResult.session.workspaceRevision != newerView.workspaceState.revision)
    #expect(workspace.view?.publicationSequence == newerView.publicationSequence)
    #expect(workspace.view?.workspaceState.displayUnit == .centimeter)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func unregisterWaitsForAnAlreadyLeasedAgentMutationBeforeReplacement() async throws {
    let gate = ProjectAgentBlockingEvaluationGate(blockedSourceName: "Agent Blocked")
    defer { gate.release() }
    let project = try ProjectController(
        document: .empty(named: "Old Project"),
        evaluatorPreparer: ProjectAgentStaticEvaluatorPreparer(
            evaluator: ProjectAgentBlockingEvaluator(gate: gate)
        ),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: project)
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController()
    let sessionID = UUID()
    try await controller.register(workspace: workspace, id: sessionID)
    let before = try #require(workspace.view)
    let inFlight = Task {
        await controller.handle(
            .execute(
                sessionID: sessionID,
                command: .renameDocument(name: "Agent Blocked"),
                expectedGeneration: before.documentGeneration
            )
        )
    }
    while !gate.didStart {
        try await Task.sleep(for: .milliseconds(1))
    }
    let unregisterTask = Task {
        await controller.unregister(id: sessionID)
    }
    var didBeginUnregister = false
    for _ in 0..<1_000 {
        let duringUnregister = await controller.handle(
            .parameters(sessionID: sessionID, expectedGeneration: before.documentGeneration)
        )
        if case .failure(let error) = duringUnregister,
           error.code == .sessionNotFound {
            didBeginUnregister = true
            break
        }
        await Task.yield()
    }
    #expect(didBeginUnregister)

    let replacement = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: .empty(named: "Replacement")
    )
    _ = try await replacement.evaluate()
    await #expect(throws: EditorError.self) {
        try await controller.register(workspace: replacement, id: sessionID)
    }
    gate.release()

    guard case .command(let committed) = await inFlight.value else {
        Issue.record("Expected the operation leased before unregister to finish first.")
        return
    }
    #expect(committed.didMutate)
    await unregisterTask.value
    try await controller.register(workspace: replacement, id: sessionID)

    let retained = try await project.currentState()
    #expect(retained.document.cadDocument.metadata.name == "Agent Blocked")
    #expect(retained.transactionRevision.value == before.transactionRevision.value + 1)
    #expect(retained.publicationSequence > before.publicationSequence)
    #expect(replacement.view?.projectName == "Replacement")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func agentReadAndExportRejectProjectAuthorityNewerThanPublishedView() async throws {
    let temporaryDirectory = try makeProjectAgentTemporaryDirectory()
    defer { removeProjectAgentTemporaryDirectory(temporaryDirectory) }
    var document = DesignDocument.empty(named: "Before Gated View")
    _ = try document.createExtrudedRectangle(
        name: "Box",
        plane: .xy,
        width: .length(10.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(10.0, .millimeter),
        direction: .normal
    )
    let gate = ProjectAgentViewBuildGate()
    defer { gate.release() }
    let project = try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(
        project: project,
        viewBuilder: ProjectAgentGatedViewBuilder(gate: gate, blockedBuildNumber: 2)
    )
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let oldView = try #require(workspace.view)
    let uiAction = try DefaultProjectWorkspaceActionPlanner().source(
        name: "ui.gated-view",
        commands: [.renameDocument(name: "Authority Is Newer")],
        from: oldView
    )
    let uiCommit = Task {
        try await workspace.perform(uiAction)
    }
    while !gate.didStart {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(workspace.view?.publicationSequence == oldView.publicationSequence)
    #expect(try await project.currentState().publicationSequence > oldView.publicationSequence)

    let readResponse = await controller.handle(
        .parameters(sessionID: sessionID, expectedGeneration: oldView.documentGeneration)
    )
    guard case .failure(let readError) = readResponse else {
        Issue.record("Expected read validation against current project authority to fail.")
        return
    }
    #expect(readError.code == .documentTransactionRevisionMismatch)

    let sessionsResponse = await controller.handle(.sessions)
    guard case .failure(let sessionsError) = sessionsResponse else {
        Issue.record("Expected session summary validation against current project authority to fail.")
        return
    }
    #expect(sessionsError.code == .documentTransactionRevisionMismatch)

    let outputURL = temporaryDirectory.appendingPathComponent("retained.stl")
    let retainedBytes = Data("retained-export".utf8)
    try retainedBytes.write(to: outputURL)
    let exportResponse = await controller.handle(
        .export(
            sessionID: sessionID,
            outputPath: outputURL.path,
            expectedGeneration: oldView.documentGeneration,
            options: ExportOptions(destinationPolicy: .overwrite),
            dryRun: false
        )
    )
    guard case .failure(let exportError) = exportResponse else {
        Issue.record("Expected staged export validation against current authority to fail.")
        return
    }
    #expect(exportError.code == .documentTransactionRevisionMismatch)
    #expect(try Data(contentsOf: outputURL) == retainedBytes)
    #expect(
        try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
            .allSatisfy { !$0.hasPrefix(".rupa-export-") }
    )

    gate.release()
    _ = try await uiCommit.value
    #expect(workspace.view?.projectName == "Authority Is Newer")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func agentRejectsWorkspaceOnlyPublicationGapWithExactTypedError() async throws {
    let gate = ProjectAgentViewBuildGate()
    defer { gate.release() }
    let project = try ProjectController(
        document: .empty(named: "Publication Gap"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(
        project: project,
        viewBuilder: ProjectAgentGatedViewBuilder(gate: gate, blockedBuildNumber: 2)
    )
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let oldView = try #require(workspace.view)

    let interactionTask = Task {
        try await workspace.applyWorkspace(.setDisplayUnit(.centimeter))
    }
    while !gate.didStart {
        try await Task.sleep(for: .milliseconds(1))
    }
    let authoritative = try await project.currentState()
    #expect(authoritative.transactionRevision == oldView.transactionRevision)
    #expect(authoritative.publicationSequence > oldView.publicationSequence)

    let readResponse = await controller.handle(
        .parameters(sessionID: sessionID, expectedGeneration: oldView.documentGeneration)
    )
    guard case .failure(let readError) = readResponse else {
        Issue.record("Expected the stale publication read to fail.")
        return
    }
    #expect(readError.code == .projectPublicationMismatch)

    let mutationResponse = await controller.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Must Not Commit"),
            expectedGeneration: oldView.documentGeneration
        )
    )
    guard case .failure(let mutationError) = mutationResponse else {
        Issue.record("Expected the stale publication mutation to fail.")
        return
    }
    #expect(mutationError.code == .projectPublicationMismatch)
    #expect(try await project.currentState().document.cadDocument.metadata.name == "Publication Gap")

    gate.release()
    let published = try await interactionTask.value
    #expect(published.publicationSequence == authoritative.publicationSequence)
    #expect(workspace.view?.workspaceState.displayUnit == .centimeter)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func cancelledAgentExportDiscardsStageAndPreservesDestination() async throws {
    let temporaryDirectory = try makeProjectAgentTemporaryDirectory()
    defer { removeProjectAgentTemporaryDirectory(temporaryDirectory) }
    var document = DesignDocument.empty(named: "Cancelled Export")
    _ = try document.createExtrudedRectangle(
        name: "Box",
        plane: .xy,
        width: .length(10.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(10.0, .millimeter),
        direction: .normal
    )
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(document: document)
    _ = try await workspace.evaluate()
    let gate = ProjectAgentExportPreflightGate()
    defer { gate.release() }
    let controller = ProjectAgentCommandController(
        exportExecutor: ProjectAgentExportExecutor(
            exportService: DocumentExportService(
                preflightValidators: [
                    ProjectAgentBlockingExportValidator(gate: gate),
                ]
            )
        )
    )
    let sessionID = try await controller.register(workspace: workspace)
    let view = try #require(workspace.view)
    let outputURL = temporaryDirectory.appendingPathComponent("cancelled.stl")
    let retainedBytes = Data("retained-cancelled-export".utf8)
    try retainedBytes.write(to: outputURL)

    let exportTask = Task {
        await controller.handle(
            .export(
                sessionID: sessionID,
                outputPath: outputURL.path,
                expectedGeneration: view.documentGeneration,
                options: ExportOptions(destinationPolicy: .overwrite),
                dryRun: false
            )
        )
    }
    while !gate.didStart {
        try await Task.sleep(for: .milliseconds(1))
    }
    exportTask.cancel()
    gate.release()

    guard case .failure = await exportTask.value else {
        Issue.record("Expected cancelled Agent export to fail without publication.")
        return
    }
    #expect(try Data(contentsOf: outputURL) == retainedBytes)
    #expect(
        try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
            .allSatisfy { !$0.hasPrefix(".rupa-export-") }
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func unregisterLinearizesAfterAnAlreadyLeasedExportPublication() async throws {
    let temporaryDirectory = try makeProjectAgentTemporaryDirectory()
    defer { removeProjectAgentTemporaryDirectory(temporaryDirectory) }
    var document = DesignDocument.empty(named: "Leased Export")
    _ = try document.createExtrudedRectangle(
        name: "Box",
        plane: .xy,
        width: .length(10.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(10.0, .millimeter),
        direction: .normal
    )
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(document: document)
    _ = try await workspace.evaluate()
    let gate = ProjectAgentExportPreflightGate()
    defer { gate.release() }
    let controller = ProjectAgentCommandController(
        exportExecutor: ProjectAgentExportExecutor(
            exportService: DocumentExportService(
                preflightValidators: [
                    ProjectAgentBlockingExportValidator(gate: gate),
                ]
            )
        )
    )
    let sessionID = try await controller.register(workspace: workspace)
    let view = try #require(workspace.view)
    let outputURL = temporaryDirectory.appendingPathComponent("leased.stl")

    let exportTask = Task {
        await controller.handle(
            .export(
                sessionID: sessionID,
                outputPath: outputURL.path,
                expectedGeneration: view.documentGeneration,
                options: ExportOptions(destinationPolicy: .overwrite),
                dryRun: false
            )
        )
    }
    while !gate.didStart {
        try await Task.sleep(for: .milliseconds(1))
    }
    let unregisterTask = Task {
        await controller.unregister(id: sessionID)
    }
    var didBeginUnregister = false
    for _ in 0..<1_000 {
        let duringUnregister = await controller.handle(
            .parameters(sessionID: sessionID, expectedGeneration: view.documentGeneration)
        )
        if case .failure(let error) = duringUnregister,
           error.code == .sessionNotFound {
            didBeginUnregister = true
            break
        }
        await Task.yield()
    }
    #expect(didBeginUnregister)

    gate.release()
    guard case .export(let result) = await exportTask.value else {
        Issue.record("Expected the export leased before unregister to publish first.")
        return
    }
    #expect(result.outputPath == outputURL.path)
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
    await unregisterTask.value

    let afterUnregister = await controller.handle(
        .parameters(sessionID: sessionID, expectedGeneration: view.documentGeneration)
    )
    guard case .failure(let error) = afterUnregister else {
        Issue.record("Expected operations acquired after unregister to fail.")
        return
    }
    #expect(error.code == .sessionNotFound)
}

@Test(.timeLimit(.minutes(1)))
func exportCleanupFailurePreservesPrimaryLifecycleAndStaleCodes() {
    let mapper = ProjectAgentErrorMapper()
    let cleanup = EditorError(code: .exportFailed, message: "Cleanup fixture failed.")
    let lifecycle = mapper.editorError(
        preserving: EditorError(code: .sessionNotFound, message: "Registration ended."),
        cleanupFailure: cleanup
    )
    let stale = mapper.editorError(
        preserving: ProjectControllerError(
            code: .publicationConflict,
            message: "Publication advanced."
        ),
        cleanupFailure: cleanup
    )

    #expect(lifecycle.code == .sessionNotFound)
    #expect(stale.code == .projectPublicationMismatch)
    #expect(lifecycle.message.contains("Cleanup fixture failed"))
    #expect(stale.message.contains("Cleanup fixture failed"))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentUnavailableHistoryFailsWithoutChangingProject() async throws {
    let (project, workspace) = try await makeProjectWorkspace(
        document: .empty(named: "No History")
    )
    let controller = ProjectAgentCommandController()
    let sessionID = try await controller.register(workspace: workspace)
    let before = try await project.currentState()

    let response = await controller.handle(
        .undo(
            sessionID: sessionID,
            expectedGeneration: before.documentGeneration
        )
    )
    guard case .failure(let error) = response else {
        Issue.record("Expected unavailable history to fail explicitly.")
        return
    }
    #expect(error.code == .commandInvalid)

    let after = try await project.currentState()
    #expect(after.documentGeneration == before.documentGeneration)
    #expect(after.transactionRevision == before.transactionRevision)
    #expect(after.publicationSequence == before.publicationSequence)
    #expect(after.package.productSource == before.package.productSource)
    #expect(after.package.cadSource == before.package.cadSource)
    #expect(after.evaluationSnapshot == before.evaluationSnapshot)
}

@MainActor
private func makeProjectWorkspace(
    document: DesignDocument
) async throws -> (ProjectController, ProjectWorkspace) {
    let project = try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: project)
    _ = try await workspace.evaluate()
    return (project, workspace)
}

private func canonicalValue<Value: Encodable>(for value: Value) throws -> CanonicalValue {
    try JSONDecoder().decode(CanonicalValue.self, from: JSONEncoder().encode(value))
}

private struct ProjectAgentDomainRenameLowering: DomainCommandLowering {
    let capabilityID: DomainCapabilityID

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        .automationBatch(
            AutomationBatch(
                commands: [.renameDocument(name: "Domain Project")],
                expectedGeneration: request.expectedGeneration,
                expectedTransactionRevision: request.expectedTransactionRevision
            )
        )
    }
}

private func projectAgentDomainRegistry(
    capabilityID: DomainCapabilityID
) throws -> DomainRegistry {
    try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: "architecture",
                supportedSchemaVersions: [
                    SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
                ]
            ),
        ],
        capabilityDescriptors: [
            DomainCapabilityDescriptor(
                id: capabilityID,
                namespace: "architecture",
                name: "Rename Project",
                summary: "Renames the authored project source.",
                effect: .documentMutation,
                resultKind: .documentTransaction,
                supportsDryRun: true,
                targetKinds: ["document"],
                failureMode: "Rejects stale project coordinates."
            ),
        ],
        commandLowerings: [
            ProjectAgentDomainRenameLowering(capabilityID: capabilityID),
        ]
    )
}

private final class ProjectAgentBlockingEvaluationGate: Sendable {
    private struct State {
        var didStart = false
        var canFinish = false
    }

    private let state = Mutex(State())
    private let blockedSourceName: String

    init(blockedSourceName: String) {
        self.blockedSourceName = blockedSourceName
    }

    var didStart: Bool {
        state.withLock { $0.didStart }
    }

    func waitIfNeeded(sourceName: String) {
        guard sourceName == blockedSourceName else {
            return
        }
        state.withLock { $0.didStart = true }
        while !state.withLock({ $0.canFinish }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func release() {
        state.withLock { $0.canFinish = true }
    }
}

private struct ProjectAgentBlockingEvaluator: ProjectEvaluating {
    let gate: ProjectAgentBlockingEvaluationGate

    func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        gate.waitIfNeeded(sourceName: project.name)
        return try ProjectEvaluationEngine().evaluate(
            project: project,
            purpose: purpose,
            revision: revision
        )
    }
}

private struct ProjectAgentStaticEvaluatorPreparer: ProjectEvaluatorPreparing {
    let evaluator: any ProjectEvaluating

    func makeEvaluator(
        for _: DesignDocument,
        reusing _: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        evaluator
    }
}

private final class ProjectAgentNthFailingViewBuilder:
    ProjectViewSnapshotBuilding,
    Sendable {
    private let count = Mutex(0)
    private let failingBuildNumber: Int

    init(failingBuildNumber: Int) {
        self.failingBuildNumber = failingBuildNumber
    }

    func build(from state: ProjectStateSnapshot) throws -> ProjectViewSnapshot {
        let buildNumber = count.withLock { value in
            value += 1
            return value
        }
        guard buildNumber != failingBuildNumber else {
            throw ProjectAgentTestError.viewProjectionFailed
        }
        return try ProjectViewSnapshotBuilder().build(from: state)
    }
}

private final class ProjectAgentViewBuildGate: Sendable {
    private struct State {
        var didStart = false
        var canFinish = false
    }

    private let state = Mutex(State())

    var didStart: Bool {
        state.withLock { $0.didStart }
    }

    func wait() {
        state.withLock { $0.didStart = true }
        while !state.withLock({ $0.canFinish }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func release() {
        state.withLock { $0.canFinish = true }
    }
}

private final class ProjectAgentExportPreflightGate: Sendable {
    private struct State {
        var didStart = false
        var canFinish = false
    }

    private let state = Mutex(State())

    var didStart: Bool {
        state.withLock { $0.didStart }
    }

    func wait() {
        state.withLock { $0.didStart = true }
        while !state.withLock({ $0.canFinish }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func release() {
        state.withLock { $0.canFinish = true }
    }
}

private struct ProjectAgentBlockingExportValidator: DocumentExportPreflightValidator {
    let gate: ProjectAgentExportPreflightGate

    func validateExport(
        context _: DocumentExportPreflightContext
    ) throws -> DocumentExportPreflightResult {
        gate.wait()
        return DocumentExportPreflightResult(
            policyEvaluation: ValidationPolicyEvaluation(
                policyID: "project-agent.cancelled-export",
                decision: .allow,
                failures: []
            ),
            diagnostics: [],
            findings: [],
            blockingReasons: []
        )
    }
}

private final class ProjectAgentGatedViewBuilder: ProjectViewSnapshotBuilding, Sendable {
    private let count = Mutex(0)
    private let gate: ProjectAgentViewBuildGate
    private let blockedBuildNumber: Int

    init(gate: ProjectAgentViewBuildGate, blockedBuildNumber: Int) {
        self.gate = gate
        self.blockedBuildNumber = blockedBuildNumber
    }

    func build(from state: ProjectStateSnapshot) throws -> ProjectViewSnapshot {
        let buildNumber = count.withLock { value in
            value += 1
            return value
        }
        if buildNumber == blockedBuildNumber {
            gate.wait()
        }
        return try ProjectViewSnapshotBuilder().build(from: state)
    }
}

private enum ProjectAgentTestError: Error {
    case viewProjectionFailed
}

private func makeProjectAgentTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func projectAgentMeshOnlyDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let mesh = try projectAgentTriangleMesh(identity: "mesh.agent-only")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let representationID: GeometryRepresentationID = "representation.agent-mesh-only"
    document.authoredMeshAssets[asset.id] = asset
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: projectAgentRepresentationSet(
                representationID: representationID,
                source: .authoredMesh(asset.id)
            )
        )
    )
    try document.validate()
    return document
}

private func projectAgentCADAndMeshDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let bodyFeatureID = try document.createExtrudedRectangle(
        name: "Body",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.0, .meter),
        depth: .length(1.0, .meter),
        direction: .normal
    )
    let bodyNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference == .body(bodyFeatureID)
    }?.key)
    var object = try #require(document.productMetadata.sceneNodes[bodyNodeID]?.object)
    let cadRepresentationID = try #require(
        object.geometryRepresentations.selection?.modeling
    )
    let mesh = try projectAgentTriangleMesh(identity: "mesh.agent-mixed")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let meshRepresentationID: GeometryRepresentationID = "representation.agent-mixed"
    document.authoredMeshAssets[asset.id] = asset
    object.geometryRepresentations.representations[meshRepresentationID] =
        GeometryRepresentation(
            id: meshRepresentationID,
            source: .authoredMesh(asset.id)
        )
    object.geometryRepresentations.selection = GeometryRepresentationSelection(
        modeling: cadRepresentationID,
        presentation: meshRepresentationID
    )
    document.productMetadata.sceneNodes[bodyNodeID]?.object = object
    try document.validate()
    return document
}

private func projectAgentRepresentationSet(
    representationID: GeometryRepresentationID,
    source: GeometrySourceReference
) -> GeometryRepresentationSet {
    GeometryRepresentationSet(
        representations: [
            representationID: GeometryRepresentation(
                id: representationID,
                source: source
            ),
        ],
        selection: GeometryRepresentationSelection(
            modeling: representationID,
            presentation: representationID
        )
    )
}

private func projectAgentTriangleMesh(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

private func removeProjectAgentTemporaryDirectory(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove Project Agent test directory: \(error)")
    }
}
