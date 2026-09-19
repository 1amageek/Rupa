import AppKit
import CADCore
import CADIR
import Foundation
import RupaAgentProtocol
import RupaAgentRuntime
import RupaCore
import RupaCoreTypes
@testable import RupaGeometry
import RupaKit
import RupaProject
import RupaProjectModel
import RupaProjectPackage
import RupaProjectAccessPlatform
import RupaUI
import RupaViewportScene
import Synchronization
import Testing
@testable import Rupa

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationGeometryExchangeUsesTransientFileAccessWithoutReplacingProjectAssociation() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let input = directory.appendingPathComponent("triangle.obj")
        try Data("# unit millimeter\nv 0 0 0\nv 10 0 0\nv 0 10 0\nf 1 2 3\n".utf8).write(to: input)
        let output = directory.appendingPathComponent("triangle.stl")
        let projectURL = directory.appendingPathComponent("design.rupa")
        let opener = ApplicationSecurityScopedAccessOpenerProbe()
        let coordinator = ApplicationProjectCoordinator(
            workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
            agentRegistrar: ApplicationAgentSessionRegistrarProbe(),
            securityScopedAccessOpener: opener
        )
        await coordinator.launch()
        await coordinator.save(to: projectURL)
        #expect(coordinator.failure == nil)
        let initial = try #require(coordinator.snapshot)
        await coordinator.importGeometry(from: input, format: .obj, unitForUnmarkedData: nil)
        #expect(coordinator.failure == nil)
        #expect(coordinator.snapshot?.document.document.authoredMeshAssets.count == 1)
        #expect(coordinator.currentFileURL == projectURL)
        #expect(!opener.activeProjectURLs.contains(input))
        await coordinator.exportGeometry(to: output, format: .stl, unit: .millimeter)
        #expect(coordinator.failure == nil)
        #expect(try Data(contentsOf: output).count > 84)
        #expect(coordinator.currentFileURL == projectURL)
        #expect(!opener.activeProjectURLs.contains(output))
        #expect(opener.openedProjectURLs.contains(input))
        #expect(opener.openedProjectURLs.contains(output))
        await coordinator.undo()
        #expect(coordinator.snapshot?.document.document.authoredMeshAssets == initial.document.document.authoredMeshAssets)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationGeometryExchangeReportsTypedFailuresWithoutMutationOrFileLoss() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let input = directory.appendingPathComponent("invalid.obj")
        try Data("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n".utf8).write(to: input)
        let opener = ApplicationSecurityScopedAccessOpenerProbe()
        let coordinator = ApplicationProjectCoordinator(
            workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
            agentRegistrar: ApplicationAgentSessionRegistrarProbe(),
            securityScopedAccessOpener: opener
        )
        await coordinator.launch()
        let initial = try #require(coordinator.snapshot)
        await coordinator.importGeometry(from: input, format: .obj, unitForUnmarkedData: nil)
        #expect(coordinator.failure?.kind == .importGeometry)
        #expect(coordinator.snapshot?.publicationSequence == initial.publicationSequence)
        #expect(opener.activeProjectURLs.isEmpty)
        let output = directory.appendingPathComponent("existing.stl")
        let original = Data("Keep existing output".utf8)
        try original.write(to: output)
        await coordinator.exportGeometry(to: output, format: .stl, unit: .meter)
        #expect(coordinator.failure?.kind == .exportGeometry)
        #expect(try Data(contentsOf: output) == original)
        #expect(opener.activeProjectURLs.isEmpty)
        #expect(coordinator.operation == nil)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationLaunchPublishesBeforeRegisteringTheSharedWorkspace() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    let registrar = ApplicationAgentSessionRegistrarProbe()
    let coordinator = ApplicationProjectCoordinator(
        workspace: workspace,
        agentRegistrar: registrar
    )

    await coordinator.launch()

    #expect(coordinator.lifecycle == .ready)
    #expect(coordinator.snapshot != nil)
    #expect(registrar.registeredWorkspace === workspace)
    #expect(registrar.registeredPath == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationLaunchIsOwnedByExactlyOneConcurrentCaller() async throws {
    let gate = ApplicationAgentRegistrationGate()
    let registrar = ApplicationAgentSessionRegistrarProbe(registrationGate: gate)
    let coordinator = ApplicationProjectCoordinator(
        workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
        agentRegistrar: registrar
    )

    let first = Task { @MainActor in
        await coordinator.launch()
    }
    await gate.waitUntilRegistrationStarts()
    let second = Task { @MainActor in
        await coordinator.launch()
    }
    await second.value
    await gate.releaseRegistration()
    await first.value

    #expect(coordinator.lifecycle == .ready)
    #expect(registrar.registerCallCount == 1)
    #expect(registrar.unregisterCallCount == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationLaunchFailurePublishesUnavailableWithoutAgentRegistration() async throws {
    let registrar = ApplicationAgentSessionRegistrarProbe()
    let missingURL = URL(
        fileURLWithPath: "/tmp/missing-launch-\(UUID().uuidString).rupa"
    )
    let coordinator = ApplicationProjectCoordinator(
        workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
        agentRegistrar: registrar,
        initialURL: missingURL
    )

    await coordinator.launch()

    guard case .unavailable(let failure) = coordinator.lifecycle else {
        Issue.record("Expected a visible unavailable launch state.")
        return
    }
    #expect(failure.kind == .launch)
    #expect(coordinator.snapshot == nil)
    #expect(registrar.registerCallCount == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationInitialURLLoadsWithoutPublishingAnEmptyProjectFirst() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Initial URL")
        )
        _ = try await sourceWorkspace.evaluate()
        let packageURL = directory.appendingPathComponent("initial-url.rupa")
        _ = try await sourceWorkspace.save(to: packageURL)

        let targetWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
        let registrar = ApplicationAgentSessionRegistrarProbe()
        let coordinator = ApplicationProjectCoordinator(
            workspace: targetWorkspace,
            agentRegistrar: registrar,
            initialURL: packageURL
        )

        await coordinator.launch()

        #expect(coordinator.lifecycle == .ready)
        #expect(coordinator.snapshot?.projectName == "Initial URL")
        #expect(coordinator.snapshot?.publicationSequence == 1)
        #expect(coordinator.currentFileURL == packageURL.standardizedFileURL)
        #expect(registrar.registeredPath == packageURL.standardizedFileURL)
        #expect(registrar.registerCallCount == 1)
        #expect(registrar.updatedPaths.isEmpty)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationLifecycleBuffersColdOpenUntilLoadedRegistrationPrecedesDiscovery() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: .empty(named: "Lifecycle Cold Open")
        )
        _ = try await sourceWorkspace.evaluate()
        let packageURL = directory.appendingPathComponent("lifecycle-cold-open.rupa")
        _ = try await sourceWorkspace.save(to: packageURL)

        let orderingState = ApplicationLifecycleOrderingState()
        let agentController = try applicationProjectAgentCommandController()
        let registrar = ApplicationLifecycleAgentRegistrar(
            controller: agentController,
            state: orderingState
        )
        let targetWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
        let coordinator = ApplicationProjectCoordinator(
            workspace: targetWorkspace,
            agentRegistrar: registrar
        )
        let requestRouter = ApplicationAgentRequestRouter(
            projectHandler: agentController,
            lifecycle: coordinator
        )
        let discoveryStore = ApplicationLifecycleDiscoveryStore(state: orderingState)
        let agentLifecycle = try ApplicationAgentHostLifecycle(
            handler: requestRouter,
            discoveryStore: discoveryStore,
            requestTimeout: .seconds(5),
            shutdownTimeout: .seconds(1)
        )
        let delegate = ApplicationLifecycleDelegate()
        delegate.configure(
            projectCoordinator: coordinator,
            agentLifecycle: agentLifecycle
        )

        delegate.application(NSApplication.shared, open: [packageURL])

        #expect(orderingState.snapshot().registrationCount == 0)
        #expect(orderingState.snapshot().discoveryPublicationCount == 0)
        #expect(coordinator.snapshot == nil)

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await delegate.waitForStartupCompletion()

        let ordering = orderingState.snapshot()
        #expect(delegate.agentFailureMessage == nil)
        #expect(coordinator.lifecycle == .ready)
        #expect(coordinator.currentFileURL == packageURL.standardizedFileURL)
        #expect(coordinator.snapshot?.projectName == "Lifecycle Cold Open")
        #expect(coordinator.snapshot?.publicationSequence == 1)
        #expect(ordering.registrationCount == 1)
        #expect(ordering.registeredPath == packageURL.standardizedFileURL)
        #expect(ordering.registeredPublicationSequence == 1)
        #expect(ordering.discoveryPublicationCount == 1)
        #expect(ordering.registrationCountAtDiscoveryPublication == 1)
        #expect(ordering.pathAtDiscoveryPublication == packageURL.standardizedFileURL)
        #expect(ordering.publicationSequenceAtDiscoveryPublication == 1)
        #expect(agentLifecycle.state == .published)

        guard case .sessions(let sessions) = try await applicationAgentResponse(
            .sessions,
            using: requestRouter
        ),
              let firstSession = sessions.first else {
            Issue.record("Expected the cold-open Agent session to be observable.")
            try await agentLifecycle.stop()
            return
        }
        #expect(sessions.count == 1)
        #expect(firstSession.path == packageURL.standardizedFileURL.path)
        #expect(firstSession.authority.publicationSequence == 1)

        try await agentLifecycle.stop()
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationAgentRouterMutatesAndExplicitlySavesTheRegisteredWorkspace() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Agent API Source")
        )
        _ = try await sourceWorkspace.evaluate()
        let packageURL = directory.appendingPathComponent("agent-api.rupa")
        _ = try await sourceWorkspace.save(to: packageURL)
        let bytesBeforeMutation = try Data(contentsOf: packageURL)

        let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
        let controller = try applicationProjectAgentCommandController()
        let coordinator = ApplicationProjectCoordinator(
            workspace: workspace,
            agentRegistrar: controller,
            initialURL: packageURL
        )
        let router = ApplicationAgentRequestRouter(
            projectHandler: controller,
            lifecycle: coordinator
        )
        await coordinator.launch()

        guard case .sessions(let sessions) = try await applicationAgentResponse(
            .sessions,
            using: router
        ),
              let session = sessions.first else {
            Issue.record("Expected the App-owned workspace session.")
            return
        }
        #expect(sessions.count == 1)
        #expect(coordinator.workspace === workspace)
        #expect(session.path == packageURL.standardizedFileURL.path)

        let staleGeneration = session.authority.documentGeneration
        let mutationResponse = try await applicationAgentResponse(
            .setParameterExpression(
                sessionID: session.id,
                name: "agentLength",
                expression: "25 mm",
                kind: .length,
                defaults: nil,
                expectedGeneration: session.authority.documentGeneration
            ),
            using: router
        )
        guard case .parameterExpression(let mutation) = mutationResponse else {
            Issue.record("Expected the parameter request to reach the registered workspace.")
            return
        }
        #expect(mutation.didMutate)
        let parameters = try #require(workspace.view).document.document.cadDocument.parameters.parameters
        #expect(parameters.values.contains { $0.name == "agentLength" })
        #expect(try Data(contentsOf: packageURL) == bytesBeforeMutation)

        guard case .failure(let wrongSession) = try await applicationAgentResponse(
            .save(
                sessionID: UUID(),
                expectedGeneration: mutation.generation
            ),
            using: router
        ) else {
            Issue.record("Expected a wrong-session failure.")
            return
        }
        #expect(wrongSession.code == .sessionNotFound)

        guard case .failure(let missingGeneration) = try await applicationAgentResponse(
            .save(sessionID: session.id, expectedGeneration: nil),
            using: router
        ) else {
            Issue.record("Expected a missing-generation failure.")
            return
        }
        #expect(missingGeneration.code == .commandInvalid)

        guard case .failure(let staleGenerationFailure) = try await applicationAgentResponse(
            .save(
                sessionID: session.id,
                expectedGeneration: staleGeneration
            ),
            using: router
        ) else {
            Issue.record("Expected a stale-generation failure.")
            return
        }
        #expect(staleGenerationFailure.code == .documentGenerationMismatch)
        #expect(try Data(contentsOf: packageURL) == bytesBeforeMutation)

        guard case .save(let saveResult) = try await applicationAgentResponse(
            .save(
                sessionID: session.id,
                expectedGeneration: mutation.generation
            ),
            using: router
        ) else {
            Issue.record("Expected explicit Agent save success.")
            return
        }
        #expect(saveResult.path == packageURL.standardizedFileURL.path)
        #expect(saveResult.generation == mutation.generation)
        #expect(saveResult.dirty == false)
        #expect(coordinator.currentFileURL == packageURL.standardizedFileURL)
        #expect(workspace.view?.isDirty == false)
        #expect(try Data(contentsOf: packageURL) != bytesBeforeMutation)

        let reloadedWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
        let reloaded = try await reloadedWorkspace.load(from: packageURL)
        #expect(reloaded.document.document.cadDocument.parameters.parameters == parameters)

        guard case .failure(let directSaveFailure) = try await applicationAgentResponse(
            .save(
                sessionID: session.id,
                expectedGeneration: mutation.generation
            ),
            using: controller
        ) else {
            Issue.record("Expected direct runtime save to remain unsupported.")
            return
        }
        #expect(directSaveFailure.code == .commandUnsupported)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationAgentRouterRejectsUntitledSaveWithoutOpeningUI() async throws {
    let controller = try applicationProjectAgentCommandController()
    let coordinator = ApplicationProjectCoordinator(
        workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
        agentRegistrar: controller
    )
    let router = ApplicationAgentRequestRouter(
        projectHandler: controller,
        lifecycle: coordinator
    )
    await coordinator.launch()
    guard case .sessions(let sessions) = try await applicationAgentResponse(
        .sessions,
        using: router
    ),
          let session = sessions.first else {
        Issue.record("Expected the App-owned untitled session.")
        return
    }

    guard case .failure(let failure) = try await applicationAgentResponse(
        .save(
            sessionID: session.id,
            expectedGeneration: session.authority.documentGeneration
        ),
        using: router
    ) else {
        Issue.record("Expected current-URL save to reject an untitled project.")
        return
    }

    #expect(failure.code == .documentSaveFailed)
    #expect(coordinator.currentFileURL == nil)
    #expect(coordinator.isBusy == false)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationAgentSaveReturnsCommittedNoRetryReceiptAfterViewFailure() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Committed Agent Save")
        )
        _ = try await sourceWorkspace.evaluate()
        let packageURL = directory.appendingPathComponent("committed-agent-save.rupa")
        _ = try await sourceWorkspace.save(to: packageURL)

        let project = try applicationProjectController(
            document: .empty(named: "Before Agent Load")
        )
        let workspace = ProjectWorkspace(
            project: project,
            viewBuilder: ApplicationNthFailingProjectViewSnapshotBuilder(
                failingBuildNumber: 2
            )
        )
        let controller = try applicationProjectAgentCommandController()
        let coordinator = ApplicationProjectCoordinator(
            workspace: workspace,
            agentRegistrar: controller,
            initialURL: packageURL
        )
        let router = ApplicationAgentRequestRouter(
            projectHandler: controller,
            lifecycle: coordinator
        )
        await coordinator.launch()
        guard case .sessions(let sessions) = try await applicationAgentResponse(
            .sessions,
            using: router
        ),
              let session = sessions.first else {
            Issue.record("Expected the committed-save App session.")
            return
        }

        let response = try await applicationAgentResponse(
            .save(
                sessionID: session.id,
                expectedGeneration: session.authority.documentGeneration
            ),
            using: router
        )
        guard case .committedMutation(let outcome) = response else {
            Issue.record("Expected a committed save receipt.")
            return
        }

        let recovered = try #require(coordinator.snapshot)
        #expect(outcome.stage == .viewProjection)
        #expect(outcome.mutation == .save)
        #expect(outcome.requestMethod == "document.save")
        #expect(outcome.retryDisposition == .mustNotRetry)
        #expect(outcome.projectID == recovered.projectID)
        #expect(outcome.documentGeneration == recovered.documentGeneration)
        #expect(outcome.transactionRevision == recovered.transactionRevision)
        #expect(outcome.publicationSequence == recovered.publicationSequence)
        #expect(outcome.workspaceRevision == recovered.workspaceState.revision)
        #expect(recovered.isDirty == false)
        #expect(FileManager.default.fileExists(atPath: packageURL.path))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationCurrentProjectAccessSurvivesSamePathSaveAndReleasesOnNewProject() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Current Project")
        )
        _ = try await sourceWorkspace.evaluate()
        let packageURL = directory.appendingPathComponent("current-project.rupa")
        _ = try await sourceWorkspace.save(to: packageURL)

        let accessOpener = ApplicationSecurityScopedAccessOpenerProbe()
        let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
        let coordinator = ApplicationProjectCoordinator(
            workspace: workspace,
            agentRegistrar: ApplicationAgentSessionRegistrarProbe(),
            securityScopedAccessOpener: accessOpener,
            initialURL: packageURL
        )
        await coordinator.launch()
        let initial = try #require(coordinator.snapshot)

        let renamed = try await workspace.commit(
            ProjectSourceTransaction(
                name: "appTest.same-path-access",
                commands: [.renameDocument(name: "Same Path Save")],
                expectedProjectID: initial.projectID,
                expectedTransactionRevision: initial.transactionRevision,
                expectedPublicationSequence: initial.publicationSequence
            )
        )
        await coordinator.save(to: packageURL)

        #expect(coordinator.failure == nil)
        #expect(coordinator.currentFileURL == packageURL.standardizedFileURL)
        #expect(coordinator.snapshot?.documentGeneration == renamed.documentGeneration)
        #expect(accessOpener.openedProjectURLs == [packageURL.standardizedFileURL])
        #expect(accessOpener.activeProjectURLs == [packageURL.standardizedFileURL])

        await coordinator.newProject()
        #expect(coordinator.currentFileURL == nil)
        #expect(accessOpener.activeProjectURLs.isEmpty)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationSuccessfulSaveAsTransfersSecurityScopedAccessOnlyAfterCommit() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Save As Access")
        )
        _ = try await sourceWorkspace.evaluate()
        let inputURL = directory.appendingPathComponent("save-as-input.rupa")
        _ = try await sourceWorkspace.save(to: inputURL)

        let accessOpener = ApplicationSecurityScopedAccessOpenerProbe()
        let coordinator = ApplicationProjectCoordinator(
            workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
            agentRegistrar: ApplicationAgentSessionRegistrarProbe(),
            securityScopedAccessOpener: accessOpener,
            initialURL: inputURL
        )
        await coordinator.launch()
        let outputURL = directory.appendingPathComponent("save-as-output.rupa")

        await coordinator.save(to: outputURL)

        #expect(coordinator.failure == nil)
        #expect(coordinator.currentFileURL == outputURL.standardizedFileURL)
        #expect(
            accessOpener.activeProjectURLs
                == [outputURL.standardizedFileURL]
        )
        await coordinator.newProject()
        #expect(accessOpener.activeProjectURLs.isEmpty)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationSaveAsFailureReleasesCandidateAndRetainsCurrentFileAccess() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Retained Project")
        )
        _ = try await sourceWorkspace.evaluate()
        let inputURL = directory.appendingPathComponent("input.rupa")
        _ = try await sourceWorkspace.save(to: inputURL)

        let workspace = ProjectWorkspace(
            project: try applicationProjectController(
                document: .empty(named: "Before Load"),
                packageWriter: ApplicationFailingProjectPackageWriter()
            )
        )
        let accessOpener = ApplicationSecurityScopedAccessOpenerProbe()
        let coordinator = ApplicationProjectCoordinator(
            workspace: workspace,
            agentRegistrar: ApplicationAgentSessionRegistrarProbe(),
            securityScopedAccessOpener: accessOpener,
            initialURL: inputURL
        )
        await coordinator.launch()
        let outputURL = directory.appendingPathComponent("failed-output.rupa")

        await coordinator.save(to: outputURL)

        #expect(coordinator.failure?.kind == .save)
        #expect(coordinator.failure?.didCommit == false)
        #expect(coordinator.currentFileURL == inputURL.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: outputURL.path) == false)
        #expect(accessOpener.activeProjectURLs == [inputURL.standardizedFileURL])

        await coordinator.newProject()
        #expect(accessOpener.activeProjectURLs.isEmpty)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationLaunchConsumesAnOpenURLThatArrivesDuringAgentRegistration() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Late Launch URL")
        )
        _ = try await sourceWorkspace.evaluate()
        let packageURL = directory.appendingPathComponent("late-launch-url.rupa")
        _ = try await sourceWorkspace.save(to: packageURL)

        let gate = ApplicationAgentRegistrationGate()
        let registrar = ApplicationAgentSessionRegistrarProbe(registrationGate: gate)
        let coordinator = ApplicationProjectCoordinator(
            workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
            agentRegistrar: registrar
        )
        let launch = Task { @MainActor in
            await coordinator.launch()
        }
        await gate.waitUntilRegistrationStarts()

        coordinator.receiveOpenURL(packageURL)
        await gate.releaseRegistration()
        await launch.value

        #expect(coordinator.lifecycle == .ready)
        #expect(coordinator.snapshot?.projectName == "Late Launch URL")
        #expect(coordinator.currentFileURL == packageURL.standardizedFileURL)
        #expect(registrar.updatedPaths.last == packageURL.standardizedFileURL)
    }
}

