import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func patternArrayPreviewServiceResolvesComponentInstanceOutputsFromSourceRootChildren() async throws {
    let session = EditorSession()
    let bodyFeatureID = try createDefaultPatternSourceDefinition(
        in: session,
        definitionName: "Preview Component Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Preview Component Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Preview Component Pattern",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(100.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Preview Component Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document)
    let emptyPreviews = ViewportPatternArrayPreviewService().previews(
        document: session.document,
        scene: scene,
        selection: .empty
    )
    let rootSelection = SelectionModel(selectedTargets: [
        SelectionTarget(sceneNodeID: source.rootSceneNodeID),
    ])

    #expect(emptyPreviews.isEmpty)

    let rootPreviews = ViewportPatternArrayPreviewService().previews(
        document: session.document,
        scene: scene,
        selection: rootSelection
    )

    let preview = try #require(rootPreviews.first)
    #expect(rootPreviews.count == 1)
    #expect(preview.sourceID == source.id)
    #expect(preview.outputMode == .componentInstance)
    #expect(preview.outputCount == 2)
    #expect(preview.outputs.map(\.index) == [0, 1])
    #expect(preview.outputs.allSatisfy { !$0.itemIDs.isEmpty })
    #expect(preview.outputs.allSatisfy { output in
        output.itemIDs.allSatisfy { itemID in
            scene.items.contains { item in
                item.id == itemID && item.featureID == bodyFeatureID
            }
        }
    })

    let secondOutputSceneNodeID = try outputSceneNodeID(
        for: source.outputInstanceIDs[1],
        source: source,
        document: session.document
    )
    let outputSelection = SelectionModel(selectedTargets: [
        SelectionTarget(sceneNodeID: secondOutputSceneNodeID),
    ])

    let outputPreviews = ViewportPatternArrayPreviewService().previews(
        document: session.document,
        scene: scene,
        selection: outputSelection
    )

    let outputPreview = try #require(outputPreviews.first)
    #expect(outputPreviews.count == 1)
    #expect(outputPreview.outputs.map(\.isSelected) == [false, true])
}

@MainActor
@Test func patternArrayPreviewServiceResolvesIndependentCopyOutputDescendantSelection() async throws {
    let session = EditorSession()
    _ = try createDefaultPatternSourceDefinition(
        in: session,
        definitionName: "Preview Independent Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Preview Independent Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Preview Independent Pattern",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(40.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Preview Independent Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document)
    let firstOutputDescendantID = try renderableDescendantSceneNodeID(
        rootedAt: source.outputSceneNodeIDs[0],
        scene: scene,
        document: session.document
    )
    let descendantSelection = SelectionModel(selectedTargets: [
        SelectionTarget(sceneNodeID: firstOutputDescendantID),
    ])

    let previews = ViewportPatternArrayPreviewService().previews(
        document: session.document,
        scene: scene,
        selection: descendantSelection
    )

    let preview = try #require(previews.first)
    #expect(previews.count == 1)
    #expect(preview.sourceID == source.id)
    #expect(preview.outputMode == .independentCopy)
    #expect(preview.outputCount == 2)
    #expect(preview.outputs.map(\.index) == [0, 1])
    #expect(preview.outputs.map(\.isSelected) == [true, false])
    #expect(preview.outputs.allSatisfy { !$0.itemIDs.isEmpty })
}

@MainActor
@discardableResult
private func createDefaultPatternSourceDefinition(
    in session: EditorSession,
    definitionName: String
) throws -> FeatureID {
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try sceneNodeID(for: bodyFeatureID, in: session.document)
    _ = try session.execute(
        .createComponentDefinition(
            name: definitionName,
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    return bodyFeatureID
}

private func outputSceneNodeID(
    for componentInstanceID: ComponentInstanceID,
    source: PatternArraySource,
    document: DesignDocument
) throws -> SceneNodeID {
    let rootNode = try #require(document.productMetadata.sceneNodes[source.rootSceneNodeID])
    return try #require(rootNode.childIDs.first { childID in
        document.productMetadata.sceneNodes[childID]?.reference?.componentInstanceID == componentInstanceID
    })
}

private func renderableDescendantSceneNodeID(
    rootedAt rootSceneNodeID: SceneNodeID,
    scene: ViewportScene,
    document: DesignDocument
) throws -> SceneNodeID {
    let descendantIDs = sceneSubtreeIDs(rootedAt: rootSceneNodeID, document: document)
    return try #require(scene.items.first { item in
        guard let sceneNodeID = item.sceneNodeID else {
            return false
        }
        return descendantIDs.contains(sceneNodeID)
    }?.sceneNodeID)
}

private func sceneSubtreeIDs(
    rootedAt rootSceneNodeID: SceneNodeID,
    document: DesignDocument
) -> Set<SceneNodeID> {
    var result: Set<SceneNodeID> = []
    appendSceneSubtreeIDs(
        rootSceneNodeID,
        document: document,
        result: &result
    )
    return result
}

private func appendSceneSubtreeIDs(
    _ sceneNodeID: SceneNodeID,
    document: DesignDocument,
    result: inout Set<SceneNodeID>
) {
    guard result.insert(sceneNodeID).inserted,
          let sceneNode = document.productMetadata.sceneNodes[sceneNodeID] else {
        return
    }
    for childID in sceneNode.childIDs {
        appendSceneSubtreeIDs(
            childID,
            document: document,
            result: &result
        )
    }
}

private func sceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) throws -> SceneNodeID {
    guard let sceneNode = document.productMetadata.sceneNodes.first(where: { _, node in
        node.reference?.featureID == featureID
    }) else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Expected a scene node for the feature."
        )
    }
    return sceneNode.key
}
