import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

/// Fillet's dialog takes the selected curve ends, or else the selected curves.
@Suite struct WorkspaceFilletSessionTests {
    private let node = SceneNodeID()
    private let feature = FeatureID()

    @Test func endsTakePrecedenceAndCSwitchesTheTreatment() throws {
        let line = SketchEntityID(), other = SketchEntityID()
        let curve = SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: feature, entityID: line)))
        let adjacent = SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: feature, entityID: other)))
        let end = SelectionTarget(sceneNodeID: node, component: .sketchEntity(
            .sketchPointHandle(featureID: feature, entityID: line, handle: .lineEnd)
        ))
        var mixed = try #require(WorkspaceFilletSession(selectedSketchTargets: [curve, end], treatment: .fillet))
        #expect(mixed.targets == .vertices([end]))
        mixed.toggleTreatment()
        #expect(mixed.treatment == .chamfer && mixed.title == "Chamfer")
        let curves = try #require(WorkspaceFilletSession(selectedSketchTargets: [curve, adjacent], treatment: .fillet))
        #expect(curves.targets == .curves(curve, adjacent: adjacent))
        #expect(WorkspaceFilletSession(selectedSketchTargets: [], treatment: .fillet) == nil)
    }
}
