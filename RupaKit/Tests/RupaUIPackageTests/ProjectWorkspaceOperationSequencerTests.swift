import RupaCore
import RupaKit
import RupaProject
import RupaRendering
import Synchronization
import Testing
@testable import RupaUI

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectWorkspaceOperationSequencerCoalescesOnlyConsecutivePendingEdits() async throws {
    let sequencer = ProjectWorkspaceOperationSequencer()
    var release: CheckedContinuation<Void, Never>?
    var events: [String] = []
    let running = sequencer.enqueue {
        events.append("running")
        await withCheckedContinuation { release = $0 }
        events.append("finished")
    }
    while release == nil { await Task.yield() }
    for value in 1...1_000 {
        sequencer.enqueueReplacingPending(key: "x") { events.append("x:\(value)") }
    }
    sequencer.enqueueReplacingPending(key: "y") { events.append("y") }
    sequencer.enqueueReplacingPending(key: "x") { events.append("x:after-y") }
    let barrier = sequencer.enqueue { events.append("undo") }
    sequencer.enqueueReplacingPending(key: "x") { events.append("x:after-undo") }
    #expect(events == ["running"])
    release?.resume()
    _ = try await running.value
    _ = try await barrier.value
    try await sequencer.run {}
    #expect(events == ["running", "finished", "x:1000", "y", "x:after-y", "undo", "x:after-undo"])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectWorkspaceOperationSequencerCoalescedTransformsPublishAndUndo() async throws {
    let node = SceneNode(name: "Object")
    var document = DesignDocument.empty(named: "Live Edits")
    document.productMetadata = ProductMetadata(sceneNodes: [node.id: node], rootSceneNodeIDs: [node.id])
    let controller = try ProjectController(document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(), projector: DesignDocumentProjectBridge())
    let workspace = ProjectWorkspace(project: controller)
    _ = try await workspace.evaluate()
    let initial = try #require(workspace.view)
    let sequencer = ProjectWorkspaceOperationSequencer()
    var commits = 0
    var failures = 0
    func edit(_ component: InspectorTransformComponent, _ value: Double) {
        sequencer.enqueueReplacingPending(key: component) {
            do {
                let current = try #require(workspace.view)
                let commands = try WorkspaceTransformMatrix.commands(replacing: component,
                    with: value, nodeIDs: [node.id], in: current.document.document)
                let action = try DefaultProjectWorkspaceActionPlanner().source(
                    name: "Transform Objects", commands: commands, from: current)
                _ = try await workspace.perform(action)
                commits += 1
            } catch { failures += 1 }
        }
    }
    for value in 1...1_000 { edit(.translationX, Double(value)) }
    edit(.translationY, 2)
    edit(.scaleZ, .nan)
    edit(.translationZ, 3)
    try await sequencer.run {}
    #expect(commits == 3)
    #expect(failures == 1)
    let final = try #require(workspace.view?.document.document.productMetadata.sceneNodes[node.id])
    let components = try WorkspaceTransformMatrix.components(of: final.localTransform)
    #expect(components.translation.x == 1_000)
    #expect(components.translation.y == 2)
    #expect(components.translation.z == 3)
    #expect(components.scale.z == 1)
    for _ in 0..<3 { _ = try await workspace.undo() }
    #expect(workspace.view?.document.document.productMetadata == initial.document.document.productMetadata)
    _ = try await workspace.redo()
    let redone = try #require(workspace.view?.document.document.productMetadata.sceneNodes[node.id])
    #expect(try WorkspaceTransformMatrix.components(of: redone.localTransform).translation.x == 1_000)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectWorkspaceOperationSequencerPreservesSubmissionOrderAcrossSuspension() async throws {
    let sequencer = ProjectWorkspaceOperationSequencer()
    var events: [String] = []
    var publishedValue = 0
    var releaseFirst: CheckedContinuation<Void, Never>?

    let first = Task { @MainActor in
        try await sequencer.run {
            events.append("first.started")
            await withCheckedContinuation { continuation in
                releaseFirst = continuation
            }
            events.append("first.finished")
            publishedValue = 1
            return 1
        }
    }
    while releaseFirst == nil {
        await Task.yield()
    }

    let second = Task { @MainActor in
        try await sequencer.run {
            events.append("second.started")
            #expect(publishedValue == 1)
            publishedValue = 2
            return 2
        }
    }
    await Task.yield()
    #expect(events == ["first.started"])

    releaseFirst?.resume()
    #expect(try await first.value == 1)
    #expect(try await second.value == 2)
    #expect(events == ["first.started", "first.finished", "second.started"])
    #expect(publishedValue == 2)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectWorkspaceOperationSequencerReservesSameTurnEnqueueOrder() async throws {
    let sequencer = ProjectWorkspaceOperationSequencer()
    var events: [String] = []

    let first = sequencer.enqueue {
        events.append("first")
        return 1
    }
    let second = sequencer.enqueue {
        events.append("second")
        return 2
    }

    #expect(try await first.value == 1)
    #expect(try await second.value == 2)
    #expect(events == ["first", "second"])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectWorkspaceOperationSequencerRejectsQueuedIntentAfterLifetimeGuardChanges() async throws {
    let sequencer = ProjectWorkspaceOperationSequencer()
    var releaseFirst: CheckedContinuation<Void, Never>?
    let acceptsQueuedIntent = Mutex(true)
    let queuedIntentDidRun = Mutex(false)

    let first = sequencer.enqueue {
        await withCheckedContinuation { continuation in
            releaseFirst = continuation
        }
    }
    while releaseFirst == nil {
        await Task.yield()
    }
    let queued = sequencer.enqueue(
        operationGuard: {
            guard acceptsQueuedIntent.withLock({ $0 }) else {
                throw ProjectWorkspaceActionError(
                    code: .documentLifetimeMismatch,
                    message: "Fixture document lifetime changed."
                )
            }
        }
    ) {
        queuedIntentDidRun.withLock { $0 = true }
    }

    acceptsQueuedIntent.withLock { $0 = false }
    releaseFirst?.resume()
    _ = try await first.value
    var caught: ProjectWorkspaceActionError?
    do {
        _ = try await queued.value
    } catch let error as ProjectWorkspaceActionError {
        caught = error
    }

    #expect(caught?.code == .documentLifetimeMismatch)
    #expect(queuedIntentDidRun.withLock { $0 } == false)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectWorkspaceOperationSequencerRebasesQueuedSavedViewNames() async throws {
    let controller = try ProjectController(
        document: .empty(named: "Saved Views"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: controller)
    _ = try await workspace.evaluate()
    let sequencer = ProjectWorkspaceOperationSequencer()
    let builder = WorkspaceSavedViewBuilder()

    func enqueueCreate() -> Task<ProjectViewSnapshot, Error> {
        sequencer.enqueue {
            let current = try #require(workspace.view)
            let savedView = builder.makeSavedView(
                name: builder.nextSavedViewName(in: current.document.document),
                workspaceState: current.workspaceState,
                projectionBasis: .isometric
            )
            let action = try DefaultProjectWorkspaceActionPlanner().source(
                name: "test.createSavedView",
                commands: [.createSavedView(savedView)],
                from: current
            )
            _ = try await workspace.perform(action)
            return try #require(workspace.view)
        }
    }

    let first = enqueueCreate()
    let second = enqueueCreate()
    _ = try await first.value
    let final = try await second.value
    let names = Set(final.document.document.productMetadata.savedViews.values.map(\.name))

    #expect(names == ["View 1", "View 2"])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectWorkspaceOperationSequencerRebasesQueuedRulerFieldUpdates() async throws {
    let controller = try ProjectController(
        document: .empty(named: "Ruler"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: controller)
    _ = try await workspace.evaluate()
    let sequencer = ProjectWorkspaceOperationSequencer()

    let first = sequencer.enqueue {
        let current = try #require(workspace.view)
        var ruler = current.workspaceState.ruler
        ruler.minorTickMeters = 0.002
        return try await workspace.applyWorkspace(.setRulerConfiguration(ruler))
    }
    let second = sequencer.enqueue {
        let current = try #require(workspace.view)
        var ruler = current.workspaceState.ruler
        ruler.majorTickMeters = 0.02
        return try await workspace.applyWorkspace(.setRulerConfiguration(ruler))
    }

    _ = try await first.value
    let final = try await second.value
    #expect(final.workspaceState.ruler.minorTickMeters == 0.002)
    #expect(final.workspaceState.ruler.majorTickMeters == 0.02)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectWorkspaceOperationSequencerResolvesConstructionPlaneTargetsAfterQueuedSelection() async throws {
    let session = EditorSession()
    _ = try session.execute(.createConstructionPlane(name: "Plane A", plane: .xy))
    _ = try session.execute(.createConstructionPlane(name: "Plane B", plane: .yz))
    let controller = try ProjectController(
        document: session.document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: controller)
    _ = try await workspace.evaluate()
    let initial = try #require(workspace.view)
    let summary = ConstructionPlaneSummaryService().summarize(
        document: initial.document.document,
        activePlaneID: initial.workspaceState.activeConstructionPlaneID
    )
    let targetA = try #require(summary.planes.first { $0.name == "Plane A" }?.selectionTarget())
    let targetB = try #require(summary.planes.first { $0.name == "Plane B" }?.selectionTarget())
    var selectionA = initial.selection
    try selectionA.selectTarget(targetA, in: initial.document.document)
    _ = try await workspace.applySelection(.replace(selectionA))
    let sequencer = ProjectWorkspaceOperationSequencer()

    let publishSelectionB = sequencer.enqueue {
        let current = try #require(workspace.view)
        var selectionB = current.selection
        try selectionB.selectTarget(targetB, in: current.document.document)
        return try await workspace.applySelection(.replace(selectionB))
    }
    let createFromCurrentSelection = sequencer.enqueue {
        let current = try #require(workspace.view)
        let targets = try #require(WorkspaceConstructionPlaneTargetSelectionBuilder(
            document: current.document.document,
            selection: current.selection
        ).constructionPlaneTargets)
        #expect(targets == [targetB])
        let action = try DefaultProjectWorkspaceActionPlanner().source(
            name: "test.createConstructionPlaneFromCurrentSelection",
            commands: [
                .createConstructionPlaneFromTargets(
                    name: "Copied Current Plane",
                    targets: targets,
                    viewNormal: nil
                ),
            ],
            from: current
        )
        _ = try await workspace.perform(action)
        return try #require(workspace.view)
    }

    _ = try await publishSelectionB.value
    let final = try await createFromCurrentSelection.value
    let created = try #require(final.document.document.productMetadata.constructionPlanes.values.first {
        $0.name == "Copied Current Plane"
    })
    guard case .plane(let createdPlane) = created.plane else {
        Issue.record("The copied current plane must preserve Plane B's resolved orientation.")
        return
    }
    #expect(createdPlane.normal == .unitX)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectWorkspaceOperationSequencerParsesDependentParametersFromCurrentSource() async throws {
    let controller = try ProjectController(
        document: .empty(named: "Parameters"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: controller)
    _ = try await workspace.evaluate()
    let sequencer = ProjectWorkspaceOperationSequencer()

    func enqueueUpsert(
        name: String,
        expression: String
    ) -> Task<ProjectViewSnapshot, Error> {
        sequencer.enqueue {
            let current = try #require(workspace.view)
            let parsed = try ParameterExpressionParser().parseForUpsert(
                expression,
                parameterName: name,
                parameters: current.document.document.cadDocument.parameters,
                targetKind: .length,
                defaults: ParameterExpressionDefaults(
                    lengthUnit: current.workspaceState.displayUnit,
                    angleUnit: .degree
                )
            )
            let action = try DefaultProjectWorkspaceActionPlanner().source(
                name: "test.upsertParameter",
                commands: [.upsertParameter(name: name, expression: parsed, kind: .length)],
                from: current
            )
            _ = try await workspace.perform(action)
            return try #require(workspace.view)
        }
    }

    let width = enqueueUpsert(name: "width", expression: "10 mm")
    let doubleWidth = enqueueUpsert(name: "doubleWidth", expression: "width * 2")
    _ = try await width.value
    let final = try await doubleWidth.value
    let parameter = try #require(
        final.document.document.cadDocument.parameters.parameters.values.first {
            $0.name == "doubleWidth"
        }
    )
    let resolved = try final.document.document.cadDocument.parameters.resolvedValue(
        for: parameter.expression
    )

    #expect(abs(resolved.value - 0.02) < 1.0e-12)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectWorkspaceOperationSequencerFitsScaleFromCurrentPublishedPresentation() async throws {
    let controller = try ProjectController(
        document: .empty(named: "Scale Fit"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: controller)
    _ = try await workspace.evaluate()
    let sequencer = ProjectWorkspaceOperationSequencer()

    let createLargeGeometry = sequencer.enqueue {
        let current = try #require(workspace.view)
        let action = try DefaultProjectWorkspaceActionPlanner().source(
            name: "test.createLargeGeometry",
            commands: [
                .createExtrudedRectangle(
                    name: "Large Site",
                    plane: .xy,
                    width: .length(25_000.0, .meter),
                    height: .length(10_000.0, .meter),
                    depth: .length(100.0, .meter),
                    direction: .normal
                ),
            ],
            from: current
        )
        _ = try await workspace.perform(action)
        return try #require(workspace.view)
    }
    let fitCurrentPresentation = sequencer.enqueue {
        let current = try #require(workspace.view)
        let plan = WorkspaceScaleFitService().plan(
            bounds: current.viewport.worldBounds.map {
                MeasurementResult.Bounds(
                    minX: $0.minimum.x,
                    minY: $0.minimum.y,
                    minZ: $0.minimum.z,
                    maxX: $0.maximum.x,
                    maxY: $0.maximum.y,
                    maxZ: $0.maximum.z
                )
            },
            ruler: current.workspaceState.ruler
        )
        guard case .applyPreset(let preset) = plan.action else {
            Issue.record("Current large presentation must require a scale preset.")
            return current
        }
        return try await workspace.applyWorkspace(
            .setRulerConfiguration(preset.rulerConfiguration.normalizedForWorkspaceScale())
        )
    }

    _ = try await createLargeGeometry.value
    let final = try await fitCurrentPresentation.value
    #expect(final.workspaceState.ruler == WorkspaceScalePreset.sitePlanning.rulerConfiguration)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectWorkspaceOperationSequencerAppliesCurrentSavedViewAfterQueuedUpdate() async throws {
    let controller = try ProjectController(
        document: .empty(named: "Saved View Apply"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: controller)
    _ = try await workspace.evaluate()
    let initial = try #require(workspace.view)
    let builder = WorkspaceSavedViewBuilder()
    let savedView = builder.makeSavedView(
        name: "Current View",
        workspaceState: initial.workspaceState,
        projectionBasis: .isometric
    )
    let createAction = try DefaultProjectWorkspaceActionPlanner().source(
        name: "test.createSavedView",
        commands: [.createSavedView(savedView)],
        from: initial
    )
    _ = try await workspace.perform(createAction)
    var updatedSavedView = savedView
    updatedSavedView.name = "Updated View"
    updatedSavedView.displayScale = SavedViewDisplayScale(
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )
    let sequencer = ProjectWorkspaceOperationSequencer()

    let update = sequencer.enqueue {
        let current = try #require(workspace.view)
        let action = try DefaultProjectWorkspaceActionPlanner().source(
            name: "test.updateSavedView",
            commands: [.updateSavedView(updatedSavedView)],
            from: current
        )
        _ = try await workspace.perform(action)
        return try #require(workspace.view)
    }
    let applyCurrent = sequencer.enqueue {
        let current = try #require(workspace.view)
        let resolved = try #require(
            current.document.document.productMetadata.savedViews[savedView.id]
        )
        return try await workspace.applyWorkspace(
            .setRulerConfiguration(resolved.displayScale.rulerConfiguration)
        )
    }

    _ = try await update.value
    let final = try await applyCurrent.value
    #expect(final.workspaceState.ruler == WorkspaceScalePreset.sitePlanning.rulerConfiguration)
    #expect(final.document.document.productMetadata.savedViews[savedView.id]?.name == "Updated View")
}
