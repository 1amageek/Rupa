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
@Test func designDisplaySnapshotReportsWorkspaceScaleForAgentPlanning() async throws {
    let session = EditorSession()
    session.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)

    let result = try DesignDisplaySnapshotService().result(
        document: session.document,
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
