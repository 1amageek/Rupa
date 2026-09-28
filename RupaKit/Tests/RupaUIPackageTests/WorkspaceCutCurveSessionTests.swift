import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

/// Cut Curve's dialog: the selection seeds its targets and cutter, clicks add to or remove from the
/// list being picked, and a curve is never in both lists.
@Suite struct WorkspaceCutCurveSessionTests {
    private let node = SceneNodeID()
    private let feature = FeatureID()

    private func curve() -> SelectionTarget {
        SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: feature, entityID: SketchEntityID())))
    }

    @Test func theSelectionSeedsTargetsAndTheLastSelectedCutter() {
        let (a, b, c) = (curve(), curve(), curve())
        let none = WorkspaceCutCurveSession(selectedCurves: [])
        #expect(none.targets.isEmpty && none.cutters.isEmpty && none.picking == .targets)
        let one = WorkspaceCutCurveSession(selectedCurves: [a])
        #expect(one.targets == [a] && one.cutters.isEmpty && one.picking == .cutters)
        let three = WorkspaceCutCurveSession(selectedCurves: [a, b, c])
        #expect(three.targets == [a, b] && three.cutters == [c] && three.canCut)
    }

    @Test func aClickTogglesTheCurveInTheListBeingPicked() throws {
        let (a, b) = (curve(), curve())
        var session = WorkspaceCutCurveSession(selectedCurves: [a])
        #expect(!session.canCut)
        session.toggle(b)
        #expect(session.cutters == [b])
        // Picking a cutter that is a target moves it.
        session.toggle(a)
        #expect(session.targets.isEmpty && session.cutters == [b, a])
        session.toggle(a)
        #expect(session.cutters == [b])
        session.picking = .targets
        session.toggle(a)
        #expect(session.targets == [a] && session.cutters == [b] && session.canCut)
        #expect(session.curves == [a, b])
    }
}

/// Screen space needs the view of a click before the cut can run, and carries it in the options.
@Test func screenSpaceCutsAlongTheLatestClicksView() {
    let target = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    let cutter = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    var session = WorkspaceCutCurveSession(selectedCurves: [target, cutter])
    #expect(session.canCut)
    session.usesScreenSpace = true
    #expect(!session.canCut)
    session.viewDirection = Vector3D(x: 0, y: 0, z: -1)
    #expect(session.canCut)
    #expect(session.options == CutCurveOptions(usesScreenSpaceDirection: true, screenDirection: Vector3D(x: 0, y: 0, z: -1)))
}

