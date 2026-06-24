import SwiftCAD
import Testing
@testable import RupaCore

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

    #expect(result.patternArrays.count == 1)
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
}

private func designDisplaySnapshotBodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}
