import Foundation
import Testing
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

@Test func agentBatchFailureRollsBackDocumentAndUndoHistory() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: .empty(named: "Before Batch"))
    _ = try AutomationRunner().execute(
        .createExtrudedRectangle(
            name: "Stable Body",
            plane: .xy,
            width: .length(20.0, .millimeter),
            height: .length(12.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let baselineGeneration = session.generation
    let baselineUndoCount = session.commandStack.undoEntries.count
    let baselineEvaluation = try #require(session.currentEvaluation)
    session.markClean()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .executeBatch(
            sessionID: sessionID,
            batch: AutomationBatch(
                commands: [
                    .renameDocument(name: "Partially Applied"),
                    .deleteParameter(name: "missing"),
                ],
                expectedGeneration: baselineGeneration
            )
        )
    )

    guard case .failure(let error) = response else {
        Issue.record("Expected batch failure.")
        return
    }
    #expect(error.code == .referenceUnresolved)
    #expect(session.document.cadDocument.metadata.name == "Before Batch")
    #expect(session.generation == baselineGeneration)
    #expect(!session.isDirty)
    #expect(session.commandStack.undoEntries.count == baselineUndoCount)
    #expect(!session.commandStack.canRedo)
    let restoredEvaluation = try #require(session.currentEvaluation)
    #expect(restoredEvaluation.matches(
        document: session.document,
        generation: baselineGeneration
    ))
    #expect(restoredEvaluation.evaluatedDocument.meshes.count == baselineEvaluation.evaluatedDocument.meshes.count)
}

@Test func agentBatchSuccessReturnsFinalGenerationAndDirtyState() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: .empty(named: "Before Batch"))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .executeBatch(
            sessionID: sessionID,
            batch: AutomationBatch(
                commands: [
                    .renameDocument(name: "Intermediate Batch"),
                    .renameDocument(name: "After Batch"),
                ],
                expectedGeneration: DocumentGeneration(0)
            )
        )
    )

    guard case .batch(let result) = response else {
        Issue.record("Expected batch result.")
        return
    }
    #expect(result.commandCount == 2)
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(result.dirty)
    #expect(result.metrics.commandCount == 2)
    #expect(result.metrics.evaluationPassCount == 1)
    #expect(result.metrics.historyEntryCount == 1)
    #expect(result.metrics.richResultCount == 0)
    #expect(session.document.cadDocument.metadata.name == "After Batch")
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.undoEntries.count == 1)

    _ = try session.undo()

    #expect(session.document.cadDocument.metadata.name == "Before Batch")
}

@Test func agentAppendsCallerOwnedFeatureGraphInOneEvaluationAndUndoEntry() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    let sketchFeatureID = FeatureID()
    let bodyFeatureID = FeatureID()
    let sketchSceneNodeID = SceneNodeID()
    let bodySceneNodeID = SceneNodeID()
    var builder = SketchBuilder(on: .xy)
    builder.rectangle(
        width: .length(30.0, .millimeter),
        height: .length(20.0, .millimeter)
    )
    let profile = ProfileReference(featureID: sketchFeatureID)
    let transaction = FeatureGraphTransaction(
        features: [
            FeatureNode(
                id: sketchFeatureID,
                name: "Agent Profile",
                operation: .sketch(builder.build()),
                outputs: [FeatureOutput(role: .profile)]
            ),
            FeatureNode(
                id: bodyFeatureID,
                name: "Agent Body",
                operation: .extrude(ExtrudeFeature(
                    profile: profile,
                    distance: .length(8.0, .millimeter),
                    direction: .normal,
                    operation: .newBody
                )),
                inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
                outputs: [FeatureOutput(role: .body)]
            ),
        ],
        presentations: [
            FeaturePresentation(
                featureID: bodyFeatureID,
                sceneNodeID: bodySceneNodeID,
                name: "Agent Body",
                kind: .body(
                    sourceSection: .profile(profile),
                    typeID: nil,
                    geometryRole: .solid,
                    properties: ObjectPropertySet()
                )
            ),
            FeaturePresentation(
                featureID: sketchFeatureID,
                sceneNodeID: sketchSceneNodeID,
                parentSceneNodeID: bodySceneNodeID,
                name: "Agent Profile",
                kind: .sketch(
                    typeID: nil,
                    geometryRole: .sketchProfile,
                    properties: ObjectPropertySet()
                ),
                isVisible: false
            ),
        ],
        primaryFeatureID: bodyFeatureID
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .appendFeatureGraph(transaction),
            expectedGeneration: DocumentGeneration()
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Expected a feature graph command result.")
        return
    }
    #expect(result.primaryFeatureID == bodyFeatureID)
    #expect(result.createdFeatureIDs == [sketchFeatureID, bodyFeatureID])
    #expect(session.document.cadDocument.designGraph.order == [sketchFeatureID, bodyFeatureID])
    #expect(session.document.cadDocument.designGraph.revision == DocumentRevision(1))
    #expect(session.document.productMetadata.sceneNodes[bodySceneNodeID]?.childIDs == [sketchSceneNodeID])
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.store.completedEvaluationPassCount == 1)
    #expect(session.commandStack.undoEntries.count == 1)
    #expect(result.executionMetrics?.evaluationPassCount == 1)
    #expect(result.executionMetrics?.historyEntryCount == 1)
    let metrics = try #require(session.store.currentModelingEvaluationMetrics)
    #expect(metrics.rebuiltFeatureCount == 2)
    #expect(metrics.tessellatedBodyCount == 1)
    #expect(result.executionMetrics?.modelingEvaluation == metrics)
}
