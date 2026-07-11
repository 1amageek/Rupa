import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func designDisplaySnapshotListsPlacedComponentInstancesForAgentPlanning() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        designDisplaySnapshotBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Display Placed Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Display Placed Source"
    })
    _ = try session.execute(
        .createComponentInstance(
            name: "Display Placed Instance",
            definitionID: definition.id,
            localTransform: .identity
        )
    )
    let instance = try #require(session.document.productMetadata.componentInstances.values.first)
    let sceneNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference == .componentInstance(instance.id)
    })

    let result = try DesignDisplaySnapshotService().result(
        document: session.document,
        workspaceState: session.workspaceState,
        currentEvaluation: session.currentEvaluation,
        generation: session.generation,
        dirty: session.isDirty
    )
    let componentInstance = try #require(result.componentInstances.first)

    #expect(result.componentDefinitions.count == 1)
    #expect(result.componentInstances.count == 1)
    #expect(componentInstance.instanceID == instance.id)
    #expect(componentInstance.name == "Display Placed Instance")
    #expect(componentInstance.definitionID == definition.id)
    #expect(componentInstance.definitionName == "Display Placed Source")
    #expect(componentInstance.sceneNodeIDs == [sceneNode.id])
    #expect(componentInstance.primarySceneNodeID == sceneNode.id)
    #expect(componentInstance.localTransform == .identity)
    #expect(componentInstance.isVisible)
    #expect(!componentInstance.isLocked)
    #expect(componentInstance.propertyCount == 0)
    #expect(componentInstance.ownership == .document)
    #expect(componentInstance.ownership.isDirectlyEditable)
}

@MainActor
@Test func designDisplaySnapshotReportsWorkspaceScaleAndViewportGridForAgentPlanning() async throws {
    let session = EditorSession()
    session.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)
    let gridSettings = ViewportGridSettings(visualSpacingMode: .fixed)
    _ = try session.execute(.setViewportGridSettings(gridSettings))
    let failingPipeline = CADPipeline(
        evaluator: DocumentEvaluator(featureEvaluator: DesignDisplayFailingFeatureEvaluator())
    )

    let result = try DesignDisplaySnapshotService(
        pipeline: failingPipeline
    ).result(
        document: session.document,
        workspaceState: session.workspaceState,
        currentEvaluation: session.currentEvaluation,
        generation: session.generation,
        dirty: session.isDirty
    )

    #expect(result.workspaceScale.displayUnit == .kilometer)
    #expect(result.workspaceScale.displayUnitSymbol == "km")
    #expect(result.workspaceScale.matchedPreset == .sitePlanning)
    #expect(result.workspaceScale.matchedPresetTitle == "Site Planning")
    #expect(result.workspaceScale.minorTickMeters == 100.0)
    #expect(result.workspaceScale.majorTickMeters == 1_000.0)
    #expect(result.workspaceScale.visibleSpanMeters == 100_000.0)
    #expect(result.workspaceScalePresetOptions.map(\.preset) == WorkspaceScalePreset.allCases)
    #expect(result.workspaceScalePresetOptions.contains { option in
        option.preset == .regionalPlanning
            && option.visibleSpanTitle == "1,000 km"
            && option.comfortableModelSpanTitle == "10 km to 800 km"
    })
    #expect(result.workspaceInteractionScale.displayUnit == .kilometer)
    #expect(result.workspaceInteractionScale.displayUnitSymbol == "km")
    #expect(result.workspaceInteractionScale.operationStep.meters == 100.0)
    #expect(result.workspaceInteractionScale.operationStep.displayValue == 0.1)
    #expect(result.workspaceInteractionScale.operationStep.displayUnit == .kilometer)
    #expect(result.workspaceInteractionScale.slotWidth.meters == 200.0)
    #expect(result.workspaceInteractionScale.surfaceFrameNormalMove.meters == 100.0)
    #expect(abs(result.workspaceInteractionScale.sketchRebuildTolerance.meters - 0.1) < 1.0e-12)
    #expect(result.viewportGridSettings == gridSettings)
    #expect(result.viewportGridScale.visualSpacingMode == .fixed)
    #expect(result.viewportGridScale.displayUnit == .kilometer)
    #expect(result.viewportGridScale.snapStep.meters == 100.0)
    #expect(result.viewportGridScale.snapStep.displayValue == 0.1)
    #expect(result.viewportGridScale.configuredMinorStep.meters == 100.0)
    #expect(result.viewportGridScale.configuredMajorStep.meters == 1_000.0)
    #expect(result.viewportGridScale.workspaceSpan.meters == 100_000.0)
    #expect(result.viewportGridScale.workspaceSpan.text == "100 km")
    #expect(result.viewportGridScale.summary.contains("mode fixed"))
    #expect(result.viewportGridScale.summary.contains("workspace span 100 km"))
}

