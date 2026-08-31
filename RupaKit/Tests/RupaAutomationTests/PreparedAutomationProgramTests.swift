import SwiftCAD
import Testing
import RupaCore
@testable import RupaAutomation

@MainActor
@Test(.timeLimit(.minutes(1)))
func preparedProgramRejectsInactiveSessionBeforeResolvingOrMutating() throws {
    let program = try makeSingleBoxProgram()
    let session = EditorSession()
    let initialDocument = session.document
    let initialGeneration = session.generation

    var caught: PreparedAutomationExecutionError?
    do {
        _ = try DefaultPreparedAutomationProgramExecutor().execute(
            program,
            in: session
        )
    } catch let error as PreparedAutomationExecutionError {
        caught = error
    }

    #expect(caught == .inactiveSourceCommandGroup)
    #expect(documentsMatch(session.document, initialDocument))
    #expect(session.generation == initialGeneration)
    #expect(session.commandStack.undoEntries.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func preparedProgramCreatesAndReferencesAllSourceIdentityKinds() throws {
    let box = PreparedAutomationStep(
        outputs: [
            output("sketch", .feature(index: 0)),
            output("body", .feature(index: 1)),
            output("body-output", .sourceBody(role: .body, index: 0)),
            output("body-scene", .sceneNode(index: 0)),
            output("sketch-scene", .sceneNode(index: 1)),
        ],
        estimatedGeneratedSourceWork: 5,
        commandBuilder: PreparedAutomationCommandBuilder(name: "create-box") { _ in
            try ContextResolvedEditorCommand(validating: .createExtrudedRectangle(
                name: "Prepared Box",
                plane: .xy,
                width: .length(0.1, .meter),
                height: .length(0.2, .meter),
                depth: .length(0.3, .meter),
                direction: .normal
            ))
        }
    )
    let definition = PreparedAutomationStep(
        inputs: [
            input("source-scene", .sceneNode, local: "body-scene"),
            input("source-body", .sourceBody(role: .body), local: "body-output"),
        ],
        outputs: [output("definition", .componentDefinition(index: 0))],
        estimatedGeneratedSourceWork: 1,
        commandBuilder: PreparedAutomationCommandBuilder(name: "create-definition") { inputs in
            let sceneNodeID = try inputs.sceneNodeID(for: slot("source-scene"))
            _ = try inputs.sourceBody(for: slot("source-body"))
            return try ContextResolvedEditorCommand(validating: .createComponentDefinition(
                name: "Prepared Definition",
                rootSceneNodeIDs: [sceneNodeID]
            ))
        }
    )
    let instance = PreparedAutomationStep(
        inputs: [input("definition-input", .componentDefinition, local: "definition")],
        outputs: [
            output("instance", .componentInstance(index: 0)),
            output("instance-scene", .sceneNode(index: 0)),
        ],
        estimatedGeneratedSourceWork: 2,
        commandBuilder: PreparedAutomationCommandBuilder(name: "create-instance") { inputs in
            let definitionID = try inputs.componentDefinitionID(for: slot("definition-input"))
            return try ContextResolvedEditorCommand(validating: .createComponentInstance(
                name: "Prepared Instance",
                definitionID: definitionID,
                localTransform: .identity
            ))
        }
    )
    let pattern = PreparedAutomationStep(
        inputs: [input("pattern-definition", .componentDefinition, local: "definition")],
        outputs: [
            output("pattern", .patternArraySource(index: 0)),
            output("pattern-instance", .componentInstance(index: 0)),
            output("pattern-root", .sceneNode(index: 0)),
            output("pattern-instance-scene", .sceneNode(index: 1)),
        ],
        estimatedGeneratedSourceWork: 4,
        commandBuilder: PreparedAutomationCommandBuilder(name: "create-pattern") { inputs in
            let definitionID = try inputs.componentDefinitionID(for: slot("pattern-definition"))
            return try ContextResolvedEditorCommand(validating: .createPatternArray(
                name: "Prepared Pattern",
                definitionID: definitionID,
                distribution: .rectangular(RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(10, .millimeter),
                        copyCount: 1
                    )
                )),
                outputMode: .componentInstance
            ))
        }
    )
    let program = try PreparedAutomationProgram(
        steps: [box, definition, instance, pattern],
        limits: limits(
            steps: 4,
            inputs: 4,
            outputs: 12,
            commands: 4,
            generatedWork: 12
        )
    )
    let session = EditorSession()
    let receipt = try session.withSourceCommandGroup(named: "prepared-identities") { staged in
        try DefaultPreparedAutomationProgramExecutor().execute(program, in: staged)
    }

    #expect(receipt.stepReceipts.count == 4)
    #expect(receipt.outputBindings.count == 12)
    #expect(receipt.telemetry.stepCount == 4)
    #expect(receipt.telemetry.commandCount == 4)
    #expect(receipt.telemetry.generatedIdentityCount == 12)
    #expect(receipt.telemetry.generatedSourceWork == 12)
    #expect(receipt.outputBindings.contains { binding in
        binding.kind == .sourceBody(role: .body)
    })
    #expect(receipt.outputBindings.contains { binding in
        if case .componentDefinition = binding.identity { return true }
        return false
    })
    #expect(receipt.outputBindings.contains { binding in
        if case .componentInstance = binding.identity { return true }
        return false
    })
    #expect(receipt.outputBindings.contains { binding in
        if case .patternArraySource = binding.identity { return true }
        return false
    })
    #expect(session.document.productMetadata.componentDefinitions.count == 1)
    #expect(session.document.productMetadata.componentInstances.count == 2)
    #expect(session.document.productMetadata.patternArrays.count == 1)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func preparedProgramBindsSheetRoleWithoutEvaluatedTopologyIdentity() throws {
    let step = PreparedAutomationStep(
        outputs: [
            output("sheet-feature", .feature(index: 0)),
            output("sheet-source", .sourceBody(role: .sheet, index: 0)),
            output("sheet-scene", .sceneNode(index: 0)),
        ],
        estimatedGeneratedSourceWork: 3,
        commandBuilder: PreparedAutomationCommandBuilder(name: "create-sheet") { _ in
            try ContextResolvedEditorCommand(validating: .createBSplineSurface(
                name: "Prepared Sheet",
                surface: .cubicBezierPatch(
                    bottomLeft: Point3D(x: 0, y: 0, z: 0),
                    bottomRight: Point3D(x: 0.02, y: 0, z: 0),
                    topRight: Point3D(x: 0.02, y: 0.01, z: 0),
                    topLeft: Point3D(x: 0, y: 0.01, z: 0)
                )
            ))
        }
    )
    let program = try PreparedAutomationProgram(
        steps: [step],
        limits: limits(
            steps: 1,
            inputs: 0,
            outputs: 3,
            commands: 1,
            generatedWork: 3
        )
    )
    let session = EditorSession()
    let receipt = try session.withSourceCommandGroup(named: "prepared-sheet") { staged in
        try DefaultPreparedAutomationProgramExecutor().execute(program, in: staged)
    }

    #expect(receipt.outputBindings.contains { binding in
        binding.kind == .sourceBody(role: .sheet)
    })
    #expect(receipt.outputBindings.allSatisfy { binding in
        if case .sourceBody = binding.identity { return true }
        if case .feature = binding.identity { return true }
        if case .sceneNode = binding.identity { return true }
        return false
    })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func preparedProgramExecutesNativePatternAsOneStepForDifferentOccurrenceCounts() throws {
    let one = try executePatternProgram(copyCount: 1)
    let four = try executePatternProgram(copyCount: 4)

    #expect(one.telemetry.stepCount == 1)
    #expect(one.telemetry.commandCount == 1)
    #expect(four.telemetry.stepCount == 1)
    #expect(four.telemetry.commandCount == 1)
    #expect(one.stepReceipts.count == 1)
    #expect(four.stepReceipts.count == 1)
    #expect(one.outputBindings.count == 1)
    #expect(four.outputBindings.count == 1)
    #expect(one.telemetry.generatedSourceWork == 4)
    #expect(four.telemetry.generatedSourceWork == 10)
    #expect(one.stepReceipts[0].generatedIdentities.patternArraySourceIDs.count == 1)
    #expect(one.stepReceipts[0].generatedIdentities.componentInstanceIDs.count == 1)
    #expect(one.stepReceipts[0].generatedIdentities.sceneNodeIDs.count == 2)
    #expect(four.stepReceipts[0].generatedIdentities.patternArraySourceIDs.count == 1)
    #expect(four.stepReceipts[0].generatedIdentities.componentInstanceIDs.count == 4)
    #expect(four.stepReceipts[0].generatedIdentities.sceneNodeIDs.count == 5)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func preparedProgramLateBindingFailureRollsBackCallerSourceAndHistory() throws {
    let first = makeSheetStep(
        featureSlot: "created-feature",
        bodySlot: "created-sheet",
        sceneSlot: "created-scene"
    )
    let missingFeatureID = FeatureID()
    let second = PreparedAutomationStep(
        inputs: [input(
            "missing-feature-input",
            .feature,
            existing: .feature(missingFeatureID)
        )],
        estimatedGeneratedSourceWork: 0,
        commandBuilder: PreparedAutomationCommandBuilder(name: "late-failure") { inputs in
            let featureID = try inputs.featureID(for: slot("missing-feature-input"))
            return try ContextResolvedEditorCommand(validating: .setFeatureSuppression(
                featureID: featureID,
                isSuppressed: true
            ))
        }
    )
    let program = try PreparedAutomationProgram(
        steps: [first, second],
        limits: limits(
            steps: 2,
            inputs: 1,
            outputs: 3,
            commands: 2,
            generatedWork: 3
        )
    )
    let session = EditorSession()
    let initialDocument = session.document
    let initialGeneration = session.generation
    let initialEvaluation = session.evaluationSnapshot
    let initialHistoryCount = session.commandStack.undoEntries.count

    var caught: PreparedAutomationExecutionError?
    do {
        _ = try session.withSourceCommandGroup(named: "prepared-rollback") { staged in
            try DefaultPreparedAutomationProgramExecutor().execute(program, in: staged)
        }
    } catch let error as PreparedAutomationExecutionError {
        caught = error
    }

    #expect(caught != nil)
    #expect(documentsMatch(session.document, initialDocument))
    #expect(session.generation == initialGeneration)
    #expect(session.evaluationSnapshot == initialEvaluation)
    #expect(session.commandStack.undoEntries.count == initialHistoryCount)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func preparedProgramMissingSelectorAfterSuccessRollsBackCallerState() throws {
    let first = makeSheetStep(
        featureSlot: "created-feature",
        bodySlot: "created-sheet",
        sceneSlot: "created-scene"
    )
    let second = PreparedAutomationStep(
        outputs: [output("missing-definition", .componentDefinition(index: 0))],
        estimatedGeneratedSourceWork: 1,
        commandBuilder: PreparedAutomationCommandBuilder(name: "missing-selector") { _ in
            try ContextResolvedEditorCommand(validating: .createConstructionPlane(
                name: "Missing Selector Plane",
                plane: .zx
            ))
        }
    )
    let program = try PreparedAutomationProgram(
        steps: [first, second],
        limits: limits(steps: 2, inputs: 0, outputs: 4, commands: 2, generatedWork: 4)
    )
    let session = EditorSession()
    let initialDocument = session.document
    let initialGeneration = session.generation
    let initialEvaluation = session.evaluationSnapshot
    let initialHistoryCount = session.commandStack.undoEntries.count

    var caught: PreparedAutomationExecutionError?
    do {
        _ = try session.withSourceCommandGroup(named: "missing-selector-rollback") { staged in
            try DefaultPreparedAutomationProgramExecutor().execute(program, in: staged)
        }
    } catch let error as PreparedAutomationExecutionError {
        caught = error
    }

    if case .generatedIdentityMissing(
        stepIndex: 1,
        selector: .componentDefinition(index: 0)
    ) = caught {
        // The second command completed, but its declared selector was absent.
    } else {
        Issue.record("Expected a missing generated selector, got \(String(describing: caught)).")
    }
    #expect(documentsMatch(session.document, initialDocument))
    #expect(session.generation == initialGeneration)
    #expect(session.evaluationSnapshot == initialEvaluation)
    #expect(session.commandStack.undoEntries.count == initialHistoryCount)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func preparedProgramLateCoreFailureRollsBackCallerState() throws {
    let first = makeSheetStep(
        featureSlot: "created-feature",
        bodySlot: "created-sheet",
        sceneSlot: "created-scene"
    )
    let second = PreparedAutomationStep(
        estimatedGeneratedSourceWork: 0,
        commandBuilder: PreparedAutomationCommandBuilder(name: "late-core-failure") { _ in
            try ContextResolvedEditorCommand(validating: .createExtrudedRectangle(
                name: "Invalid Late Box",
                plane: .xy,
                width: .length(0, .meter),
                height: .length(0.01, .meter),
                depth: .length(0.01, .meter),
                direction: .normal
            ))
        }
    )
    let program = try PreparedAutomationProgram(
        steps: [first, second],
        limits: limits(steps: 2, inputs: 0, outputs: 3, commands: 2, generatedWork: 3)
    )
    let session = EditorSession()
    let initialDocument = session.document
    let initialGeneration = session.generation
    let initialEvaluation = session.evaluationSnapshot
    let initialHistoryCount = session.commandStack.undoEntries.count

    var caught: PreparedAutomationExecutionError?
    do {
        _ = try session.withSourceCommandGroup(named: "late-core-rollback") { staged in
            try DefaultPreparedAutomationProgramExecutor().execute(program, in: staged)
        }
    } catch let error as PreparedAutomationExecutionError {
        caught = error
    }

    if case .coreCommandFailed(
        stepIndex: 1,
        commandName: "createExtrudedRectangle",
        code: _,
        message: _
    ) = caught {
        // The first source command was successful; the second failed in Core.
    } else {
        Issue.record("Expected a late Core command failure, got \(String(describing: caught)).")
    }
    #expect(documentsMatch(session.document, initialDocument))
    #expect(session.generation == initialGeneration)
    #expect(session.evaluationSnapshot == initialEvaluation)
    #expect(session.commandStack.undoEntries.count == initialHistoryCount)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func preparedProgramCancellationAfterFirstCommandRollsBackGroup() async throws {
    let step = PreparedAutomationStep(
        outputs: [
            output("feature", .feature(index: 0)),
            output("sheet", .sourceBody(role: .sheet, index: 0)),
            output("scene", .sceneNode(index: 0)),
        ],
        estimatedGeneratedSourceWork: 3,
        commandBuilder: PreparedAutomationCommandBuilder(name: "cancel-after-command") { _ in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try ContextResolvedEditorCommand(validating: .createBSplineSurface(
                name: "Cancelled Sheet",
                surface: .cubicBezierPatch(
                    bottomLeft: Point3D(x: 0, y: 0, z: 0),
                    bottomRight: Point3D(x: 0.02, y: 0, z: 0),
                    topRight: Point3D(x: 0.02, y: 0.01, z: 0),
                    topLeft: Point3D(x: 0, y: 0.01, z: 0)
                )
            ))
        }
    )
    let program = try PreparedAutomationProgram(
        steps: [step],
        limits: limits(
            steps: 1,
            inputs: 0,
            outputs: 3,
            commands: 1,
            generatedWork: 3
        )
    )
    let session = EditorSession()
    let initialDocument = session.document
    let initialGeneration = session.generation
    let initialEvaluation = session.evaluationSnapshot
    let initialHistoryCount = session.commandStack.undoEntries.count
    var caught: PreparedAutomationExecutionError?
    do {
        _ = try session.withSourceCommandGroup(named: "prepared-cancellation") { staged in
            try DefaultPreparedAutomationProgramExecutor().execute(program, in: staged)
        }
    } catch let error as PreparedAutomationExecutionError {
        caught = error
    }

    #expect(caught == .cancelled)
    #expect(documentsMatch(session.document, initialDocument))
    #expect(session.generation == initialGeneration)
    #expect(session.evaluationSnapshot == initialEvaluation)
    #expect(session.commandStack.undoEntries.count == initialHistoryCount)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func preparedProgramAcceptsWorkBoundaryAndRejectsDynamicBoundaryPlusOne() throws {
    let boundary = makeSheetStep(
        featureSlot: "feature",
        bodySlot: "sheet",
        sceneSlot: "scene",
        estimatedWork: 3
    )
    let boundaryProgram = try PreparedAutomationProgram(
        steps: [boundary],
        limits: limits(
            steps: 1,
            inputs: 0,
            outputs: 3,
            commands: 1,
            generatedWork: 3
        )
    )
    let boundarySession = EditorSession()
    let boundaryReceipt = try boundarySession.withSourceCommandGroup(named: "work-boundary") { staged in
        try DefaultPreparedAutomationProgramExecutor().execute(boundaryProgram, in: staged)
    }
    #expect(boundaryReceipt.telemetry.generatedSourceWork == 3)

    let dynamic = makeSheetStep(
        featureSlot: "feature",
        bodySlot: "sheet",
        sceneSlot: "scene",
        estimatedWork: 1
    )
    let dynamicProgram = try PreparedAutomationProgram(
        steps: [dynamic],
        limits: limits(
            steps: 1,
            inputs: 0,
            outputs: 3,
            commands: 1,
            generatedWork: 2
        )
    )
    let dynamicSession = EditorSession()
    let initialDocument = dynamicSession.document
    let initialGeneration = dynamicSession.generation
    let initialEvaluation = dynamicSession.evaluationSnapshot
    let initialHistoryCount = dynamicSession.commandStack.undoEntries.count
    var caught: PreparedAutomationExecutionError?
    do {
        _ = try dynamicSession.withSourceCommandGroup(named: "dynamic-work-boundary") { staged in
            try DefaultPreparedAutomationProgramExecutor().execute(dynamicProgram, in: staged)
        }
    } catch let error as PreparedAutomationExecutionError {
        caught = error
    }

    if case .generatedSourceWorkExceeded(_, 3, 2) = caught {
        // The measured result crossed the accepted ceiling only after Core ran.
    } else {
        Issue.record("Expected dynamic generated-source work rejection, got \(String(describing: caught)).")
    }
    #expect(documentsMatch(dynamicSession.document, initialDocument))
    #expect(dynamicSession.generation == initialGeneration)
    #expect(dynamicSession.evaluationSnapshot == initialEvaluation)
    #expect(dynamicSession.commandStack.undoEntries.count == initialHistoryCount)
}

