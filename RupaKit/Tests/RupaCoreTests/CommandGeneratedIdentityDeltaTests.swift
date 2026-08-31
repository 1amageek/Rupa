import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test(.timeLimit(.minutes(1)))
func commandResultReportsCompleteFeatureBodyAndSceneDelta() throws {
    let session = EditorSession()
    let initialSceneNodeIDs = Set(session.document.productMetadata.sceneNodes.keys)

    let result = try #require(session.createDefaultExtrudedRectangle())
    let featureIDs = session.document.cadDocument.designGraph.order
    let bodyFeatureID = try #require(featureIDs.last)
    let generatedSceneNodeIDs = Set(session.document.productMetadata.sceneNodes.keys)
        .subtracting(initialSceneNodeIDs)
    let expectedBodyOutput = try GeneratedSourceBodyOutputIdentity(
        featureID: bodyFeatureID,
        sourcePort: .body
    )

    #expect(result.generatedIdentities.featureIDs == featureIDs)
    #expect(result.createdFeatureIDs == featureIDs)
    #expect(result.primaryFeatureID == bodyFeatureID)
    #expect(result.generatedIdentities.sourceBodyOutputs == [expectedBodyOutput])
    #expect(Set(result.generatedIdentities.sceneNodeIDs) == generatedSceneNodeIDs)
    #expect(result.generatedIdentities.sceneNodeIDs.count == 2)
    let bodySceneNodeID = try #require(result.generatedIdentities.sceneNodeIDs.first)
    let sketchSceneNodeID = try #require(result.generatedIdentities.sceneNodeIDs.last)
    #expect(session.document.productMetadata.sceneNodes[bodySceneNodeID]?.reference == .body(bodyFeatureID))
    #expect(session.document.productMetadata.sceneNodes[bodySceneNodeID]?.childIDs == [sketchSceneNodeID])
    #expect(result.generatedIdentities.componentDefinitionIDs.isEmpty)
    #expect(result.generatedIdentities.componentInstanceIDs.isEmpty)
    #expect(result.generatedIdentities.patternArraySourceIDs.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func commandResultReportsSheetSourceRoleWithoutTopologyBodyIdentity() throws {
    let session = EditorSession()
    let result = try session.execute(
        .createBSplineSurface(
            name: "Sheet",
            surface: .cubicBezierPatch(
                bottomLeft: Point3D(x: 0, y: 0, z: 0),
                bottomRight: Point3D(x: 0.02, y: 0, z: 0),
                topRight: Point3D(x: 0.02, y: 0.01, z: 0),
                topLeft: Point3D(x: 0, y: 0.01, z: 0)
            )
        )
    )
    let featureID = try #require(result.primaryFeatureID)
    let expectedSheetOutput = try GeneratedSourceBodyOutputIdentity(
        featureID: featureID,
        sourcePort: .sheet
    )

    #expect(result.generatedIdentities.featureIDs == [featureID])
    #expect(result.generatedIdentities.sourceBodyOutputs == [expectedSheetOutput])
    #expect(result.generatedIdentities.sceneNodeIDs.count == 1)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func componentCommandsReportDefinitionInstanceAndSceneIdentities() throws {
    let session = EditorSession()
    let rootSceneNodeID = try #require(session.document.productMetadata.rootSceneNodeIDs.first)

    let definitionResult = try session.execute(
        .createComponentDefinition(name: "Frame", rootSceneNodeIDs: [rootSceneNodeID])
    )
    let definitionID = try #require(definitionResult.generatedIdentities.componentDefinitionIDs.first)
    #expect(definitionResult.generatedIdentities.componentDefinitionIDs == [definitionID])
    #expect(definitionResult.generatedIdentities.featureIDs.isEmpty)
    #expect(definitionResult.generatedIdentities.sceneNodeIDs.isEmpty)

    let instanceResult = try session.execute(
        .createComponentInstance(
            name: "Frame Instance",
            definitionID: definitionID,
            localTransform: .identity
        )
    )
    let instanceID = try #require(instanceResult.generatedIdentities.componentInstanceIDs.first)
    let sceneNodeID = try #require(instanceResult.generatedIdentities.sceneNodeIDs.first)
    #expect(instanceResult.generatedIdentities.componentInstanceIDs == [instanceID])
    #expect(instanceResult.generatedIdentities.sceneNodeIDs == [sceneNodeID])
    #expect(session.document.productMetadata.componentInstances[instanceID]?.definitionID == definitionID)
    #expect(session.document.productMetadata.sceneNodes[sceneNodeID]?.reference == .componentInstance(instanceID))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func nativePatternReportsCompleteServerGeneratedSourceProductDelta() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference == .body(bodyFeatureID)
        }?.id
    )
    let definitionResult = try session.execute(
        .createComponentDefinition(
            name: "Pattern Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definitionID = try #require(definitionResult.generatedIdentities.componentDefinitionIDs.first)
    let beforeSceneNodeIDs = Set(session.document.productMetadata.sceneNodes.keys)
    let beforeInstanceIDs = Set(session.document.productMetadata.componentInstances.keys)

    let result = try session.execute(
        .createPatternArray(
            name: "Pattern",
            definitionID: definitionID,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10, .millimeter),
                    copyCount: 3
                )
            )),
            outputMode: .componentInstance
        )
    )
    let patternID = try #require(result.generatedIdentities.patternArraySourceIDs.first)
    let pattern = try #require(session.document.productMetadata.patternArrays[patternID])
    let expectedSceneNodeIDs = Set(session.document.productMetadata.sceneNodes.keys)
        .subtracting(beforeSceneNodeIDs)
    let expectedInstanceIDs = Set(session.document.productMetadata.componentInstances.keys)
        .subtracting(beforeInstanceIDs)

    #expect(result.generatedIdentities.patternArraySourceIDs == [patternID])
    #expect(Set(result.generatedIdentities.componentInstanceIDs) == expectedInstanceIDs)
    #expect(Set(pattern.outputInstanceIDs) == expectedInstanceIDs)
    #expect(Set(result.generatedIdentities.sceneNodeIDs) == expectedSceneNodeIDs)
    #expect(result.generatedIdentities.sceneNodeIDs.first == pattern.rootSceneNodeID)
    #expect(result.generatedIdentities.featureIDs.isEmpty)
    #expect(result.generatedIdentities.sourceBodyOutputs.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func independentCopyPatternReportsEveryCloneIdentityInSourceOrder() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference == .body(bodyFeatureID)
        }?.id
    )
    let definitionResult = try session.execute(
        .createComponentDefinition(
            name: "Independent Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definitionID = try #require(definitionResult.generatedIdentities.componentDefinitionIDs.first)
    let beforeFeatureIDs = Set(session.document.cadDocument.designGraph.nodes.keys)
    let beforeSceneNodeIDs = Set(session.document.productMetadata.sceneNodes.keys)

    let result = try session.execute(
        .createPatternArray(
            name: "Independent",
            definitionID: definitionID,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let patternID = try #require(result.generatedIdentities.patternArraySourceIDs.first)
    let pattern = try #require(session.document.productMetadata.patternArrays[patternID])
    let expectedFeatureIDs = session.document.cadDocument.designGraph.order.filter {
        !beforeFeatureIDs.contains($0)
    }
    let expectedSceneNodeIDs = Set(session.document.productMetadata.sceneNodes.keys)
        .subtracting(beforeSceneNodeIDs)

    #expect(result.generatedIdentities.featureIDs == expectedFeatureIDs)
    #expect(Set(result.generatedIdentities.featureIDs) == Set(pattern.outputFeatureIDs))
    #expect(result.generatedIdentities.sourceBodyOutputs.count == 2)
    #expect(result.generatedIdentities.sourceBodyOutputs.allSatisfy { $0.role == .body })
    #expect(Set(result.generatedIdentities.sceneNodeIDs) == expectedSceneNodeIDs)
    #expect(result.generatedIdentities.componentInstanceIDs.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func patternRebuildReportsNewFeaturesWhenTotalFeatureCountDecreases() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference == .body(bodyFeatureID)
        }?.id
    )
    let firstDefinitionResult = try session.execute(
        .createComponentDefinition(name: "First", rootSceneNodeIDs: [bodySceneNodeID])
    )
    let firstDefinitionID = try #require(
        firstDefinitionResult.generatedIdentities.componentDefinitionIDs.first
    )
    let creation = try session.execute(
        .createPatternArray(
            name: "Rebuilt",
            definitionID: firstDefinitionID,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let patternID = try #require(creation.generatedIdentities.patternArraySourceIDs.first)
    let secondDefinitionResult = try session.execute(
        .createComponentDefinition(name: "Second", rootSceneNodeIDs: [bodySceneNodeID])
    )
    let secondDefinitionID = try #require(
        secondDefinitionResult.generatedIdentities.componentDefinitionIDs.first
    )
    let previousFeatureCount = session.document.cadDocument.designGraph.order.count

    let result = try session.execute(
        .updatePatternArray(
            id: patternID,
            name: nil,
            definitionID: secondDefinitionID,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: nil
        )
    )
    let rebuilt = try #require(session.document.productMetadata.patternArrays[patternID])

    #expect(session.document.cadDocument.designGraph.order.count < previousFeatureCount)
    #expect(result.generatedIdentities.featureIDs == rebuilt.outputFeatureIDs)
    #expect(result.generatedIdentities.featureIDs.count == 2)
    #expect(result.generatedIdentities.sourceBodyOutputs.count == 1)
    #expect(result.generatedIdentities.sourceBodyOutputs.first?.role == .body)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func noOpHistoryFailureAndPriorResultsNeverFabricateGeneratedIdentity() throws {
    let session = EditorSession()
    let creation = try #require(session.createDefaultExtrudedRectangle())
    let retainedDelta = creation.generatedIdentities
    let featureID = try #require(creation.primaryFeatureID)

    _ = try session.execute(.setFeatureSuppression(featureID: featureID, isSuppressed: true))
    let noOp = try session.execute(
        .setFeatureSuppression(featureID: featureID, isSuppressed: true)
    )
    #expect(!noOp.didMutate)
    #expect(noOp.generatedIdentities.isEmpty)
    #expect(noOp.primaryFeatureID == featureID)

    let undo = try session.undo()
    let redo = try session.redo()
    #expect(undo.generatedIdentities.isEmpty)
    #expect(redo.generatedIdentities.isEmpty)
    #expect(creation.generatedIdentities == retainedDelta)

    let beforeFailure = session.document.cadDocument.designGraph.order
    #expect(throws: EditorError.self) {
        _ = try session.execute(
            .createComponentInstance(
                name: "Missing",
                definitionID: ComponentDefinitionID(),
                localTransform: .identity
            )
        )
    }
    #expect(session.document.cadDocument.designGraph.order == beforeFailure)
}

