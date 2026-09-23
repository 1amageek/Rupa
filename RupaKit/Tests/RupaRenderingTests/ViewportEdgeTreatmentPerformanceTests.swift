import Foundation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test(.timeLimit(.minutes(1)))
func edgeTreatmentPreparationAndEvaluationCosts() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySnapshotService().snapshot(document: session.document, metricPolicy: .omit)
    let target = try #require(topology.entries.first { $0.kind == .edge }?.selectionTarget())
    let clock = ContinuousClock()
    var preparation: [Double] = []
    var evaluation: [Double] = []
    for index in 0..<5 {
        let start = clock.now
        let preview = try ViewportEdgeTreatmentPreviewDocumentBuilder().previewDocument(
            for: .fillet(target: target, radius: 0.001 + Double(index) * 0.0001),
            in: session.document, currentEvaluation: session.currentEvaluation,
            currentGeneration: session.generation)
        let prepared = clock.now
        let result = EvaluationScheduler().evaluateResult(document: preview,
            generation: session.generation, objectRegistry: .builtIn,
            reusing: session.currentEvaluation?.evaluatedDocument)
        let completed = clock.now
        #expect(result.snapshot.status == .valid)
        func milliseconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
        preparation.append(milliseconds(start.duration(to: prepared)))
        evaluation.append(milliseconds(prepared.duration(to: completed)))
    }
    print("Edge preview median ms: prepare=\(preparation.sorted()[2]), evaluate=\(evaluation.sorted()[2])")
}