@Test(.timeLimit(.minutes(1)))
func preparedProgramReportsTheCorrectNegativeLimitMetric() throws {
    #expect(throws: PreparedAutomationPlanError.invalidLimit(.steps)) {
        try PreparedAutomationProgram(
            steps: [],
            limits: limits(steps: -1, inputs: 0, outputs: 0, commands: 0, generatedWork: 0)
        )
    }
    #expect(throws: PreparedAutomationPlanError.invalidLimit(.inputSlots)) {
        try PreparedAutomationProgram(
            steps: [],
            limits: limits(steps: 0, inputs: -1, outputs: 0, commands: 0, generatedWork: 0)
        )
    }
    #expect(throws: PreparedAutomationPlanError.invalidLimit(.outputSlots)) {
        try PreparedAutomationProgram(
            steps: [],
            limits: limits(steps: 0, inputs: 0, outputs: -1, commands: 0, generatedWork: 0)
        )
    }
    #expect(throws: PreparedAutomationPlanError.invalidLimit(.commands)) {
        try PreparedAutomationProgram(
            steps: [],
            limits: limits(steps: 0, inputs: 0, outputs: 0, commands: -1, generatedWork: 0)
        )
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func preparedProgramAcceptsEachLimitBoundaryAndRejectsBoundaryPlusOne() throws {
    let boundarySession = EditorSession()
    let rootSceneNodeID = try #require(boundarySession.document.productMetadata.rootSceneNodeIDs.first)
    let noOutputStep = makeSceneVisibilityStep(rootSceneNodeID: rootSceneNodeID)
    let inputStep = makeSceneVisibilityStep(rootSceneNodeID: rootSceneNodeID)
    let outputStep = makeSheetStep(
        featureSlot: "feature",
        bodySlot: "sheet",
        sceneSlot: "scene"
    )

    let stepBoundary = try PreparedAutomationProgram(
        steps: [noOutputStep],
        limits: limits(steps: 1, inputs: 1, outputs: 0, commands: 1, generatedWork: 0)
    )
    let stepReceipt = try boundarySession.withSourceCommandGroup(named: "step-boundary") { staged in
        try DefaultPreparedAutomationProgramExecutor().execute(stepBoundary, in: staged)
    }
    #expect(stepReceipt.telemetry.stepCount == 1)

    #expect(throws: PreparedAutomationPlanError.estimateExceedsLimit(
        metric: .steps,
        estimated: 1,
        maximum: 0
    )) {
        try PreparedAutomationProgram(
            steps: [noOutputStep],
            limits: limits(steps: 0, inputs: 1, outputs: 0, commands: 1, generatedWork: 0)
        )
    }

    let inputBoundary = try PreparedAutomationProgram(
        steps: [inputStep],
        limits: limits(steps: 1, inputs: 1, outputs: 0, commands: 1, generatedWork: 0)
    )
    _ = try boundarySession.withSourceCommandGroup(named: "input-boundary") { staged in
        try DefaultPreparedAutomationProgramExecutor().execute(inputBoundary, in: staged)
    }
    #expect(throws: PreparedAutomationPlanError.estimateExceedsLimit(
        metric: .inputSlots,
        estimated: 1,
        maximum: 0
    )) {
        try PreparedAutomationProgram(
            steps: [inputStep],
            limits: limits(steps: 1, inputs: 0, outputs: 0, commands: 1, generatedWork: 0)
        )
    }

    let outputBoundary = try PreparedAutomationProgram(
        steps: [outputStep],
        limits: limits(steps: 1, inputs: 0, outputs: 3, commands: 1, generatedWork: 3)
    )
    let outputSession = EditorSession()
    _ = try outputSession.withSourceCommandGroup(named: "output-boundary") { staged in
        try DefaultPreparedAutomationProgramExecutor().execute(outputBoundary, in: staged)
    }
    #expect(throws: PreparedAutomationPlanError.estimateExceedsLimit(
        metric: .outputSlots,
        estimated: 3,
        maximum: 2
    )) {
        try PreparedAutomationProgram(
            steps: [outputStep],
            limits: limits(steps: 1, inputs: 0, outputs: 2, commands: 1, generatedWork: 3)
        )
    }

    let commandBoundary = try PreparedAutomationProgram(
        steps: [noOutputStep],
        limits: limits(steps: 1, inputs: 1, outputs: 0, commands: 1, generatedWork: 0)
    )
    _ = try boundarySession.withSourceCommandGroup(named: "command-boundary") { staged in
        try DefaultPreparedAutomationProgramExecutor().execute(commandBoundary, in: staged)
    }
    #expect(throws: PreparedAutomationPlanError.estimateExceedsLimit(
        metric: .commands,
        estimated: 1,
        maximum: 0
    )) {
        try PreparedAutomationProgram(
            steps: [noOutputStep],
            limits: limits(steps: 1, inputs: 1, outputs: 0, commands: 0, generatedWork: 0)
        )
    }

    let workBoundary = try PreparedAutomationProgram(
        steps: [outputStep],
        limits: limits(steps: 1, inputs: 0, outputs: 3, commands: 1, generatedWork: 3)
    )
    let workSession = EditorSession()
    _ = try workSession.withSourceCommandGroup(named: "work-boundary-preflight") { staged in
        try DefaultPreparedAutomationProgramExecutor().execute(workBoundary, in: staged)
    }
    #expect(throws: PreparedAutomationPlanError.estimateExceedsLimit(
        metric: .generatedSourceWork,
        estimated: 3,
        maximum: 2
    )) {
        try PreparedAutomationProgram(
            steps: [outputStep],
            limits: limits(steps: 1, inputs: 0, outputs: 3, commands: 1, generatedWork: 2)
        )
    }
}