@MainActor
@Test(.timeLimit(.minutes(3)))
func applicationRouteRoundTripsCADMeshAndMixedProjects() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let fixtures: [(String, DesignDocument)] = [
            ("cad", try applicationCADOnlyDocument(named: "CAD Project")),
            ("mesh", try applicationMeshOnlyDocument(named: "Mesh Project")),
            ("mixed", try applicationMixedDocument(named: "Mixed Project")),
        ]

        for (kind, document) in fixtures {
            let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(document: document)
            let registrar = ApplicationAgentSessionRegistrarProbe()
            let coordinator = ApplicationProjectCoordinator(
                workspace: workspace,
                agentRegistrar: registrar
            )
            await coordinator.launch()
            let initial = try #require(coordinator.snapshot)
            let item = try #require(initial.viewport.items.first)
            let sceneNodeID = try #require(initial.sceneNodeID(for: item.id))

            let navigated = try await workspace.applyWorkspace(
                .setDisplayUnit(.millimeter)
            )
            #expect(navigated.workspaceState.displayUnit == .millimeter)

            let selected = try await workspace.applySelection(
                .replace(SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: sceneNodeID)]))
            )
            #expect(selected.selection.selectedTargets.count == 1)

            let renamedName = "\(kind)-renamed"
            let renamed = try await workspace.commit(
                ProjectSourceTransaction(
                    name: "appTest.rename",
                    commands: [.renameDocument(name: renamedName)],
                    expectedProjectID: selected.projectID,
                    expectedTransactionRevision: selected.transactionRevision,
                    expectedPublicationSequence: selected.publicationSequence
                )
            )
            #expect(renamed.projectName == renamedName)

            await coordinator.undo()
            #expect(coordinator.failure == nil)
            #expect(coordinator.snapshot?.projectName == initial.projectName)
            await coordinator.redo()
            #expect(coordinator.failure == nil)
            #expect(coordinator.snapshot?.projectName == renamedName)

            let packageURL = directory.appendingPathComponent("\(kind).rupa")
            await coordinator.save(to: packageURL)
            #expect(coordinator.failure == nil)
            #expect(coordinator.currentFileURL == packageURL.standardizedFileURL)
            #expect(coordinator.isDirty == false)

            await coordinator.newProject()
            #expect(coordinator.failure == nil)
            #expect(coordinator.currentFileURL == nil)
            #expect(coordinator.snapshot?.projectName == "Untitled")

            await coordinator.load(from: packageURL)
            let loaded = try #require(coordinator.snapshot)
            #expect(coordinator.failure == nil)
            #expect(loaded.projectName == renamedName)
            #expect(loaded.viewport.items.count == initial.viewport.items.count)
            #expect(registrar.updatedPaths.last == packageURL.standardizedFileURL)
            try expectApplicationAuthoredMeshStorageIsShared(
                loaded,
                requiresAuthoredMesh: kind != "cad"
            )
        }
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationRejectsOpenWhileDirtyWithoutChangingCurrentProject() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Retained Project")
        )
        let registrar = ApplicationAgentSessionRegistrarProbe()
        let accessOpener = ApplicationSecurityScopedAccessOpenerProbe()
        let coordinator = ApplicationProjectCoordinator(
            workspace: workspace,
            agentRegistrar: registrar,
            securityScopedAccessOpener: accessOpener
        )
        await coordinator.launch()
        let originalURL = directory.appendingPathComponent("retained.rupa")
        await coordinator.save(to: originalURL)
        let clean = try #require(coordinator.snapshot)
        let retained = try await workspace.commit(
            ProjectSourceTransaction(
                name: "appTest.dirty",
                commands: [.renameDocument(name: "Dirty")],
                expectedProjectID: clean.projectID,
                expectedTransactionRevision: clean.transactionRevision,
                expectedPublicationSequence: clean.publicationSequence
            )
        )
        let requestedURL = directory.appendingPathComponent("requested.rupa")
        let retainedAgentPaths = registrar.updatedPaths
        let retainedRegistrationID = registrar.registeredID

        await coordinator.load(from: requestedURL)

        #expect(coordinator.failure?.kind == .unsavedChanges)
        #expect(coordinator.failure?.message.contains(requestedURL.path) == true)
        #expect(coordinator.currentFileURL == originalURL.standardizedFileURL)
        #expect(accessOpener.openedProjectURLs == [originalURL.standardizedFileURL])
        #expect(accessOpener.activeProjectURLs == [originalURL.standardizedFileURL])
        #expect(registrar.updatedPaths == retainedAgentPaths)
        #expect(registrar.registeredID == retainedRegistrationID)
        try expectApplicationPublication(coordinator.snapshot, unchangedFrom: retained)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationReopeningCurrentCanonicalProjectWhileDirtyIsAnIdempotentNoOp() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Retained Project")
        )
        let registrar = ApplicationAgentSessionRegistrarProbe()
        let accessOpener = ApplicationSecurityScopedAccessOpenerProbe()
        let coordinator = ApplicationProjectCoordinator(
            workspace: workspace,
            agentRegistrar: registrar,
            securityScopedAccessOpener: accessOpener
        )
        await coordinator.launch()
        let originalURL = directory.appendingPathComponent("retained.rupa")
        await coordinator.save(to: originalURL)
        let clean = try #require(coordinator.snapshot)
        let dirty = try await workspace.commit(
            ProjectSourceTransaction(
                name: "appTest.reopen-current-dirty",
                commands: [.renameDocument(name: "Dirty Retained Project")],
                expectedProjectID: clean.projectID,
                expectedTransactionRevision: clean.transactionRevision,
                expectedPublicationSequence: clean.publicationSequence
            )
        )
        let retainedPaths = registrar.updatedPaths
        let retainedRegistrationID = registrar.registeredID
        let retainedOpenedURLs = accessOpener.openedProjectURLs
        let retainedPublication = dirty

        await coordinator.load(from: originalURL)

        #expect(coordinator.failure == nil)
        #expect(coordinator.currentFileURL == originalURL.standardizedFileURL)
        #expect(coordinator.isDirty)
        try expectApplicationPublication(coordinator.snapshot, unchangedFrom: retainedPublication)
        #expect(registrar.updatedPaths == retainedPaths)
        #expect(registrar.registeredID == retainedRegistrationID)
        #expect(accessOpener.openedProjectURLs == retainedOpenedURLs)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationRejectsLegacyProjectFormatWithoutChangingPublishedProject() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Current Project")
        )
        let registrar = ApplicationAgentSessionRegistrarProbe()
        let accessOpener = ApplicationSecurityScopedAccessOpenerProbe()
        let coordinator = ApplicationProjectCoordinator(
            workspace: workspace,
            agentRegistrar: registrar,
            securityScopedAccessOpener: accessOpener
        )
        await coordinator.launch()
        let originalURL = directory.appendingPathComponent("current.rupa")
        await coordinator.save(to: originalURL)
        let retained = try #require(coordinator.snapshot)
        let retainedAgentPaths = registrar.updatedPaths
        let retainedRegistrationID = registrar.registeredID
        let legacyURL = directory.appendingPathComponent("legacy.swcad")

        await coordinator.load(from: legacyURL)

        #expect(coordinator.failure?.kind == .unsupportedProjectFormat)
        #expect(coordinator.failure?.message.contains(legacyURL.path) == true)
        #expect(coordinator.currentFileURL == originalURL.standardizedFileURL)
        #expect(accessOpener.openedProjectURLs == [originalURL.standardizedFileURL])
        #expect(accessOpener.activeProjectURLs == [originalURL.standardizedFileURL])
        #expect(registrar.updatedPaths == retainedAgentPaths)
        #expect(registrar.registeredID == retainedRegistrationID)
        try expectApplicationPublication(coordinator.snapshot, unchangedFrom: retained)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationRejectsLegacyInitialURLBeforeRegistration() async throws {
    let registrar = ApplicationAgentSessionRegistrarProbe()
    let accessOpener = ApplicationSecurityScopedAccessOpenerProbe()
    let legacyURL = URL(
        fileURLWithPath: "/tmp/legacy-launch-\(UUID().uuidString).swcad"
    )
    let coordinator = ApplicationProjectCoordinator(
        workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
        agentRegistrar: registrar,
        securityScopedAccessOpener: accessOpener,
        initialURL: legacyURL
    )

    await coordinator.launch()

    guard case .unavailable(let failure) = coordinator.lifecycle else {
        Issue.record("Expected an unsupported initial project to remain unavailable.")
        return
    }
    #expect(failure.kind == .unsupportedProjectFormat)
    #expect(failure.message.contains(legacyURL.path))
    #expect(coordinator.snapshot == nil)
    #expect(coordinator.currentFileURL == nil)
    #expect(registrar.registerCallCount == 0)
    #expect(accessOpener.openedProjectURLs.isEmpty)
    #expect(accessOpener.activeProjectURLs.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationLateUnsupportedURLPreservesThePublishedLaunchWorkspace() async throws {
    let gate = ApplicationAgentRegistrationGate()
    let registrar = ApplicationAgentSessionRegistrarProbe(registrationGate: gate)
    let accessOpener = ApplicationSecurityScopedAccessOpenerProbe()
    let coordinator = ApplicationProjectCoordinator(
        workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Visible Launch Project")
        ),
        agentRegistrar: registrar,
        securityScopedAccessOpener: accessOpener
    )
    let launch = Task { @MainActor in
        await coordinator.launch()
    }
    await gate.waitUntilRegistrationStarts()
    let retained = try #require(coordinator.snapshot)
    let legacyURL = URL(
        fileURLWithPath: "/tmp/late-legacy-\(UUID().uuidString).swcad"
    )

    coordinator.receiveOpenURL(legacyURL)
    await gate.releaseRegistration()
    await launch.value

    #expect(coordinator.lifecycle == .ready)
    #expect(coordinator.failure?.kind == .unsupportedProjectFormat)
    #expect(coordinator.failure?.message.contains(legacyURL.path) == true)
    #expect(coordinator.currentFileURL == nil)
    #expect(registrar.registerCallCount == 1)
    #expect(registrar.unregisterCallCount == 0)
    #expect(registrar.updatePathAttemptCount == 0)
    #expect(accessOpener.openedProjectURLs.isEmpty)
    #expect(accessOpener.activeProjectURLs.isEmpty)
    try expectApplicationPublication(coordinator.snapshot, unchangedFrom: retained)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationInvalidRupaPackagePreservesPublishedProject() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Valid Current Project")
        )
        let registrar = ApplicationAgentSessionRegistrarProbe()
        let accessOpener = ApplicationSecurityScopedAccessOpenerProbe()
        let coordinator = ApplicationProjectCoordinator(
            workspace: workspace,
            agentRegistrar: registrar,
            securityScopedAccessOpener: accessOpener
        )
        await coordinator.launch()
        let originalURL = directory.appendingPathComponent("valid-current.rupa")
        await coordinator.save(to: originalURL)
        let retained = try #require(coordinator.snapshot)
        let retainedAgentPaths = registrar.updatedPaths
        let invalidURL = directory.appendingPathComponent("invalid.rupa")
        try Data("not a project package".utf8).write(to: invalidURL)

        await coordinator.load(from: invalidURL)

        #expect(coordinator.failure?.kind == .load)
        #expect(coordinator.failure?.message.contains(invalidURL.path) == true)
        #expect(coordinator.currentFileURL == originalURL.standardizedFileURL)
        #expect(
            accessOpener.openedProjectURLs
                == [originalURL.standardizedFileURL, invalidURL.standardizedFileURL]
        )
        #expect(accessOpener.activeProjectURLs == [originalURL.standardizedFileURL])
        #expect(registrar.updatedPaths == retainedAgentPaths)
        #expect(registrar.updatePathAttemptCount == retainedAgentPaths.count)
        try expectApplicationPublication(coordinator.snapshot, unchangedFrom: retained)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationRejectsNewProjectWhileDirty() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    let coordinator = ApplicationProjectCoordinator(
        workspace: workspace,
        agentRegistrar: ApplicationAgentSessionRegistrarProbe()
    )
    await coordinator.launch()
    let initial = try #require(coordinator.snapshot)
    _ = try await workspace.commit(
        ProjectSourceTransaction(
            name: "appTest.dirty-new",
            commands: [.renameDocument(name: "Retained Dirty Project")],
            expectedProjectID: initial.projectID,
            expectedTransactionRevision: initial.transactionRevision,
            expectedPublicationSequence: initial.publicationSequence
        )
    )

    await coordinator.newProject()

    #expect(coordinator.failure?.kind == .unsavedChanges)
    #expect(coordinator.snapshot?.projectName == "Retained Dirty Project")
    #expect(coordinator.snapshot?.projectID == initial.projectID)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationSameProjectIDReloadChangesPresentationLifetime() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let original = try applicationMeshOnlyDocument(named: "Before Same-ID Reload")
        let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: original
        )
        let sourceInitial = try await sourceWorkspace.evaluate()
        _ = try await sourceWorkspace.commit(
            ProjectSourceTransaction(
                name: "appTest.prepare-same-id-reload",
                commands: [.renameDocument(name: "After Same-ID Reload")],
                expectedProjectID: sourceInitial.projectID,
                expectedTransactionRevision: sourceInitial.transactionRevision,
                expectedPublicationSequence: sourceInitial.publicationSequence
            )
        )
        let packageURL = directory.appendingPathComponent("same-id.rupa")
        _ = try await sourceWorkspace.save(to: packageURL)

        let coordinator = ApplicationProjectCoordinator(
            workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(document: original),
            agentRegistrar: ApplicationAgentSessionRegistrarProbe()
        )
        await coordinator.launch()
        let visibleBeforeLoad = try #require(coordinator.snapshot)

        await coordinator.load(from: packageURL)
        let loaded = try #require(coordinator.snapshot)

        #expect(coordinator.failure == nil)
        #expect(loaded.projectID == visibleBeforeLoad.projectID)
        #expect(loaded.projectName == "After Same-ID Reload")
        #expect(loaded.documentLifetimeID != visibleBeforeLoad.documentLifetimeID)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationPrecommitLoadFailureRetainsPublishedProjectAndAgentPath() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: try applicationMeshOnlyDocument(named: "Retained Load")
    )
    let registrar = ApplicationAgentSessionRegistrarProbe()
    let coordinator = ApplicationProjectCoordinator(
        workspace: workspace,
        agentRegistrar: registrar
    )
    await coordinator.launch()
    let retained = try #require(coordinator.snapshot)
    let missingURL = URL(fileURLWithPath: "/tmp/missing-load-\(UUID().uuidString).rupa")

    await coordinator.load(from: missingURL)

    #expect(coordinator.failure?.kind == .load)
    #expect(coordinator.failure?.didCommit == false)
    #expect(coordinator.snapshot?.publicationSequence == retained.publicationSequence)
    #expect(coordinator.snapshot?.documentLifetimeID == retained.documentLifetimeID)
    #expect(coordinator.currentFileURL == nil)
    #expect(registrar.updatePathAttemptCount == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationPrecommitSaveFailureRetainsDirtyProjectAndFileAccess() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let controller = try applicationProjectController(
            document: .empty(named: "Before Failed Save"),
            packageWriter: ApplicationFailingProjectPackageWriter()
        )
        let workspace = ProjectWorkspace(project: controller)
        let registrar = ApplicationAgentSessionRegistrarProbe()
        let coordinator = ApplicationProjectCoordinator(
            workspace: workspace,
            agentRegistrar: registrar
        )
        await coordinator.launch()
        let initial = try #require(coordinator.snapshot)
        let dirty = try await workspace.commit(
            ProjectSourceTransaction(
                name: "appTest.dirty-before-save-failure",
                commands: [.renameDocument(name: "Retained Dirty Save")],
                expectedProjectID: initial.projectID,
                expectedTransactionRevision: initial.transactionRevision,
                expectedPublicationSequence: initial.publicationSequence
            )
        )
        let packageURL = directory.appendingPathComponent("failed-save.rupa")

        await coordinator.save(to: packageURL)

        #expect(coordinator.failure?.kind == .save)
        #expect(coordinator.failure?.didCommit == false)
        #expect(coordinator.snapshot?.publicationSequence == dirty.publicationSequence)
        #expect(coordinator.snapshot?.projectName == "Retained Dirty Save")
        #expect(coordinator.isDirty)
        #expect(coordinator.currentFileURL == nil)
        #expect(registrar.updatePathAttemptCount == 0)
        #expect(FileManager.default.fileExists(atPath: packageURL.path) == false)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationCancelledLoadDoesNotPublishOrRebindAgentPath() async throws {
    let loadURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "cancelled-load-\(UUID().uuidString).rupa"
    )
    try Data().write(to: loadURL)
    defer {
        removeApplicationProjectTestFile(loadURL)
    }
    let loadedController = try applicationProjectController(
        document: try applicationMeshOnlyDocument(named: "Cancelled Load")
    )
    let loadedPackage = await loadedController.currentPackage()
    let gate = ApplicationBlockingOperationGate()
    let controller = try applicationProjectController(
        document: try applicationMeshOnlyDocument(named: "Retained Cancellation"),
        packageReader: ApplicationBlockingProjectPackageReader(
            package: loadedPackage,
            gate: gate
        )
    )
    let workspace = ProjectWorkspace(project: controller)
    let registrar = ApplicationAgentSessionRegistrarProbe()
    let accessOpener = ApplicationSecurityScopedAccessOpenerProbe()
    let coordinator = ApplicationProjectCoordinator(
        workspace: workspace,
        agentRegistrar: registrar,
        securityScopedAccessOpener: accessOpener
    )
    await coordinator.launch()
    let retained = try #require(coordinator.snapshot)

    coordinator.startLoad(from: loadURL)
    while !gate.didStart {
        await Task.yield()
    }
    #expect(coordinator.canCancelOperation)
    coordinator.cancelCurrentOperation()
    gate.release()
    while coordinator.isBusy {
        await Task.yield()
    }

    #expect(coordinator.failure?.kind == .load)
    #expect(coordinator.failure?.didCommit == false)
    #expect(coordinator.snapshot?.publicationSequence == retained.publicationSequence)
    #expect(coordinator.snapshot?.projectName == "Retained Cancellation")
    #expect(coordinator.currentFileURL == nil)
    #expect(registrar.updatePathAttemptCount == 0)
    #expect(accessOpener.activeProjectURLs.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationStaleLoadCannotReplaceANewerWorkspacePublication() async throws {
    let loadURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "stale-load-\(UUID().uuidString).rupa"
    )
    try Data().write(to: loadURL)
    defer { removeApplicationProjectTestFile(loadURL) }
    let loadedController = try applicationProjectController(
        document: try applicationMeshOnlyDocument(named: "Stale Load")
    )
    let loadedPackage = await loadedController.currentPackage()
    let gate = ApplicationBlockingOperationGate()
    let controller = try applicationProjectController(
        document: try applicationMeshOnlyDocument(named: "Before Concurrent Edit"),
        packageReader: ApplicationBlockingProjectPackageReader(
            package: loadedPackage,
            gate: gate
        )
    )
    let workspace = ProjectWorkspace(project: controller)
    let coordinator = ApplicationProjectCoordinator(
        workspace: workspace,
        agentRegistrar: ApplicationAgentSessionRegistrarProbe()
    )
    await coordinator.launch()
    let initial = try #require(coordinator.snapshot)

    let load = Task { @MainActor in
        await coordinator.load(from: loadURL)
    }
    while !gate.didStart {
        await Task.yield()
    }
    let newer = try await workspace.commit(
        ProjectSourceTransaction(
            name: "appTest.concurrent-newer-publication",
            commands: [.renameDocument(name: "Newer Publication")],
            expectedProjectID: initial.projectID,
            expectedTransactionRevision: initial.transactionRevision,
            expectedPublicationSequence: initial.publicationSequence
        )
    )
    gate.release()
    await load.value

    #expect(coordinator.failure?.kind == .load)
    #expect(coordinator.failure?.didCommit == false)
    #expect(coordinator.snapshot?.publicationSequence == newer.publicationSequence)
    #expect(coordinator.snapshot?.projectName == "Newer Publication")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationRecoversACommittedLoadWithItsNewProjectIdentity() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Recovered Load")
        )
        _ = try await sourceWorkspace.evaluate()
        let packageURL = directory.appendingPathComponent("recovered-load.rupa")
        _ = try await sourceWorkspace.save(to: packageURL)

        let controller = try applicationProjectController(
            document: try applicationMeshOnlyDocument(named: "Previous Project")
        )
        let workspace = ProjectWorkspace(
            project: controller,
            viewBuilder: ApplicationNthFailingProjectViewSnapshotBuilder(
                failingBuildNumber: 2
            )
        )
        let registrar = ApplicationAgentSessionRegistrarProbe()
        let coordinator = ApplicationProjectCoordinator(
            workspace: workspace,
            agentRegistrar: registrar
        )
        await coordinator.launch()
        let initial = try #require(coordinator.snapshot)

        await coordinator.load(from: packageURL)

        let recovered = try #require(coordinator.snapshot)
        #expect(coordinator.lifecycle == .ready)
        #expect(coordinator.failure?.kind == .load)
        #expect(coordinator.failure?.didCommit == true)
        #expect(recovered.projectName == "Recovered Load")
        #expect(recovered.projectID != initial.projectID)
        #expect(recovered.documentLifetimeID != initial.documentLifetimeID)
        #expect(coordinator.currentFileURL == packageURL.standardizedFileURL)
        #expect(registrar.updatedPaths.last == packageURL.standardizedFileURL)
        #expect(registrar.registeredWorkspace === workspace)
        #expect(registrar.registeredWorkspace?.view?.projectID == recovered.projectID)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationRecoversACommittedSaveViewWithoutReplayingTheSave() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let controller = try applicationProjectController(
            document: try applicationMeshOnlyDocument(named: "Recovered Save")
        )
        let workspace = ProjectWorkspace(
            project: controller,
            viewBuilder: ApplicationNthFailingProjectViewSnapshotBuilder(
                failingBuildNumber: 2
            )
        )
        let registrar = ApplicationAgentSessionRegistrarProbe()
        let coordinator = ApplicationProjectCoordinator(
            workspace: workspace,
            agentRegistrar: registrar
        )
        await coordinator.launch()
        let initial = try #require(coordinator.snapshot)
        let packageURL = directory.appendingPathComponent("recovered-save.rupa")

        await coordinator.save(to: packageURL)

        #expect(coordinator.failure?.kind == .save)
        #expect(coordinator.failure?.didCommit == true)
        #expect(coordinator.snapshot?.publicationSequence == initial.publicationSequence + 1)
        #expect(coordinator.snapshot?.isDirty == false)
        #expect(coordinator.currentFileURL == packageURL.standardizedFileURL)
        #expect(registrar.updatedPaths.last == packageURL.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: packageURL.path))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationRecoversACommittedUndoWithoutReplayingHistory() async throws {
    let controller = try applicationProjectController(
        document: try applicationMeshOnlyDocument(named: "History Origin")
    )
    let workspace = ProjectWorkspace(
        project: controller,
        viewBuilder: ApplicationNthFailingProjectViewSnapshotBuilder(
            failingBuildNumber: 3
        )
    )
    let coordinator = ApplicationProjectCoordinator(
        workspace: workspace,
        agentRegistrar: ApplicationAgentSessionRegistrarProbe()
    )
    await coordinator.launch()
    let initial = try #require(coordinator.snapshot)
    let renamed = try await workspace.commit(
        ProjectSourceTransaction(
            name: "appTest.history-recovery",
            commands: [.renameDocument(name: "History Edit")],
            expectedProjectID: initial.projectID,
            expectedTransactionRevision: initial.transactionRevision,
            expectedPublicationSequence: initial.publicationSequence
        )
    )
    #expect(renamed.projectName == "History Edit")

    await coordinator.undo()

    #expect(coordinator.lifecycle == .ready)
    #expect(coordinator.failure?.kind == .undo)
    #expect(coordinator.failure?.didCommit == true)
    #expect(coordinator.snapshot?.projectName == "History Origin")
    #expect(coordinator.snapshot?.canRedo == true)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationReportsAgentPathRebindFailureAfterACommittedSave() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let registrar = ApplicationAgentSessionRegistrarProbe(
            updatePathFailure: ApplicationProjectFailure(
                kind: .agentRegistration,
                message: "Fixture path rebind failure."
            )
        )
        let coordinator = ApplicationProjectCoordinator(
            workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
            agentRegistrar: registrar
        )
        await coordinator.launch()
        let packageURL = directory.appendingPathComponent("agent-rebind-failure.rupa")

        await coordinator.save(to: packageURL)

        let committed = try #require(coordinator.snapshot)
        guard case .unavailable(let lifecycleFailure) = coordinator.lifecycle,
              let outcome = lifecycleFailure.committedMutation else {
            Issue.record("Expected save path rebind failure to terminate App access with a receipt.")
            return
        }
        #expect(lifecycleFailure.kind == .agentRegistration)
        #expect(lifecycleFailure.didCommit)
        #expect(coordinator.failure == lifecycleFailure)
        #expect(outcome.mutation == .save)
        #expect(outcome.requestMethod == "project.save")
        #expect(outcome.retryDisposition == .mustNotRetry)
        #expect(outcome.projectID == committed.projectID)
        #expect(outcome.documentGeneration == committed.documentGeneration)
        #expect(outcome.transactionRevision == committed.transactionRevision)
        #expect(outcome.publicationSequence == committed.publicationSequence)
        #expect(outcome.workspaceRevision == committed.workspaceState.revision)
        #expect(committed.isDirty == false)
        #expect(coordinator.currentFileURL == packageURL.standardizedFileURL)
        #expect(registrar.updatePathAttemptCount == 1)
        #expect(registrar.unregisterCallCount == 1)
        #expect(FileManager.default.fileExists(atPath: packageURL.path))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationLoadPathRebindFailureIsTerminalWithExactCommittedReceipt() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: try applicationMeshOnlyDocument(named: "Loaded Before Path Failure")
        )
        _ = try await sourceWorkspace.evaluate()
        let packageURL = directory.appendingPathComponent("load-path-failure.rupa")
        _ = try await sourceWorkspace.save(to: packageURL)
        let registrar = ApplicationAgentSessionRegistrarProbe(
            updatePathFailure: ApplicationProjectFailure(
                kind: .agentRegistration,
                message: "Fixture load path failure."
            )
        )
        let coordinator = ApplicationProjectCoordinator(
            workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
            agentRegistrar: registrar
        )
        await coordinator.launch()

        await coordinator.load(from: packageURL)

        let committed = try #require(coordinator.snapshot)
        guard case .unavailable(let lifecycleFailure) = coordinator.lifecycle,
              let outcome = lifecycleFailure.committedMutation else {
            Issue.record("Expected load path rebind failure to terminate App access with a receipt.")
            return
        }
        #expect(lifecycleFailure.kind == .agentRegistration)
        #expect(lifecycleFailure.didCommit)
        #expect(outcome.mutation == .source)
        #expect(outcome.requestMethod == "project.open")
        #expect(outcome.retryDisposition == .mustNotRetry)
        #expect(outcome.projectID == committed.projectID)
        #expect(outcome.documentGeneration == committed.documentGeneration)
        #expect(outcome.transactionRevision == committed.transactionRevision)
        #expect(outcome.publicationSequence == committed.publicationSequence)
        #expect(outcome.workspaceRevision == committed.workspaceState.revision)
        #expect(committed.projectName == "Loaded Before Path Failure")
        #expect(coordinator.currentFileURL == packageURL.standardizedFileURL)
        #expect(registrar.updatePathAttemptCount == 1)
        #expect(registrar.unregisterCallCount == 1)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationNewProjectPathClearFailureIsTerminalWithExactCommittedReceipt() async throws {
    let registrar = ApplicationAgentSessionRegistrarProbe(
        updatePathFailure: ApplicationProjectFailure(
            kind: .agentRegistration,
            message: "Fixture new-project path failure."
        )
    )
    let coordinator = ApplicationProjectCoordinator(
        workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
        agentRegistrar: registrar
    )
    await coordinator.launch()

    await coordinator.newProject(named: "Committed New Project")

    let committed = try #require(coordinator.snapshot)
    guard case .unavailable(let lifecycleFailure) = coordinator.lifecycle,
          let outcome = lifecycleFailure.committedMutation else {
        Issue.record("Expected new-project path clear failure to terminate App access with a receipt.")
        return
    }
    #expect(lifecycleFailure.kind == .agentRegistration)
    #expect(lifecycleFailure.didCommit)
    #expect(outcome.mutation == .source)
    #expect(outcome.requestMethod == "project.new")
    #expect(outcome.retryDisposition == .mustNotRetry)
    #expect(outcome.projectID == committed.projectID)
    #expect(outcome.documentGeneration == committed.documentGeneration)
    #expect(outcome.transactionRevision == committed.transactionRevision)
    #expect(outcome.publicationSequence == committed.publicationSequence)
    #expect(outcome.workspaceRevision == committed.workspaceState.revision)
    #expect(committed.projectName == "Committed New Project")
    #expect(coordinator.currentFileURL == nil)
    #expect(registrar.updatePathAttemptCount == 1)
    #expect(registrar.unregisterCallCount == 1)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationSaveDoesNotAdvertiseOrAcceptMidCommitCancellation() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let gate = ApplicationBlockingOperationGate()
        let controller = try applicationProjectController(
            document: .empty(named: "Non-Cancellable Save"),
            packageWriter: ApplicationBlockingProjectPackageWriter(gate: gate)
        )
        let coordinator = ApplicationProjectCoordinator(
            workspace: ProjectWorkspace(project: controller),
            agentRegistrar: ApplicationAgentSessionRegistrarProbe()
        )
        await coordinator.launch()
        let packageURL = directory.appendingPathComponent("non-cancellable-save.rupa")

        coordinator.startSave(to: packageURL)
        while !gate.didStart {
            await Task.yield()
        }
        #expect(coordinator.operation == .save)
        #expect(coordinator.canCancelOperation == false)
        coordinator.cancelCurrentOperation()
        gate.release()
        while coordinator.isBusy {
            await Task.yield()
        }

        #expect(coordinator.failure == nil)
        #expect(coordinator.currentFileURL == packageURL.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: packageURL.path))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationHistorySharesSubmissionOrderWithWorkspaceUIOperations() async throws {
    let sequencer = ProjectWorkspaceOperationSequencer()
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    let coordinator = ApplicationProjectCoordinator(
        workspace: workspace,
        agentRegistrar: ApplicationAgentSessionRegistrarProbe(),
        operationSequencer: sequencer
    )
    await coordinator.launch()

    func enqueueRename(_ name: String) -> Task<ProjectViewSnapshot, Error> {
        sequencer.enqueue {
            let current = try #require(workspace.view)
            return try await workspace.commit(
                ProjectSourceTransaction(
                    name: "appTest.ordered-rename",
                    commands: [.renameDocument(name: name)],
                    expectedProjectID: current.projectID,
                    expectedTransactionRevision: current.transactionRevision,
                    expectedPublicationSequence: current.publicationSequence
                )
            )
        }
    }

    let first = enqueueRename("First Ordered Edit")
    let second = enqueueRename("Second Ordered Edit")
    let undo = Task { @MainActor in
        await coordinator.undo()
    }

    _ = try await first.value
    _ = try await second.value
    await undo.value

    #expect(coordinator.failure == nil)
    #expect(coordinator.snapshot?.projectName == "First Ordered Edit")
}

