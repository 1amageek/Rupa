import Foundation
import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProjectModel
import RupaViewportScene
import Synchronization
import Testing
@testable import RupaRendering

// MARK: - Off-actor preparation

@MainActor
@Test(.timeLimit(.minutes(1)))
func planPreparationRunsOffTheMainActor() async throws {
    let scene = try planCacheScene(suffix: "off-main")
    let hasStarted = Mutex(false)
    let mayFinish = Mutex(false)
    let cache = MeshSourcePresentationPlanCache { scene in
        hasStarted.withLock { $0 = true }
        // Spin without suspending. A build that ran on `MainActor` could never
        // observe the release below, because only `MainActor` publishes it, so
        // this loop is what proves the build left `MainActor`.
        while mayFinish.withLock({ $0 }) == false {
            continue
        }
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }

    cache.prepare(for: scene)
    #expect(cache.isPreparing(scene))
    #expect(cache.plan(for: scene) == nil)

    while hasStarted.withLock({ $0 }) == false {
        await Task.yield()
    }
    mayFinish.withLock { $0 = true }

    try await settlePlanCache(cache)
    #expect(cache.plan(for: scene) != nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planPreparationDoesNotCompleteOnTheCallingActor() async throws {
    let scene = try planCacheScene(suffix: "not-synchronous")
    let cache = MeshSourcePresentationPlanCache()

    cache.prepare(for: scene)

    guard case let .preparing(snapshotID) = cache.state else {
        Issue.record("Plan preparation must not complete on the calling actor.")
        return
    }
    #expect(snapshotID == scene.snapshotID)
    #expect(cache.plan(for: scene) == nil)
    #expect(cache.failure(for: scene) == nil)

    try await settlePlanCache(cache)
    #expect(cache.plan(for: scene) != nil)
}

// MARK: - Identity

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheExposesReadyPlanOnlyToItsOwnScene() async throws {
    let scene = try planCacheScene(suffix: "identity")
    let otherScene = try planCacheScene(suffix: "identity-other")
    let cache = MeshSourcePresentationPlanCache()

    cache.prepare(for: scene)
    try await settlePlanCache(cache)

    #expect(cache.plan(for: scene) != nil)
    #expect(cache.plan(for: otherScene) == nil)
    #expect(cache.isPreparing(otherScene) == false)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheIgnoresARepeatedPrepareForTheSameScene() async throws {
    let scene = try planCacheScene(suffix: "repeat")
    let buildCount = Mutex(0)
    let cache = MeshSourcePresentationPlanCache { scene in
        buildCount.withLock { $0 += 1 }
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }

    cache.prepare(for: scene)
    cache.prepare(for: scene)
    try await settlePlanCache(cache)
    cache.prepare(for: scene)
    await Task.yield()

    #expect(buildCount.withLock { $0 } == 1)
    #expect(cache.plan(for: scene) != nil)
}

// MARK: - Staleness

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheDiscardsAStaleSuccess() async throws {
    let firstScene = try planCacheScene(suffix: "stale-success-first")
    let secondScene = try planCacheScene(suffix: "stale-success-second")
    let gate = PlanBuildGate()
    let cache = MeshSourcePresentationPlanCache { scene in
        await gate.arrive(scene.snapshotID.projectID.rawValue)
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }

    cache.prepare(for: firstScene)
    await gate.waitForArrival(firstScene.snapshotID.projectID.rawValue)

    // The scene changes while the first build is parked at the gate.
    cache.prepare(for: secondScene)
    #expect(cache.isPreparing(secondScene))

    // Releasing the superseded build must publish nothing.
    await gate.open(firstScene.snapshotID.projectID.rawValue)
    await Task.yield()
    #expect(cache.plan(for: firstScene) == nil)
    #expect(cache.isPreparing(secondScene))

    await gate.open(secondScene.snapshotID.projectID.rawValue)
    try await settlePlanCache(cache)
    #expect(cache.plan(for: secondScene) != nil)
    #expect(cache.plan(for: firstScene) == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheDiscardsAStaleFailure() async throws {
    let firstScene = try planCacheScene(suffix: "stale-failure-first")
    let secondScene = try planCacheScene(suffix: "stale-failure-second")
    let failingProjectID = firstScene.snapshotID.projectID.rawValue
    let gate = PlanBuildGate()
    let cache = MeshSourcePresentationPlanCache { scene in
        await gate.arrive(scene.snapshotID.projectID.rawValue)
        if scene.snapshotID.projectID.rawValue == failingProjectID {
            throw MeshSourcePresentationRenderError(
                code: .failed,
                message: "Superseded build failed."
            )
        }
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }

    cache.prepare(for: firstScene)
    await gate.waitForArrival(failingProjectID)
    cache.prepare(for: secondScene)

    await gate.open(failingProjectID)
    await Task.yield()
    #expect(cache.failure(for: firstScene) == nil)
    #expect(cache.isPreparing(secondScene))

    await gate.open(secondScene.snapshotID.projectID.rawValue)
    try await settlePlanCache(cache)
    #expect(cache.plan(for: secondScene) != nil)
}