@Test(.timeLimit(.minutes(1)))
func preparedProgramRejectsForwardMissingDuplicateAndWrongKindReferences() throws {
    let builder = PreparedAutomationCommandBuilder(name: "noop") { _ in
        try ContextResolvedEditorCommand(validating: .createBSplineSurface(
            name: "Invalid Plan Probe",
            surface: .cubicBezierPatch(
                bottomLeft: Point3D(x: 0, y: 0, z: 0),
                bottomRight: Point3D(x: 0.01, y: 0, z: 0),
                topRight: Point3D(x: 0.01, y: 0.01, z: 0),
                topLeft: Point3D(x: 0, y: 0.01, z: 0)
            )
        ))
    }
    let producer = PreparedAutomationStep(
        outputs: [output("feature", .feature(index: 0)), output("sheet", .sourceBody(role: .sheet, index: 0)), output("scene", .sceneNode(index: 0))],
        estimatedGeneratedSourceWork: 3,
        commandBuilder: builder
    )
    let consumer = PreparedAutomationStep(
        inputs: [input("forward", .feature, local: "feature")],
        estimatedGeneratedSourceWork: 0,
        commandBuilder: builder
    )
    var forwardCaught: PreparedAutomationPlanError?
    do {
        _ = try PreparedAutomationProgram(
            steps: [consumer, producer],
            limits: limits(steps: 2, inputs: 1, outputs: 3, commands: 2, generatedWork: 3)
        )
    } catch let error as PreparedAutomationPlanError {
        forwardCaught = error
    }
    #expect(forwardCaught != nil)

    var missingCaught: PreparedAutomationPlanError?
    do {
        _ = try PreparedAutomationProgram(
            steps: [
                PreparedAutomationStep(
                    inputs: [input("missing", .feature, local: "unknown")],
                    estimatedGeneratedSourceWork: 0,
                    commandBuilder: builder
                )
            ],
            limits: limits(steps: 1, inputs: 1, outputs: 0, commands: 1, generatedWork: 0)
        )
    } catch let error as PreparedAutomationPlanError {
        missingCaught = error
    }
    #expect(missingCaught != nil)

    var duplicateCaught: PreparedAutomationPlanError?
    do {
        _ = try PreparedAutomationProgram(
            steps: [
                PreparedAutomationStep(
                    outputs: [
                        output("duplicate", .feature(index: 0)),
                        output("duplicate", .sceneNode(index: 0)),
                    ],
                    estimatedGeneratedSourceWork: 1,
                    commandBuilder: builder
                )
            ],
            limits: limits(steps: 1, inputs: 0, outputs: 2, commands: 1, generatedWork: 1)
        )
    } catch let error as PreparedAutomationPlanError {
        duplicateCaught = error
    }
    #expect(duplicateCaught != nil)

    var duplicateSelectorCaught: PreparedAutomationPlanError?
    do {
        _ = try PreparedAutomationProgram(
            steps: [
                PreparedAutomationStep(
                    outputs: [
                        output("first-feature", .feature(index: 0)),
                        output("second-feature", .feature(index: 0)),
                    ],
                    estimatedGeneratedSourceWork: 1,
                    commandBuilder: builder
                )
            ],
            limits: limits(steps: 1, inputs: 0, outputs: 2, commands: 1, generatedWork: 1)
        )
    } catch let error as PreparedAutomationPlanError {
        duplicateSelectorCaught = error
    }
    #expect(duplicateSelectorCaught == .duplicateOutputSelector(
        stepIndex: 0,
        selector: .feature(index: 0)
    ))

    var wrongKindCaught: PreparedAutomationPlanError?
    do {
        _ = try PreparedAutomationProgram(
            steps: [
                PreparedAutomationStep(
                    outputs: [output("kind", .feature(index: 0))],
                    estimatedGeneratedSourceWork: 1,
                    commandBuilder: builder
                ),
                PreparedAutomationStep(
                    inputs: [input("wrong", .sceneNode, local: "kind")],
                    estimatedGeneratedSourceWork: 0,
                    commandBuilder: builder
                ),
            ],
            limits: limits(steps: 2, inputs: 1, outputs: 1, commands: 2, generatedWork: 1)
        )
    } catch let error as PreparedAutomationPlanError {
        wrongKindCaught = error
    }
    #expect(wrongKindCaught != nil)

    #expect(throws: PreparedAutomationPlanError.evaluatedTopologyIdentityUnsupported) {
        try PreparedAutomationInputReference(evaluatedBodyID: BodyID())
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func preparedProgramRejectsWorkspaceAndRawGraphCommands() throws {
    let workspaceStep = PreparedAutomationStep(
        estimatedGeneratedSourceWork: 0,
        commandBuilder: PreparedAutomationCommandBuilder(name: "workspace") { _ in
            try ContextResolvedEditorCommand(validating: .renameDocument(name: "Rejected"))
        }
    )
    let workspaceProgram = try PreparedAutomationProgram(
        steps: [workspaceStep],
        limits: limits(steps: 1, inputs: 0, outputs: 0, commands: 1, generatedWork: 0)
    )
    let session = EditorSession()
    var workspaceCaught: PreparedAutomationExecutionError?
    do {
        _ = try session.withSourceCommandGroup(named: "reject-workspace") { staged in
            try DefaultPreparedAutomationProgramExecutor().execute(workspaceProgram, in: staged)
        }
    } catch let error as PreparedAutomationExecutionError {
        workspaceCaught = error
    }
    #expect(workspaceCaught != nil)
    #expect(session.document.cadDocument.metadata.name == "Untitled")

    let graphStep = PreparedAutomationStep(
        estimatedGeneratedSourceWork: 0,
        commandBuilder: PreparedAutomationCommandBuilder(name: "raw-graph") { _ in
            try ContextResolvedEditorCommand(validating: .appendFeatureGraph(
                FeatureGraphTransaction(features: [])
            ))
        }
    )
    let graphProgram = try PreparedAutomationProgram(
        steps: [graphStep],
        limits: limits(steps: 1, inputs: 0, outputs: 0, commands: 1, generatedWork: 0)
    )
    var graphCaught: PreparedAutomationExecutionError?
    do {
        _ = try session.withSourceCommandGroup(named: "reject-raw-graph") { staged in
            try DefaultPreparedAutomationProgramExecutor().execute(graphProgram, in: staged)
        }
    } catch let error as PreparedAutomationExecutionError {
        graphCaught = error
    }
    #expect(graphCaught == .sourceCommandRejected(
        stepIndex: 0,
        commandName: "appendFeatureGraph"
    ))
    #expect(session.document.cadDocument.metadata.name == "Untitled")
}