private func expectApplicationPublication(
    _ actual: ProjectViewSnapshot?,
    unchangedFrom expected: ProjectViewSnapshot
) throws {
    let actual = try #require(actual)
    #expect(actual.projectID == expected.projectID)
    #expect(actual.documentGeneration == expected.documentGeneration)
    #expect(actual.transactionRevision == expected.transactionRevision)
    #expect(actual.publicationSequence == expected.publicationSequence)
    #expect(actual.documentLifetimeID == expected.documentLifetimeID)
    #expect(actual.projectName == expected.projectName)
    #expect(actual.viewport == expected.viewport)
    #expect(actual.isDirty == expected.isDirty)
}

private func removeApplicationProjectTestFile(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove application project test file: \(error)")
    }
}

@MainActor
private final class ApplicationAgentSessionRegistrarProbe: ApplicationAgentSessionRegistering {
    private(set) var registeredWorkspace: ProjectWorkspace?
    private(set) var registeredPath: URL?
    private(set) var registeredID: UUID?
    private(set) var updatedPaths: [URL?] = []
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var updatePathAttemptCount = 0
    private let registrationGate: ApplicationAgentRegistrationGate?
    private let updatePathFailure: ApplicationProjectFailure?

    init(
        registrationGate: ApplicationAgentRegistrationGate? = nil,
        updatePathFailure: ApplicationProjectFailure? = nil
    ) {
        self.registrationGate = registrationGate
        self.updatePathFailure = updatePathFailure
    }

