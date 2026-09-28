import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

/// Bridge Edge's dialog starts at the nearest ends and submits its sides, continuity and tensions.
@Test func theBridgeEdgeDialogSubmitsItsSidesContinuityAndTensions() {
    let a = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    let b = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    var session = WorkspaceBridgeEdgeSession(nearest: (SpatialBridgeEnd(target: a, fraction: 1), SpatialBridgeEnd(target: b, fraction: 0)))
    #expect(session.firstAtEnd && !session.secondAtEnd && session.continuity == .g1)
    session.secondAtEnd = true
    session.continuity.first = .g2
    session.tensions.second = 1.5
    #expect(session.command == .createBridgeCurveBetweenEnds(
        first: SpatialBridgeEnd(target: a, fraction: 1), second: SpatialBridgeEnd(target: b, fraction: 1),
        continuity: BridgeCurveContinuity(first: .g2, second: .g1), tensions: SpatialBridgeTensions(first: 1, second: 1.5)
    ))
}
