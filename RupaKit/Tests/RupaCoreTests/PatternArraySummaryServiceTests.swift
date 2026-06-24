import SwiftCAD
import Testing
@testable import RupaCore

@Test func patternArraySummaryReportsComponentInstanceOutputOwnershipForEditing() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        patternArraySummaryBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Summary Component Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Summary Component Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Summary Component Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Summary Component Array"
    })

    let result = PatternArraySummaryService().summarize(
        document: session.document,
        generation: session.generation,
        dirty: session.isDirty
    )
    let summary = try #require(result.patternArrays.first)

    #expect(result.generation == session.generation)
    #expect(result.dirty == session.isDirty)
    #expect(summary.sourceID == source.id)
    #expect(summary.name == "Summary Component Array")
    #expect(summary.definitionID == definition.id)
    #expect(summary.definitionName == "Summary Component Source")
    #expect(summary.rootSceneNodeID == source.rootSceneNodeID)
    #expect(summary.rootSceneNodeName == "Summary Component Array")
    #expect(summary.distributionKind == .rectangular)
    #expect(summary.outputMode == .componentInstance)
    #expect(summary.outputCount == source.outputInstanceIDs.count)
    #expect(summary.componentInstanceOutputIDs == source.outputInstanceIDs)
    #expect(summary.outputSceneNodeIDs.isEmpty)
    #expect(summary.outputFeatureIDs.isEmpty)
    #expect(summary.editableFields == [.name, .definitionID, .distribution, .outputMode])
    #expect(summary.lifecycleActions == [.updatePatternArray, .explodePatternArray])
    #expect(summary.outputOwnership.kind == .sourceOwnedComponentInstances)
    #expect(!summary.outputOwnership.directOutputEditingAllowed)
    #expect(summary.outputOwnership.sourceEditAction == .updatePatternArray)
    #expect(summary.outputOwnership.detachAction == .explodePatternArray)
    #expect(summary.outputOwnership.editableAfterDetach)
    #expect(summary.diagnostics.isEmpty)
}

@Test func patternArraySummaryReportsIndependentCopyOutputOwnershipForEditing() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        patternArraySummaryBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Summary Independent Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Summary Independent Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Summary Independent Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Summary Independent Array"
    })

    let result = PatternArraySummaryService().summarize(
        document: session.document,
        generation: session.generation,
        dirty: session.isDirty
    )
    let summary = try #require(result.patternArrays.first)

    #expect(summary.sourceID == source.id)
    #expect(summary.distributionKind == .rectangular)
    #expect(summary.outputMode == .independentCopy)
    #expect(summary.outputCount == source.outputSceneNodeIDs.count)
    #expect(summary.componentInstanceOutputIDs.isEmpty)
    #expect(summary.outputSceneNodeIDs == source.outputSceneNodeIDs)
    #expect(summary.outputFeatureIDs == source.outputFeatureIDs)
    #expect(!summary.outputFeatureIDs.isEmpty)
    #expect(summary.outputOwnership.kind == .sourceOwnedIndependentCopies)
    #expect(!summary.outputOwnership.directOutputEditingAllowed)
    #expect(summary.outputOwnership.sourceEditAction == .updatePatternArray)
    #expect(summary.outputOwnership.detachAction == .explodePatternArray)
    #expect(summary.outputOwnership.editableAfterDetach)
    #expect(summary.diagnostics.isEmpty)
}

private func patternArraySummaryBodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}