    func register(
        workspace: ProjectWorkspace,
        path: URL?,
        id: UUID
    ) async throws -> UUID {
        registerCallCount += 1
        registeredWorkspace = workspace
        registeredPath = path?.standardizedFileURL
        registeredID = id
        if let registrationGate {
            await registrationGate.suspendRegistration()
        }
        return id
    }

    func updatePath(id: UUID, path: URL?) async throws {
        updatePathAttemptCount += 1
        guard id == registeredID else {
            throw ApplicationProjectFailure(
                kind: .agentRegistration,
                message: "The test Agent registration ID does not match."
            )
        }
        if let updatePathFailure {
            throw updatePathFailure
        }
        updatedPaths.append(path?.standardizedFileURL)
    }

    func unregister(id _: UUID) async {
        unregisterCallCount += 1
    }
}

@MainActor
private final class ApplicationAgentSessionRegistrarProbeProxy:
    ApplicationAgentSessionRegistering
{
    private let controller: ProjectAgentCommandController
    private(set) var updatedPaths: [URL?] = []
    private(set) var unregisterCallCount = 0

    init(_ controller: ProjectAgentCommandController) {
        self.controller = controller
    }

    func register(
        workspace: ProjectWorkspace,
        path: URL?,
        id: UUID
    ) async throws -> UUID {
        try await controller.register(workspace: workspace, path: path, id: id)
    }

    func updatePath(id: UUID, path: URL?) async throws {
        try await controller.updatePath(id: id, path: path)
        updatedPaths.append(path?.standardizedFileURL)
    }

    func unregister(id: UUID) async {
        await controller.unregister(id: id)
        unregisterCallCount += 1
    }
}