@MainActor
@Test func designDisplaySnapshotListsSavedViewsForAgentPlanning() async throws {
    let session = EditorSession()
    let viewID = SavedViewID()
    let savedView = designDisplaySavedView(id: viewID, name: " Display Saved View ")
    _ = try session.execute(.createSavedView(savedView))

    let result = try DesignDisplaySnapshotService().result(
        document: session.document,
        workspaceState: session.workspaceState,
        currentEvaluation: session.currentEvaluation,
        generation: session.generation,
        dirty: session.isDirty
    )
    let entry = try #require(result.savedViews.first)

    #expect(result.savedViews.count == 1)
    #expect(entry.id == viewID)
    #expect(entry.name == "Display Saved View")
    #expect(entry.displayScale.displayUnit == .kilometer)
    #expect(entry.displayScale.scaleBarLengthMeters == 1_000.0)
    #expect(entry.displayScale.matchedPreset == .sitePlanning)
    #expect(entry.projection.mode == .orthographic)
}

@Test func designDisplaySnapshotDecodesMissingWorkspaceInteractionScaleFromWorkspaceScale() throws {
    let json = """
    {
      "generation": {
        "value": 2
      },
      "dirty": false,
      "workspaceScale": {
        "displayUnit": "kilometer",
        "displayUnitSymbol": "km",
        "minorTickMeters": 100.0,
        "majorTickMeters": 1000.0,
        "visibleSpanMeters": 100000.0,
        "matchedPreset": "sitePlanning",
        "matchedPresetTitle": "Site Planning"
      },
      "viewportGridSettings": {
        "visualSpacingMode": "fixed"
      },
      "sketches": [],
      "extrudes": [],
      "straightPrismSweeps": [],
      "bodies": []
    }
    """

    let result = try JSONDecoder().decode(
        DesignDisplaySnapshotResult.self,
        from: try #require(json.data(using: .utf8))
    )

    #expect(result.workspaceInteractionScale.displayUnit == .kilometer)
    #expect(result.workspaceInteractionScale.operationStep.meters == 100.0)
    #expect(result.workspaceInteractionScale.operationStep.displayValue == 0.1)
    #expect(result.workspaceInteractionScale.slotWidth.meters == 200.0)
    #expect(result.viewportGridSettings.visualSpacingMode == .fixed)
    #expect(result.viewportGridScale.visualSpacingMode == .fixed)
    #expect(result.viewportGridScale.snapStep.meters == 100.0)
    #expect(result.viewportGridScale.configuredMajorStep.meters == 1_000.0)
    #expect(result.viewportGridScale.workspaceSpan.meters == 100_000.0)
    #expect(result.viewportGridScale.workspaceSpan.text == "100 km")
    #expect(result.workspaceScalePresetOptions.map(\.preset) == WorkspaceScalePreset.allCases)
    #expect(result.workspaceScalePresetOptions.contains { option in
        option.preset == .regionalPlanning
            && option.agentGuidance.contains("regionalPlanning")
            && option.agentGuidance.contains("1,000 km")
    })
    #expect(result.savedViews.isEmpty)
}