// MARK: - Failure

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCachePublishesAMatchingFailure() async throws {
    let scene = try planCacheScene(suffix: "failure")
    let cache = MeshSourcePresentationPlanCache { _ in
        throw MeshSourcePresentationRenderError(
            code: .resourceExhausted,
            message: "Presentation plan exceeded its ceiling."
        )
    }

    cache.prepare(for: scene)
    try await settlePlanCacheFailure(cache)

    let failure = try #require(cache.failure(for: scene))
    #expect(failure.code == .resourceExhausted)
    #expect(cache.plan(for: scene) == nil)
    #expect(cache.isPreparing(scene) == false)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheRecordsNothingForACancelledBuild() async throws {
    let scene = try planCacheScene(suffix: "cancelled")
    let cache = MeshSourcePresentationPlanCache { _ in
        throw CancellationError()
    }

    cache.prepare(for: scene)
    for _ in 0..<32 {
        await Task.yield()
    }

    // A cancellation is not a failure, so the state stays `preparing` until a
    // newer scene or a teardown replaces it.
    #expect(cache.isPreparing(scene))
    #expect(cache.failure(for: scene) == nil)
    #expect(cache.plan(for: scene) == nil)
}

// MARK: - Cancellation and teardown

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheCancelsTheBuildASceneChangeSupersedes() async throws {
    let firstScene = try planCacheScene(suffix: "cancel-first")
    let secondScene = try planCacheScene(suffix: "cancel-second")
    let gate = PlanBuildGate()
    let observedCancellation = Mutex(false)
    let cache = MeshSourcePresentationPlanCache { scene in
        await gate.arrive(scene.snapshotID.projectID.rawValue)
        if Task.isCancelled {
            observedCancellation.withLock { $0 = true }
            throw CancellationError()
        }
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }

    cache.prepare(for: firstScene)
    await gate.waitForArrival(firstScene.snapshotID.projectID.rawValue)
    cache.prepare(for: secondScene)
    await gate.open(firstScene.snapshotID.projectID.rawValue)
    await gate.open(secondScene.snapshotID.projectID.rawValue)
    try await settlePlanCache(cache)

    #expect(observedCancellation.withLock { $0 })
    #expect(cache.plan(for: secondScene) != nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheTeardownReturnsToIdleAndDiscardsALaterCompletion() async throws {
    let scene = try planCacheScene(suffix: "teardown")
    let gate = PlanBuildGate()
    let cache = MeshSourcePresentationPlanCache { scene in
        await gate.arrive(scene.snapshotID.projectID.rawValue)
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }

    cache.prepare(for: scene)
    await gate.waitForArrival(scene.snapshotID.projectID.rawValue)
    cache.teardown()

    guard case .idle = cache.state else {
        Issue.record("Teardown must return the plan cache to idle.")
        return
    }

    await gate.open(scene.snapshotID.projectID.rawValue)
    for _ in 0..<32 {
        await Task.yield()
    }

    guard case .idle = cache.state else {
        Issue.record("A completion after teardown must be discarded.")
        return
    }
    #expect(cache.plan(for: scene) == nil)

    // A torn-down cache still accepts the same scene again.
    cache.prepare(for: scene)
    await gate.open(scene.snapshotID.projectID.rawValue)
    try await settlePlanCache(cache)
    #expect(cache.plan(for: scene) != nil)
}

// MARK: - Support

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheCoalescesAndRejectsFailureFromARestartedSnapshot() async throws {
    let scene = try planCacheScene(suffix: "restart")
    let skipped = try planCacheScene(suffix: "skipped")
    let gate = PlanBuildGate()
    let started = Mutex(0)
    let cache = MeshSourcePresentationPlanCache { scene in
        let index = started.withLock { count in
            count += 1
            return count
        }
        await gate.arrive(String(index))
        if index == 1 {
            throw MeshSourcePresentationRenderError(code: .failed, message: "Abandoned worker failure.")
        }
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }
    cache.prepare(for: scene)
    await gate.waitForArrival("1")
    cache.teardown()
    cache.prepare(for: skipped)
    cache.prepare(for: scene)
    await gate.open("1")
    await gate.waitForArrival("2")
    #expect(cache.isPreparing(scene))
    #expect(cache.failure(for: scene) == nil)
    #expect(started.withLock { $0 } == 2)
    await gate.open("2")
    try await settlePlanCache(cache)
    #expect(cache.plan(for: scene) != nil)
    #expect(cache.surface(for: scene) != nil)
    #expect(started.withLock { $0 } == 2)
}

