import Foundation
import RupaCore
import RupaCoreTypes
@testable import RupaGeometry
import RupaKit
import RupaProject
import RupaProjectModel
import RupaProjectPackage
import RupaUI
import RupaViewportScene
import Synchronization
import Testing
@testable import Rupa

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationLaunchPublishesBeforeRegisteringTheSharedWorkspace() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    let registrar = ApplicationAgentSessionRegistrarProbe()
    let coordinator = ApplicationProjectCoordinator(
        workspace: workspace,
        agentRegistrar: registrar,
        launchArguments: []
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
        agentRegistrar: registrar,
        launchArguments: []
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
        initialURL: missingURL,
        launchArguments: []
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
            initialURL: packageURL,
            launchArguments: []
        )

        await coordinator.launch()

        #expect(coordinator.lifecycle == .ready)
        #expect(coordinator.snapshot?.projectName == "Initial URL")
        #expect(coordinator.snapshot?.publicationSequence == 1)
        #expect(coordinator.currentFileURL == packageURL.standardizedFileURL)
        #expect(registrar.registeredPath == packageURL.standardizedFileURL)
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
            agentRegistrar: registrar,
            launchArguments: []
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
                agentRegistrar: registrar,
                launchArguments: []
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
func applicationRejectsOpenWhileDirtyWithoutChangingFileOwnership() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    let coordinator = ApplicationProjectCoordinator(
        workspace: workspace,
        agentRegistrar: ApplicationAgentSessionRegistrarProbe(),
        launchArguments: []
    )
    await coordinator.launch()
    let initial = try #require(coordinator.snapshot)
    _ = try await workspace.commit(
        ProjectSourceTransaction(
            name: "appTest.dirty",
            commands: [.renameDocument(name: "Dirty")],
            expectedProjectID: initial.projectID,
            expectedTransactionRevision: initial.transactionRevision,
            expectedPublicationSequence: initial.publicationSequence
        )
    )
    let missingURL = URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString).rupa")

    await coordinator.load(from: missingURL)

    #expect(coordinator.failure?.kind == .unsavedChanges)
    #expect(coordinator.currentFileURL == nil)
    #expect(coordinator.snapshot?.projectName == "Dirty")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationRejectsNewProjectWhileDirty() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    let coordinator = ApplicationProjectCoordinator(
        workspace: workspace,
        agentRegistrar: ApplicationAgentSessionRegistrarProbe(),
        launchArguments: []
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
            agentRegistrar: ApplicationAgentSessionRegistrarProbe(),
            launchArguments: []
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
func applicationPrecommitLoadFailureRetainsPublishedAuthorityAndAgentPath() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: try applicationMeshOnlyDocument(named: "Retained Load")
    )
    let registrar = ApplicationAgentSessionRegistrarProbe()
    let coordinator = ApplicationProjectCoordinator(
        workspace: workspace,
        agentRegistrar: registrar,
        launchArguments: []
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
func applicationPrecommitSaveFailureRetainsDirtyAuthorityAndFileOwnership() async throws {
    try await withApplicationProjectTemporaryDirectory { directory in
        let controller = try applicationProjectController(
            document: .empty(named: "Before Failed Save"),
            packageWriter: ApplicationFailingProjectPackageWriter()
        )
        let workspace = ProjectWorkspace(project: controller)
        let registrar = ApplicationAgentSessionRegistrarProbe()
        let coordinator = ApplicationProjectCoordinator(
            workspace: workspace,
            agentRegistrar: registrar,
            launchArguments: []
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
    let coordinator = ApplicationProjectCoordinator(
        workspace: workspace,
        agentRegistrar: registrar,
        launchArguments: []
    )
    await coordinator.launch()
    let retained = try #require(coordinator.snapshot)

    coordinator.startLoad(from: URL(fileURLWithPath: "/ignored/cancelled.rupa"))
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
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationStaleLoadCannotReplaceANewerWorkspacePublication() async throws {
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
        agentRegistrar: ApplicationAgentSessionRegistrarProbe(),
        launchArguments: []
    )
    await coordinator.launch()
    let initial = try #require(coordinator.snapshot)

    let load = Task { @MainActor in
        await coordinator.load(from: URL(fileURLWithPath: "/ignored/stale.rupa"))
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
            agentRegistrar: registrar,
            launchArguments: []
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
            agentRegistrar: registrar,
            launchArguments: []
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
        agentRegistrar: ApplicationAgentSessionRegistrarProbe(),
        launchArguments: []
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
            agentRegistrar: registrar,
            launchArguments: []
        )
        await coordinator.launch()
        let packageURL = directory.appendingPathComponent("agent-rebind-failure.rupa")

        await coordinator.save(to: packageURL)

        #expect(coordinator.failure?.kind == .agentRegistration)
        #expect(coordinator.failure?.didCommit == true)
        #expect(coordinator.snapshot?.isDirty == false)
        #expect(coordinator.currentFileURL == packageURL.standardizedFileURL)
        #expect(registrar.updatePathAttemptCount == 1)
        #expect(FileManager.default.fileExists(atPath: packageURL.path))
    }
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
            agentRegistrar: ApplicationAgentSessionRegistrarProbe(),
            launchArguments: []
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
        operationSequencer: sequencer,
        launchArguments: []
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
