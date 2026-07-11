import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func documentStoreReusesCADFeatureAndMeshResultsAcrossMetadataEdits() throws {
    let store = CADDocumentStore()
    _ = try store.apply(.createExtrudedRectangle(
        name: "Box",
        plane: .xy,
        width: .length(40.0, .millimeter),
        height: .length(20.0, .millimeter),
        depth: .length(10.0, .millimeter),
        direction: .normal
    ))
    let initialMetrics = try #require(store.currentModelingEvaluationMetrics)
    #expect(initialMetrics.totalFeatureCount == 2)
    #expect(initialMetrics.rebuiltFeatureCount == 2)
    #expect(initialMetrics.tessellatedBodyCount == 1)

    _ = try store.apply(.renameDocument(name: "Renamed"))

    let renamedMetrics = try #require(store.currentModelingEvaluationMetrics)
    #expect(renamedMetrics.totalFeatureCount == 2)
    #expect(renamedMetrics.rebuiltFeatureCount == 0)
    #expect(renamedMetrics.reusedFeatureCount == 2)
    #expect(renamedMetrics.invalidatedFeatureCount == 0)
    #expect(renamedMetrics.replayFallbackCount == 0)
    #expect(renamedMetrics.tessellatedBodyCount == 0)
    #expect(renamedMetrics.reusedMeshCount == 1)
}