private func makeSingleBoxProgram() throws -> PreparedAutomationProgram {
    let step = PreparedAutomationStep(
        outputs: [
            output("sketch", .feature(index: 0)),
            output("body", .feature(index: 1)),
            output("body-output", .sourceBody(role: .body, index: 0)),
            output("body-scene", .sceneNode(index: 0)),
            output("sketch-scene", .sceneNode(index: 1)),
        ],
        estimatedGeneratedSourceWork: 5,
        commandBuilder: PreparedAutomationCommandBuilder(name: "single-box") { _ in
            try ContextResolvedEditorCommand(validating: .createExtrudedRectangle(
                name: "Single Box",
                plane: .xy,
                width: .length(0.1, .meter),
                height: .length(0.1, .meter),
                depth: .length(0.1, .meter),
                direction: .normal
            ))
        }
    )
    return try PreparedAutomationProgram(
        steps: [step],
        limits: limits(steps: 1, inputs: 0, outputs: 5, commands: 1, generatedWork: 5)
    )
}

private func makeSheetStep(
    featureSlot: String,
    bodySlot: String,
    sceneSlot: String,
    estimatedWork: UInt64 = 3
) -> PreparedAutomationStep {
    PreparedAutomationStep(
        outputs: [
            output(featureSlot, .feature(index: 0)),
            output(bodySlot, .sourceBody(role: .sheet, index: 0)),
            output(sceneSlot, .sceneNode(index: 0)),
        ],
        estimatedGeneratedSourceWork: estimatedWork,
        commandBuilder: PreparedAutomationCommandBuilder(name: "sheet-step") { _ in
            try ContextResolvedEditorCommand(validating: .createBSplineSurface(
                name: "Sheet Step",
                surface: .cubicBezierPatch(
                    bottomLeft: Point3D(x: 0, y: 0, z: 0),
                    bottomRight: Point3D(x: 0.02, y: 0, z: 0),
                    topRight: Point3D(x: 0.02, y: 0.01, z: 0),
                    topLeft: Point3D(x: 0, y: 0.01, z: 0)
                )
            ))
        }
    )
}

