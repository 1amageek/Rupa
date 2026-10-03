import Testing
import RupaCore
import SwiftCAD
@testable import RupaUI

/// Imprint takes its target, curves and tool as clicks while it runs, as Plasticity's slots do,
/// whatever was selected when it started.
@Suite("Imprint session picking")
struct WorkspaceImprintSessionPickTests {
    @Test func startedOnNothingTheFirstBodyIsTheTargetThenCurvesOrATool() throws {
        let body = SceneNodeID(), other = SceneNodeID()
        let curve = SelectionTarget(sceneNodeID: SceneNodeID())
        var session = WorkspaceImprintSession(kind: .picking(target: nil, curves: []))
        #expect(session.takesPicks && session.command() == nil)
        #expect(session.missingInput == "Imprint: click the solid or sheet to imprint on.")
        session.pick(body: body)
        #expect(session.kind == .picking(target: body, curves: []))
        #expect(session.missingInput == "Imprint: click the curves, or a body as the tool, to imprint.")
        session.pick(curve: curve)
        #expect(session.kind == .curves(target: body, curves: [curve]) && session.missingInput == nil)
        guard case .imprintCurves(_, let target, let curves, _, _)? = session.command() else {
            Issue.record("Expected Imprint Curve Body.")
            return
        }
        #expect(target == body && curves == [curve])
        // Clicked again the curve goes off; a second body is the tool.
        session.pick(curve: curve)
        #expect(session.kind == .picking(target: body, curves: []))
        session.pick(body: other)
        #expect(session.kind == .bodies(target: body, tools: [other]))
        // A third body is another tool; clicked again a tool goes off.
        let third = SceneNodeID()
        session.pick(body: third)
        #expect(session.kind == .bodies(target: body, tools: [other, third]))
        session.pick(body: other)
        #expect(session.kind == .bodies(target: body, tools: [third]))
    }

    @Test func startedOnCurvesTheBodyClickedIsTheTarget() {
        let body = SceneNodeID()
        let curve = SelectionTarget(sceneNodeID: SceneNodeID())
        var session = WorkspaceImprintSession(kind: .picking(target: nil, curves: [curve]))
        session.pick(body: body)
        #expect(session.kind == .curves(target: body, curves: [curve]))
        // The target clicked again changes nothing.
        session.pick(body: body)
        #expect(session.kind == .curves(target: body, curves: [curve]))
    }
}