@MainActor
private final class ApplicationSecurityScopedAccessOpenerProbe:
    SecurityScopedProjectAccessOpening
{
    private(set) var openedProjectURLs: [URL] = []
    private var weakAccesses: [ApplicationWeakSecurityScopedProjectAccess] = []

    var activeProjectURLs: [URL] {
        weakAccesses.compactMap { $0.value?.url }
    }

    func open(_ url: URL) -> any SecurityScopedProjectAccess {
        let access = ApplicationSecurityScopedProjectAccessProbe(url: url)
        openedProjectURLs.append(access.url)
        weakAccesses.append(ApplicationWeakSecurityScopedProjectAccess(access))
        return access
    }
}

@MainActor
private final class ApplicationSecurityScopedProjectAccessProbe:
    SecurityScopedProjectAccess
{
    let url: URL

    init(url: URL) {
        self.url = url.standardizedFileURL
    }
}

@MainActor
private final class ApplicationWeakSecurityScopedProjectAccess {
    weak var value: ApplicationSecurityScopedProjectAccessProbe?

    init(_ value: ApplicationSecurityScopedProjectAccessProbe) {
        self.value = value
    }
}

private actor ApplicationAgentRegistrationGate {
    private var didStart = false
    private var isReleased = false
    private var registrationContinuation: CheckedContinuation<Void, Never>?

    func suspendRegistration() async {
        didStart = true
        guard !isReleased else {
            return
        }
        await withCheckedContinuation { continuation in
            if isReleased {
                continuation.resume()
            } else {
                registrationContinuation = continuation
            }
        }
    }

    func waitUntilRegistrationStarts() async {
        while !didStart {
            await Task.yield()
        }
    }

    func releaseRegistration() {
        isReleased = true
        registrationContinuation?.resume()
        registrationContinuation = nil
    }
}

