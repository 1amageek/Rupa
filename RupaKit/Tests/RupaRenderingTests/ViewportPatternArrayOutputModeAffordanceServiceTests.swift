import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func patternArrayOutputModeAffordanceServiceResolvesRootSelection() async throws {
    let session = EditorSession()
    _ = try createOutputModePatternSourceDefinition(
        in: session,
        definitionName: "Output Mode Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Output Mode Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Output Mode Pattern",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(0.03, .meter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Output Mode Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let candidates = ViewportPatternArrayOutputModeAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: source.rootSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    #expect(candidates.count == 1)
    #expect(candidate.target.sourceID == source.id)
    #expect(candidate.target.currentOutputMode == .componentInstance)
    #expect(candidate.target.nextOutputMode == .independentCopy)
    #expect(candidate.target.commitTarget == ViewportPatternArrayOutputModeTarget(
        sourceID: source.id,
        outputMode: .independentCopy
    ))
    #expect(candidate.target.title == "Output Instance")
    #expect(candidate.target.highlightedTitle == "Switch Independent")
    #expect(candidate.hitRect.contains(candidate.center))
}

@MainActor
@Test func patternArrayOutputModeAffordanceServiceResolvesIndependentOutputSelection() async throws {
    let session = EditorSession()
    _ = try createOutputModePatternSourceDefinition(
        in: session,
        definitionName: "Independent Output Mode Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Independent Output Mode Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Independent Output Mode Pattern",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(0.03, .meter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Independent Output Mode Pattern"
    })
    let outputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let candidates = ViewportPatternArrayOutputModeAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: outputSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    #expect(candidates.count == 1)
    #expect(candidate.target.sourceID == source.id)
    #expect(candidate.target.currentOutputMode == .independentCopy)
    #expect(candidate.target.nextOutputMode == .componentInstance)
    #expect(candidate.target.commitTarget == ViewportPatternArrayOutputModeTarget(
        sourceID: source.id,
        outputMode: .componentInstance
    ))
    #expect(candidate.target.title == "Output Independent")
    #expect(candidate.target.highlightedTitle == "Switch Instance")
}

@MainActor
@discardableResult
private func createOutputModePatternSourceDefinition(
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