@MainActor
@Test func designDisplaySnapshotReportsWorkspaceScaleRecommendationForAgentPlanning() throws {
    var document = DesignDocument.empty(named: "Display Site")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Display Site Footprint",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(25_000.0, .meter),
            y: .length(10_000.0, .meter)
        )
    )
    _ = try document.extrudeProfile(
        name: "Display Site Mass",
        profile: ProfileReference(featureID: profileID),
        distance: .length(100.0, .meter),
        direction: .normal
    )
    let generation = DocumentGeneration(1)
    let currentEvaluation = try designDisplayEvaluationContext(
        document: document,
        generation: generation
    )

    let result = try DesignDisplaySnapshotService().result(
        document: document,
        workspaceState: WorkspaceState(),
        currentEvaluation: currentEvaluation,
        generation: generation,
        dirty: false
    )

    #expect(result.workspaceScaleRecommendation?.reason == .modelExceedsComfortableSpan)
    #expect(result.workspaceScaleRecommendation?.recommendedPreset == .sitePlanning)
    #expect(result.workspaceScaleRecommendation?.recommendedScale.displayUnit == .kilometer)
    #expect(result.workspaceScaleRecommendation?.recommendedScaleProfile.comfortableModelSpanTitle == "1 km to 80 km")
    #expect(result.workspaceBounds?.sizeX == 25_000.0)
    #expect(result.workspaceBounds?.sizeY == 10_000.0)
    #expect(result.workspaceBounds?.sizeZ == 100.0)
    #expect(result.workspaceBounds?.maximumSpan == 25_000.0)
    #expect(result.workspacePrecision == nil)
}

@MainActor
@Test func designDisplaySnapshotReportsWorkspacePrecisionForAgentPlanning() throws {
    var document = DesignDocument.empty(named: "Display Remote Site")
    let workspaceState = WorkspaceState(
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Display Remote Footprint",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(1.0e12, .meter),
            y: .length(1.0e12, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(1.0e12 + 10.0, .meter),
            y: .length(1.0e12 + 10.0, .meter)
        )
    )
    _ = try document.extrudeProfile(
        name: "Display Remote Mass",
        profile: ProfileReference(featureID: profileID),
        distance: .length(10.0, .meter),
        direction: .normal
    )
    let generation = DocumentGeneration(1)
    let currentEvaluation = try designDisplayEvaluationContext(
        document: document,
        generation: generation
    )

    let result = try DesignDisplaySnapshotService().result(
        document: document,
        workspaceState: workspaceState,
        currentEvaluation: currentEvaluation,
        generation: generation,
        dirty: false
    )

    #expect(result.workspacePrecision?.reason == .coordinateResolution)
    #expect(result.workspaceBounds?.maximumSpan == 10.0)
    #expect(result.workspaceBounds?.maximumAbsoluteCoordinate == 1.0e12 + 10.0)
    #expect(result.workspacePrecision?.recommendedRebaseTranslation == Vector3D(
        x: -(1.0e12 + 5.0),
        y: -(1.0e12 + 5.0),
        z: 0.0
    ))
}

