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
    #expect(patternArray.rootSceneNodeID == source.rootSceneNodeID)
    #expect(patternArray.outputMode == .componentInstance)
    #expect(patternArray.outputCount == source.outputInstanceIDs.count)
    #expect(patternArray.outputs.count == source.outputInstanceIDs.count)
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

private func designDisplaySnapshotBodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}