private final class ApplicationBlockingOperationGate: Sendable {
    private struct State {
        var didStart = false
        var isReleased = false
    }

    private let state = Mutex(State())

    var didStart: Bool {
        state.withLock { $0.didStart }
    }

    func wait() {
        state.withLock { $0.didStart = true }
        while !state.withLock({ $0.isReleased }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func release() {
        state.withLock { $0.isReleased = true }
    }
}

private struct ApplicationBlockingProjectPackageReader: ProjectPackageReading {
    let package: ProjectPackageDocument
    let gate: ApplicationBlockingOperationGate

    func load(from _: URL) throws -> ProjectPackageDocument {
        gate.wait()
        return package
    }
}

private struct ApplicationBlockingProjectPackageWriter: ProjectPackageWriting {
    let gate: ApplicationBlockingOperationGate

    func save(
        _ document: ProjectPackageDocument,
        to url: URL
    ) throws -> ProjectPackageSaveResult {
        gate.wait()
        return try ProjectPackageStore().save(document, to: url)
    }
}

private struct ApplicationFailingProjectPackageWriter: ProjectPackageWriting {
    func save(
        _: ProjectPackageDocument,
        to _: URL
    ) throws -> ProjectPackageSaveResult {
        throw ProjectPackageError(
            code: .atomicSaveFailure,
            message: "Fixture package save failure."
        )
    }
}

private final class ApplicationNthFailingProjectViewSnapshotBuilder:
    ProjectViewSnapshotBuilding,
    Sendable
{
    private let buildCount = Mutex(0)
    private let failingBuildNumber: Int

    init(failingBuildNumber: Int) {
        self.failingBuildNumber = failingBuildNumber
    }

    func build(from state: ProjectStateSnapshot) throws -> ProjectViewSnapshot {
        let buildNumber = buildCount.withLock { count in
            count += 1
            return count
        }
        if buildNumber == failingBuildNumber {
            throw ApplicationProjectFailure(
                kind: .viewRecovery,
                message: "Fixture project view build failure."
            )
        }
        return try ProjectViewSnapshotBuilder().build(from: state)
    }
}

private func applicationProjectController(
    document: DesignDocument,
    packageReader: any ProjectPackageReading = ProjectPackageStore(),
    packageWriter: any ProjectPackageWriting = ProjectPackageStore()
) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge(),
        packageReader: packageReader,
        packageWriter: packageWriter
    )
}

