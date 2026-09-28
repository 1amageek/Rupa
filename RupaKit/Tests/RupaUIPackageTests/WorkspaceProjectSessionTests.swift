import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

/// Project's dialog: Normal projects along the construction plane's normal one way; Vector along
/// the typed direction, both ways when Bidirectional is on.
@Test func theProjectDialogSubmitsNormalOrVector() throws {
    let curve = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    let face = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    #expect(WorkspaceProjectSession(curves: [], face: face) == nil)
    var session = try #require(WorkspaceProjectSession(curves: [curve], face: face))
    session.isBidirectional = true
    let up = Vector3D(x: 0, y: 0, z: 1)
    #expect(session.command(constructionPlaneNormal: up)
        == .projectCurvesAlongDirection(targets: [curve], face: face, direction: up, bidirectional: false))
    session.method = .vector
    session.vectorX = 1
    session.vectorY = 2
    session.vectorZ = 3
    #expect(session.command(constructionPlaneNormal: up)
        == .projectCurvesAlongDirection(targets: [curve], face: face, direction: Vector3D(x: 1, y: 2, z: 3), bidirectional: true))
}
