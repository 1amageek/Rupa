import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func patternArrayPreviewServiceKeepsAllMatchingSharedSources() async throws {
    let session = EditorSession()
    let source = try makePatternSource(in: session, name: "Shared Source")
    var document = session.document
    var metadata = document.productMetadata
    var sharedSource = source
    sharedSource.id = PatternArraySourceID()
    sharedSource.name = "Shared Source Duplicate"
    metadata.patternArrays[sharedSource.id] = sharedSource
    document.productMetadata = metadata

    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: session.workspaceState.ruler
    )
    let selection = SelectionModel(selectedTargets: [
        SelectionTarget(sceneNodeID: source.rootSceneNodeID),
    ])
    let previews = ViewportPatternArrayPreviewService().previews(
        document: document,
        scene: scene,
        selection: selection
    )

    #expect(Set(previews.map(\.sourceID)) == Set([source.id, sharedSource.id]))
    #expect(previews.allSatisfy { $0.outputCount == source.outputInstanceIDs.count })
}

@MainActor
@Test func patternArrayPreviewServiceSkipsUnselectedHugeOutputsBeforeMaterialization() async throws {
    let session = EditorSession()
    let selectedSource = try makePatternSource(in: session, name: "Selected Source")
    var document = session.document
    var metadata = document.productMetadata
    var unselectedSource = selectedSource
    unselectedSource.id = PatternArraySourceID()
    unselectedSource.name = "Unselected Huge Source"
    let unselectedRoot = SceneNode(name: "Unselected Huge Root")
    metadata.sceneNodes[unselectedRoot.id] = unselectedRoot
    unselectedSource.rootSceneNodeID = unselectedRoot.id
    unselectedSource.outputInstanceIDs = (0 ..< 2_048).map { _ in ComponentInstanceID() }
    metadata.patternArrays[unselectedSource.id] = unselectedSource
    document.productMetadata = metadata

    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: session.workspaceState.ruler
    )
    let selection = SelectionModel(selectedTargets: [
        SelectionTarget(sceneNodeID: selectedSource.rootSceneNodeID),
    ])
    var peakAdmittedItems = 0
    var admissionExceeded = false
    var previews: [ViewportPatternArrayPreview] = []
    do {
        previews = try ViewportPatternArrayPreviewService().previews(
            document: document,
            scene: scene,
            selection: selection,
            checkpoint: { items, _, _ in
                peakAdmittedItems = max(peakAdmittedItems, items)
                if items > 128 {
                    throw PatternPreviewAdmissionExceeded()
                }
            }
        )
    } catch is PatternPreviewAdmissionExceeded {
        admissionExceeded = true
    }

    #expect(!admissionExceeded)
    #expect(peakAdmittedItems <= 128)
    #expect(previews.count == 1)
    #expect(previews.first?.sourceID == selectedSource.id)
    #expect(previews.first?.outputCount == selectedSource.outputInstanceIDs.count)
}

private struct PatternPreviewAdmissionExceeded: Error {}

@MainActor
@Test func patternArrayPreviewServicePropagatesWorkerCheckpointCancellation() async throws {
    let session = EditorSession()
    let source = try makePatternSource(in: session, name: "Cancellable Source")
    let document = session.document
    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: session.workspaceState.ruler
    )
    let selection = SelectionModel(selectedTargets: [
        SelectionTarget(sceneNodeID: source.rootSceneNodeID),
    ])

    #expect(throws: CancellationError.self) {
        try ViewportPatternArrayPreviewService().previews(
            document: document,
            scene: scene,
            selection: selection,
            checkpoint: { items, _, _ in
                if items > 0 {
                    throw CancellationError()
                }
            }
        )
    }
}

@MainActor
private func makePatternSource(
    in session: EditorSession,
    name: String
) throws -> PatternArraySource {
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(session.document.productMetadata.sceneNodes.first {
        $0.value.reference?.featureID == bodyFeatureID
    }?.key)
    _ = try session.execute(
        .createComponentDefinition(
            name: "\(name) Definition",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "\(name) Definition"
    })
    _ = try session.execute(
        .createPatternArray(
            name: name,
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
    return try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == name
    })
}