@MainActor
@Test func designDisplaySnapshotListsPatternArraySourcesForAgentPlanning() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        designDisplaySnapshotBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Display Array Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Display Array Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Display Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(12.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Display Array"
    })
    let bodyFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case .extrude(let extrude) = bodyFeature.operation else {
        Issue.record("Default body should be produced by an extrude.")
        return
    }
    let firstOutputID = try #require(source.outputInstanceIDs.first)
    let firstOutputInstance = try #require(
        session.document.productMetadata.componentInstances[firstOutputID]
    )
    let firstOutputSceneNodeID = try #require(
        session.document.productMetadata.sceneNodes[source.rootSceneNodeID]?.childIDs.first
    )

    let result = try DesignDisplaySnapshotService().result(
        document: session.document,
        workspaceState: session.workspaceState,
        currentEvaluation: session.currentEvaluation,
        generation: session.generation,
        dirty: session.isDirty
    )
    let patternArray = try #require(result.patternArrays.first)
    let firstOutput = try #require(patternArray.outputs.first)
    let componentDefinition = try #require(result.componentDefinitions.first)
    let componentInstances = result.componentInstances
    let firstComponentInstance = try #require(componentInstances.first {
        $0.instanceID == firstOutputID
    })
    let rootSceneNode = try #require(componentDefinition.rootSceneNodes.first)

    #expect(result.patternArrays.count == 1)
    #expect(result.componentDefinitions.count == 1)
    #expect(result.componentInstances.count == source.outputInstanceIDs.count)
    #expect(componentDefinition.definitionID == definition.id)
    #expect(componentDefinition.name == "Display Array Source")
    #expect(componentDefinition.bodySceneNodeIDs == [bodySceneNodeID])
    #expect(componentDefinition.bodyFeatureIDs == [bodyFeatureID])
    #expect(componentDefinition.featureIDs.contains(bodyFeatureID))
    #expect(componentDefinition.featureIDs.contains(extrude.profile.featureID))
    #expect(componentDefinition.isRenderable)
    #expect(rootSceneNode.sceneNodeID == bodySceneNodeID)
    #expect(rootSceneNode.referenceKind == .body)
    #expect(rootSceneNode.featureID == bodyFeatureID)
    #expect(patternArray.sourceID == source.id)
    #expect(patternArray.name == "Display Array")
    #expect(patternArray.definitionID == definition.id)
    #expect(patternArray.definitionName == "Display Array Source")
    #expect(patternArray.definitionIdentity == nil)
    #expect(patternArray.rootSceneNodeID == source.rootSceneNodeID)
    #expect(patternArray.outputMode == .componentInstance)
    #expect(patternArray.outputCount == source.outputInstanceIDs.count)
    #expect(patternArray.outputs.count == source.outputInstanceIDs.count)
    #expect(patternArray.diagnostics.isEmpty)
    #expect(firstOutput.componentInstanceID == firstOutputID)
    #expect(firstOutput.sceneNodeID == firstOutputSceneNodeID)
    #expect(firstOutput.localTransform == firstOutputInstance.localTransform)
    #expect(firstComponentInstance.definitionID == definition.id)
    #expect(firstComponentInstance.definitionName == "Display Array Source")
    #expect(firstComponentInstance.sceneNodeIDs == [firstOutputSceneNodeID])
    #expect(firstComponentInstance.primarySceneNodeID == firstOutputSceneNodeID)
    #expect(firstComponentInstance.localTransform == firstOutputInstance.localTransform)
    #expect(firstComponentInstance.ownership.kind == .patternArrayOutput)
    #expect(firstComponentInstance.ownership.patternArraySourceID == source.id)
    #expect(firstComponentInstance.ownership.patternArraySourceName == "Display Array")
    #expect(firstComponentInstance.ownership.patternArrayOutputIndex == 0)
    #expect(!firstComponentInstance.ownership.isDirectlyEditable)
}

@MainActor
@Test func designDisplaySnapshotReportsIndependentCopyOutputStatesForAgentPlanning() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        designDisplaySnapshotBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Display Independent Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Display Independent Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Display Independent Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(12.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Display Independent Array"
    })
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let firstCloneBodyFeatureID = try #require(
        designDisplaySnapshotBodyFeatureID(
            inSceneSubtreeRootedAt: firstOutputSceneNodeID,
            document: session.document
        )
    )
    _ = try session.execute(
        .setExtrudeDistance(
            featureID: firstCloneBodyFeatureID,
            distance: .length(7.0, .millimeter)
        )
    )

    let result = try DesignDisplaySnapshotService().result(
        document: session.document,
        workspaceState: session.workspaceState,
        currentEvaluation: session.currentEvaluation,
        generation: session.generation,
        dirty: session.isDirty
    )
    let patternArray = try #require(result.patternArrays.first)
    let firstOutput = try #require(patternArray.outputs.first)
    let secondOutput = try #require(patternArray.outputs.dropFirst().first)

    #expect(patternArray.outputMode == .independentCopy)
    #expect(patternArray.definitionIdentity == source.definitionIdentity)
    #expect(patternArray.definitionIdentity != nil)
    #expect(patternArray.outputs.count == 2)
    #expect(firstOutput.sceneNodeID == firstOutputSceneNodeID)
    #expect(firstOutput.featureIDs.contains(firstCloneBodyFeatureID))
    #expect(firstOutput.independentCopyState == .divergedFromSourceDefinition)
    #expect(firstOutput.independentCopyRegenerationPolicy == .reuseUntilDefinitionIdentityChanges)
    #expect(secondOutput.independentCopyState == .matchesSourceDefinition)
    #expect(secondOutput.independentCopyRegenerationPolicy == .reuseUntilDefinitionIdentityChanges)
    #expect(patternArray.diagnostics.isEmpty)
}

