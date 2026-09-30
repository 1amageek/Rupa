import Foundation
import RupaCore
import RupaEvaluation
import RupaProject
import Testing
@testable import RupaKit

/// A publication of the same document state (a selection change) keeps the previous view's
/// validated document, presentation scene and navigation instead of building them again.
@Test(.timeLimit(.minutes(1)))
func aViewOfTheSameDocumentStateReusesThePreviousOne() async throws {
    var document = DesignDocument.empty(named: "Reuse")
    for index in 0..<6 {
        _ = try document.createExtrudedRectangle(name: "Box \(index)", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter), depth: .length(0.1, .meter), direction: .normal)
    }
    let controller = try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    _ = try await workspace.evaluate()
    let state = try await controller.currentState()
    let builder = ProjectViewSnapshotBuilder()
    let full = try builder.build(from: state)
    let reused = try builder.build(from: state, reusing: full)
    #expect(reused.viewport == full.viewport)
    #expect(reused.sceneNodeIDByOccurrenceID == full.sceneNodeIDByOccurrenceID)
    #expect(reused.documentGeneration == full.documentGeneration)
    #expect(!reused.viewport.items.isEmpty)

    let clock = ContinuousClock()
    let rounds = 10
    let fullDuration = try clock.measure { for _ in 0..<rounds { _ = try builder.build(from: state) } }
    let reuseDuration = try clock.measure { for _ in 0..<rounds { _ = try builder.build(from: state, reusing: full) } }
    print("View build for one state: whole \(fullDuration / rounds), reusing \(reuseDuration / rounds)")
    #expect(reuseDuration < fullDuration)
}