private func makeSceneVisibilityStep(
    rootSceneNodeID: SceneNodeID
) -> PreparedAutomationStep {
    PreparedAutomationStep(
        inputs: [input(
            "root",
            .sceneNode,
            existing: .sceneNode(rootSceneNodeID)
        )],
        estimatedGeneratedSourceWork: 0,
        commandBuilder: PreparedAutomationCommandBuilder(name: "set-visibility") { inputs in
            let sceneNodeID = try inputs.sceneNodeID(for: slot("root"))
            return try ContextResolvedEditorCommand(validating: .setSceneNodeVisibility(
                id: sceneNodeID,
                isVisible: true
            ))
        }
    )
}

private func executePatternProgram(copyCount: Int) throws -> PreparedAutomationExecutionReceipt {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(bodyFeatureID)
    }?.id)
    let definitionResult = try session.execute(.createComponentDefinition(
        name: "Pattern Definition \(copyCount)",
        rootSceneNodeIDs: [bodySceneNodeID]
    ))
    let definitionID = try #require(
        definitionResult.generatedIdentities.componentDefinitionIDs.first
    )
    let outputs = [output("pattern", .patternArraySource(index: 0))]
    let generatedWork = UInt64(3 + (2 * copyCount))
    let step = PreparedAutomationStep(
        inputs: [input("definition", .componentDefinition, existing: .componentDefinition(definitionID))],
        outputs: outputs,
        estimatedGeneratedSourceWork: generatedWork,
        commandBuilder: PreparedAutomationCommandBuilder(name: "native-pattern") { inputs in
            let resolvedDefinitionID = try inputs.componentDefinitionID(for: slot("definition"))
            return try ContextResolvedEditorCommand(validating: .createPatternArray(
                name: "Prepared Pattern \(copyCount)",
                definitionID: resolvedDefinitionID,
                distribution: .rectangular(RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(5, .millimeter),
                        copyCount: copyCount
                    )
                )),
                outputMode: .componentInstance
            ))
        }
    )
    let program = try PreparedAutomationProgram(
        steps: [step],
        limits: limits(
            steps: 1,
            inputs: 1,
            outputs: 1,
            commands: 1,
            generatedWork: generatedWork
        )
    )
    return try session.withSourceCommandGroup(named: "native-pattern") { staged in
        try DefaultPreparedAutomationProgramExecutor().execute(program, in: staged)
    }
}