@MainActor
@Test func designDisplaySnapshotKeepsInvalidPatternArraySourcesForDiagnostics() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        designDisplaySnapshotBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Invalid Display Array Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Invalid Display Array Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Invalid Display Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(12.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Invalid Display Array"
    })
    var document = session.document
    document.productMetadata.componentDefinitions.removeValue(forKey: definition.id)
    document.productMetadata.sceneNodes.removeValue(forKey: source.rootSceneNodeID)

    let result = try DesignDisplaySnapshotService().result(
        document: document,
        workspaceState: session.workspaceState,
        currentEvaluation: session.currentEvaluation,
        generation: session.generation,
        dirty: session.isDirty
    )
    let patternArray = try #require(result.patternArrays.first)
    let diagnosticCodes = Set(patternArray.diagnostics.map(\.code))

    #expect(result.patternArrays.count == 1)
    #expect(patternArray.sourceID == source.id)
    #expect(patternArray.name == "Invalid Display Array")
    #expect(patternArray.definitionID == definition.id)
    #expect(patternArray.definitionName == nil)
    #expect(patternArray.rootSceneNodeID == source.rootSceneNodeID)
    #expect(patternArray.rootSceneNodeName == nil)
    #expect(patternArray.outputCount == source.outputInstanceIDs.count)
    #expect(patternArray.outputs.isEmpty)
    #expect(diagnosticCodes.contains("missingDefinition"))
    #expect(diagnosticCodes.contains("missingRootSceneNode"))
}

private func designDisplaySnapshotBodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

private func designDisplaySnapshotBodyFeatureID(
    inSceneSubtreeRootedAt rootSceneNodeID: SceneNodeID,
    document: DesignDocument
) -> FeatureID? {
    var pendingSceneNodeIDs = [rootSceneNodeID]
    var visitedSceneNodeIDs: Set<SceneNodeID> = []
    while let sceneNodeID = pendingSceneNodeIDs.popLast() {
        guard visitedSceneNodeIDs.insert(sceneNodeID).inserted,
              let sceneNode = document.productMetadata.sceneNodes[sceneNodeID] else {
            continue
        }
        if sceneNode.reference?.kind == .body,
           let featureID = sceneNode.reference?.featureID {
            return featureID
        }
        pendingSceneNodeIDs.append(contentsOf: sceneNode.childIDs)
    }
    return nil
}

private func designDisplayEvaluationContext(
    document: DesignDocument,
    generation: DocumentGeneration
) throws -> DocumentEvaluationContext {
    let validatedDocument = try document.validate()
    let evaluatedDocument = try DocumentEvaluator.modelingDefault(for: document)
        .evaluate(validatedDocument.validatedCADDocument)
    return DocumentEvaluationContext(
        generation: generation,
        modelingSettings: document.modelingSettings,
        evaluatedDocument: evaluatedDocument,
        validatedDocument: validatedDocument
    )
}

private func designDisplaySavedView(
    id: SavedViewID,
    name: String
) -> SavedView {
    SavedView(
        id: id,
        name: name,
        camera: SavedViewCamera(
            target: Point3D(x: 250.0, y: 10.0, z: 500.0),
            distanceMeters: 2_000.0,
            yawRadians: 0.35,
            pitchRadians: -0.45
        ),
        projection: .orthographic(heightMeters: 1_000.0),
        displayScale: SavedViewDisplayScale(
            ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration,
            scaleBarLengthMeters: 1_000.0
        )
    )
}

private struct DesignDisplayFailingFeatureEvaluator: FeatureEvaluating {
    func evaluate(feature _: FeatureNode, context _: EvaluationContext) throws -> EvaluationResult {
        throw FeatureEvaluationError.unsupportedOperation("Body evaluation should not be required.")
    }
}
