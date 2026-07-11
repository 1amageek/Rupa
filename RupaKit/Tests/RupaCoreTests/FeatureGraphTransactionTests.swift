import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test(.timeLimit(.minutes(1)))
func featureGraphTransactionAppendsCallerOwnedIdentitiesWithOneRevisionAndEvaluation() async throws {
    let session = EditorSession()
    let first = makeBoxFeatures(name: "First", width: 0.04, height: 0.02, depth: 0.01)
    let second = makeBoxFeatures(name: "Second", width: 0.03, height: 0.015, depth: 0.006)
    let transaction = FeatureGraphTransaction(
        features: first.features + second.features,
        presentations: first.presentations + second.presentations,
        primaryFeatureID: second.bodyFeatureID
    )

    let result = try session.execute(.appendFeatureGraph(transaction))

    #expect(result.generation == DocumentGeneration(1))
    #expect(result.primaryFeatureID == second.bodyFeatureID)
    #expect(result.createdFeatureIDs == transaction.features.map(\.id))
    #expect(session.document.cadDocument.designGraph.revision == DocumentRevision(1))
    #expect(session.document.cadDocument.designGraph.order == transaction.features.map(\.id))
    #expect(session.evaluatedBodyCount == 2)
    #expect(session.commandStack.undoEntries.count == 1)
    #expect(session.store.currentEvaluationCache?.validatedDocument.document.cadDocument.designGraph.revision
        == session.document.cadDocument.designGraph.revision)
    let metrics = try #require(session.store.currentModelingEvaluationMetrics)
    #expect(metrics.totalFeatureCount == 4)
    #expect(metrics.rebuiltFeatureCount == 4)
    #expect(metrics.tessellatedBodyCount == 2)

    let firstBodyNode = try #require(session.document.productMetadata.sceneNodes[first.bodySceneNodeID])
    let firstSketchNode = try #require(session.document.productMetadata.sceneNodes[first.sketchSceneNodeID])
    #expect(firstBodyNode.childIDs == [first.sketchSceneNodeID])
    #expect(!firstSketchNode.isVisible)
    #expect(firstSketchNode.reference == .sketch(first.sketchFeatureID))
    #expect(firstBodyNode.reference == .body(first.bodyFeatureID))

    _ = try session.undo()
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    _ = try session.redo()
    #expect(session.document.cadDocument.designGraph.order == transaction.features.map(\.id))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func featureGraphTransactionRejectsFailedGeometryWithoutPublishingSourceOrHistory() async throws {
    let session = EditorSession()
    let sketchFeatureID = FeatureID()
    let bodyFeatureID = FeatureID()
    var builder = SketchBuilder(on: .xy)
    _ = builder.line(
        from: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        to: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let transaction = FeatureGraphTransaction(
        features: [
            FeatureNode(
                id: sketchFeatureID,
                name: "Open Profile",
                operation: .sketch(builder.build()),
                outputs: [FeatureOutput(role: .profile)]
            ),
            FeatureNode(
                id: bodyFeatureID,
                name: "Invalid Extrude",
                operation: .extrude(ExtrudeFeature(
                    profile: ProfileReference(featureID: sketchFeatureID),
                    distance: .length(5.0, .millimeter),
                    direction: .normal,
                    operation: .newBody
                )),
                inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
                outputs: [FeatureOutput(role: .body)]
            ),
        ],
        primaryFeatureID: bodyFeatureID
    )

    do {
        _ = try session.execute(.appendFeatureGraph(transaction))
        Issue.record("Expected the invalid graph evaluation to fail.")
    } catch let error as EditorError {
        #expect(error.code == .evaluationFailed)
    }

    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    #expect(session.generation == DocumentGeneration())
    #expect(session.commandStack.undoEntries.isEmpty)
    #expect(session.commandStack.redoEntries.isEmpty)
    #expect(session.evaluationStatus == .notEvaluated)
    #expect(session.store.completedEvaluationPassCount == 1)
}

private struct BoxFeatureGraphFixture {
    var features: [FeatureNode]
    var presentations: [FeaturePresentation]
    var sketchFeatureID: FeatureID
    var bodyFeatureID: FeatureID
    var sketchSceneNodeID: SceneNodeID
    var bodySceneNodeID: SceneNodeID
}

private func makeBoxFeatures(
    name: String,
    width: Double,
    height: Double,
    depth: Double
) -> BoxFeatureGraphFixture {
    let sketchFeatureID = FeatureID()
    let bodyFeatureID = FeatureID()
    let sketchSceneNodeID = SceneNodeID()
    let bodySceneNodeID = SceneNodeID()
    var builder = SketchBuilder(on: .xy)
    builder.rectangle(
        width: .length(width, .meter),
        height: .length(height, .meter)
    )
    let sketch = builder.build()
    let profile = ProfileReference(featureID: sketchFeatureID)
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        name: "\(name) Sketch",
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile), FeatureOutput(role: .curve)]
    )
    let bodyFeature = FeatureNode(
        id: bodyFeatureID,
        name: name,
        operation: .extrude(ExtrudeFeature(
            profile: profile,
            distance: .length(depth, .meter),
            direction: .normal,
            operation: .newBody
        )),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let bodyPresentation = FeaturePresentation(
        featureID: bodyFeatureID,
        sceneNodeID: bodySceneNodeID,
        name: name,
        kind: .body(
            sourceSection: .profile(profile),
            typeID: .cube,
            geometryRole: .solid,
            properties: ObjectPropertySet()
        )
    )
    let sketchPresentation = FeaturePresentation(
        featureID: sketchFeatureID,
        sceneNodeID: sketchSceneNodeID,
        parentSceneNodeID: bodySceneNodeID,
        name: "\(name) Sketch",
        kind: .sketch(
            typeID: .rectangle,
            geometryRole: .sketchProfile,
            properties: ObjectPropertySet()
        ),
        isVisible: false
    )
    return BoxFeatureGraphFixture(
        features: [sketchFeature, bodyFeature],
        presentations: [bodyPresentation, sketchPresentation],
        sketchFeatureID: sketchFeatureID,
        bodyFeatureID: bodyFeatureID,
        sketchSceneNodeID: sketchSceneNodeID,
        bodySceneNodeID: bodySceneNodeID
    )
}
