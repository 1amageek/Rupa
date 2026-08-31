import Foundation
import Darwin
import RupaAgentProtocol
import RupaAgentRuntime
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaKit
import RupaProjectAccess
@testable import RupaProjectAccessComposition
import RupaProjectModel
import RupaProjectPackage
import Testing

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessUsesOneLeaseForCanonicalDuplicatePaths() async throws {
    let directory = try makeAccessTemporaryDirectory()
    defer { removeAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("input.rupa")
    let alias = directory.appendingPathComponent("alias.rupa")
    try Data("source".utf8).write(to: input)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: input)
    let leaseRoot = directory.appendingPathComponent("leases", isDirectory: true)
    let firstStore = ProjectFileAuthorityLeaseStore(rootDirectory: leaseRoot)
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    let lease = try await firstStore.acquire(
        paths: [input, input, alias],
        requiredPaths: [input, alias],
        deadline: deadline
    )
    try await withAccessLease(lease) {
        let rootAttributes = try FileManager.default.attributesOfItem(atPath: leaseRoot.path)
        #expect((rootAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        let lockEntries = try FileManager.default.contentsOfDirectory(
            at: leaseRoot,
            includingPropertiesForKeys: nil
        )
        let pathLocks = lockEntries.filter { $0.pathExtension == "lock" && $0.lastPathComponent != ".coordinator.lock" }
        #expect(pathLocks.count == 1)
        let lockAttributes = try FileManager.default.attributesOfItem(atPath: pathLocks[0].path)
        #expect((lockAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        let secondStore = ProjectFileAuthorityLeaseStore(rootDirectory: leaseRoot)
        do {
            _ = try await secondStore.acquire(
                paths: [alias],
                requiredPaths: [alias],
                deadline: deadline
            )
            Issue.record("An overlapping closed-file lease must be rejected.")
        } catch let error as ProjectAccessError {
            #expect(error == .fileAuthorityConflict(input.standardizedFileURL))
        }

        try await lease.validate()
        let heldEntries = try FileManager.default.contentsOfDirectory(
            at: leaseRoot,
            includingPropertiesForKeys: nil
        )
        #expect(heldEntries.contains { $0.lastPathComponent == ".coordinator.lock" })
        #expect(heldEntries.contains { $0.pathExtension == "lock" && $0.lastPathComponent != ".coordinator.lock" })
    }

    let releasedEntries = try FileManager.default.contentsOfDirectory(
        at: leaseRoot,
        includingPropertiesForKeys: nil
    )
    #expect(releasedEntries.contains { $0.lastPathComponent == ".coordinator.lock" })
    #expect(!releasedEntries.contains { $0.pathExtension == "lock" && $0.lastPathComponent != ".coordinator.lock" })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessDetectsReplacedPathIdentity() async throws {
    let directory = try makeAccessTemporaryDirectory()
    defer { removeAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("input.rupa")
    let replacement = directory.appendingPathComponent("replacement.rupa")
    try Data("first".utf8).write(to: input)
    try Data("second".utf8).write(to: replacement)
    let store = ProjectFileAuthorityLeaseStore(
        rootDirectory: directory.appendingPathComponent("leases", isDirectory: true)
    )
    let lease = try await store.acquire(
        paths: [input],
        requiredPaths: [input],
        deadline: ContinuousClock.now.advanced(by: .seconds(5))
    )
    try await withAccessLease(lease) {
        _ = try FileManager.default.replaceItemAt(
            input,
            withItemAt: replacement,
            backupItemName: nil,
            options: .usingNewMetadataOnly
        )
        do {
            try await lease.validate()
            Issue.record("Replacing the leased file inode must invalidate the lease.")
        } catch let error as ProjectAccessError {
            #expect(error == .fileAuthorityLost(input.standardizedFileURL))
        }
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessRoutesLoadMutationAndExplicitSaveThroughWorkspace() async throws {
    let directory = try makeAccessTemporaryDirectory()
    defer { removeAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("input.rupa")
    let output = directory.appendingPathComponent("output.rupa")
    let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: .empty(named: "Closed Source")
    )
    _ = try await sourceWorkspace.evaluate()
    _ = try await sourceWorkspace.save(to: input)
    let inputBytes = try Data(contentsOf: input)

    let opener = ClosedProjectAccessOpening(
        leaseStore: ProjectFileAuthorityLeaseStore(
            rootDirectory: directory.appendingPathComponent("leases", isDirectory: true)
        )
    )
    let session = try await opener.open(
        .closedProject(input: input, output: output),
        deadline: ContinuousClock.now.advanced(by: .seconds(30))
    )
    let sessionID = session.sessionID
    let initial = try await session.send(
        .designDisplaySnapshot(sessionID: sessionID, expectedGeneration: nil)
    )
    guard case .designDisplaySnapshot(let initialSnapshot) = initial else {
        Issue.record("Closed access must use the registered ProjectAgentCommandController route.")
        await session.finish()
        return
    }

    let mutation = try await session.send(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Closed Mutated"),
            expectedGeneration: initialSnapshot.generation
        )
    )
    guard case .command(let commandResult) = mutation else {
        if case .failure(let error) = mutation {
            Issue.record("Closed access mutation failed: \(error.code.rawValue) \(error.message)")
        } else {
            Issue.record("Closed access mutation must be handled by the existing Agent runtime.")
        }
        await session.finish()
        return
    }
    #expect(commandResult.didMutate)
    #expect(!FileManager.default.fileExists(atPath: output.path))
    #expect(try Data(contentsOf: input) == inputBytes)

    let rejectedSaveRequest = try await session.send(
        .save(
            sessionID: sessionID,
            expectedGeneration: nil
        )
    )
    guard case .failure(let saveError) = rejectedSaveRequest else {
        Issue.record("The Agent save request must remain outside the command route.")
        await session.finish()
        return
    }
    #expect(saveError.code == .commandUnsupported)

    let saveResult = try await session.save(expectedGeneration: nil)
    #expect(saveResult.path == output.path)
    #expect(FileManager.default.fileExists(atPath: output.path))
    #expect(try Data(contentsOf: input) == inputBytes)
    await session.finish()

    let reload = try await opener.open(
        .closedProject(input: output, output: nil),
        deadline: ContinuousClock.now.advanced(by: .seconds(30))
    )
    let reloaded = try await reload.send(
        .designDisplaySnapshot(sessionID: reload.sessionID, expectedGeneration: nil)
    )
    guard case .designDisplaySnapshot = reloaded else {
        Issue.record("The explicitly saved package must reload through the same access route.")
        await reload.finish()
        return
    }
    await reload.finish()
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessRejectsUnsupportedFormatAndExpiredDeadline() async throws {
    let directory = try makeAccessTemporaryDirectory()
    defer { removeAccessTemporaryDirectory(directory) }
    let store = ProjectFileAuthorityLeaseStore(
        rootDirectory: directory.appendingPathComponent("leases", isDirectory: true)
    )
    let opener = ClosedProjectAccessOpening(leaseStore: store)
    let legacy = directory.appendingPathComponent("legacy.swcad")
    try Data("legacy".utf8).write(to: legacy)
    do {
        _ = try await opener.open(
            .closedProject(input: legacy, output: nil),
            deadline: ContinuousClock.now.advanced(by: .seconds(5))
        )
        Issue.record("Legacy .swcad input must be rejected before lease creation.")
    } catch let error as ProjectAccessError {
        #expect(error == .unsupportedProjectFormat(legacy))
    }

    do {
        _ = try await opener.open(
            .closedProject(input: legacy, output: nil),
            deadline: ContinuousClock.now
        )
        Issue.record("An expired deadline must be rejected before opening.")
    } catch let error as ProjectAccessError {
        #expect(error == .deadlineExceeded)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessCancellationAfterRegistrationReleasesSessionAndLease() async throws {
    let directory = try makeAccessTemporaryDirectory()
    defer { removeAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("input.rupa")
    let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: .empty(named: "Registration Cancellation")
    )
    _ = try await sourceWorkspace.evaluate()
    _ = try await sourceWorkspace.save(to: input)

    let leaseRoot = directory.appendingPathComponent("leases", isDirectory: true)
    let gate = AccessRegistrationGate()
    let opener = ClosedProjectAccessOpening(
        leaseStore: ProjectFileAuthorityLeaseStore(rootDirectory: leaseRoot),
        workspaceMaker: DefaultProjectWorkspaceMaker(),
        afterRegistration: {
            await gate.enter()
            await gate.waitUntilReleased()
            try Task.checkCancellation()
        }
    )
    let openingTask = Task { @MainActor in
        try await opener.open(
            .closedProject(input: input, output: nil),
            deadline: ContinuousClock.now.advanced(by: .seconds(30))
        )
    }

    await gate.waitUntilEntered()
    openingTask.cancel()
    await gate.release()
    do {
        _ = try await openingTask.value
        Issue.record("Cancellation after registration must not publish a session.")
    } catch is CancellationError {
        // Expected: the post-registration guard aborts the opening.
    } catch {
        Issue.record("Opening cancellation returned an unexpected error: \(error)")
    }

    let replacementLease = try await ProjectFileAuthorityLeaseStore(
        rootDirectory: leaseRoot
    ).acquire(
        paths: [input],
        requiredPaths: [input],
        deadline: ContinuousClock.now.advanced(by: .seconds(5))
    )
    try await replacementLease.validate()
    await replacementLease.release()
}

@MainActor
@Test(.timeLimit(.minutes(2)))
func closedAccessRoundTripsCADOnlyCADAndMeshAndMeshOnlyThroughOneAuthority() async throws {
    for kind in ClosedAccessFixtureKind.allCases {
        let directory = try makeAccessTemporaryDirectory()
        let input = directory.appendingPathComponent("input.rupa")
        let output = directory.appendingPathComponent("output.rupa")
        let sourceDocument = try closedAccessFixtureDocument(
            kind: kind,
            name: "Closed \(kind.rawValue)"
        )
        let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
            document: sourceDocument
        )
        _ = try await sourceWorkspace.evaluate()
        _ = try await sourceWorkspace.save(to: input)
        let inputBytes = try Data(contentsOf: input)

        let opener = ClosedProjectAccessOpening(
            leaseStore: ProjectFileAuthorityLeaseStore(
                rootDirectory: directory.appendingPathComponent(
                    "leases",
                    isDirectory: true
                )
            )
        )
        let session = try await opener.open(
            .closedProject(input: input, output: output),
            deadline: ContinuousClock.now.advanced(by: .seconds(90))
        )

        let initial = try await session.send(
            .designDisplaySnapshot(
                sessionID: session.sessionID,
                expectedGeneration: nil
            )
        )
        guard case .designDisplaySnapshot(let initialDisplay) = initial else {
            Issue.record("Closed access must return the registered display snapshot.")
            await session.finish()
            removeAccessTemporaryDirectory(directory)
            continue
        }
        let initialCatalog = try await closedAccessMeshCatalog(
            session: session,
            generation: initialDisplay.generation
        )
        try expectCatalog(
            initialCatalog,
            matches: sourceDocument.authoredMeshAssets,
            document: sourceDocument
        )
        let initialVertexRecords = try await closedAccessMeshVertexRecords(
            session: session,
            catalog: initialCatalog,
            generation: initialDisplay.generation
        )

        let initialViewport = try await closedAccessViewport(
            session: session,
            generation: initialDisplay.generation
        )
        #expect(!initialViewport.items.isEmpty)
        if kind == .meshOnly {
            #expect(initialViewport.items.allSatisfy {
                if case .authoredMesh = $0.sourceReference {
                    return true
                }
                return false
            })
        }
        if kind != .cadOnly {
            #expect(!initialViewport.copyTelemetry.didCopy)
        }

        let mutation = try await session.send(
            .execute(
                sessionID: session.sessionID,
                command: .renameDocument(name: "Renamed \(kind.rawValue)"),
                expectedGeneration: initialDisplay.generation
            )
        )
        guard case .command(let commandResult) = mutation else {
            Issue.record("The existing Agent command route must execute the mutation.")
            await session.finish()
            removeAccessTemporaryDirectory(directory)
            continue
        }
        #expect(commandResult.didMutate)
        #expect(try Data(contentsOf: input) == inputBytes)

        let mutated = try await session.send(
            .designDisplaySnapshot(
                sessionID: session.sessionID,
                expectedGeneration: commandResult.generation
            )
        )
        guard case .designDisplaySnapshot(let mutatedDisplay) = mutated else {
            Issue.record("A successful mutation must publish a new display snapshot.")
            await session.finish()
            removeAccessTemporaryDirectory(directory)
            continue
        }
        let mutatedCatalog = try await closedAccessMeshCatalog(
            session: session,
            generation: mutatedDisplay.generation
        )
        try expectCatalog(
            mutatedCatalog,
            matches: sourceDocument.authoredMeshAssets,
            document: sourceDocument
        )
        let mutatedVertexRecords = try await closedAccessMeshVertexRecords(
            session: session,
            catalog: mutatedCatalog,
            generation: mutatedDisplay.generation
        )
        #expect(mutatedVertexRecords == initialVertexRecords)

        let saved = try await session.save(expectedGeneration: mutatedDisplay.generation)
        #expect(saved.path == output.path)
        #expect(try Data(contentsOf: input) == inputBytes)
        await session.finish()

        let package = try ProjectPackageStore().load(from: output)
        #expect(package.authoredMeshAssets == sourceDocument.authoredMeshAssets)

        let reloaded = try await opener.open(
            .closedProject(input: output, output: nil),
            deadline: ContinuousClock.now.advanced(by: .seconds(90))
        )
        let reloadedDisplayResponse = try await reloaded.send(
            .designDisplaySnapshot(
                sessionID: reloaded.sessionID,
                expectedGeneration: nil
            )
        )
        guard case .designDisplaySnapshot(let reloadedDisplay) = reloadedDisplayResponse else {
            Issue.record("The explicitly saved package must reload through the same access route.")
            await reloaded.finish()
            removeAccessTemporaryDirectory(directory)
            continue
        }
        let reloadedCatalog = try await closedAccessMeshCatalog(
            session: reloaded,
            generation: reloadedDisplay.generation
        )
        try expectCatalog(
            reloadedCatalog,
            matches: sourceDocument.authoredMeshAssets,
            document: sourceDocument
        )
        let reloadedVertexRecords = try await closedAccessMeshVertexRecords(
            session: reloaded,
            catalog: reloadedCatalog,
            generation: reloadedDisplay.generation
        )
        #expect(reloadedVertexRecords == initialVertexRecords)
        let reloadedViewport = try await closedAccessViewport(
            session: reloaded,
            generation: reloadedDisplay.generation
        )
        #expect(!reloadedViewport.items.isEmpty)
        if kind != .cadOnly {
            #expect(!reloadedViewport.copyTelemetry.didCopy)
        }
        await reloaded.finish()
        removeAccessTemporaryDirectory(directory)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessRejectsNonRegularTargetsAndInvalidOutputParents() async throws {
    let directory = try makeAccessTemporaryDirectory()
    defer { removeAccessTemporaryDirectory(directory) }
    let leaseRoot = directory.appendingPathComponent("leases", isDirectory: true)
    let opener = ClosedProjectAccessOpening(
        leaseStore: ProjectFileAuthorityLeaseStore(rootDirectory: leaseRoot)
    )
    let input = directory.appendingPathComponent("input.rupa")
    try Data("source".utf8).write(to: input)
    let missingParent = directory
        .appendingPathComponent("missing", isDirectory: true)
        .appendingPathComponent("output.rupa")
    do {
        _ = try await opener.open(
            .closedProject(input: input, output: missingParent),
            deadline: ContinuousClock.now.advanced(by: .seconds(5))
        )
        Issue.record("An output whose parent is absent must be rejected.")
    } catch let error as ProjectAccessError {
        #expect(error == .invalidTarget(missingParent))
    }

    let fifo = directory.appendingPathComponent("input-fifo.rupa")
    guard mkfifo(fifo.path, mode_t(0o600)) == 0 else {
        Issue.record("The FIFO fixture could not be created.")
        return
    }
    do {
        _ = try await opener.open(
            .closedProject(input: fifo, output: nil),
            deadline: ContinuousClock.now.advanced(by: .seconds(5))
        )
        Issue.record("A FIFO input must be rejected as a non-regular file.")
    } catch let error as ProjectAccessError {
        #expect(error == .invalidTarget(fifo))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func closedAccessRejectsWrongSessionStaleGenerationAndFinishedSession() async throws {
    let directory = try makeAccessTemporaryDirectory()
    defer { removeAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("input.rupa")
    let sourceWorkspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: .empty(named: "Session Guards")
    )
    _ = try await sourceWorkspace.evaluate()
    _ = try await sourceWorkspace.save(to: input)
    let opener = ClosedProjectAccessOpening(
        leaseStore: ProjectFileAuthorityLeaseStore(
            rootDirectory: directory.appendingPathComponent("leases", isDirectory: true)
        )
    )
    let session = try await opener.open(
        .closedProject(input: input, output: nil),
        deadline: ContinuousClock.now.advanced(by: .seconds(30))
    )
    let wrongID = UUID()
    do {
        _ = try await session.send(
            .designDisplaySnapshot(sessionID: wrongID, expectedGeneration: nil)
        )
        Issue.record("A request for another session must be rejected.")
    } catch let error as ProjectAccessError {
        #expect(error == .sessionMismatch(expected: session.sessionID, actual: wrongID))
    }

    let current = try await session.send(
        .designDisplaySnapshot(sessionID: session.sessionID, expectedGeneration: nil)
    )
    guard case .designDisplaySnapshot(let display) = current else {
        Issue.record("The session guard fixture requires a display snapshot.")
        await session.finish()
        return
    }
    let staleResponse = try await session.send(
        .execute(
            sessionID: session.sessionID,
            command: .renameDocument(name: "Stale"),
            expectedGeneration: DocumentGeneration(display.generation.value + 1)
        )
    )
    guard case .failure(let staleError) = staleResponse else {
        Issue.record("A stale generation must be rejected by the existing handler.")
        await session.finish()
        return
    }
    #expect(staleError.code == .documentGenerationMismatch)
    await session.finish()
    do {
        _ = try await session.send(
            .designDisplaySnapshot(sessionID: session.sessionID, expectedGeneration: nil)
        )
        Issue.record("A finished session must reject later requests.")
    } catch let error as ProjectAccessError {
        #expect(error == .finished)
    }
}

@Test(.timeLimit(.minutes(2)))
func closedAccessLeaseIsReleasedWhenOwningProcessExits() async throws {
    let directory = try makeAccessTemporaryDirectory()
    defer { removeAccessTemporaryDirectory(directory) }
    let input = directory.appendingPathComponent("input.rupa")
    try Data("source".utf8).write(to: input)
    let leaseRoot = directory.appendingPathComponent("leases", isDirectory: true)
    let marker = directory.appendingPathComponent("acquired.marker")
    let probeURL = try authorityLeaseCrashProbeURL()
    let probe = Process()
    probe.executableURL = probeURL
    probe.arguments = [
        "--root", leaseRoot.path,
        "--input", input.path,
        "--marker", marker.path,
    ]
    try probe.run()
    defer {
        if probe.isRunning {
            _ = kill(probe.processIdentifier, SIGKILL)
            probe.waitUntilExit()
        }
    }
    let markerDeadline = Date().addingTimeInterval(10)
    while !FileManager.default.fileExists(atPath: marker.path), probe.isRunning {
        guard Date() < markerDeadline else {
            Issue.record("The crash probe did not acquire its lease before the deadline.")
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(FileManager.default.fileExists(atPath: marker.path))
    guard probe.isRunning else {
        Issue.record("The crash probe exited before its held lease could be terminated.")
        return
    }

    let contender = ProjectFileAuthorityLeaseStore(rootDirectory: leaseRoot)
    do {
        let contenderLease = try await contender.acquire(
            paths: [input],
            requiredPaths: [input],
            deadline: ContinuousClock.now.advanced(by: .seconds(5))
        )
        await contenderLease.release()
        Issue.record("A live process lease must reject an overlapping acquisition.")
    } catch let error as ProjectAccessError {
        #expect(error == .fileAuthorityConflict(input.standardizedFileURL))
    } catch {
        Issue.record("The overlapping lease failed with an unexpected error: \(error)")
    }

    _ = kill(probe.processIdentifier, SIGKILL)
    probe.waitUntilExit()
    #expect(probe.terminationReason == .uncaughtSignal)

    let store = ProjectFileAuthorityLeaseStore(rootDirectory: leaseRoot)
    let lease = try await store.acquire(
        paths: [input],
        requiredPaths: [input],
        deadline: ContinuousClock.now.advanced(by: .seconds(5))
    )
    try await lease.validate()
    await lease.release()
}

private func authorityLeaseCrashProbeURL() throws -> URL {
    let fileManager = FileManager.default
    var candidates: [URL] = []
    let environment = ProcessInfo.processInfo.environment
    for key in ["BUILT_PRODUCTS_DIR", "TARGET_BUILD_DIR"] {
        if let directory = environment[key] {
            candidates.append(
                URL(fileURLWithPath: directory)
                    .appendingPathComponent("ProjectAuthorityLeaseCrashProbe")
            )
        }
    }
    func appendAncestorCandidates(of executable: URL) {
        var directory = executable.deletingLastPathComponent()
        for _ in 0..<8 {
            candidates.append(
                directory.appendingPathComponent("ProjectAuthorityLeaseCrashProbe")
            )
            directory.deleteLastPathComponent()
        }
    }
    if let mainExecutable = Bundle.main.executableURL {
        appendAncestorCandidates(of: mainExecutable)
    }
    if let testPath = CommandLine.arguments.first {
        appendAncestorCandidates(of: URL(fileURLWithPath: testPath))
    }
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    candidates.append(
        packageRoot
            .appendingPathComponent(".build/out/Products/Debug/ProjectAuthorityLeaseCrashProbe")
    )
    for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
        return candidate
    }
    throw EditorError(
        code: .commandFailed,
        message: "The prebuilt ProjectAuthorityLeaseCrashProbe could not be found. Checked: \(candidates.map(\.path).joined(separator: ", "))"
    )
}

private enum ClosedAccessFixtureKind: String, CaseIterable, Sendable {
    case cadOnly = "cad-only"
    case cadAndMesh = "cad-and-mesh"
    case meshOnly = "mesh-only"
}

private func closedAccessFixtureDocument(
    kind: ClosedAccessFixtureKind,
    name: String
) throws -> DesignDocument {
    switch kind {
    case .cadOnly:
        var document = DesignDocument.empty(named: name)
        _ = try document.createExtrudedRectangle(
            name: "CAD Body",
            plane: .xy,
            width: .length(1, .meter),
            height: .length(1, .meter),
            depth: .length(1, .meter),
            direction: .normal
        )
        _ = try document.validate()
        return document
    case .meshOnly:
        var document = DesignDocument.empty(named: name)
        let asset = try AuthoredMeshAsset(
            source: closedAccessTriangleMesh(identity: "mesh.closed-only"),
            provenance: .created
        )
        document.authoredMeshAssets[asset.id] = asset
        _ = try document.productMetadata.appendSceneNodeToFirstRoot(
            name: "Mesh Body",
            reference: .authoredMesh(asset.id),
            object: ObjectDescriptor(
                category: .body,
                geometryRole: .mesh,
                geometryRepresentations: closedAccessRepresentationSet(
                    representationID: "representation.closed-mesh",
                    source: .authoredMesh(asset.id)
                )
            )
        )
        _ = try document.validate()
        return document
    case .cadAndMesh:
        var document = DesignDocument.empty(named: name)
        let bodyFeatureID = try document.createExtrudedRectangle(
            name: "CAD Body",
            plane: .xy,
            width: .length(1, .meter),
            height: .length(1, .meter),
            depth: .length(1, .meter),
            direction: .normal
        )
        let bodyNodeID = try #require(document.productMetadata.sceneNodes.first {
            $0.value.reference == .body(bodyFeatureID)
        }?.key)
        var object = try #require(document.productMetadata.sceneNodes[bodyNodeID]?.object)
        let cadRepresentationID = try #require(
            object.geometryRepresentations.selection?.modeling
        )
        let asset = try AuthoredMeshAsset(
            source: closedAccessTriangleMesh(identity: "mesh.closed-presentation"),
            provenance: .created
        )
        document.authoredMeshAssets[asset.id] = asset
        let meshRepresentationID: GeometryRepresentationID =
            "representation.closed-presentation"
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
        _ = try document.validate()
        return document
    }
}

private func closedAccessRepresentationSet(
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

private func closedAccessTriangleMesh(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addTriangle(first, second, third)
    return try builder.build()
}

private func closedAccessMeshCatalog(
    session: any ProjectAccessSession,
    generation: DocumentGeneration
) async throws -> ProjectMeshCatalog {
    let response = try await session.send(
        .meshCatalog(
            AgentMeshCatalogRequest(
                sessionID: session.sessionID,
                expectedGeneration: generation
            )
        )
    )
    guard case .meshCatalog(let result) = response else {
        throw EditorError(
            code: .commandFailed,
            message: "Closed access did not return a Mesh catalog."
        )
    }
    return result.catalog
}

private func closedAccessMeshVertexRecords(
    session: any ProjectAccessSession,
    catalog: ProjectMeshCatalog,
    generation: DocumentGeneration
) async throws -> [ProjectMeshElementRecord] {
    var records: [ProjectMeshElementRecord] = []
    for source in catalog.sources.sorted(by: { $0.sourceID.rawValue < $1.sourceID.rawValue }) {
        let response = try await session.send(
            .meshPage(
                AgentMeshPageRequest(
                    sessionID: session.sessionID,
                    expectedGeneration: generation,
                    handle: source.handle,
                    domain: .vertex
                )
            )
        )
        guard case .meshPage(let result) = response else {
            throw EditorError(
                code: .commandFailed,
                message: "Closed access did not return a Mesh vertex page."
            )
        }
        records.append(contentsOf: result.page.records)
    }
    return records
}

private func closedAccessViewport(
    session: any ProjectAccessSession,
    generation: DocumentGeneration
) async throws -> AgentProjectViewportSnapshot {
    let response = try await session.send(
        .viewportSnapshot(
            sessionID: session.sessionID,
            expectedGeneration: generation
        )
    )
    guard case .viewportSnapshot(let snapshot) = response else {
        throw EditorError(
            code: .commandFailed,
            message: "Closed access did not return a viewport snapshot."
        )
    }
    return snapshot
}

private func expectCatalog(
    _ catalog: ProjectMeshCatalog,
    matches assets: [GeometrySourceID: AuthoredMeshAsset],
    document: DesignDocument
) throws {
    #expect(Set(catalog.sources.map(\.sourceID)) == Set(assets.keys))
    let expectedReferences = closedAccessMeshReferences(in: document)
    for source in catalog.sources {
        guard let asset = assets[source.sourceID] else {
            Issue.record("The Mesh catalog returned an unexpected source identity.")
            continue
        }
        #expect(source.contentIdentity == asset.contentIdentity)
        #expect(source.provenance == asset.provenance)
        #expect(source.counts.vertices == asset.source.vertexIDs.count)
        #expect(source.counts.edges == asset.source.edgeIDs.count)
        #expect(source.counts.faces == asset.source.faceIDs.count)
        #expect(source.counts.corners == asset.source.cornerIDs.count)
        let expected = expectedReferences[source.sourceID] ?? []
        #expect(source.references.count == expected.count)
        for reference in expected {
            let actual = source.references.first {
                $0.sceneNodeID == reference.sceneNodeID
                    && $0.representationID == reference.representationID
            }
            #expect(actual?.selectedPurposes == reference.selectedPurposes)
        }
    }
}

private func closedAccessMeshReferences(
    in document: DesignDocument
) -> [GeometrySourceID: [ProjectMeshCatalogReference]] {
    var references: [GeometrySourceID: [ProjectMeshCatalogReference]] = [:]
    for (sceneNodeID, sceneNode) in document.productMetadata.sceneNodes {
        guard let object = sceneNode.object else {
            continue
        }
        for (representationID, representation) in object.geometryRepresentations.representations {
            guard case .authoredMesh(let sourceID) = representation.source else {
                continue
            }
            var selectedPurposes: [GeometryRepresentationPurpose] = []
            if object.geometryRepresentations.selection?.modeling == representationID {
                selectedPurposes.append(.modeling)
            }
            if object.geometryRepresentations.selection?.presentation == representationID {
                selectedPurposes.append(.presentation)
            }
            references[sourceID, default: []].append(
                ProjectMeshCatalogReference(
                    sceneNodeID: sceneNodeID,
                    representationID: representationID,
                    selectedPurposes: selectedPurposes
                )
            )
        }
    }
    return references
}

@MainActor
private func withAccessLease<Result>(
    _ lease: ProjectFileAuthorityLease,
    operation: @MainActor () async throws -> Result
) async throws -> Result {
    do {
        let result = try await operation()
        await lease.release()
        return result
    } catch {
        await lease.release()
        throw error
    }
}

private func makeAccessTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("RupaProjectAccessComposition-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func removeAccessTemporaryDirectory(_ directory: URL) {
    do {
        try FileManager.default.removeItem(at: directory)
    } catch {
        Issue.record("Failed to remove access test directory: \(error)")
    }
}

private actor AccessRegistrationGate {
    private var hasEntered = false
    private var hasReleased = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enter() {
        hasEntered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilEntered() async {
        if hasEntered {
            return
        }
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            enteredWaiters.append(continuation)
        }
    }

    func release() {
        hasReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilReleased() async {
        if hasReleased {
            return
        }
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            releaseWaiters.append(continuation)
        }
    }
}