@MainActor
private func applicationProjectAgentCommandController() throws -> ProjectAgentCommandController {
    ProjectAgentCommandController(
        semanticProgramCompiler: try ApplicationDomainRegistry.makeCADSemanticCompiler()
    )
}

@MainActor
private func applicationAgentResponse(
    _ request: AgentRequest,
    using handler: any AgentRequestHandling,
    requestID: String = UUID().uuidString
) async throws -> AgentResponse {
    let handled = await handler.handle(
        AgentRequestEnvelope(id: requestID, params: request)
    )
    guard case .ordinary(let response) = handled else {
        throw ApplicationAgentTestError.expectedOrdinaryResponse
    }
    return response
}

private enum ApplicationAgentTestError: Error {
    case expectedOrdinaryResponse
}

private final class ApplicationLifecycleOrderingState: Sendable {
    struct Snapshot: Sendable {
        var registrationCount = 0
        var registeredPath: URL?
        var registeredPublicationSequence: UInt64?
        var discoveryPublicationCount = 0
        var registrationCountAtDiscoveryPublication: Int?
        var pathAtDiscoveryPublication: URL?
        var publicationSequenceAtDiscoveryPublication: UInt64?
        var discoveryRecord: AgentDiscoveryRecord?
    }

    private let state = Mutex(Snapshot())

