import RupaCore
import RupaEvaluation
import RupaKit
import RupaProjectModel
import RupaViewportScene
import Testing

@Test(.timeLimit(.minutes(1)))
func universalViewportScenePreservesEvaluatedIdentityAndBounds() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bridge = DesignDocumentProjectBridge()
    let project = try bridge.sourceModel(for: session.document)
    let snapshot = try bridge.evaluationEngine(for: session.document).evaluate(project)

    let scene = try UniversalViewportSceneBuilder().build(
        from: snapshot,
        project: project
    )

    #expect(scene.snapshotID == snapshot.id)
    #expect(scene.projectID == project.id)
    #expect(scene.items.count == snapshot.occurrences.count)
    #expect(scene.items.allSatisfy { $0.mesh.faceIDs.count > 0 })
    #expect(scene.worldBounds != nil)
}