@Test(.timeLimit(.minutes(1)))
func generatedIdentityValidationRejectsWrongAmbiguousAndUnreportedIdentityKinds() throws {
    #expect(throws: CommandGeneratedIdentityError.self) {
        _ = try GeneratedSourceBodyOutputIdentity(
            featureID: FeatureID(),
            sourcePort: .profile
        )
    }

    let session = EditorSession()
    let before = session.document
    _ = try #require(session.createDefaultExtrudedRectangle())
    let after = session.document
    #expect(throws: CommandGeneratedIdentityError.self) {
        _ = try CommandGeneratedIdentityDelta(
            before: before,
            after: after,
            didMutate: false
        )
    }

    var ambiguous = after
    let bodyFeatureID = try #require(ambiguous.cadDocument.designGraph.order.last)
    var bodyFeature = try #require(ambiguous.cadDocument.designGraph.nodes[bodyFeatureID])
    bodyFeature.outputs.append(FeatureOutput(role: .sheet))
    ambiguous.cadDocument.designGraph.nodes[bodyFeatureID] = bodyFeature
    #expect(throws: CommandGeneratedIdentityError.self) {
        _ = try CommandGeneratedIdentityDelta(
            before: before,
            after: ambiguous,
            didMutate: true
        )
    }
}

@Test(.timeLimit(.minutes(1)))
func generatedIdentityDeltaDecoderRejectsEveryStructuralInvariantViolation() throws {
    let featureID = FeatureID()
    let otherFeatureID = FeatureID()
    let sceneNodeID = SceneNodeID()
    let definitionID = ComponentDefinitionID()
    let instanceID = ComponentInstanceID()
    let patternID = PatternArraySourceID()
    let body = try GeneratedSourceBodyOutputIdentity(featureID: featureID, sourcePort: .body)
    let sheet = try GeneratedSourceBodyOutputIdentity(featureID: featureID, sourcePort: .sheet)
    let orphan = try GeneratedSourceBodyOutputIdentity(featureID: otherFeatureID, sourcePort: .body)

    try expectGeneratedIdentityDecodeRejected(.init(featureIDs: [featureID, featureID]))
    try expectGeneratedIdentityDecodeRejected(.init(
        featureIDs: [featureID],
        sourceBodyOutputs: [body, body]
    ))
    try expectGeneratedIdentityDecodeRejected(.init(
        featureIDs: [featureID],
        sourceBodyOutputs: [body, sheet]
    ))
    try expectGeneratedIdentityDecodeRejected(.init(
        featureIDs: [featureID],
        sourceBodyOutputs: [orphan]
    ))
    try expectGeneratedIdentityDecodeRejected(.init(sceneNodeIDs: [sceneNodeID, sceneNodeID]))
    try expectGeneratedIdentityDecodeRejected(.init(
        componentDefinitionIDs: [definitionID, definitionID]
    ))
    try expectGeneratedIdentityDecodeRejected(.init(
        componentInstanceIDs: [instanceID, instanceID]
    ))
    try expectGeneratedIdentityDecodeRejected(.init(
        patternArraySourceIDs: [patternID, patternID]
    ))
}

