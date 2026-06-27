import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func ownershipResolverFindsComponentInstancePatternOutputs() async throws {
    let setup = try patternArrayOwnershipSetup(outputMode: .componentInstance)
    let source = setup.source
    let outputInstanceID = try #require(source.outputInstanceIDs.first)
    let outputSceneNodeID = try #require(
        setup.metadata.sceneNodes[source.rootSceneNodeID]?.childIDs.first
    )
    let resolver = PatternArrayOwnershipResolver()

    #expect(
        resolver.sourceID(
            owningOutputInstance: outputInstanceID,
            in: setup.metadata
        ) == source.id
    )
    #expect(
        resolver.sourceID(
            containingGeneratedOutputSceneNode: outputSceneNodeID,
            in: setup.metadata
        ) == source.id
    )
    #expect(
        resolver.sourceID(
            containingOutputSceneNode: source.rootSceneNodeID,
            in: setup.metadata
        ) == source.id
    )
    #expect(
        resolver.sourceID(
            containingGeneratedOutputSceneNode: source.rootSceneNodeID,
            in: setup.metadata
        ) == nil
    )
    #expect(
        resolver.sourceID(
            owningOutputInstance: ComponentInstanceID(),
            in: setup.metadata
        ) == nil
    )
}

@MainActor
@Test func ownershipResolverFindsIndependentCopyPatternOutputSubtrees() async throws {
    let setup = try patternArrayOwnershipSetup(outputMode: .independentCopy)
    let source = setup.source
    let outputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let resolver = PatternArrayOwnershipResolver()

    #expect(
        resolver.sourceID(
            containingGeneratedOutputSceneNode: outputSceneNodeID,
            in: setup.metadata
        ) == source.id
    )
    #expect(
        resolver.sourceID(
            containingOutputSceneNode: outputSceneNodeID,
            in: setup.metadata
        ) == source.id
    )
    #expect(
        resolver.sourceID(
            containingOutputSceneNode: source.rootSceneNodeID,
            in: setup.metadata
        ) == source.id
    )
    #expect(
        resolver.sourceID(
            owningOutputInstance: ComponentInstanceID(),
            in: setup.metadata
        ) == nil
    )
    #expect(
        resolver.sourceID(
            containingOutputSceneNode: SceneNodeID(),
            in: setup.metadata
        ) == nil
    )
}

private func patternArrayOwnershipSetup(
    outputMode: PatternArrayOutputMode
) throws -> (
    metadata: ProductMetadata,
    source: PatternArraySource
) {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == bodyFeatureID
        }?.id
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Ownership Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(
        session.document.productMetadata.componentDefinitions.values.first {
            $0.name == "Ownership Source"
        }
    )
    _ = try session.execute(
        .createPatternArray(
            name: "Ownership Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: outputMode
        )
    )
    let source = try #require(
        session.document.productMetadata.patternArrays.values.first {
            $0.name == "Ownership Array"
        }
    )
    return (
        metadata: session.document.productMetadata,
        source: source
    )
}
