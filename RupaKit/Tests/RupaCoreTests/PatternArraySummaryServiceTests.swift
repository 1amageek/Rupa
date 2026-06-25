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
    #expect(summary.definitionIdentity == nil)
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
    #expect(!summary.outputOwnership.directFeatureEditingAllowed)
    #expect(summary.outputOwnership.sourceEditAction == .updatePatternArray)
    #expect(summary.outputOwnership.detachAction == .explodePatternArray)
    #expect(summary.outputOwnership.editableAfterDetach)
    #expect(summary.independentCopyOutputs.isEmpty)
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
    #expect(summary.definitionIdentity == source.definitionIdentity)
    #expect(summary.definitionIdentity != nil)
    #expect(summary.outputCount == source.outputSceneNodeIDs.count)
    #expect(summary.componentInstanceOutputIDs.isEmpty)
    #expect(summary.outputSceneNodeIDs == source.outputSceneNodeIDs)
    #expect(summary.outputFeatureIDs == source.outputFeatureIDs)
    #expect(!summary.outputFeatureIDs.isEmpty)
    #expect(summary.outputOwnership.kind == .sourceOwnedIndependentCopies)
    #expect(!summary.outputOwnership.directOutputEditingAllowed)
    #expect(summary.outputOwnership.directFeatureEditingAllowed)
    #expect(summary.outputOwnership.sourceEditAction == .updatePatternArray)
    #expect(summary.outputOwnership.detachAction == .explodePatternArray)
    #expect(summary.outputOwnership.editableAfterDetach)
    #expect(summary.independentCopyOutputs.count == source.outputSceneNodeIDs.count)
    #expect(summary.independentCopyOutputs.map(\.sceneNodeID) == source.outputSceneNodeIDs)
    #expect(summary.independentCopyOutputs.allSatisfy { $0.state == .matchesSourceDefinition })
    #expect(summary.independentCopyOutputs.allSatisfy {
        $0.regenerationPolicy == .reuseUntilDefinitionIdentityChanges
    })
    #expect(summary.diagnostics.isEmpty)
}

@Test func patternArraySummaryReportsDivergedIndependentCopyOutputsForAgentPlanning() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        patternArraySummaryBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Summary Divergence Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Summary Divergence Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Summary Divergence Array",
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
        $0.name == "Summary Divergence Array"
    })
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let firstCloneBodyFeatureID = try #require(
        patternArraySummaryBodyFeatureID(
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

    let result = PatternArraySummaryService().summarize(
        document: session.document,
        generation: session.generation,
        dirty: session.isDirty
    )
    let summary = try #require(result.patternArrays.first)
    let firstOutput = try #require(summary.independentCopyOutputs.first)
    let secondOutput = try #require(summary.independentCopyOutputs.dropFirst().first)

    #expect(summary.independentCopyOutputs.count == 2)
    #expect(summary.definitionIdentity == source.definitionIdentity)
    #expect(firstOutput.outputIndex == 0)
    #expect(firstOutput.sceneNodeID == firstOutputSceneNodeID)
    #expect(firstOutput.featureIDs.contains(firstCloneBodyFeatureID))
    #expect(firstOutput.state == .divergedFromSourceDefinition)
    #expect(firstOutput.regenerationPolicy == .reuseUntilDefinitionIdentityChanges)
    #expect(secondOutput.outputIndex == 1)
    #expect(secondOutput.state == .matchesSourceDefinition)
    #expect(secondOutput.regenerationPolicy == .reuseUntilDefinitionIdentityChanges)
    #expect(summary.diagnostics.isEmpty)
}

@Test func patternArraySummaryReportsComponentInstanceStructuralDiagnostics() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        patternArraySummaryBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Diagnostic Component Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Diagnostic Component Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Diagnostic Component Array",
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
        $0.name == "Diagnostic Component Array"
    })
    let firstOutputInstanceID = try #require(source.outputInstanceIDs.first)
    let secondOutputInstanceID = try #require(source.outputInstanceIDs.dropFirst().first)
    let firstOutputSceneNodeID = try #require(
        session.document.productMetadata.sceneNodes[source.rootSceneNodeID]?.childIDs.first
    )

    var document = session.document
    document.productMetadata.componentInstances.removeValue(forKey: firstOutputInstanceID)
    document.productMetadata.componentInstances[secondOutputInstanceID]?.definitionID = ComponentDefinitionID()
    document.productMetadata.sceneNodes[firstOutputSceneNodeID]?.localTransform = try patternArraySummaryTranslationTransform(
        x: 1.0,
        y: 0.0,
        z: 0.0
    )
    var duplicateSource = source
    duplicateSource.id = PatternArraySourceID()
    duplicateSource.name = "Diagnostic Component Array Duplicate"
    document.productMetadata.patternArrays[duplicateSource.id] = duplicateSource

    let result = PatternArraySummaryService().summarize(
        document: document,
        generation: session.generation,
        dirty: session.isDirty
    )
    let summary = try #require(result.patternArrays.first { $0.sourceID == source.id })
    let codes = Set(summary.diagnostics.map(\.code))

    #expect(codes.contains("missingOutputInstance"))
    #expect(codes.contains("outputInstanceDefinitionMismatch"))
    #expect(codes.contains("duplicateOutputInstanceOwnership"))
    #expect(codes.contains("outputSceneNodeTransformNotIdentity"))
}

@Test func patternArraySummaryReportsIndependentCopyStructuralDiagnostics() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        patternArraySummaryBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Diagnostic Independent Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Diagnostic Independent Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Diagnostic Independent Array",
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
        $0.name == "Diagnostic Independent Array"
    })
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let secondOutputSceneNodeID = try #require(source.outputSceneNodeIDs.dropFirst().first)

    var document = session.document
    document.productMetadata.sceneNodes[source.rootSceneNodeID]?.childIDs = [
        secondOutputSceneNodeID,
        firstOutputSceneNodeID,
    ]
    document.productMetadata.sceneNodes[firstOutputSceneNodeID]?.localTransform = .identity
    var duplicateSource = source
    duplicateSource.id = PatternArraySourceID()
    duplicateSource.name = "Diagnostic Independent Array Duplicate"
    document.productMetadata.patternArrays[duplicateSource.id] = duplicateSource

    let result = PatternArraySummaryService().summarize(
        document: document,
        generation: session.generation,
        dirty: session.isDirty
    )
    let summary = try #require(result.patternArrays.first { $0.sourceID == source.id })
    let codes = Set(summary.diagnostics.map(\.code))

    #expect(codes.contains("independentCopyRootChildrenMismatch"))
    #expect(codes.contains("independentCopyOutputTransformMismatch"))
    #expect(codes.contains("duplicateOutputSceneNodeOwnership"))
    #expect(codes.contains("duplicateOutputFeatureOwnership"))
}

private func patternArraySummaryBodyFeatureID(
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

private func patternArraySummaryBodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

private func patternArraySummaryTranslationTransform(
    x: Double,
    y: Double,
    z: Double
) throws -> Transform3D {
    Transform3D(
        matrix: try Matrix4x4(
            values: [
                1.0, 0.0, 0.0, x,
                0.0, 1.0, 0.0, y,
                0.0, 0.0, 1.0, z,
                0.0, 0.0, 0.0, 1.0,
            ]
        )
    )
}