@Test(.timeLimit(.minutes(1)))
func sourceCommandGroupFailurePublishesNoGeneratedIdentityOrSource() throws {
    let session = EditorSession()
    let initialDocument = session.document

    #expect(throws: EditorError.self) {
        try session.withSourceCommandGroup(named: "generated.identity.rollback") { staged in
            let result = try staged.execute(
                .createRectangleSketch(
                    name: "Rolled Back",
                    plane: .xy,
                    width: .length(10, .millimeter),
                    height: .length(5, .millimeter)
                )
            )
            #expect(!result.generatedIdentities.isEmpty)
            throw EditorError(code: .commandFailed, message: "Injected rollback.")
        } as Void
    }

    #expect(session.document.cadDocument.designGraph.order == initialDocument.cadDocument.designGraph.order)
    #expect(session.document.productMetadata.sceneNodes == initialDocument.productMetadata.sceneNodes)
    #expect(session.commandStack.undoEntries.isEmpty)
}

private struct CommandGeneratedIdentityDeltaEncodingFixture: Encodable {
    var featureIDs: [FeatureID] = []
    var sourceBodyOutputs: [GeneratedSourceBodyOutputIdentity] = []
    var sceneNodeIDs: [SceneNodeID] = []
    var componentDefinitionIDs: [ComponentDefinitionID] = []
    var componentInstanceIDs: [ComponentInstanceID] = []
    var patternArraySourceIDs: [PatternArraySourceID] = []
}

private func expectGeneratedIdentityDecodeRejected(
    _ fixture: CommandGeneratedIdentityDeltaEncodingFixture
) throws {
    let data = try JSONEncoder().encode(fixture)
    do {
        _ = try JSONDecoder().decode(CommandGeneratedIdentityDelta.self, from: data)
        Issue.record("Invalid generated identity payload was accepted.")
    } catch is CommandGeneratedIdentityError {
        return
    } catch {
        Issue.record("Invalid generated identity payload failed with an unexpected error: \(error)")
    }
}