private func input(
    _ id: String,
    _ kind: PreparedAutomationIdentityKind,
    local: String
) -> PreparedAutomationInputSlot {
    PreparedAutomationInputSlot(
        id: slot(id),
        expectedKind: kind,
        reference: .local(slot(local))
    )
}

private func input(
    _ id: String,
    _ kind: PreparedAutomationIdentityKind,
    existing identity: PreparedAutomationIdentity
) -> PreparedAutomationInputSlot {
    PreparedAutomationInputSlot(
        id: slot(id),
        expectedKind: kind,
        reference: .existing(identity)
    )
}

private func output(
    _ id: String,
    _ selector: PreparedAutomationOutputSelector
) -> PreparedAutomationOutputSlot {
    PreparedAutomationOutputSlot(id: slot(id), selector: selector)
}

private func slot(_ id: String) -> PreparedAutomationSlotID {
    PreparedAutomationSlotID(id)
}

private func limits(
    steps: Int,
    inputs: Int,
    outputs: Int,
    commands: Int,
    generatedWork: UInt64
) -> PreparedAutomationLimitPolicy {
    PreparedAutomationLimitPolicy(
        maximumStepCount: steps,
        maximumInputSlotCount: inputs,
        maximumOutputSlotCount: outputs,
        maximumCommandCount: commands,
        maximumGeneratedSourceWork: generatedWork
    )
}