    func recordRegistration(path: URL?, publicationSequence: UInt64?) {
        state.withLock { state in
            state.registrationCount += 1
            state.registeredPath = path?.standardizedFileURL
            state.registeredPublicationSequence = publicationSequence
        }
    }

    func recordDiscoveryPublication(_ record: AgentDiscoveryRecord) {
        state.withLock { state in
            state.discoveryPublicationCount += 1
            state.registrationCountAtDiscoveryPublication = state.registrationCount
            state.pathAtDiscoveryPublication = state.registeredPath
            state.publicationSequenceAtDiscoveryPublication =
                state.registeredPublicationSequence
            state.discoveryRecord = record
        }
    }

    func readDiscoveryRecord() throws -> AgentDiscoveryRecord {
        try state.withLock { state in
            guard let record = state.discoveryRecord else {
                throw AgentDiscoveryError.unavailable(
                    "The lifecycle fixture has no discovery record."
                )
            }
            return record
        }
    }

    func removeDiscoveryRecord(ifGeneration generation: UInt64) throws {
        try state.withLock { state in
            guard state.discoveryRecord?.generation == generation else {
                throw AgentDiscoveryError.staleGeneration(
                    expected: generation,
                    actual: state.discoveryRecord?.generation
                )
            }
            state.discoveryRecord = nil
        }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

@MainActor
private final class ApplicationLifecycleAgentRegistrar:
    ApplicationAgentSessionRegistering
{
    private let controller: ProjectAgentCommandController
    private let state: ApplicationLifecycleOrderingState

    init(
        controller: ProjectAgentCommandController,
        state: ApplicationLifecycleOrderingState
    ) {
        self.controller = controller
        self.state = state
    }

    func register(
        workspace: ProjectWorkspace,
        path: URL?,
        id: UUID
    ) async throws -> UUID {
        let registeredID = try await controller.register(
            workspace: workspace,
            path: path,
            id: id
        )
        state.recordRegistration(
            path: path,
            publicationSequence: workspace.view?.publicationSequence
        )
        return registeredID
    }

    func updatePath(id: UUID, path: URL?) async throws {
        try await controller.updatePath(id: id, path: path)
    }

    func unregister(id: UUID) async {
        await controller.unregister(id: id)
    }
}

private struct ApplicationLifecycleDiscoveryStore:
    AgentDiscoveryRecordStore,
    Sendable
{
    let state: ApplicationLifecycleOrderingState

    func read() throws -> AgentDiscoveryRecord {
        try state.readDiscoveryRecord()
    }

    func publish(_ record: AgentDiscoveryRecord) throws {
        state.recordDiscoveryPublication(record)
    }

    func remove(ifGeneration generation: UInt64) throws {
        try state.removeDiscoveryRecord(ifGeneration: generation)
    }
}

private func applicationCADOnlyDocument(named name: String) throws -> DesignDocument {
    let session = EditorSession(document: .empty(named: name))
    guard session.createDefaultExtrudedRectangle() != nil else {
        throw ApplicationProjectFailure(
            kind: .launch,
            message: "The CAD-only application test fixture could not create its body."
        )
    }
    let document = session.document
    try document.validate()
    return document
}

private func applicationMeshOnlyDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let mesh = try applicationTriangleMesh(
        identity: GeometrySourceID(rawValue: "mesh.\(UUID().uuidString)")
    )
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let representationID = GeometryRepresentationID(
        rawValue: "representation.\(UUID().uuidString)"
    )
    document.authoredMeshAssets[asset.id] = asset
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: applicationRepresentationSet(
                representationID: representationID,
                source: .authoredMesh(asset.id)
            )
        )
    )
    try document.validate()
    return document
}

private func applicationMixedDocument(named name: String) throws -> DesignDocument {
    var document = try applicationCADOnlyDocument(named: name)
    let bodyNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference?.kind == .body
    }?.key)
    var object = try #require(document.productMetadata.sceneNodes[bodyNodeID]?.object)
    let cadRepresentationID = try #require(
        object.geometryRepresentations.selection?.modeling
    )
    let mesh = try applicationTriangleMesh(
        identity: GeometrySourceID(rawValue: "mesh.\(UUID().uuidString)")
    )
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let meshRepresentationID = GeometryRepresentationID(
        rawValue: "representation.\(UUID().uuidString)"
    )
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

private func applicationRepresentationSet(
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

private func applicationTriangleMesh(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

private func expectApplicationAuthoredMeshStorageIsShared(
    _ snapshot: ProjectViewSnapshot,
    requiresAuthoredMesh: Bool
) throws {
    let authoredMeshItems = snapshot.viewport.items.filter {
        if case .authoredMesh = $0.reference {
            return true
        }
        return false
    }
    guard requiresAuthoredMesh else {
        #expect(authoredMeshItems.isEmpty)
        #expect(snapshot.document.document.authoredMeshAssets.isEmpty)
        return
    }
    let item = try #require(authoredMeshItems.first)
    let sourceID: GeometrySourceID
    guard case .authoredMesh(let authoredSourceID) = item.reference else {
        Issue.record("The required Authored Mesh item has a different source reference.")
        return
    }
    sourceID = authoredSourceID
    let source = try #require(snapshot.document.document.authoredMeshAssets[sourceID]?.source)
    #expect(item.mesh == source)
    #expect(item.copyTelemetry.didCopy == false)
    #expect(
        item.mesh.vertexPositions.storage.chunkIdentities
            == source.vertexPositions.storage.chunkIdentities
    )
    #expect(
        item.mesh.vertexPositions.storage.pageIdentities
            == source.vertexPositions.storage.pageIdentities
    )
    #expect(
        item.mesh.faceIDs.storage.chunkIdentities
            == source.faceIDs.storage.chunkIdentities
    )
    #expect(
        item.mesh.cornerVertexIDs.storage.chunkIdentities
            == source.cornerVertexIDs.storage.chunkIdentities
    )
}

private func withApplicationProjectTemporaryDirectory<Result: Sendable>(
    _ body: (URL) async throws -> Result
) async throws -> Result {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "rupa-application-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Failed to remove the application test directory: \(error)")
        }
    }
    return try await body(directory)
}