/// Parks each build until the test opens its key, so staleness, cancellation,
/// and teardown are decided by the test rather than by construction timing.
private actor PlanBuildGate {
    private var openedKeys: Set<String> = []
    private var arrivedKeys: Set<String> = []
    private var releaseWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var arrivalWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func arrive(_ key: String) async {
        arrivedKeys.insert(key)
        if let waiters = arrivalWaiters.removeValue(forKey: key) {
            for waiter in waiters {
                waiter.resume()
            }
        }
        if openedKeys.contains(key) {
            return
        }
        await withCheckedContinuation { continuation in
            releaseWaiters[key, default: []].append(continuation)
        }
    }

    func open(_ key: String) {
        openedKeys.insert(key)
        if let waiters = releaseWaiters.removeValue(forKey: key) {
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitForArrival(_ key: String) async {
        if arrivedKeys.contains(key) {
            return
        }
        await withCheckedContinuation { continuation in
            arrivalWaiters[key, default: []].append(continuation)
        }
    }
}

@MainActor
private func settlePlanCache(
    _ cache: MeshSourcePresentationPlanCache
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if case .ready = cache.state {
            return
        }
        if case let .failed(_, error) = cache.state {
            throw error
        }
        // GPU preparation can include cold shader compilation. Scheduler yield
        // counts are not a duration budget and can expire before that work runs.
        try await Task.sleep(for: .milliseconds(1))
    }
    throw MeshSourcePresentationRenderError(
        code: .failed,
        message: "The plan cache did not reach a ready state."
    )
}

@MainActor
private func settlePlanCacheFailure(
    _ cache: MeshSourcePresentationPlanCache
) async throws {
    for _ in 0..<10_000 {
        if case .failed = cache.state {
            return
        }
        await Task.yield()
    }
    throw MeshSourcePresentationRenderError(
        code: .failed,
        message: "The plan cache did not reach a failed state."
    )
}

private func planCacheScene(suffix: String) throws -> UniversalViewportScene {
    let projectID = ProjectID(rawValue: "project.plan-cache.\(suffix)")
    let sourceID = GeometrySourceID(rawValue: "mesh.plan-cache.\(suffix)")
    let definitionID = ObjectDefinitionID(rawValue: "object.plan-cache.\(suffix)")
    let representationID = GeometryRepresentationID(
        rawValue: "representation.plan-cache.\(suffix)"
    )
    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.plan-cache.\(suffix)")
    let reference = GeometrySourceReference.authoredMesh(sourceID)

    var builder = MeshSourceBuilder(identity: sourceID)
    try builder.reserveCapacity(vertexCount: 4, faceCount: 1, cornerCount: 4)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let fourth = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third, fourth])
    let source = try builder.build()

    let transform = try GeometryTransform3D(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ])
    let project = try ProjectSourceModel(
        id: projectID,
        name: "Plan cache",
        authoredMeshAssets: [
            sourceID: try AuthoredMeshAsset(source: source, provenance: .created)
        ],
        objectDefinitions: [
            definitionID: ObjectDefinition(
                id: definitionID,
                name: "Plan cache \(suffix)",
                representations: GeometryRepresentationSet(
                    representations: [
                        representationID: GeometryRepresentation(
                            id: representationID,
                            source: reference
                        )
                    ],
                    selection: GeometryRepresentationSelection(
                        modeling: representationID,
                        presentation: representationID
                    )
                )
            )
        ],
        occurrences: [
            occurrenceID: SceneOccurrence(id: occurrenceID, definitionID: definitionID)
        ],
        rootOccurrenceIDs: [occurrenceID]
    )
    let snapshot = EvaluatedProjectSnapshot(
        id: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        occurrences: [
            occurrenceID: EvaluatedOccurrenceSnapshot(
                occurrenceID: occurrenceID,
                definitionID: definitionID,
                representationID: representationID,
                reference: reference,
                mesh: source,
                worldTransform: transform,
                worldBounds: try source.bounds().transformed(by: transform)
            )
        ],
        copyTelemetry: GeometryCopyTelemetry()
    )
    return try UniversalViewportSceneBuilder().build(from: snapshot, project: project)
}