private func documentsMatch(_ lhs: DesignDocument, _ rhs: DesignDocument) -> Bool {
    let leftCAD = lhs.cadDocument
    let rightCAD = rhs.cadDocument
    return lhs.modelingSettings == rhs.modelingSettings
        && lhs.productMetadata == rhs.productMetadata
        && lhs.authoredMeshAssets == rhs.authoredMeshAssets
        && leftCAD.id == rightCAD.id
        && leftCAD.schemaVersion == rightCAD.schemaVersion
        && leftCAD.units == rightCAD.units
        && leftCAD.parameters.parameters == rightCAD.parameters.parameters
        && leftCAD.parameters.revision == rightCAD.parameters.revision
        && leftCAD.designGraph.nodes.materializedDictionary() == rightCAD.designGraph.nodes.materializedDictionary()
        && leftCAD.designGraph.order == rightCAD.designGraph.order
        && leftCAD.designGraph.dependencies == rightCAD.designGraph.dependencies
        && leftCAD.designGraph.revision == rightCAD.designGraph.revision
        && leftCAD.selectionDimensions == rightCAD.selectionDimensions
        && leftCAD.metadata.name == rightCAD.metadata.name
        && leftCAD.metadata.createdAt == rightCAD.metadata.createdAt
        && leftCAD.metadata.updatedAt == rightCAD.metadata.updatedAt
}
