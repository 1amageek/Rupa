import RupaCore
import RupaKit
import RupaProject
import RupaRendering
import Testing
@testable import RupaUI

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
